const std = @import("std");
const Allocator = std.mem.Allocator;

const QuadBatch = @import("QuadBatch.zig");

const zm = @import("zmath");
const Rect = @import("Rect.zig");

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
