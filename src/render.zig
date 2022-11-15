const QuadBatch = @import("QuadBatch.zig");
const ImmRenderer = @import("ImmRenderer.zig");
const BitmapFont = @import("bmfont.zig").BitmapFont;
const SpriteBatch = @import("SpriteBatch.zig");
const texmod = @import("texture.zig");

pub const RenderServices = struct {
    // TODO: should this just live in render services?
    texman: *texmod.TextureManager,
    r_quad: QuadBatch,
    r_batch: SpriteBatch,
    r_font: BitmapFont,
    r_imm: ImmRenderer,

    pub fn init(self: *RenderServices, texman: *texmod.TextureManager) void {
        self.texman = texman;
        self.r_quad = QuadBatch.create();
        self.r_batch = SpriteBatch.create();
        self.r_imm = ImmRenderer.create();
        self.r_font = BitmapFont.init(&self.r_batch);
    }

    pub fn deinit(self: *RenderServices) void {
        self.r_imm.destroy();
        self.r_batch.destroy();
        self.r_quad.destroy();
    }
};
