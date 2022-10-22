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

const FoamDraw = struct {
    dest: Rect,
    left: bool,
    right: bool,
    top: bool,
    bottom: bool,

    fn leftSrc(self: FoamDraw) Rect {
        _ = self;
        return Rect.init(0, 0, 2, 16);
    }
    fn rightSrc(self: FoamDraw) Rect {
        _ = self;
        return Rect.init(16 - 2, 0, 2, 16);
    }
    fn topSrc(self: FoamDraw) Rect {
        _ = self;
        return Rect.init(0, 0, 16, 2);
    }
    fn bottomSrc(self: FoamDraw) Rect {
        _ = self;
        return Rect.init(0, 16 - 2, 16, 2);
    }
    fn leftDest(self: FoamDraw) Rect {
        var d = self.dest;
        d.w = 2;
        return d;
    }
    fn rightDest(self: FoamDraw) Rect {
        var d = self.dest;
        d.x = (d.x + d.w) - 2;
        d.w = 2;
        return d;
    }
    fn topDest(self: FoamDraw) Rect {
        var d = self.dest;
        d.h = 2;
        return d;
    }
    fn bottomDest(self: FoamDraw) Rect {
        var d = self.dest;
        d.y = (d.y + d.h) - 2;
        d.h = 2;
        return d;
    }
};

game: *Game,
map: tilemap.Tilemap = .{},
camera: Camera = DEFAULT_CAMERA,
prev_camera: Camera = DEFAULT_CAMERA,
r_batch: SpriteBatch,
r_water: WaterRenderer,
water_buf: []WaterDraw,
n_water: usize = 0,
foam_buf: []FoamDraw,

pub fn create(game: *Game) !*PlayState {
    var self = try game.allocator.create(PlayState);
    self.* = .{
        .game = game,
        .r_batch = SpriteBatch.create(),
        .r_water = WaterRenderer.create(),
        .water_buf = try game.allocator.alloc(WaterDraw, max_onscreen_tiles),
        .foam_buf = try game.allocator.alloc(FoamDraw, max_onscreen_tiles),
    };
    return self;
}

pub fn destroy(self: *PlayState) void {
    self.game.allocator.free(self.water_buf);
    self.game.allocator.free(self.foam_buf);
    self.r_batch.destroy();
    self.map.deinit(self.game.allocator);
    self.game.allocator.destroy(self);
}

