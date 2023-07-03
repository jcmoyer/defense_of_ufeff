const WorldRenderer = @This();

const Camera = @import("Camera.zig");
const tilemap = @import("tilemap.zig");
const Tilemap = tilemap.Tilemap;
const TileCoord = tilemap.TileCoord;
const TileLayer = tilemap.TileLayer;
const TileBank = tilemap.TileBank;
const TileRange = tilemap.TileRange;
const RenderServices = @import("render.zig").RenderServices;
const Rect = @import("Rect.zig");
const zm = @import("zmath");
const std = @import("std");
const Game = @import("Game.zig");
const WaterRenderer = @import("WaterRenderer.zig");
const anim = @import("animation.zig");

const max_onscreen_tiles = 33 * 17;

renderers: *RenderServices,
r_water: WaterRenderer,
water_buf: []WaterDraw,
n_water: usize = 0,
foam_buf: []FoamDraw,

foam_anim_l: anim.Animator,
foam_anim_r: anim.Animator,
foam_anim_u: anim.Animator,
foam_anim_d: anim.Animator,
heart_anim: anim.Animator = anim.a_goal_heart.animationSet().createAnimator("default"),

const WaterDraw = struct {
    dest: Rect,
    world_xy: zm.Vec,
};

const FoamDraw = struct {
    dest: Rect,
    left: bool,
    right: bool,
    top: bool,
    bottom: bool,
};

pub fn create(allocator: std.mem.Allocator, renderers: *RenderServices) !*WorldRenderer {
    var self = try allocator.create(WorldRenderer);
    errdefer allocator.destroy(self);

    self.* = .{
        .renderers = renderers,
        // Initialized below
        .r_water = undefined,
        .water_buf = undefined,
        .foam_buf = undefined,
        .foam_anim_l = undefined,
        .foam_anim_r = undefined,
        .foam_anim_u = undefined,
        .foam_anim_d = undefined,
    };

    self.water_buf = try allocator.alloc(WaterDraw, max_onscreen_tiles);
    errdefer allocator.free(self.water_buf);

    self.foam_buf = try allocator.alloc(FoamDraw, max_onscreen_tiles);
    errdefer allocator.free(self.foam_buf);

    self.r_water = WaterRenderer.create();
    errdefer self.r_water.destroy();

    self.foam_anim_l = anim.a_foam.animationSet().createAnimator("l");
    self.foam_anim_r = anim.a_foam.animationSet().createAnimator("r");
    self.foam_anim_u = anim.a_foam.animationSet().createAnimator("u");
    self.foam_anim_d = anim.a_foam.animationSet().createAnimator("d");

    return self;
}

pub fn destroy(self: *WorldRenderer, allocator: std.mem.Allocator) void {
    self.r_water.destroy();
    allocator.free(self.water_buf);
    allocator.free(self.foam_buf);
    allocator.destroy(self);
}

pub fn updateAnimations(self: *WorldRenderer) void {
    self.foam_anim_l.update();
    self.foam_anim_r.update();
    self.foam_anim_u.update();
    self.foam_anim_d.update();
    self.heart_anim.update();
}

fn renderTilemapLayer(
    self: *WorldRenderer,
    map: *const Tilemap,
    layer: TileLayer,
    bank: TileBank,
    range: TileRange,
    translate_x: i32,
    translate_y: i32,
) void {
    const source_texture = switch (bank) {
        .none => return,
        .terrain => self.renderers.texman.getNamedTexture("terrain.png"),
        .special => self.renderers.texman.getNamedTexture("special.png"),
    };
    const n_tiles_wide = @as(u16, @intCast(source_texture.width / 16));
    self.renderers.r_batch.begin(.{
        .texture = source_texture,
    });
    var y: usize = range.min.y;
    var x: usize = 0;
    var ty: u8 = 0;
    while (y < range.max.y) : (y += 1) {
        x = range.min.x;
        var tx: u8 = 0;
        while (x < range.max.x) : (x += 1) {
            const t = map.at2DPtr(layer, x, y);
            // filter tiles to selected bank
            if (t.bank != bank) {
                continue;
            }
            if (t.isWater()) {
                const dest = Rect{
                    .x = @as(i32, @intCast(x * 16)) + translate_x,
                    .y = @as(i32, @intCast(y * 16)) + translate_y,
                    .w = 16,
                    .h = 16,
                };
                self.water_buf[self.n_water] = WaterDraw{
                    .dest = dest,
                    .world_xy = zm.f32x4(
                        @as(f32, @floatFromInt(x * 16)),
                        @as(f32, @floatFromInt(y * 16)),
                        0,
                        0,
                    ),
                };

                self.foam_buf[self.n_water] = FoamDraw{
                    .dest = dest,
                    .left = x > 0 and map.isValidIndex(x - 1, y) and !map.at2DPtr(layer, x - 1, y).isWater(),
                    .right = map.isValidIndex(x + 1, y) and !map.at2DPtr(layer, x + 1, y).isWater(),
                    .top = y > 0 and map.isValidIndex(x, y - 1) and !map.at2DPtr(layer, x, y - 1).isWater(),
                    .bottom = map.isValidIndex(x, y + 1) and !map.at2DPtr(layer, x, y + 1).isWater(),
                };
                // self.foam_buf[self.n_water].dest.inflate(1, 1);

                self.n_water += 1;
            } else {
                const src = Rect{
                    .x = (t.id % n_tiles_wide) * 16,
                    .y = (t.id / n_tiles_wide) * 16,
                    .w = 16,
                    .h = 16,
                };
                const dest = Rect{
                    .x = @as(i32, @intCast(x * 16)) + translate_x,
                    .y = @as(i32, @intCast(y * 16)) + translate_y,
                    .w = 16,
                    .h = 16,
                };
                self.renderers.r_batch.drawQuad(.{
                    .src = src.toRectf(),
                    .dest = dest.toRectf(),
                });
            }
            tx += 1;
        }
        ty += 1;
    }
    self.renderers.r_batch.end();
}

