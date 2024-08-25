const std = @import("std");

pub fn build(b: *std.Build) void {
    const stb_image = b.addModule("stb_image", .{
        .root_source_file = b.path("src/stb_image.zig"),
    });
    stb_image.addCSourceFile(.{ .file = b.path("src/stb_image.c"), .flags = &[_][]const u8{} });

    const stb_vorbis = b.addModule("stb_vorbis", .{
        .root_source_file = b.path("src/stb_vorbis.zig"),
    });
    stb_vorbis.addCSourceFile(.{ .file = b.path("src/stb_vorbis.c"), .flags = &[_][]const u8{} });
}
