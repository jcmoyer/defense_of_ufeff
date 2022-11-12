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

pub const AudioParameters = struct {
    allocator: Allocator,
    refcount: std.atomic.Atomic(u32) = .{ .value = 1 },
    volume: std.atomic.Atomic(f32) = .{ .value = 1 },
    pan: std.atomic.Atomic(f32) = .{ .value = 0.5 },
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
    shutdown: bool,
};

pub const AudioOptions = struct {
    initial_volume: f32 = 1,
    initial_pan: f32 = 0.5,
};

const AudioDecodeThread = struct {
    thread: std.Thread,
    queue_m: std.Thread.Mutex = .{},
    queue: std.ArrayListUnmanaged(DecodeRequest) = .{},
    cv: std.Thread.Condition = .{},
    allocator: Allocator,
    system: *AudioSystem,

    fn spawn(self: *AudioDecodeThread, system: *AudioSystem) !void {
        self.* = .{
            .system = system,
            .allocator = system.allocator,
            .thread = undefined,
        };
        self.thread = try std.Thread.spawn(.{}, loop, .{self});
    }

    fn deinit(self: *AudioDecodeThread) void {
        self.queue.deinit(self.allocator);
    }

    fn postRequest(self: *AudioDecodeThread, req: DecodeRequest) void {
        self.queue_m.lock();
        self.queue.append(self.allocator, req) catch |err| {
            log.err("Failed to allocate decode queue space: {!}", .{err});
            std.process.exit(1);
        };
        self.queue_m.unlock();
        self.cv.signal();
    }

    fn postShutdown(self: *AudioDecodeThread) void {
        self.postRequest(DecodeRequest{
            .filename = "",
            .loop = true,
            .parameters = undefined,
            .shutdown = true,
        });
    }

    fn join(self: *AudioDecodeThread) void {
        self.thread.join();
    }

    fn loop(self: *AudioDecodeThread) void {
        var local_queue = std.ArrayListUnmanaged(DecodeRequest){};
        defer {
            for (local_queue.items) |*req| {
                if (!req.shutdown)
                    req.parameters.release();
            }
            local_queue.deinit(self.allocator);
        }

        while (true) {
            self.queue_m.lock();
            // go to sleep until there are items to process
            while (self.queue.items.len == 0) {
                self.cv.wait(&self.queue_m);
            }
            // we have the lock here, quickly take the queue and release
            std.mem.swap(
                std.ArrayListUnmanaged(DecodeRequest),
                &local_queue,
                &self.queue,
            );
            self.queue_m.unlock();

            // now we can load the requests and put them into the tracklist
            while (local_queue.popOrNull()) |req| {
                // empty filename kills the thread
                if (req.shutdown) {
                    return;
                }
                const t = Track{
                    .buffer = self.system.getOrLoad(req.filename),
                    .loop = req.loop,
                    .parameters = req.parameters,
                };
                self.system.tracks_m.lock();
                defer self.system.tracks_m.unlock();
                self.system.tracks.append(self.system.allocator, t) catch |err| {
                    log.err("Failed to allocate space for track: {!}", .{err});
                    std.process.exit(1);
                };
            }
        }
    }
};

