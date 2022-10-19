const PlayState = @This();

const std = @import("std");
const Game = @import("Game.zig");
const gl = @import("gl33.zig");
const tilemap = @import("tilemap.zig");
const Rect = @import("Rect.zig");
const Camera = @import("Camera.zig");

const DEFAULT_CAMERA = Camera{
    .view = Rect.init(0, 0, Game.INTERNAL_WIDTH, Game.INTERNAL_HEIGHT),
};

game: *Game,
map: tilemap.Tilemap = .{},
camera: Camera = DEFAULT_CAMERA,
prev_camera: Camera = DEFAULT_CAMERA,

pub fn create(game: *Game) !*PlayState {
    var self = try game.allocator.create(PlayState);
    self.* = .{
        .game = game,
    };
    return self;
}

pub fn destroy(self: *PlayState) void {
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
    self.camera.view.x += 1;
    self.camera.view.y += 1;
}

pub fn render(self: *PlayState, alpha: f64) void {
    gl.clearColor(0x64.0 / 255.0, 0x95.0 / 255.0, 0xED.0 / 255.0, 1);
    gl.clear(gl.COLOR_BUFFER_BIT);

    const terrain_h = self.game.texman.getNamedTexture("terrain.png");
    const terrain_s = self.game.texman.getTextureState(terrain_h);
    terrain_h.bind(gl.TEXTURE_2D);
    self.game.imm.begin();

    var cam_interp = Camera.lerp(self.prev_camera, self.camera, alpha);
    cam_interp.clampToBounds();

    const min_tile_x = @intCast(usize, cam_interp.view.left()) / 16;
    const min_tile_y = @intCast(usize, cam_interp.view.top()) / 16;
    const max_tile_x = std.math.min(
        self.map.width,
        1 + @intCast(usize, cam_interp.view.right()) / 16,
    );
    const max_tile_y = std.math.min(
        self.map.height,
        1 + @intCast(usize, cam_interp.view.bottom()) / 16,
    );

    var y: usize = min_tile_y;
    var x: usize = 0;
    while (y < max_tile_y) : (y += 1) {
        x = min_tile_x;
        while (x < max_tile_x) : (x += 1) {
            const t = self.map.at2DPtr(x, y);
            if (t.bank == .terrain) {
                const nx = @intCast(u16, terrain_s.width / 16);
                const ny = @intCast(u16, terrain_s.height / 16);

                const src = Rect{
                    .x = (t.id % nx) * 16,
                    .y = (t.id / ny) * 16,
                    .w = 16,
                    .h = 16,
                };

                const dest = Rect{
                    .x = @intCast(i32, x) * 16 - cam_interp.view.left(),
                    .y = @intCast(i32, y) * 16 - cam_interp.view.top(),
                    .w = 16,
                    .h = 16,
                };

                self.game.imm.drawQuadTextured(terrain_s.*, src, dest);
            }
        }
    }
}
