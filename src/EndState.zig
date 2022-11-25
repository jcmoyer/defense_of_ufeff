const EndState = @This();

const std = @import("std");
const Game = @import("Game.zig");
const Rect = @import("Rect.zig");
const Rectf = @import("Rectf.zig");
const zm = @import("zmath");
const anim = @import("animation.zig");
const wo = @import("world.zig");
const World = wo.World;
const bmfont = @import("bmfont.zig");
const QuadBatch = @import("QuadBatch.zig");
const BitmapFont = bmfont.BitmapFont;
const particle = @import("particle.zig");
const audio = @import("audio.zig");
const rend = @import("render.zig");
// eventually should probably eliminate this dependency
const sdl = @import("sdl.zig");
const ui = @import("ui.zig");
const Texture = @import("texture.zig").Texture;
const WorldRenderer = @import("WorldRenderer.zig");
const FingerRenderer = @import("FingerRenderer.zig");
const FrameTimer = @import("timing.zig").FrameTimer;

const Substate = enum {
    none,
    fadein,
    fadeout,
    fadeout_to_menu,
};

game: *Game,
fontspec: bmfont.BitmapFontSpec,
ui_root: ui.Root,
sub: Substate = .none,
fade_timer: FrameTimer = .{},

pub fn create(game: *Game) !*EndState {
    var self = try game.allocator.create(EndState);
    self.* = .{
        .game = game,
        .ui_root = ui.Root.init(game.allocator, &game.sdl_backend),
        // Initialized below
        .fontspec = undefined,
    };

    errdefer self.ui_root.deinit();

    var lbl = try self.ui_root.createLabel();
    lbl.text = "All levels complete!\nThanks for playing!\n\ndefense of ufeff\nA game for ufeffjam2 by jcmoyer";
    lbl.rect = Rect.init(0, 0, Game.INTERNAL_WIDTH, 128);
    lbl.rect.centerOn(Game.INTERNAL_WIDTH / 2, Game.INTERNAL_HEIGHT / 2);
    try self.ui_root.addChild(lbl.control());

    var b_back = try self.ui_root.createButton();
    b_back.ev_click.setCallback(self, onBackClick);
    b_back.rect = Rect.init(0, 0, 32, 32);
    b_back.rect.alignLeft(0);
    b_back.rect.alignBottom(Game.INTERNAL_HEIGHT);
    b_back.rect.translate(8, -8);
    b_back.text = "<<";
    b_back.setTexture(self.game.texman.getNamedTexture("button_base.png"));
    try self.ui_root.addChild(b_back.control());

    self.fontspec = try bmfont.BitmapFontSpec.loadFromFile(self.game.allocator, "assets/tables/CommonCase.json");
    errdefer self.fontspec.deinit();

    return self;
}

fn onBackClick(_: *ui.Button, self: *EndState) void {
    self.game.audio.playSound("assets/sounds/click.ogg", .{}).release();
    self.beginFadeOut();
}

pub fn destroy(self: *EndState) void {
    self.fontspec.deinit();
    self.ui_root.deinit();
    self.game.allocator.destroy(self);
}

pub fn enter(self: *EndState, from: ?Game.StateId) void {
    _ = from;
    self.beginFadeIn();
}

pub fn leave(self: *EndState, to: ?Game.StateId) void {
    _ = to;
    self.ui_root.clearTransientState();
}

pub fn update(self: *EndState) void {
    if (self.sub == .fadein and self.fade_timer.expired(self.game.frame_counter)) {
        self.sub = .none;
    } else if (self.sub == .fadeout and self.fade_timer.expired(self.game.frame_counter)) {
        self.endFadeOut();
    }
}

pub fn render(self: *EndState, alpha: f64) void {
    _ = alpha;
    self.game.renderers.r_batch.setOutputDimensions(Game.INTERNAL_WIDTH, Game.INTERNAL_HEIGHT);

    ui.renderUI(.{
        .r_batch = &self.game.renderers.r_batch,
        .r_font = &self.game.renderers.r_font,
        .r_imm = &self.game.renderers.r_imm,
        .r_quad = &self.game.renderers.r_quad,
        .font_texture = self.game.texman.getNamedTexture("CommonCase.png"),
        .font_spec = &self.fontspec,
    }, self.ui_root);

    self.renderFade();
}

pub fn handleEvent(self: *EndState, ev: sdl.SDL_Event) void {
    if (self.sub != .none) {
        return;
    }
    _ = self.ui_root.backend.dispatchEvent(ev, &self.ui_root);
}

fn beginFadeIn(self: *EndState) void {
    self.sub = .fadein;
    self.fade_timer = FrameTimer.initSeconds(self.game.frame_counter, 1);
}

fn beginFadeOut(self: *EndState) void {
    self.sub = .fadeout;
    self.fade_timer = FrameTimer.initSeconds(self.game.frame_counter, 1);
}

fn endFadeOut(self: *EndState) void {
    std.debug.assert(self.sub == .fadeout);
    self.sub = .none;
    self.game.changeState(.levelselect);
}

fn renderFade(self: *EndState) void {
    const d: rend.FadeDirection = switch (self.sub) {
        .fadein => .in,
        .fadeout => .out,
        else => return,
    };
    rend.renderLinearFade(self.game.renderers, d, self.fade_timer.progressClamped(self.game.frame_counter));
}
