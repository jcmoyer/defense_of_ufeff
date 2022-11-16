const std = @import("std");
const Allocator = std.mem.Allocator;

const QuadBatch = @import("QuadBatch.zig");

const zm = @import("zmath");
const mu = @import("mathutil.zig");
const Rect = @import("Rect.zig");
const timing = @import("timing.zig");

const V2 = @Vector(2, f32);

pub const Particle = struct {
    pos: [2]@Vector(2, f32) = [2]@Vector(2, f32){ @splat(2, @as(f32, 0)), @splat(2, @as(f32, 0)) },
    vel: @Vector(2, f32) = @splat(2, @as(f32, 0)),
    size: f32 = 0,
    alive: bool = false,
    frames_alive: u32 = 0,
    color_r: u8 = 255,
    color_g: u8 = 255,
    color_b: u8 = 255,
    color_a: u8 = 255,

    updateFn: *const fn (*Particle) void = nopUpdate,

    pub fn nopUpdate(_: *Particle) void {}
};

pub const ParticleV2 = struct {
    prev_pos: [2]f32 = .{ 0, 0 },
    pos: [2]f32 = .{ 0, 0 },
    vel: [2]f32 = .{ 0, 0 },
    acc: [2]f32 = .{ 0, 0 },
    rgba: [4]u8 = .{ 255, 255, 255, 255 },
    scale: f32 = 1,
    life: timing.FrameTimer = .{},
    kind: ParticleKind = .color,
    alive: bool = false,
};

pub const ParticleKind = enum(u8) {
    color,
    fire,
};

pub const CircleEmitter = struct {
    parent: *ParticleSystem,
    pos: [2]f32 = .{ 0, 0 },
    radius: f32,

    pub fn emit(self: *CircleEmitter, kind: ParticleKind, frame: u64) void {
        var rand = self.parent.rng.random();
        const vx = rand.float(f32) - 0.5;
        const vy = -rand.float(f32);

        const a = rand.float(f32) * std.math.tau;
        const m = rand.float(f32) * self.radius;
        const dx = std.math.cos(a) * m;
        const dy = std.math.sin(a) * m;

        self.parent.addParticle(.{
            .pos = @bitCast(V2, self.pos) + V2{ dx, dy },
            .vel = .{ vx, vy },
            .alive = true,
            .kind = kind,
            .life = timing.FrameTimer.initSeconds(frame, 1),
        });
    }
};

pub const ParticleSystem = struct {
    allocator: Allocator,
    particles: std.MultiArrayList(ParticleV2) = .{},
    capacity: usize,
    num_alive: usize = 0,
    rng: std.rand.DefaultPrng,

    pub fn initCapacity(allocator: Allocator, capacity: usize) !ParticleSystem {
        std.debug.assert(capacity % 16 == 0);
        var self: ParticleSystem = .{
            .allocator = allocator,
            .capacity = capacity,
            .rng = std.rand.DefaultPrng.init(@intCast(u64, std.time.milliTimestamp())),
        };
        try self.particles.resize(allocator, capacity);
        var i: usize = 0;
        while (i < self.particles.len) : (i += 1) {
            self.particles.set(i, .{});
        }
        return self;
    }

    pub fn deinit(self: *ParticleSystem) void {
        self.particles.deinit(self.allocator);
    }

    pub fn addParticle(self: *ParticleSystem, p: ParticleV2) void {
        if (self.num_alive < self.capacity) {
            self.particles.set(self.num_alive, p);
            self.num_alive += 1;
        }
    }

    pub fn clear(self: *ParticleSystem) void {
        self.num_alive = 0;
    }

    pub fn update(self: *ParticleSystem, frame: u64) void {
        std.mem.copy(
            [2]f32,
            self.particles.items(.prev_pos)[0..self.num_alive],
            self.particles.items(.pos)[0..self.num_alive],
        );

        var i: usize = 0;
        while (i < self.num_alive) {
            if (self.particles.items(.life)[i].expired(frame)) {
                self.particles.items(.alive)[i] = false;
                const this = self.particles.get(i);
                const last = self.particles.get(self.num_alive - 1);
                self.particles.set(self.num_alive - 1, this);
                self.particles.set(i, last);
                self.num_alive -= 1;
            } else {
                self.particles.items(.pos)[i] = @bitCast(V2, self.particles.items(.pos)[i]) + @bitCast(V2, self.particles.items(.vel)[i]);
                self.particles.items(.vel)[i] = @bitCast(V2, self.particles.items(.vel)[i]) + @bitCast(V2, self.particles.items(.acc)[i]);

                // TODO: non-hardcoded animation
                const a = self.particles.items(.life)[i].invProgressClamped(frame) * 255.0;
                const rgba = self.particles.items(.rgba)[i];
                self.particles.items(.rgba)[i] = .{
                    rgba[0],
                    rgba[1],
                    rgba[2],
                    mu.colorMulU8Scalar(rgba[3], @floatToInt(u8, a)),
                };
                const s = self.particles.items(.life)[i].invProgressClamped(frame);
                self.particles.items(.scale)[i] = s;

                i += 1;
            }
        }
    }
};

pub const GeneratorContext = struct {
    userdata: ?*anyopaque = null,
    index: usize,
    count: usize,
};

pub const GeneratorFn = *const fn (output: *Particle, ctx: *const GeneratorContext) void;

pub const Emitter = struct {
    head: usize = 0,
    particles: []Particle,
    pos: @Vector(2, f32) = @splat(2, @as(f32, 0)),

    pub fn initCapacity(allocator: Allocator, capacity: usize) !Emitter {
        var slice = try allocator.alloc(Particle, capacity);
        std.mem.set(Particle, slice, .{});

        return Emitter{
            .particles = slice,
        };
    }

    pub fn deinit(self: *Emitter, allocator: Allocator) void {
        allocator.free(self.particles);
    }

    pub fn emitFunc(self: *Emitter, count: usize, f: GeneratorFn, userdata: ?*anyopaque) void {
        var ctx = GeneratorContext{
            .userdata = userdata,
            .index = 0,
            .count = count,
        };
        while (ctx.index < count) : (ctx.index += 1) {
            var ptr = &self.particles[self.head];
            ptr.* = .{
                .alive = true,
            };
            f(ptr, &ctx);
            self.head = (self.head + 1) % self.particles.len;
        }
    }

    pub fn update(self: *Emitter) void {
        for (self.particles) |*p| {
            if (!p.alive) {
                continue;
            }

            p.updateFn(p);

            p.frames_alive += 1;
            p.pos[0] = p.pos[1];
            p.pos[1] += p.vel;
        }
    }

    pub fn render(self: Emitter, r_quad: *QuadBatch, a: f32) void {
        r_quad.begin(.{});

        for (self.particles) |*p| {
            if (!p.alive) {
                continue;
            }

            var pos = zm.lerp(p.pos[0], p.pos[1], a);
            pos -= @splat(2, p.size / 2);
            pos += self.pos;

            r_quad.drawQuadRGBA(
                Rect.init(
                    @floatToInt(i32, pos[0]),
                    @floatToInt(i32, pos[1]),
                    @floatToInt(i32, p.size),
                    @floatToInt(i32, p.size),
                ),
                p.color_r,
                p.color_g,
                p.color_b,
                p.color_a,
            );
        }

        r_quad.end();
    }
};
