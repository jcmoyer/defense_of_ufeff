const MenuState = @This();

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
const rend = @import("render.zig");
// eventually should probably eliminate this dependency
const sdl = @import("sdl.zig");
const ui = @import("ui.zig");
const Texture = @import("texture.zig").Texture;
const FrameTimer = @import("timing.zig").FrameTimer;

const Substate = enum {
    none,
    fade_from_levelselect,
    fade_to_levelselect,
};

game: *Game,
fontspec: bmfont.BitmapFontSpec,
ui_root: ui.Root,
ui_tip: *ui.Button,
rng: std.rand.DefaultPrng,
tip_index: usize = 0,
menu_start: i32 = 76,
p_scroll_offset: f32 = 0,
scroll_offset: f32 = 0,
sub: Substate = .none,
fade_timer: FrameTimer = .{},

const tips = [_][]const u8{
    "You can build over top of walls!\nThis lets you maze first, then build towers.",
    "You can't build towers that would\ntotally block access to the goal.",
    "Cryomancers can slow monster movement by 33%.\nThis effect does not stack.",
    "Monsters warp back to their spawn\npoint if you have no lives at the goal.",
    "WASD pans the camera, but you can\nalso click the minimap to immediately go there.",
    "You can sell towers and replace them while\npaused so that monsters don't move into that space.",
    "Pause frequently to spend gold while under pressure!",
    "AoE units are much more effective when\nmonsters are stacked.",
    "Get an idea of the lay of the land before building\ntowers. Walls are essential to force monsters down certain paths.",
};