pub fn enter(self: *PlayState, from: ?Game.StateId) void {
    _ = from;
    self.loadTilemapFromJson();
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

fn renderTilemapLayer(
    self: *PlayState,
    layer: tilemap.TileLayer,
    bank: tilemap.TileBank,
    min_tile_x: usize,
    max_tile_x: usize,
    min_tile_y: usize,
    max_tile_y: usize,
    translate_x: i32,
    translate_y: i32,
) void {
    const source_texture = switch (bank) {
        .none => return,
        .terrain => self.game.texman.getNamedTexture("terrain.png"),
        .special => self.game.texman.getNamedTexture("special.png"),
    };
    const source_texture_state = self.game.texman.getTextureState(source_texture);
    const n_tiles_wide = @intCast(u16, source_texture_state.width / 16);
    self.r_batch.begin(SpriteBatch.SpriteBatchParams{
        .texture_manager = &self.game.texman,
        .texture = source_texture,
    });
    var y: usize = min_tile_y;
    var x: usize = 0;
    var ty: u8 = 0;
    while (y < max_tile_y) : (y += 1) {
        x = min_tile_x;
        var tx: u8 = 0;
        while (x < max_tile_x) : (x += 1) {
            const t = self.map.at2DPtr(layer, x, y);
            if (t.isWater()) {
                const dest = Rect{
                    .x = @intCast(i32, x * 16) + translate_x,
                    .y = @intCast(i32, y * 16) + translate_y,
                    .w = 16,
                    .h = 16,
                };
                self.water_buf[self.n_water] = WaterDraw{
                    .dest = dest,
                    .world_xy = zm.f32x4(
                        @intToFloat(f32, x * 16),
                        @intToFloat(f32, y * 16),
                        0,
                        0,
                    ),
                };

                self.foam_buf[self.n_water] = FoamDraw{
                    .dest = dest,
                    .left = x > 0 and self.map.isValidIndex(x - 1, y) and !self.map.at2DPtr(layer, x - 1, y).isWater(),
                    .right = self.map.isValidIndex(x + 1, y) and !self.map.at2DPtr(layer, x + 1, y).isWater(),
                    .top = y > 0 and self.map.isValidIndex(x, y - 1) and !self.map.at2DPtr(layer, x, y - 1).isWater(),
                    .bottom = self.map.isValidIndex(x, y + 1) and !self.map.at2DPtr(layer, x, y + 1).isWater(),
                };
                self.foam_buf[self.n_water].dest.inflate(1, 1);

                self.n_water += 1;
            } else if (t.bank == bank) {
                const src = Rect{
                    .x = (t.id % n_tiles_wide) * 16,
                    .y = (t.id / n_tiles_wide) * 16,
                    .w = 16,
                    .h = 16,
                };
                const dest = Rect{
                    .x = @intCast(i32, x * 16) + translate_x,
                    .y = @intCast(i32, y * 16) + translate_y,
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
}

fn renderTilemap(self: *PlayState, cam: Camera) void {
    self.n_water = 0;

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

    self.r_batch.setOutputDimensions(Game.INTERNAL_WIDTH, Game.INTERNAL_HEIGHT);
    self.renderTilemapLayer(.base, .terrain, min_tile_x, max_tile_x, min_tile_y, max_tile_y, -cam.view.left(), -cam.view.top());
    self.renderTilemapLayer(.base, .special, min_tile_x, max_tile_x, min_tile_y, max_tile_y, -cam.view.left(), -cam.view.top());

    // water_direction, water_drift, speed set on a per-map basis?
    var water_params = WaterRenderer.WaterRendererParams{
        .texture_manager = &self.game.texman,
        .water_base = self.game.texman.getNamedTexture("water.png"),
        .water_blend = self.game.texman.getNamedTexture("water.png"),
        .blend_amount = 0.3,
        .global_time = @intToFloat(f32, self.game.frame_counter) / 30.0,
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
    self.renderTilemapLayer(.detail, .terrain, min_tile_x, max_tile_x, min_tile_y, max_tile_y, -cam.view.left(), -cam.view.top());
    self.renderTilemapLayer(.detail, .special, min_tile_x, max_tile_x, min_tile_y, max_tile_y, -cam.view.left(), -cam.view.top());
}

fn loadTilemapFromJson(self: *PlayState) void {
    self.map = tilemap.loadTilemapFromJson(self.game.allocator, "assets/maps/map01.tmj") catch |err| {
        std.log.err("failed to load tilemap {!}", .{err});
        std.process.exit(1);
    };

    // Init camera for this map

    self.camera.bounds = Rect.init(
        0,
        0,
        @intCast(i32, self.map.width * 16),
        @intCast(i32, self.map.height * 16),
    );
    self.prev_camera = self.camera;
}

fn renderFoam(
    self: *PlayState,
) void {
    const t_foam = self.game.texman.getNamedTexture("water_foam.png");
    self.r_batch.begin(.{
        .texture_manager = &self.game.texman,
        .texture = t_foam,
    });
    for (self.foam_buf[0..self.n_water]) |f| {
        if (f.left) {
            self.r_batch.drawQuad(f.leftSrc(), f.leftDest());
        }
        if (f.top) {
            self.r_batch.drawQuad(f.topSrc(), f.topDest());
        }
        if (f.bottom) {
            self.r_batch.drawQuad(f.bottomSrc(), f.bottomDest());
        }
        if (f.right) {
            self.r_batch.drawQuad(f.rightSrc(), f.rightDest());
        }
    }
    self.r_batch.end();
}
