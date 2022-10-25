const SpriteBatch = @import("SpriteBatch.zig");
const texmod = @import("texture.zig");
const TextureHandle = texmod.TextureHandle;
const TextureManager = texmod.TextureManager;
const Rect = @import("Rect.zig");

pub const BitmapFontParams = struct {
    texture_manager: *const TextureManager,
    texture: TextureHandle,
};

pub const BitmapFont = struct {
    r_batch: *SpriteBatch,
    ref_width: u32 = 0,
    ref_height: u32 = 0,

    pub fn init(batch: *SpriteBatch) BitmapFont {
        return .{
            .r_batch = batch,
        };
    }

    pub fn begin(self: *BitmapFont, params: BitmapFontParams) void {
        self.r_batch.begin(.{
            .texture = params.texture,
            .texture_manager = params.texture_manager,
        });
        const ts = params.texture_manager.getTextureState(params.texture);
        self.ref_width = ts.width;
        self.ref_height = ts.height;
    }

    pub fn end(self: BitmapFont) void {
        self.r_batch.end();
    }

    pub fn drawText(self: BitmapFont, text: []const u8, x: i32, y: i32) void {
        var dx = x;
        var dy = y;
        for (text) |ch| {
            const src = self.mapGlyph(ch);
            const dest = Rect.init(
                dx,
                dy,
                src.w,
                src.h,
            );
            self.r_batch.drawQuad(src, dest);
            dx += src.w;
        }
    }

    pub fn mapGlyph(self: BitmapFont, glyph: u8) Rect {
        const lo = (glyph & 0x0F);
        const hi = (glyph & 0xF0) >> 4;
        const glyph_w = @intCast(i32, self.ref_width / 16);
        const glyph_h = @intCast(i32, self.ref_height / 16);
        return Rect.init(
            lo * glyph_w,
            hi * glyph_h,
            glyph_w,
            glyph_h,
        );
    }
};
