const std = @import("std");
const Game = @import("Game.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    var allocator = gpa.allocator();

    var g = try Game.create(allocator);
    defer g.destroy();

    g.run();
}
