const LevelResultState = @This();

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

pub const ResultKind = enum {
    win,
    lose,
};

const Substate = enum {
    none,
    fade_in,
    fade_to_levelselect,
    fade_to_play,
};

game: *Game,
fontspec: bmfont.BitmapFontSpec,
ui_root_win: ui.Root,
ui_root_lose: ui.Root,
sub: Substate = .none,
fade_timer: FrameTimer = .{},
result_kind: ResultKind = .lose,

const wide_button_rects = [4]Rect{
    // .normal
    Rect.init(0, 0, 128, 32),
    // .hover
    Rect.init(0, 0, 128, 32),
    // .down
    Rect.init(0, 32, 128, 32),
    // .disabled
    Rect.init(0, 64, 128, 32),
};

pub fn create(game: *Game) !*LevelResultState {
    var self = try game.allocator.create(LevelResultState);
    self.* = .{
        .game = game,
        .fontspec = undefined,
        .ui_root_win = ui.Root.init(game.allocator, &game.sdl_backend),
        .ui_root_lose = ui.Root.init(game.allocator, &game.sdl_backend),
        // Initialized below
    };

    errdefer self.ui_root_win.deinit();
    errdefer self.ui_root_lose.deinit();

    // TODO: might be cool to display some stats as well

    const screen_rect = Rect.init(0, 0, Game.INTERNAL_WIDTH, Game.INTERNAL_HEIGHT);
    const screen_center = screen_rect.centerPoint();

    var lbl_win = try self.ui_root_win.createLabel();
    lbl_win.text = "Victory!";
    lbl_win.rect = Rect.init(0, 0, 200, 30);
    lbl_win.rect.centerOnPoint(screen_center);
    lbl_win.rect.translate(0, -25);
    try self.ui_root_win.addChild(lbl_win.control());

    var lbl_lose = try self.ui_root_lose.createLabel();
    lbl_lose.text = "Defeat";
    lbl_lose.rect = Rect.init(0, 0, 200, 30);
    lbl_lose.rect.centerOnPoint(screen_center);
    lbl_lose.rect.translate(0, -25);
    try self.ui_root_lose.addChild(lbl_lose.control());

    var btn_levelselect_w = try self.ui_root_win.createButton();
    btn_levelselect_w.text = "Level Select";
    btn_levelselect_w.ev_click.setCallback(self, onLevelSelectClick);
    btn_levelselect_w.rect = Rect.init(0, 0, 128, 32);
    btn_levelselect_w.rect.centerOnPoint(screen_center);
    btn_levelselect_w.rect.translate(0, 25);
    btn_levelselect_w.setTexture(self.game.texman.getNamedTexture("menu_button.png"));
    btn_levelselect_w.texture_rects = wide_button_rects;
    try self.ui_root_win.addChild(btn_levelselect_w.control());

    var btn_levelselect_l = try self.ui_root_lose.createButton();
    btn_levelselect_l.text = "Level Select";
    btn_levelselect_l.ev_click.setCallback(self, onLevelSelectClick);
    btn_levelselect_l.rect = Rect.init(0, 0, 128, 32);
    btn_levelselect_l.rect.centerOnPoint(screen_center);
    btn_levelselect_l.rect.translate(0, 25);
    btn_levelselect_l.rect.alignRight(screen_center[0]);
    btn_levelselect_l.rect.translate(-4, 0);
    btn_levelselect_l.setTexture(self.game.texman.getNamedTexture("menu_button.png"));
    btn_levelselect_l.texture_rects = wide_button_rects;
    try self.ui_root_lose.addChild(btn_levelselect_l.control());

    var btn_retry_l = try self.ui_root_lose.createButton();
    btn_retry_l.text = "Retry";
    btn_retry_l.ev_click.setCallback(self, onRetryClick);
    btn_retry_l.rect = Rect.init(0, 0, 128, 32);
    btn_retry_l.rect.centerOnPoint(screen_center);
    btn_retry_l.rect.translate(0, 25);
    btn_retry_l.rect.alignLeft(screen_center[0]);
    btn_retry_l.rect.translate(4, 0);
    btn_retry_l.setTexture(self.game.texman.getNamedTexture("menu_button.png"));
    btn_retry_l.texture_rects = wide_button_rects;
    try self.ui_root_lose.addChild(btn_retry_l.control());

    self.fontspec = try bmfont.BitmapFontSpec.loadFromFile(self.game.allocator, "assets/tables/CommonCase.json");
    errdefer self.fontspec.deinit();

    return self;
}

