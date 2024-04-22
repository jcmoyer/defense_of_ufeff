const std = @import("std");

inline fn thisDir() []const u8 {
    return comptime std.fs.path.dirname(@src().file) orelse ".";
}

/// Present only for zls
pub fn build(b: *std.build.Builder) void {
    _ = b;
}

pub fn linkImage(b: *std.Build, exe: *std.Build.Step.Compile) void {
    const m = b.addModule("stb_image", .{
        .root_source_file = .{ .path = thisDir() ++ "/src/stb_image.zig" },
    });
    exe.root_module.addImport("stb_image", m);
    exe.addCSourceFile(.{ .file = .{ .path = thisDir() ++ "/src/stb_image.c" }, .flags = &[_][]const u8{} });
}

pub fn linkVorbis(b: *std.Build, exe: *std.Build.Step.Compile) void {
    const m = b.addModule("stb_vorbis", .{
        .root_source_file = .{ .path = thisDir() ++ "/src/stb_vorbis.zig" },
    });
    exe.root_module.addImport("stb_vorbis", m);
    exe.addCSourceFile(.{ .file = .{ .path = thisDir() ++ "/src/stb_vorbis.c" }, .flags = &[_][]const u8{} });
}
