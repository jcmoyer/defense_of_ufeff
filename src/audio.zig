const std = @import("std");
const log = std.log.scoped(.audio);
const Allocator = std.mem.Allocator;
const sdl = @import("sdl.zig");
const stb_vorbis = @import("stb_vorbis");

const Buffer = struct {
    sample_rate: c_int = 0,
    channels: c_int = 0,
    samples: ?[*]i16 = null,
    sample_count: std.atomic.Atomic(u32) = .{ .value = 0 },

    fn destroy(self: *Buffer, allocator: Allocator) void {
        if (self.samples) |ptr| {
            std.c.free(ptr);
            self.samples = null;
        }
        allocator.destroy(self);
    }
};

const AudioParameters = struct {
    allocator: Allocator,
    refcount: std.atomic.Atomic(u32) = .{ .value = 1 },
    volume: std.atomic.Atomic(f32) = .{ .value = 1 },
    done: std.atomic.Atomic(bool) = .{ .value = false },
    paused: std.atomic.Atomic(bool) = .{ .value = false },

    fn create(allocator: Allocator) !*AudioParameters {
        var ptr = try allocator.create(AudioParameters);
        ptr.* = .{
            .allocator = allocator,
        };
        return ptr;
    }

    pub fn addRef(self: *AudioParameters) *AudioParameters {
        _ = self.refcount.fetchAdd(1, .Monotonic);
        return self;
    }

    pub fn release(self: *AudioParameters) void {
        if (self.refcount.fetchSub(1, .Release) == 1) {
            self.refcount.fence(.Acquire);
            self.allocator.destroy(self);
        }
    }
};

const Track = struct {
    buffer: *const Buffer,
    cursor: usize = 0,
    loop: bool = false,
    done: bool = false,
    parameters: *AudioParameters,

    fn deinit(self: Track) void {
        self.parameters.release();
    }
};

const DecodeRequest = struct {
    filename: [:0]const u8,
    loop: bool,
    parameters: *AudioParameters,
};

