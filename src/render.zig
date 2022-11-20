const QuadBatch = @import("QuadBatch.zig");
const ImmRenderer = @import("ImmRenderer.zig");
const BitmapFont = @import("bmfont.zig").BitmapFont;
const SpriteBatch = @import("SpriteBatch.zig");
const texmod = @import("texture.zig");
const Rect = @import("Rect.zig");

pub const RenderServices = struct {
    // TODO: should this just live in render services?
    texman: *texmod.TextureManager,
    r_quad: QuadBatch,
    r_batch: SpriteBatch,
    r_font: BitmapFont,
    r_imm: ImmRenderer,

    output_width: u32,
    output_height: u32,

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

pub const FadeDirection = enum {
    in,
    out,
};

pub fn renderLinearFade(renderers: RenderServices, dir: FadeDirection, amt: f32) void {
    const t_out = amt;
    const t_in = 1 - t_out;
    const a = if (dir == .in) t_in else t_out;

    renderers.r_imm.beginUntextured();
    renderers.r_imm.drawQuadRGBA(Rect.init(0, 0, @intCast(i32, renderers.output_width), @intCast(i32, renderers.output_height)), .{ 0, 0, 0, a });
}
