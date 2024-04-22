const std = @import("std");
const Game = @import("Game.zig");

pub const log_level: std.log.Level = .info;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{ .thread_safe = true }){};
    const allocator = gpa.allocator();
    defer _ = gpa.deinit();

    var g = try Game.create(allocator);
    defer g.destroy();

    g.run();
}
