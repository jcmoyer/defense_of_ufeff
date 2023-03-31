const std = @import("std");

pub const gl33_pkg = std.build.Pkg{
    .name = "gl33",
    .source = .{ .path = thisDir() ++ "/src/gl_3v3.zig" },
};

/// Present only for zls
pub fn build(b: *std.build.Builder) void {
    _ = b;
}

inline fn thisDir() []const u8 {
    return comptime std.fs.path.dirname(@src().file) orelse ".";
}

pub fn link(b: *std.build.Builder, exe: *std.build.LibExeObjStep) void {
    const m = b.addModule("gl33", .{
        .source_file = .{ .path = thisDir() ++ "/src/gl_3v3.zig" },
    });
    exe.addModule("gl33", m);
}
