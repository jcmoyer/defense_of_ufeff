const PlayState = @This();

const std = @import("std");
const Game = @import("Game.zig");
const gl = @import("gl33.zig");
const tilemap = @import("tilemap.zig");
const Rect = @import("Rect.zig");
const Camera = @import("Camera.zig");
const SpriteBatch = @import("SpriteBatch.zig");
const WaterRenderer = @import("WaterRenderer.zig");
const zm = @import("zmath");

const DEFAULT_CAMERA = Camera{
    .view = Rect.init(0, 0, Game.INTERNAL_WIDTH, Game.INTERNAL_HEIGHT),
};
const max_onscreen_tiles = 33 * 17;

const WaterDraw = struct {
    dest: Rect,
    world_xy: zm.Vec,
};

game: *Game,
map: tilemap.Tilemap = .{},
camera: Camera = DEFAULT_CAMERA,
prev_camera: Camera = DEFAULT_CAMERA,
r_batch: SpriteBatch,
r_water: WaterRenderer,
water_buf: []WaterDraw,

pub fn create(game: *Game) !*PlayState {
    var self = try game.allocator.create(PlayState);
    self.* = .{
        .game = game,
        .r_batch = SpriteBatch.create(),
        .r_water = WaterRenderer.create(),
        .water_buf = try game.allocator.alloc(WaterDraw, max_onscreen_tiles),
    };
    return self;
}

pub fn destroy(self: *PlayState) void {
    self.game.allocator.free(self.water_buf);
    self.r_batch.destroy();
    self.map.deinit(self.game.allocator);
    self.game.allocator.destroy(self);
}

pub fn enter(self: *PlayState, from: ?Game.StateId) void {
    _ = from;

    self.map = tilemap.loadTilemapFromJson(self.game.allocator, "assets/maps/map01.tmj") catch |err| {
        std.log.err("failed to load tilemap {!}", .{err});
        std.process.exit(1);
    };
    self.camera.bounds = Rect.init(
        0,
        0,
        @intCast(i32, self.map.width * 16),
        @intCast(i32, self.map.height * 16),
    );
    self.prev_camera = self.camera;
}

pub fn leave(self: *PlayState, to: ?Game.StateId) void {
    _ = self;
    _ = to;
}

pub fn update(self: *PlayState) void {
    self.prev_camera = self.camera;
    // self.camera.view.x += 1;
    // self.camera.view.y += 1;
}

pub fn render(self: *PlayState, alpha: f64) void {
    gl.clearColor(0x64.0 / 255.0, 0x95.0 / 255.0, 0xED.0 / 255.0, 1);
    gl.clear(gl.COLOR_BUFFER_BIT);

    var cam_interp = Camera.lerp(self.prev_camera, self.camera, alpha);
    cam_interp.clampToBounds();

    self.renderTilemap(cam_interp);
}

fn renderTilemap(self: *PlayState, cam: Camera) void {
    var n_water: usize = 0;
    const min_tile_x = @intCast(usize, cam.view.left()) / 16;
    const min_tile_y = @intCast(usize, cam.view.top()) / 16;
    const max_tile_x = std.math.min(
        self.map.width,
        1 + @intCast(usize, cam.view.right()) / 16,
    );
    const max_tile_y = std.math.min(
        self.map.height,
        1 + @intCast(usize, cam.view.bottom()) / 16,
    );

    var y: usize = min_tile_y;
    var x: usize = 0;

    self.r_batch.begin(SpriteBatch.SpriteBatchParams{
        .texture_manager = &self.game.texman,
        .texture = self.game.texman.getNamedTexture("terrain.png"),
    });
    self.r_batch.setOutputDimensions(Game.INTERNAL_WIDTH, Game.INTERNAL_HEIGHT);

    var ty: u8 = 0;
    while (y < max_tile_y) : (y += 1) {
        x = min_tile_x;
        var tx: u8 = 0;
        while (x < max_tile_x) : (x += 1) {
            const t = self.map.at2DPtr(x, y);
            if (t.isWater()) {
                const dest = Rect{
                    .x = @intCast(i32, x * 16) - cam.view.left(),
                    .y = @intCast(i32, y * 16) - cam.view.top(),
                    .w = 16,
                    .h = 16,
                };
                self.water_buf[n_water] = WaterDraw{
                    .dest = dest,
                    .world_xy = zm.f32x4(
                        @intToFloat(f32, x * 16),
                        @intToFloat(f32, y * 16),
                        0,
                        0,
                    ),
                };
                n_water += 1;
            } else if (t.bank == .terrain) {
                const src = Rect{
                    .x = (t.id % 32) * 16,
                    .y = (t.id / 32) * 16,
                    .w = 16,
                    .h = 16,
                };
                const dest = Rect{
                    .x = @intCast(i32, x * 16) - cam.view.left(),
                    .y = @intCast(i32, y * 16) - cam.view.top(),
                    .w = 16,
                    .h = 16,
                };
                self.r_batch.drawQuad(
                    src,
                    dest,
                );
            }
            tx += 1;
        }
        ty += 1;
    }

    self.r_batch.end();

    // water_direction, water_drift, speed set on a per-map basis?
    var water_params = WaterRenderer.WaterRendererParams{
        .texture_manager = &self.game.texman,
        .water_base = self.game.texman.getNamedTexture("water.png"),
        .water_blend = self.game.texman.getNamedTexture("water.png"),
        .blend_amount = 0.5,
        .global_time = @intToFloat(f32, self.game.frame_counter) / 30.0,
        .water_direction = zm.f32x4(0.3, 0.2, 0, 0),
        .water_drift_range = zm.f32x4(0.3, 0.2, 0, 0),
        .water_drift_scale = zm.f32x4(32, 16, 0, 0),
        .water_speed = 1,
    };

    self.r_water.setOutputDimensions(Game.INTERNAL_WIDTH, Game.INTERNAL_HEIGHT);
    self.r_water.begin(water_params);
    for (self.water_buf[0..n_water]) |cmd| {
        self.r_water.drawQuad(cmd.dest, cmd.world_xy);
    }
    self.r_water.end();
}