fn createMenuButton(self: *MenuState, comptime text: []const u8, comptime cb: anytype) !*ui.Button {
    var btn = try self.ui_root.createButton();
    btn.text = text;
    btn.rect = Rect.init(0, 0, 128, 32);
    btn.rect.centerOn(Game.INTERNAL_WIDTH / 2, 0);
    btn.rect.y = self.menu_start;
    self.menu_start += btn.rect.h + 4;
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

pub fn create(game: *Game) !*MenuState {
    var self = try game.allocator.create(MenuState);
    self.* = .{
        .game = game,
        .fontspec = undefined,
        .ui_root = ui.Root.init(game.allocator, &game.sdl_backend),
        .rng = std.rand.DefaultPrng.init(@intCast(u64, std.time.milliTimestamp())),
        // Initialized below
        .ui_tip = undefined,
    };

    _ = try self.createMenuButton("Play Game", onPlayGameClick);
    _ = try self.createMenuButton("Options", onOptionsClick);
    _ = try self.createMenuButton("Quit", onQuitClick);

    self.ui_tip = try self.ui_root.createButton();
    self.ui_tip.background = .{ .texture = .{ .texture = self.game.texman.getNamedTexture("special.png") } };
    self.ui_tip.texture_rects = [4]Rect{
        // .normal
        Rect.init(208, 48, 16, 16),
        // .hover
        Rect.init(208, 48, 16, 16),
        // .down
        Rect.init(208, 48, 16, 16),
        // .disabled
        Rect.init(208, 48, 16, 16),
    };
    self.ui_tip.rect = Rect.init(0, 0, 16, 16);
    self.ui_tip.ev_click.setCallback(self, onButtonClick);
    self.ui_tip.rect.alignRight(Game.INTERNAL_WIDTH);
    self.ui_tip.rect.alignBottom(Game.INTERNAL_HEIGHT);
    self.ui_tip.rect.translate(-8, -8);
    try self.ui_root.addChild(self.ui_tip.control());

    self.showRandomTip();

    self.fontspec = try bmfont.BitmapFontSpec.loadFromFile(self.game.allocator, "assets/tables/CommonCase.json");
    return self;
}

fn showRandomTip(self: *MenuState) void {
    const old_index = self.tip_index;
    while (self.tip_index == old_index) {
        self.tip_index = self.rng.random().intRangeLessThan(usize, 0, tips.len);
    }
}

fn onPlayGameClick(button: *ui.Button, self: *MenuState) void {
    _ = button;
    self.game.audio.playSound("assets/sounds/click.ogg", .{}).release();
    self.beginFadeToLevelSelect();
}

fn onOptionsClick(button: *ui.Button, self: *MenuState) void {
    _ = button;
    self.game.audio.playSound("assets/sounds/click.ogg", .{}).release();
    self.game.changeState(.options);
}

fn onQuitClick(button: *ui.Button, self: *MenuState) void {
    _ = button;
    self.game.quit();
}

fn onButtonClick(button: *ui.Button, self: *MenuState) void {
    _ = button;
    self.game.audio.playSound("assets/sounds/click.ogg", .{}).release();
    self.showRandomTip();
}

pub fn destroy(self: *MenuState) void {
    self.fontspec.deinit();
    self.ui_root.deinit();
    self.game.allocator.destroy(self);
}

pub fn enter(self: *MenuState, from: ?Game.StateId) void {
    if (from == Game.StateId.levelselect) {
        self.beginFadeFromLevelSelect();
    }
}

pub fn leave(self: *MenuState, to: ?Game.StateId) void {
    _ = to;
    self.ui_root.clearTransientState();
}

pub fn update(self: *MenuState) void {
    self.updateBackground();

    if (self.sub == .fade_to_levelselect and self.fade_timer.expired(self.game.frame_counter)) {
        self.endFadeToLevelSelect();
    }

    if (self.sub == .fade_from_levelselect and self.fade_timer.expired(self.game.frame_counter)) {
        self.endFadeFromLevelSelect();
    }
}

pub fn render(self: *MenuState, alpha: f64) void {
    self.game.renderers.r_batch.setOutputDimensions(Game.INTERNAL_WIDTH, Game.INTERNAL_HEIGHT);

    gl.clearColor(0x64.0 / 255.0, 0x95.0 / 255.0, 0xED.0 / 255.0, 1);
    gl.clear(gl.COLOR_BUFFER_BIT);

    self.renderBackground(alpha);

    self.game.renderers.r_font.begin(.{
        .texture = self.game.texman.getNamedTexture("CommonCase.png"),
        .spec = &self.fontspec,
    });

    self.game.renderers.r_font.drawText("Defense of Ufeff", .{ .dest = Rect.init(0, 0, Game.INTERNAL_WIDTH, 50), .h_alignment = .center });

    var measured = self.fontspec.measureText(tips[self.tip_index]);
    measured.centerOn(Game.INTERNAL_WIDTH / 2, @floatToInt(i32, 0.8 * Game.INTERNAL_HEIGHT));

    self.game.renderers.r_font.drawText(tips[self.tip_index], .{ .dest = Rect.init(0, 200, 512, 50), .h_alignment = .center });
    self.game.renderers.r_font.end();

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

pub fn handleEvent(self: *MenuState, ev: sdl.SDL_Event) void {
    if (self.sub != .none) {
        return;
    }

    _ = self.ui_root.backend.dispatchEvent(ev, &self.ui_root);
}

pub fn updateBackground(self: *MenuState) void {
    self.p_scroll_offset = self.scroll_offset;
    self.scroll_offset += 0.5;
    while (self.scroll_offset >= 32) {
        self.scroll_offset -= 32;
        self.p_scroll_offset -= 32;
    }
}

pub fn renderBackground(self: *MenuState, alpha: f64) void {
    self.game.renderers.r_batch.begin(.{
        .texture = self.game.texman.getNamedTexture("special.png"),
    });

    const src = Rect.init(224, 128, 32, 32).toRectf();

    const num_x = @divTrunc(Game.INTERNAL_WIDTH, 32) + 1;
    const num_y = @divTrunc(Game.INTERNAL_HEIGHT, 32) + 1;

    const scroll_offset = zm.lerpV(self.p_scroll_offset, self.scroll_offset, @floatCast(f32, alpha));

    var y: i32 = 0;
    var x: i32 = 0;
    while (y < num_y) : (y += 1) {
        x = 0;
        while (x < num_x) : (x += 1) {
            self.game.renderers.r_batch.drawQuad(.{
                .src = src,
                .dest = Rectf.init(
                    @intToFloat(f32, x) * src.w - scroll_offset,
                    @intToFloat(f32, y) * src.h - scroll_offset,
                    src.w,
                    src.h,
                ),
                .color = @Vector(4, u8){ 100, 100, 100, 255 },
            });
        }
    }
    self.game.renderers.r_batch.end();
}

fn beginFadeToLevelSelect(self: *MenuState) void {
    self.fade_timer = FrameTimer.initSeconds(self.game.frame_counter, 1);
    self.sub = .fade_to_levelselect;
}

fn endFadeToLevelSelect(self: *MenuState) void {
    self.sub = .none;
    self.game.changeState(.levelselect);
}

fn beginFadeFromLevelSelect(self: *MenuState) void {
    self.fade_timer = FrameTimer.initSeconds(self.game.frame_counter, 1);
    self.sub = .fade_from_levelselect;
}

fn endFadeFromLevelSelect(self: *MenuState) void {
    self.sub = .none;
}

fn renderFade(self: *MenuState) void {
    const d: rend.FadeDirection = switch (self.sub) {
        .fade_to_levelselect => .out,
        .fade_from_levelselect => .in,
        else => return,
    };
    rend.renderLinearFade(self.game.renderers, d, self.fade_timer.progressClamped(self.game.frame_counter));
}