pub const AudioSystem = struct {
    pub var instance: *AudioSystem = undefined;

    allocator: Allocator,

    device: sdl.SDL_AudioDeviceID,
    spec: sdl.SDL_AudioSpec,

    tracks_m: std.Thread.Mutex = .{},
    tracks: std.ArrayListUnmanaged(Track) = .{},

    cache_m: std.Thread.Mutex = .{},
    cache: std.StringArrayHashMapUnmanaged(*Buffer) = .{},

    sound_thread: AudioDecodeThread,
    music_thread: AudioDecodeThread,

    pub fn create(allocator: Allocator) *AudioSystem {
        const self = allocator.create(AudioSystem) catch |err| {
            log.err("Failed to spawn audio decode thread: {!}", .{err});
            std.process.exit(1);
        };
        instance = self;
        self.* = AudioSystem{
            .allocator = allocator,
            // Initialized below
            .spec = undefined,
            .sound_thread = undefined,
            .music_thread = undefined,
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

        AudioDecodeThread.spawn(&self.sound_thread, self) catch |err| {
            log.err("Failed to spawn sound thread: {!}", .{err});
            std.process.exit(1);
        };

        AudioDecodeThread.spawn(&self.music_thread, self) catch |err| {
            log.err("Failed to spawn sound thread: {!}", .{err});
            std.process.exit(1);
        };

        return self;
    }

    pub fn destroy(self: *AudioSystem) void {
        sdl.SDL_CloseAudioDevice(self.device);

        self.postShutdown();
        self.sound_thread.join();
        self.sound_thread.deinit();
        self.music_thread.join();
        self.music_thread.deinit();
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
            ptr.* = .{};
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

    fn fillBuffer(self: *AudioSystem, buffer: []i16) void {
        // buffer is uninitialized; zero to silence
        std.mem.set(i16, buffer, 0);

        self.tracks_m.lock();
        defer self.tracks_m.unlock();

        for (self.tracks.items) |*track| {
            const input_buffer = track.buffer;
            const volume = track.parameters.volume.load(.SeqCst);
            const pan = track.parameters.pan.load(.SeqCst);

            if (track.parameters.paused.load(.SeqCst)) {
                continue;
            }

            if (input_buffer.sample_count.load(.SeqCst) == 0) {
                continue;
            }

            // Next loop is hot, so hoist the atomic load out to this point.
            // NOTE: We always multiply by 2 because we assume all sounds are
            // stereo. This may need to change in the future.
            const buffer_sample_count = 2 * input_buffer.sample_count.load(.SeqCst);

            const m_left = 1 - pan;
            const m_right = pan;

            var i: usize = 0;
            while (i < buffer.len) : (i += 2) {
                if (track.done) {
                    break;
                }

                const output_left = &buffer[i];
                const output_right = &buffer[i + 1];
                const input_left = input_buffer.samples.?[track.cursor];
                const input_right = input_buffer.samples.?[track.cursor + 1];

                std.debug.assert(m_left >= 0 and m_left <= 1);
                std.debug.assert(m_right >= 0 and m_right <= 1);
                std.debug.assert(volume >= 0 and volume <= 1);

                output_left.* +|= @intCast(i16, (@floatToInt(i32, @intToFloat(f32, input_left) * volume * m_left)));
                output_right.* +|= @intCast(i16, (@floatToInt(i32, @intToFloat(f32, input_right) * volume * m_right)));

                track.cursor += 2;
                if (track.cursor == buffer_sample_count) {
                    if (track.loop) {
                        track.cursor = 0;
                    } else {
                        track.done = true;
                    }
                }
            }
        }

        // erase finished tracks
        var i: usize = self.tracks.items.len -% 1;
        while (i < self.tracks.items.len) {
            if (self.tracks.items[i].done or self.tracks.items[i].parameters.done.load(.SeqCst)) {
                var t = self.tracks.swapRemove(i);
                t.deinit();
            } else {
                i -%= 1;
            }
        }
    }

    fn audioCallback(sys: ?*anyopaque, stream: [*]u8, len: c_int) callconv(.C) void {
        var self = @ptrCast(*AudioSystem, @alignCast(@alignOf(*AudioSystem), sys));
        const stream_bytes = stream[0..@intCast(usize, len)];
        self.fillBuffer(
            std.mem.bytesAsSlice(i16, @alignCast(@sizeOf(i16), stream_bytes)),
        );
    }

    pub fn playMusic(self: *AudioSystem, filename: [:0]const u8, opts: AudioOptions) *AudioParameters {
        const parameters = AudioParameters.create(self.allocator) catch |err| {
            log.err("Failed to create AudioParameters for music: {!}", .{err});
            std.process.exit(1);
        };
        parameters.volume.storeUnchecked(opts.initial_volume);
        parameters.pan.storeUnchecked(opts.initial_pan);
        var req = DecodeRequest{
            .filename = filename,
            .loop = true,
            .parameters = parameters,
            .shutdown = false,
        };
        self.music_thread.postRequest(req);
        return parameters.addRef();
    }

    pub fn playSound(self: *AudioSystem, filename: [:0]const u8, opts: AudioOptions) *AudioParameters {
        const parameters = AudioParameters.create(self.allocator) catch |err| {
            log.err("Failed to create AudioParameters for sound: {!}", .{err});
            std.process.exit(1);
        };
        parameters.volume.storeUnchecked(opts.initial_volume);
        parameters.pan.storeUnchecked(opts.initial_pan);
        var req = DecodeRequest{
            .filename = filename,
            .loop = false,
            .parameters = parameters,
            .shutdown = false,
        };
        self.sound_thread.postRequest(req);
        return parameters.addRef();
    }

    fn postShutdown(self: *AudioSystem) void {
        self.music_thread.postShutdown();
        self.sound_thread.postShutdown();
    }
};

const Rect = @import("Rect.zig");
const mathutil = @import("mathutil.zig");
const zm = @import("zmath");

pub fn computePositionalOptions(view: Rect, audio_position: [2]i32) AudioOptions {
    const V2 = @Vector(2, f32);

    const view_center = view.centerPoint();
    const theta = mathutil.angleBetween(
        V2{ @intToFloat(f32, view_center[0]), @intToFloat(f32, view_center[1]) },
        V2{ @intToFloat(f32, audio_position[0]), @intToFloat(f32, audio_position[1]) },
    );

    // cosine except shifted from -1..1 to 0..1
    const cos_shift = 0.5 * (1.0 + std.math.cos(theta));

    const d_center = mathutil.dist(view.centerPoint(), audio_position);
    const d_edge = @intToFloat(f32, view.w);
    // normalized distance to edge of view, 0 = right in center, 1 = at edge
    const d_norm = std.math.clamp(d_center / d_edge, 0, 1);
    const volume = std.math.clamp(0.9 - d_norm, 0, 1);
    const pan = zm.lerpV(0.5, cos_shift, d_norm);

    return .{
        .initial_pan = pan,
        .initial_volume = volume,
    };
}
