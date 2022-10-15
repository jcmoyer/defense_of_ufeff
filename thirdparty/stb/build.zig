const std = @import("std");

pub const stb_image_pkg = std.build.Pkg{
    .name = "stb_image",
    .source = .{ .path = thisDir() ++ "/src/stb_image.zig" },
};

pub const stb_vorbis_pkg = std.build.Pkg{
    .name = "stb_vorbis",
    .source = .{ .path = thisDir() ++ "/src/stb_vorbis.zig" },
};

inline fn thisDir() []const u8 {
    return comptime std.fs.path.dirname(@src().file) orelse ".";
}

pub fn link(exe: *std.build.LibExeObjStep) void {
    exe.addCSourceFile(thisDir() ++ "/src/stb_image.c", &[_][]const u8{});
    exe.addCSourceFile(thisDir() ++ "/src/stb_vorbis.c", &[_][]const u8{});
}

/// Present only for zls
pub fn build(b: *std.build.Builder) void {
    _ = b;
}
