const PlayMenuState = @This();

const std = @import("std");
const Game = @import("Game.zig");
const gl = @import("gl33");
const tilemap = @import("tilemap.zig");
const Rect = @import("Rect.zig");
const Rectf = @import("Rectf.zig");
const Camera = @import("Camera.zig");
const SpriteBatch = @import("SpriteBatch.zig");
const WaterRenderer = @import("WaterRenderer.zig");
const zm = @import("zmath");
const anim = @import("animation.zig");
const wo = @import("world.zig");
const bmfont = @import("bmfont.zig");
const QuadBatch = @import("QuadBatch.zig");
const BitmapFont = bmfont.BitmapFont;
const particle = @import("particle.zig");
const audio = @import("audio.zig");
// eventually should probably eliminate this dependency
const sdl = @import("sdl.zig");
const ui = @import("ui.zig");
const Texture = @import("texture.zig").Texture;

game: *Game,
fontspec: bmfont.BitmapFontSpec,
ui_root: ui.Root,
menu_start: i32 = 80,

fn createMenuButton(self: *PlayMenuState, comptime text: []const u8, comptime cb: anytype) !*ui.Button {
    var btn = try self.ui_root.createButton();
    btn.text = text;
    btn.rect = Rect.init(0, 0, 128, 32);
    btn.rect.centerOn(Game.INTERNAL_WIDTH / 2, 0);
    btn.rect.y = self.menu_start;
    self.menu_start += btn.rect.h;
    btn.background = ui.Background{
        .texture = .{ .texture = self.game.texman.getNamedTexture("menu_button.png") },
    };
    btn.texture_rects = [4]Rect{
        // .normal
        Rect.init(0, 0, 128, 32),
        // .hover
        Rect.init(0, 0, 128, 32),
        // .down
        Rect.init(0, 32, 128, 32),
        // .disabled
        Rect.init(0, 64, 128, 32),
    };
    btn.ev_click.setCallback(self, cb);
    try self.ui_root.addChild(btn.control());
    return btn;
}

pub fn create(game: *Game) !*PlayMenuState {
    var self = try game.allocator.create(PlayMenuState);
    self.* = .{
        .game = game,
        .fontspec = undefined,
        .ui_root = ui.Root.init(game.allocator, &game.sdl_backend),
        // Initialized below
    };

    _ = try self.createMenuButton("Options", onOptionsClick);
    _ = try self.createMenuButton("Level Select", onLevelSelectClick);
    _ = try self.createMenuButton("Resume", onResumeClick);

    self.fontspec = try bmfont.BitmapFontSpec.loadFromFile(self.game.allocator, "assets/tables/CommonCase.json");
    return self;
}

fn onOptionsClick(button: *ui.Button, self: *PlayMenuState) void {
    _ = button;
    self.game.audio.playSound("assets/sounds/click.ogg", .{}).release();
    self.game.changeState(.options);
}

fn onLevelSelectClick(button: *ui.Button, self: *PlayMenuState) void {
    _ = button;
    self.game.audio.playSound("assets/sounds/click.ogg", .{}).release();
    self.game.st_play.beginTransitionGameOver();
    self.game.changeState(.play);
}

fn onResumeClick(button: *ui.Button, self: *PlayMenuState) void {
    _ = button;
    self.game.audio.playSound("assets/sounds/click.ogg", .{}).release();
    self.game.changeState(.play);
}

pub fn destroy(self: *PlayMenuState) void {
    self.fontspec.deinit();
    self.ui_root.deinit();
    self.game.allocator.destroy(self);
}

pub fn enter(self: *PlayMenuState, from: ?Game.StateId) void {
    _ = self;
    _ = from;
}

pub fn leave(self: *PlayMenuState, to: ?Game.StateId) void {
    _ = to;
    self.ui_root.clearTransientState();
}

pub fn update(self: *PlayMenuState) void {
    _ = self;
}

pub fn render(self: *PlayMenuState, alpha: f64) void {
    _ = alpha;

    self.game.st_play.render(0);
    // darken
    self.game.renderers.r_imm.setOutputDimensions(1, 1);
    self.game.renderers.r_imm.beginUntextured();
    self.game.renderers.r_imm.drawQuadRGBA(Rect.init(0, 0, 1, 1), .{ 0, 0, 0, 0.5 });

    ui.renderUI(.{
        .r_batch = &self.game.renderers.r_batch,
        .r_font = &self.game.renderers.r_font,
        .r_imm = &self.game.renderers.r_imm,
        .r_quad = &self.game.renderers.r_quad,
        .font_texture = self.game.texman.getNamedTexture("CommonCase.png"),
        .font_spec = &self.fontspec,
    }, self.ui_root);
}

pub fn handleEvent(self: *PlayMenuState, ev: sdl.SDL_Event) void {
    _ = self.ui_root.backend.dispatchEvent(ev, &self.ui_root);

    if (ev.type == .SDL_KEYDOWN) {
        switch (ev.key.keysym.sym) {
            sdl.SDLK_ESCAPE => self.game.changeState(.play),
            else => {},
        }
    }
}
