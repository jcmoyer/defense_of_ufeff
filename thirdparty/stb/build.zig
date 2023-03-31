const std = @import("std");

inline fn thisDir() []const u8 {
    return comptime std.fs.path.dirname(@src().file) orelse ".";
}

/// Present only for zls
pub fn build(b: *std.build.Builder) void {
    _ = b;
}

pub fn linkImage(b: *std.build.Builder, exe: *std.build.LibExeObjStep) void {
    const m = b.addModule("stb_image", .{
        .source_file = .{ .path = thisDir() ++ "/src/stb_image.zig" },
    });
    exe.addModule("stb_image", m);
    exe.addCSourceFile(thisDir() ++ "/src/stb_image.c", &[_][]const u8{});
}

pub fn linkVorbis(b: *std.build.Builder, exe: *std.build.LibExeObjStep) void {
    const m = b.addModule("stb_vorbis", .{
        .source_file = .{ .path = thisDir() ++ "/src/stb_vorbis.zig" },
    });
    exe.addModule("stb_vorbis", m);
    exe.addCSourceFile(thisDir() ++ "/src/stb_vorbis.c", &[_][]const u8{});
}