pub const AudioSystem = struct {
    allocator: Allocator,

    device: sdl.SDL_AudioDeviceID,
    spec: sdl.SDL_AudioSpec,

    tracks_m: std.Thread.Mutex = .{},
    tracks: std.ArrayListUnmanaged(Track) = .{},

    cache_m: std.Thread.Mutex = .{},
    cache: std.StringArrayHashMapUnmanaged(*Buffer) = .{},

    decode_thread: std.Thread,
    decode_queue_m: std.Thread.Mutex = .{},
    decode_queue: std.ArrayList(DecodeRequest),
    decode_cv: std.Thread.Condition = .{},

    pub fn create(allocator: Allocator) *AudioSystem {
        const self = allocator.create(AudioSystem) catch |err| {
            log.err("Failed to spawn audio decode thread: {!}", .{err});
            std.process.exit(1);
        };
        self.* = AudioSystem{
            .allocator = allocator,
            .decode_queue = std.ArrayList(DecodeRequest).init(allocator),
            // Initialized below
            .spec = undefined,
            .decode_thread = undefined,
            .device = undefined,
        };
        self.tracks = std.ArrayListUnmanaged(Track).initCapacity(allocator, 1024) catch |err| {
            log.err("Failed to allocate track storage: {!}", .{err});
            std.process.exit(1);
        };

        var want = std.mem.zeroes(sdl.SDL_AudioSpec);
        want.freq = 44100;
        want.format = sdl.AUDIO_S16;
        want.channels = 2;
        want.samples = 128;
        want.callback = audioCallback;
        want.userdata = self;

        const device = sdl.SDL_OpenAudioDevice(null, 0, &want, &self.spec, 0);
        if (device == 0) {
            log.err("Failed to open audio device: {s}", .{sdl.SDL_GetError()});
            std.process.exit(1);
        }

        self.device = device;
        sdl.SDL_PauseAudioDevice(self.device, 0);

        self.decode_thread = std.Thread.spawn(.{}, decodeThread, .{self}) catch |err| {
            log.err("Failed to spawn audio decode thread: {!}", .{err});
            std.process.exit(1);
        };

        return self;
    }

    pub fn destroy(self: *AudioSystem) void {
        sdl.SDL_CloseAudioDevice(self.device);

        self.postShutdown();
        self.decode_thread.join();
        self.decode_queue.deinit();
        for (self.cache.values()) |val| {
            val.destroy(self.allocator);
        }
        self.cache.deinit(self.allocator);
        for (self.tracks.items) |*track| {
            track.deinit();
        }
        self.tracks.deinit(self.allocator);

        self.allocator.destroy(self);
    }

    fn decodeThread(self: *AudioSystem) void {
        var local_queue = std.ArrayList(DecodeRequest).init(self.allocator);
        defer {
            for (local_queue.items) |*req| {
                req.parameters.release();
            }
            local_queue.deinit();
        }

        while (true) {
            self.decode_queue_m.lock();
            // go to sleep until there are items to process
            while (self.decode_queue.items.len == 0) {
                self.decode_cv.wait(&self.decode_queue_m);
            }
            // we have the lock here, quickly take the queue and release
            std.mem.swap(
                std.ArrayList(DecodeRequest),
                &local_queue,
                &self.decode_queue,
            );
            self.decode_queue_m.unlock();

            // now we can load the requests and put them into the tracklist
            for (local_queue.items) |req| {
                // empty filename kills the thread
                if (req.filename.len == 0) {
                    return;
                }
                const t = Track{
                    .buffer = self.getOrLoad(req.filename),
                    .loop = req.loop,
                    .parameters = req.parameters,
                };
                self.tracks_m.lock();
                defer self.tracks_m.unlock();
                self.tracks.append(self.allocator, t) catch |err| {
                    log.err("Failed to allocate space for track: {!}", .{err});
                    std.process.exit(1);
                };
            }
            local_queue.clearRetainingCapacity();
        }
    }

    fn getOrLoad(self: *AudioSystem, filename: [:0]const u8) *Buffer {
        self.cache_m.lock();
        var gop = self.cache.getOrPut(self.allocator, filename) catch |err| {
            log.err("Failed to allocate space in cache: {!}", .{err});
            std.process.exit(1);
        };
        if (gop.found_existing) {
            self.cache_m.unlock();
            return gop.value_ptr.*;
        } else {
            var timer = std.time.Timer.start() catch |err| {
                log.err("Failed to start decode timer: {!}", .{err});
                std.process.exit(1);
            };

            log.info("Sound load start '{s}'", .{filename});
            var ptr = self.allocator.create(Buffer) catch |err| {
                log.err("Failed to allocate audio buffer: {!}", .{err});
                std.process.exit(1);
            };
            gop.value_ptr.* = ptr;
            self.cache_m.unlock();

            loadInto(filename, ptr);
            log.info("Sound load end '{s}' in {d}ms", .{ filename, timer.read() / std.time.ns_per_ms });

            return ptr;
        }
    }

    fn loadInto(filename: [:0]const u8, buffer: *Buffer) void {
        var samples: [*]c_short = undefined;
        const sample_count =
            stb_vorbis.stb_vorbis_decode_filename(
            filename,
            &buffer.channels,
            &buffer.sample_rate,
            &samples,
        );
        buffer.samples = samples;
        buffer.sample_count.store(@intCast(u32, sample_count), .SeqCst);
    }

    fn audioCallback(sys: ?*anyopaque, stream: [*]u8, len: c_int) callconv(.C) void {
        std.mem.set(u8, stream[0..@intCast(usize, len)], 0);
        var self = @ptrCast(*AudioSystem, @alignCast(@alignOf(*AudioSystem), sys));
        self.tracks_m.lock();
        defer self.tracks_m.unlock();

        const data_base = @ptrCast([*]i16, @alignCast(2, stream));

        for (self.tracks.items) |*track| {
            const buffer = track.buffer;
            const volume = track.parameters.volume.load(.SeqCst);

            if (track.parameters.paused.load(.SeqCst)) {
                continue;
            }

            if (buffer.sample_count.load(.SeqCst) == 0) {
                continue;
            }

            var output = data_base;

            var samp: usize = 0;
            while (samp < @divExact(len, 2)) : (samp += 1) {
                if (track.done) {
                    break;
                }

                output[samp] = @intCast(i16, std.math.clamp(
                    @intCast(i32, @intCast(i32, output[samp]) + @floatToInt(i32, @intToFloat(f32, buffer.samples.?[track.cursor]) * volume)),
                    std.math.minInt(i16),
                    std.math.maxInt(i16),
                ));
                track.cursor += 1;

                if (track.cursor == 2 * buffer.sample_count.load(.SeqCst)) {
                    if (track.loop) {
                        track.cursor = 0;
                    } else {
                        track.done = true;
                    }
                }
            }
        }

        // erase finished tracks
        var i: usize = 0;
        while (i < self.tracks.items.len) : (i += 1) {
            if (self.tracks.items[i].done) {
                log.debug("Erase audio track {d}", .{i});
                var t = self.tracks.swapRemove(i);
                t.deinit();
            }
        }
    }

    pub fn playMusic(self: *AudioSystem, filename: [:0]const u8) *AudioParameters {
        const parameters = AudioParameters.create(self.allocator) catch |err| {
            log.err("Failed to create AudioParameters for music: {!}", .{err});
            std.process.exit(1);
        };
        var req = DecodeRequest{
            .filename = filename,
            .loop = true,
            .parameters = parameters,
        };
        self.decode_queue_m.lock();
        self.decode_queue.append(req) catch |err| {
            log.err("Failed to allocate decode queue space: {!}", .{err});
            std.process.exit(1);
        };
        self.decode_queue_m.unlock();
        self.decode_cv.signal();
        return parameters.addRef();
    }

    pub fn playSound(self: *AudioSystem, filename: [:0]const u8) *AudioParameters {
        const parameters = AudioParameters.create(self.allocator) catch |err| {
            log.err("Failed to create AudioParameters for sound: {!}", .{err});
            std.process.exit(1);
        };
        var req = DecodeRequest{
            .filename = filename,
            .loop = false,
            .parameters = parameters,
        };
        self.decode_queue_m.lock();
        self.decode_queue.append(req) catch |err| {
            log.err("Failed to allocate decode queue space: {!}", .{err});
            std.process.exit(1);
        };
        self.decode_queue_m.unlock();
        self.decode_cv.signal();
        return parameters.addRef();
    }

    fn postShutdown(self: *AudioSystem) void {
        const parameters = AudioParameters.create(self.allocator) catch |err| {
            log.err("Failed to create AudioParameters for shutdown: {!}", .{err});
            std.process.exit(1);
        };
        var req = DecodeRequest{
            .filename = "",
            .loop = true,
            .parameters = parameters,
        };
        self.decode_queue_m.lock();
        self.decode_queue.append(req) catch |err| {
            log.err("Failed to allocate decode queue space: {!}", .{err});
            std.process.exit(1);
        };
        self.decode_queue_m.unlock();
        self.decode_cv.signal();
    }
};
