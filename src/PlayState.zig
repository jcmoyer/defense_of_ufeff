const PlayState = @This();

const std = @import("std");
const Game = @import("Game.zig");
const gl = @import("gl33.zig");
const tilemap = @import("tilemap.zig");

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

    const t = self.game.texman.getNamedTexture("terrain.png");
    t.bind(gl.TEXTURE_2D);
    self.game.imm.begin();
    self.game.imm.drawQuad(0, 0, 128, 128, 1, 0, 0);
}