pub fn destroy(self: *LevelResultState) void {
    self.fontspec.deinit();
    self.ui_root_win.deinit();
    self.ui_root_lose.deinit();
    self.game.allocator.destroy(self);
}

pub fn enter(self: *LevelResultState, from: ?Game.StateId) void {
    _ = from;
    self.beginFadeIn();
}

pub fn leave(self: *LevelResultState, to: ?Game.StateId) void {
    _ = to;
    self.ui_root_win.clearTransientState();
    self.ui_root_lose.clearTransientState();
}

pub fn update(self: *LevelResultState) void {
    if (self.sub == .fade_in and self.fade_timer.expired(self.game.frame_counter)) {
        self.endFadeIn();
    }

    if (self.sub == .fade_to_levelselect and self.fade_timer.expired(self.game.frame_counter)) {
        self.endFadeToLevelSelect();
    }

    if (self.sub == .fade_to_play and self.fade_timer.expired(self.game.frame_counter)) {
        self.endFadeToPlay();
    }
}

pub fn render(self: *LevelResultState, alpha: f64) void {
    _ = alpha;

    ui.renderUI(.{
        .r_batch = &self.game.renderers.r_batch,
        .r_font = &self.game.renderers.r_font,
        .r_imm = &self.game.renderers.r_imm,
        .r_quad = &self.game.renderers.r_quad,
        .font_texture = self.game.texman.getNamedTexture("CommonCase.png"),
        .font_spec = &self.fontspec,
    }, self.getCurrentUiRoot().*);

    self.renderFade();
}

pub fn handleEvent(self: *LevelResultState, ev: sdl.SDL_Event) void {
    if (self.sub != .none) {
        return;
    }
    _ = self.game.sdl_backend.dispatchEvent(ev, self.getCurrentUiRoot());
}

fn beginFadeIn(self: *LevelResultState) void {
    self.sub = .fade_in;
    self.fade_timer = FrameTimer.initSeconds(self.game.frame_counter, 1);
}

fn endFadeIn(self: *LevelResultState) void {
    self.sub = .none;
}

fn beginFadeToLevelSelect(self: *LevelResultState) void {
    self.sub = .fade_to_levelselect;
    self.fade_timer = FrameTimer.initSeconds(self.game.frame_counter, 1);
}

fn endFadeToLevelSelect(self: *LevelResultState) void {
    self.sub = .none;
    self.game.changeState(.levelselect);
}

fn beginFadeToPlay(self: *LevelResultState) void {
    self.sub = .fade_to_play;
    self.fade_timer = FrameTimer.initSeconds(self.game.frame_counter, 1);
}

fn endFadeToPlay(self: *LevelResultState) void {
    self.sub = .none;
    self.game.st_play.restartCurrentWorld();
    self.game.changeState(.play);
}

fn endFadeOut(self: *LevelResultState) void {
    std.debug.assert(self.sub == .fadeout);
    self.sub = .none;
    self.game.changeState(.play);
}

fn renderFade(self: *LevelResultState) void {
    const d: rend.FadeDirection = switch (self.sub) {
        .fade_in => .in,
        .fade_to_levelselect, .fade_to_play => .out,
        else => return,
    };
    rend.renderLinearFade(self.game.renderers, d, self.fade_timer.progressClamped(self.game.frame_counter));
}

pub fn setResultKind(self: *LevelResultState, kind: ResultKind) void {
    self.result_kind = kind;
}

fn getCurrentUiRoot(self: *LevelResultState) *ui.Root {
    return if (self.result_kind == .win) &self.ui_root_win else &self.ui_root_lose;
}

fn onLevelSelectClick(_: *ui.Button, self: *LevelResultState) void {
    self.game.audio.playSound("assets/sounds/click.ogg", .{}).release();
    self.beginFadeToLevelSelect();
}

fn onRetryClick(_: *ui.Button, self: *LevelResultState) void {
    self.game.audio.playSound("assets/sounds/click.ogg", .{}).release();
    self.beginFadeToPlay();
}
