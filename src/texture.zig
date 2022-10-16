const stb_image = @import("stb_image");
const gl = @import("gl33.zig");
const std = @import("std");
const Allocator = std.mem.Allocator;
const log = std.log.scoped(.texture);

pub const TextureState = struct {
    handle: gl.GLuint,
    width: u32,
    height: u32,
};

pub const TextureHandle = struct {
    raw_handle: gl.GLuint = 0,

    pub fn bind(self: TextureHandle, target: gl.GLenum) void {
        gl.bindTexture(target, self.raw_handle);
    }
};

pub const TextureManager = struct {
    allocator: Allocator,
    /// String to handle for named lookups
    cache: std.StringArrayHashMapUnmanaged(TextureHandle) = .{},
    /// GL handle to TextureState index
    raw_to_tex: std.AutoArrayHashMapUnmanaged(gl.GLuint, usize) = .{},
    /// TextureState storage; index 0 is the default texture
    textures: std.ArrayListUnmanaged(TextureState) = .{},

    pub fn init(allocator: Allocator) TextureManager {
        var self = TextureManager{
            .allocator = allocator,
        };
        self.createDefaultTexture();
        return self;
    }

    pub fn deinit(self: *TextureManager) void {
        for (self.textures.items) |t| {
            gl.deleteTextures(1, &t.handle);
        }
        self.textures.deinit(self.allocator);
        self.raw_to_tex.deinit(self.allocator);
        self.cache.deinit(self.allocator);
    }

    pub fn getNamedTexture(self: *TextureManager, name: [:0]const u8) TextureHandle {
        var gop = self.cache.getOrPut(self.allocator, name) catch |err| {
            log.err("Failed to put texture name '{s}': {!}", .{ name, err });
            std.process.exit(1);
        };

        if (gop.found_existing) {
            return gop.value_ptr.*;
        } else {
            // this leaves 112 bytes for `name` including its extension
            var filename_buf: [128]u8 = undefined;
            const filename = std.fmt.bufPrintZ(&filename_buf, "{s}/{s}", .{ "assets/textures", name }) catch |err| {
                log.err("Failed to format filename for texture '{s}': {!}", .{ name, err });
                std.process.exit(1);
            };

            log.info("Load new texture '{s}'", .{filename});
            const h = self.createInMemory();
            gop.value_ptr.* = h;
            loadTexture(filename, self.getTextureStateInternalMut(h)) catch {
                log.err("Failed to load texture '{s}'; using default", .{filename});
                gop.value_ptr.* = self.getDefaultTexture();
                // free the texture we created
                const t = self.textures.pop();
                gl.deleteTextures(1, &t.handle);
            };
            return gop.value_ptr.*;
        }
    }

    pub fn createInMemory(self: *TextureManager) TextureHandle {
        var ptr = self.textures.addOne(self.allocator) catch |err| {
            log.err("Failed to allocate texture: {!}", .{err});
            std.process.exit(1);
        };
        ptr.* = TextureState{
            .handle = 0,
            .width = 0,
            .height = 0,
        };
        gl.genTextures(1, &ptr.handle);
        self.raw_to_tex.putNoClobber(self.allocator, ptr.handle, self.textures.items.len - 1) catch |err| {
            log.err("Failed to map handle to TextureState: {!}", .{err});
            std.process.exit(1);
        };
        return TextureHandle{ .raw_handle = ptr.handle };
    }

    pub fn getDefaultTexture(self: *TextureManager) TextureHandle {
        return TextureHandle{ .raw_handle = self.textures.items[0].handle };
    }

    /// Initializes texture 0 to a magenta-black checkerbox pattern
    fn createDefaultTexture(self: *TextureManager) void {
        std.debug.assert(self.textures.items.len == 0);
        var h = self.createInMemory();
        var t = self.getTextureStateInternalMut(h);
        const bytes = [_]u8{
            255, 0, 255, 255,
            0,   0, 0,   255,
            0,   0, 0,   255,
            255, 0, 255, 255,
        };
        t.width = 2;
        t.height = 2;
        h.bind(gl.TEXTURE_2D);
        gl.texImage2D(
            gl.TEXTURE_2D,
            0,
            gl.RGBA,
            @intCast(gl.GLsizei, t.width),
            @intCast(gl.GLsizei, t.height),
            0,
            gl.RGBA,
            gl.UNSIGNED_BYTE,
            &bytes,
        );
        gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.REPEAT);
        gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.REPEAT);
        gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.NEAREST);
        gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.NEAREST);
    }

    pub fn getTextureState(self: TextureManager, h: TextureHandle) *const TextureState {
        return &self.textures.items[self.raw_to_tex.get(h.raw_handle).?];
    }

    fn getTextureStateInternalMut(self: TextureManager, h: TextureHandle) *TextureState {
        return &self.textures.items[self.raw_to_tex.get(h.raw_handle).?];
    }
};

fn loadTexture(filename: [:0]const u8, into: *TextureState) !void {
    stb_image.stbi_set_flip_vertically_on_load(1);

    var width: c_int = 0;
    var height: c_int = 0;
    var channels: c_int = 0;

    const data = stb_image.stbi_load(filename, &width, &height, &channels, 4) orelse {
        return error.FailedToLoadTexture;
    };
    defer stb_image.stbi_image_free(data);

    into.width = @intCast(u32, width);
    into.height = @intCast(u32, height);

    gl.bindTexture(gl.TEXTURE_2D, into.handle);
    gl.texImage2D(gl.TEXTURE_2D, 0, gl.RGBA, width, height, 0, gl.RGBA, gl.UNSIGNED_BYTE, data);
    // need?
    // gl.generateMipmap()
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.REPEAT);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.REPEAT);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.NEAREST);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.NEAREST);
}
