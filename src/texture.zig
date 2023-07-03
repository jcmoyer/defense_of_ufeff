const stb_image = @import("stb_image");
const gl = @import("gl33");
const std = @import("std");
const Allocator = std.mem.Allocator;
const log = std.log.scoped(.texture);

pub const Texture = struct {
    handle: gl.GLuint = 0,
    width: u32,
    height: u32,
};

pub const TextureManager = struct {
    const max_textures = 1024;

    allocator: Allocator,
    /// String to texture for named lookups
    cache: std.StringArrayHashMapUnmanaged(usize) = .{},
    /// Texture storage; index 0 is the default texture
    textures: []Texture = &[_]Texture{},
    num_textures: usize = 0,

    pub fn init(allocator: Allocator) TextureManager {
        var self = TextureManager{
            .allocator = allocator,
        };
        self.textures = self.allocator.alloc(Texture, max_textures) catch |err| {
            log.err("Failed to allocate initial texture storage: {!}", .{err});
            std.process.exit(1);
        };
        self.createDefaultTexture();
        return self;
    }

    pub fn deinit(self: *TextureManager) void {
        for (self.textures[0..self.num_textures]) |t| {
            gl.deleteTextures(1, &t.handle);
        }
        self.allocator.free(self.textures);
        self.cache.deinit(self.allocator);
    }

    pub fn getNamedTexture(self: *TextureManager, name: [:0]const u8) *const Texture {
        var gop = self.cache.getOrPut(self.allocator, name) catch |err| {
            log.err("Failed to put texture name '{s}': {!}", .{ name, err });
            std.process.exit(1);
        };

        if (gop.found_existing) {
            return &self.textures[gop.value_ptr.*];
        } else {
            // this leaves 112 bytes for `name` including its extension
            var filename_buf: [128]u8 = undefined;
            const filename = std.fmt.bufPrintZ(&filename_buf, "{s}/{s}", .{ "assets/textures", name }) catch |err| {
                log.err("Failed to format filename for texture '{s}': {!}", .{ name, err });
                std.process.exit(1);
            };

            log.info("Load new texture '{s}'", .{filename});
            const h = self.createInMemory();
            gop.value_ptr.* = self.num_textures - 1;
            loadTexture(filename, h) catch {
                log.err("Failed to load texture '{s}'; using default", .{filename});
                gop.value_ptr.* = 0;
                // free the texture we created
                const t = &self.textures[self.num_textures - 1];
                gl.deleteTextures(1, &t.handle);
                self.num_textures -= 1;
            };
            return &self.textures[gop.value_ptr.*];
        }
    }

    pub fn createInMemory(self: *TextureManager) *Texture {
        var ptr = &self.textures[self.num_textures];
        self.num_textures += 1;
        ptr.* = Texture{
            .handle = 0,
            .width = 0,
            .height = 0,
        };
        gl.genTextures(1, &ptr.handle);
        return ptr;
    }

    pub fn getDefaultTexture(self: *TextureManager) *const Texture {
        return &self.textures.items[0];
    }

    /// Initializes texture 0 to a magenta-black checkerbox pattern
    fn createDefaultTexture(self: *TextureManager) void {
        std.debug.assert(self.num_textures == 0);
        var t = self.createInMemory();
        const bytes = [_]u8{
            255, 0, 255, 255,
            0,   0, 0,   255,
            0,   0, 0,   255,
            255, 0, 255, 255,
        };
        t.width = 2;
        t.height = 2;
        gl.bindTexture(gl.TEXTURE_2D, t.handle);
        gl.texImage2D(
            gl.TEXTURE_2D,
            0,
            gl.RGBA,
            @intCast(t.width),
            @intCast(t.height),
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
};

fn loadTexture(filename: [:0]const u8, into: *Texture) !void {
    stb_image.stbi_set_flip_vertically_on_load(1);

    var width: c_int = 0;
    var height: c_int = 0;
    var channels: c_int = 0;

    const data = stb_image.stbi_load(filename, &width, &height, &channels, 4) orelse {
        return error.FailedToLoadTexture;
    };
    defer stb_image.stbi_image_free(data);

    into.width = @intCast(width);
    into.height = @intCast(height);

    gl.bindTexture(gl.TEXTURE_2D, into.handle);
    gl.texImage2D(gl.TEXTURE_2D, 0, gl.RGBA, width, height, 0, gl.RGBA, gl.UNSIGNED_BYTE, data);
    // need?
    // gl.generateMipmap()
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.REPEAT);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.REPEAT);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.NEAREST);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.NEAREST);
}
