const PlayState = @This();

const std = @import("std");
const Game = @import("Game.zig");
const gl = @import("gl33.zig");
const tilemap = @import("tilemap.zig");
const Rect = @import("Rect.zig");

game: *Game,
map: tilemap.Tilemap,

pub fn create(game: *Game) !*PlayState {
    var self = try game.allocator.create(PlayState);
    self.* = .{
        .game = game,
        .map = .{},
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
}

pub fn leave(self: *PlayState, to: ?Game.StateId) void {
    _ = self;
    _ = to;
}

pub fn update(self: *PlayState) void {
    _ = self;
}

pub fn render(self: *PlayState, alpha: f64) void {
    _ = alpha;

    gl.clearColor(0x64.0 / 255.0, 0x95.0 / 255.0, 0xED.0 / 255.0, 1);
    gl.clear(gl.COLOR_BUFFER_BIT);

    const terrain_h = self.game.texman.getNamedTexture("terrain.png");
    const terrain_s = self.game.texman.getTextureState(terrain_h);
    terrain_h.bind(gl.TEXTURE_2D);
    self.game.imm.begin();

    var y: usize = 0;
    var x: usize = 0;
    while (y < self.map.height) : (y += 1) {
        x = 0;
        while (x < self.map.width) : (x += 1) {
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
                    .x = @intCast(i32, x) * 16,
                    .y = @intCast(i32, y) * 16,
                    .w = 16,
                    .h = 16,
                };

                self.game.imm.drawQuadTextured(terrain_s.*, src, dest);
            }
        }
    }
}