pub fn renderTilemap(self: *WorldRenderer, cam: Camera, map: *const Tilemap, frame_count: u64) void {
    self.n_water = 0;

    const min_tile_x = @as(usize, @intCast(cam.view.left())) / 16;
    const min_tile_y = @as(usize, @intCast(cam.view.top())) / 16;
    const max_tile_x = @min(
        map.width,
        // +1 to account for partially transparent UI panel
        1 + 1 + @as(usize, @intCast(cam.view.right())) / 16,
    );
    const max_tile_y = @min(
        map.height,
        1 + @as(usize, @intCast(cam.view.bottom())) / 16,
    );
    const range = TileRange{
        .min = TileCoord{ .x = @as(u16, @intCast(min_tile_x)), .y = @as(u16, @intCast(min_tile_y)) },
        .max = TileCoord{ .x = @as(u16, @intCast(max_tile_x)), .y = @as(u16, @intCast(max_tile_y)) },
    };

    self.renderers.r_batch.setOutputDimensions(Game.INTERNAL_WIDTH, Game.INTERNAL_HEIGHT);
    self.renderTilemapLayer(map, .base, .terrain, range, -cam.view.left(), -cam.view.top());
    self.renderTilemapLayer(map, .base, .special, range, -cam.view.left(), -cam.view.top());

    // water_direction, water_drift, speed set on a per-map basis?
    var water_params = WaterRenderer.WaterRendererParams{
        .water_base = self.renderers.texman.getNamedTexture("water.png"),
        .water_blend = self.renderers.texman.getNamedTexture("water.png"),
        .blend_amount = 0.3,
        .global_time = @as(f32, @floatFromInt(frame_count)) / 30.0,
        .water_direction = zm.f32x4(0.3, 0.2, 0, 0),
        .water_drift_range = zm.f32x4(0.2, 0.05, 0, 0),
        .water_drift_scale = zm.f32x4(32, 16, 0, 0),
        .water_speed = 1,
    };

    self.r_water.setOutputDimensions(Game.INTERNAL_WIDTH, Game.INTERNAL_HEIGHT);
    self.r_water.begin(water_params);
    for (self.water_buf[0..self.n_water]) |cmd| {
        self.r_water.drawQuad(cmd.dest, cmd.world_xy);
    }
    self.r_water.end();

    // render foam
    self.renderFoam();

    // detail layer rendered on top of water
    self.renderTilemapLayer(map, .detail, .terrain, range, -cam.view.left(), -cam.view.top());
    self.renderTilemapLayer(map, .detail, .special, range, -cam.view.left(), -cam.view.top());
}

fn renderFoam(
    self: *WorldRenderer,
) void {
    const t_foam = self.renderers.texman.getNamedTexture("water_foam.png");
    const l_rectf = self.foam_anim_l.getCurrentRect().toRectf();
    const r_rectf = self.foam_anim_r.getCurrentRect().toRectf();
    const u_rectf = self.foam_anim_u.getCurrentRect().toRectf();
    const d_rectf = self.foam_anim_d.getCurrentRect().toRectf();
    self.renderers.r_batch.begin(.{
        .texture = t_foam,
    });
    for (self.foam_buf[0..self.n_water]) |f| {
        const destf = f.dest.toRectf();
        if (f.left) {
            self.renderers.r_batch.drawQuad(.{ .src = l_rectf, .dest = destf });
        }
        if (f.top) {
            self.renderers.r_batch.drawQuad(.{ .src = u_rectf, .dest = destf });
        }
        if (f.bottom) {
            self.renderers.r_batch.drawQuad(.{ .src = d_rectf, .dest = destf });
        }
        if (f.right) {
            self.renderers.r_batch.drawQuad(.{ .src = r_rectf, .dest = destf });
        }
    }
    self.renderers.r_batch.end();
}
