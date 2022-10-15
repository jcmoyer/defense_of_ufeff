const stb_image = @import("stb_image");
const gl = @import("gl33.zig");
const std = @import("std");
const Allocator = std.mem.Allocator;
const log = std.log.scoped(.texture);

pub const Texture = struct {
    handle: gl.GLuint,
    width: u32,
    height: u32,
};

pub const TextureManager = struct {
    allocator: Allocator,
    cache: std.StringArrayHashMapUnmanaged(Texture),

    pub fn init(allocator: Allocator) TextureManager {
        return TextureManager{
            .allocator = allocator,
            .cache = .{},
        };
    }

    pub fn deinit(self: *TextureManager) void {
        for (self.cache.values()) |t| {
            gl.deleteTextures(1, &t.handle);
        }
        self.cache.deinit(self.allocator);
    }

    pub fn get(self: *TextureManager, name: [:0]const u8) Texture {
        var gop = self.cache.getOrPut(self.allocator, name) catch |err| {
            log.err("Failed to put texture name '{s}': {!}", .{ name, err });
            std.process.exit(1);
        };

        if (gop.found_existing) {
            return gop.value_ptr.*;
        } else {
            log.info("Load new texture '{s}'", .{name});
            const t = loadTexture(name);
            gop.value_ptr.* = t;
            return t;
        }
    }
};

fn loadTexture(filename: [:0]const u8) Texture {
    stb_image.stbi_set_flip_vertically_on_load(1);

    var w: c_int = 0;
    var h: c_int = 0;
    var channels: c_int = 0;

    const data = stb_image.stbi_load(filename, &w, &h, &channels, 4);
    defer stb_image.stbi_image_free(data);

    var t = Texture{
        .handle = 0,
        .width = @intCast(u32, w),
        .height = @intCast(u32, h),
    };
    gl.genTextures(1, &t.handle);
    gl.bindTexture(gl.TEXTURE_2D, t.handle);
    gl.texImage2D(gl.TEXTURE_2D, 0, gl.RGBA, w, h, 0, gl.RGBA, gl.UNSIGNED_BYTE, data);
    // need?
    // gl.generateMipmap()
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.REPEAT);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.REPEAT);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.NEAREST);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.NEAREST);
    return t;
}
