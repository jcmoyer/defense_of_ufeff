const std = @import("std");
const Allocator = std.mem.Allocator;

const QuadBatch = @import("QuadBatch.zig");

const zm = @import("zmath");
const mu = @import("mathutil.zig");
const Rect = @import("Rect.zig");
const timing = @import("timing.zig");

const V2 = @Vector(2, f32);

pub const ParticleV2 = struct {
    prev_pos: [2]f32 = .{ 0, 0 },
    pos: [2]f32 = .{ 0, 0 },
    vel: [2]f32 = .{ 0, 0 },
    damp_vel: [2]f32 = .{ 0, 0 },
    acc: [2]f32 = .{ 0, 0 },
    rgba: [4]u8 = .{ 255, 255, 255, 255 },
    prev_scale: f32 = 1,
    scale: f32 = 1,
    prev_rotation: f32 = 0,
    rotation: f32 = 0,
    angular_vel: f32 = 0,
    life: timing.FrameTimer = .{},
    kind: ParticleKind = .color,
    alive: bool = false,
};

pub const ParticleKind = enum(u8) {
    color,
    fire,
    warp,
    frost,
};

pub const EmissionParams = struct {
    vel_x_range: [2]f32 = .{ -1, 1 },
    vel_y_range: [2]f32 = .{ -1, 1 },
    accel_x_range: [2]f32 = .{ 0, 0 },
    accel_y_range: [2]f32 = .{ 0, 0 },
    life_range: [2]f32 = .{ 1, 1 },
    damp_vel_x_range: [2]f32 = .{ 1, 1 },
    damp_vel_y_range: [2]f32 = .{ 1, 1 },
    angular_vel_range: [2]f32 = .{ 0, 0 },
};

pub const warp_params = EmissionParams{
    .vel_x_range = .{ -5, 5 },
    .vel_y_range = .{ 0, -5 },
    .accel_y_range = .{ -0.4, 0 },
    .damp_vel_x_range = .{ 0.5, 0.7 },
    .damp_vel_y_range = .{ 0.45, 0.6 },
    .angular_vel_range = .{ 0.0, 0.3 },
    .life_range = .{ 1.5, 2.5 },
};

pub const PointEmitter = struct {
    parent: *ParticleSystem,
    pos: [2]f32 = .{ 0, 0 },
    params: EmissionParams = .{},

    pub fn emit(self: *PointEmitter, kind: ParticleKind, frame: u64) void {
        var rand = self.parent.rng.random();

        const ax = zm.lerpV(self.params.accel_x_range[0], self.params.accel_x_range[1], rand.float(f32));
        const ay = zm.lerpV(self.params.accel_y_range[0], self.params.accel_y_range[1], rand.float(f32));
        const vx = zm.lerpV(self.params.vel_x_range[0], self.params.vel_x_range[1], rand.float(f32));
        const vy = zm.lerpV(self.params.vel_y_range[0], self.params.vel_y_range[1], rand.float(f32));
        const life_sec = zm.lerpV(self.params.life_range[0], self.params.life_range[1], rand.float(f32));
        const dvx = zm.lerpV(self.params.damp_vel_x_range[0], self.params.damp_vel_x_range[1], rand.float(f32));
        const dvy = zm.lerpV(self.params.damp_vel_y_range[0], self.params.damp_vel_y_range[1], rand.float(f32));
        const av = zm.lerpV(self.params.angular_vel_range[0], self.params.angular_vel_range[1], rand.float(f32));

        self.parent.addParticle(.{
            .pos = self.pos,
            .acc = .{ ax, ay },
            .vel = .{ vx, vy },
            .damp_vel = .{ dvx, dvy },
            .angular_vel = av,
            .alive = true,
            .kind = kind,
            .life = timing.FrameTimer.initSeconds(frame, life_sec),
        });
    }

    pub fn emitCount(self: *PointEmitter, kind: ParticleKind, frame: u64, count: u16) void {
        var i: u16 = 0;
        while (i < count) : (i += 1) {
            self.emit(kind, frame);
        }
    }
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
        std.mem.copy(
            f32,
            self.particles.items(.prev_rotation)[0..self.num_alive],
            self.particles.items(.rotation)[0..self.num_alive],
        );
        std.mem.copy(
            f32,
            self.particles.items(.prev_scale)[0..self.num_alive],
            self.particles.items(.scale)[0..self.num_alive],
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
                self.particles.items(.vel)[i] = (@bitCast(V2, self.particles.items(.vel)[i]) + @bitCast(V2, self.particles.items(.acc)[i])) * @bitCast(V2, self.particles.items(.damp_vel)[i]);
                self.particles.items(.rotation)[i] = self.particles.items(.rotation)[i] + self.particles.items(.angular_vel)[i];

                // TODO: non-hardcoded animation
                const a = self.particles.items(.life)[i].invProgressClamped(frame) * 255.0;
                const rgba = self.particles.items(.rgba)[i];
                self.particles.items(.rgba)[i] = .{
                    rgba[0],
                    rgba[1],
                    rgba[2],
                    @floatToInt(u8, a),
                };
                const s = self.particles.items(.life)[i].invProgressClamped(frame);
                self.particles.items(.scale)[i] = s;

                i += 1;
            }
        }
    }
};
