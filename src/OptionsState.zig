const OptionsState = @This();

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
const mathutil = @import("mathutil.zig");

game: *Game,
fontspec: bmfont.BitmapFontSpec,
ui_root: ui.Root,

next_option_y: i32 = 50,

btn_fullscreen: *ui.Button,
scale_index: usize = 1,
scale_text: [1]u8 = undefined,

tb_music: *ui.Trackbar,
tb_sound: *ui.Trackbar,

sound_tooltip: [32]u8 = undefined,
music_tooltip: [32]u8 = undefined,

/// We can get to Options from Menu or PlayMenu
entered_from: ?Game.StateId = null,

const scales = [5]u8{ 1, 2, 3, 4, 5 };
const option_width = 128;
const option_height = 32;

const OptionControls = struct {
    label: *ui.Label,
    button: *ui.Button,
};

fn addOption(self: *OptionsState, name: []const u8, cb: anytype, text: []const u8, tooltip: ?[]const u8) !OptionControls {
    var label = try self.ui_root.createLabel();
    label.rect = Rect.init(0, self.next_option_y, option_width, option_height);
    label.rect.alignRight(Game.INTERNAL_WIDTH / 2);
    label.text = name;
    try self.ui_root.addChild(label.control());

    var button = try self.ui_root.createButton();
    button.rect = label.rect;
    button.rect.alignLeft(Game.INTERNAL_WIDTH / 2);
    button.text = text;
    button.tooltip_text = tooltip;
    button.background = ui.Background{
        .texture = .{ .texture = self.game.texman.getNamedTexture("menu_button.png") },
    };
    button.texture_rects = [4]Rect{
        // .normal
        Rect.init(0, 0, 128, 32),
        // .hover
        Rect.init(0, 0, 128, 32),
        // .down
        Rect.init(0, 32, 128, 32),
        // .disabled
        Rect.init(0, 64, 128, 32),
    };
    button.ev_click.setCallback(self, cb);
    try self.ui_root.addChild(button.control());

    self.next_option_y += option_height;
    return OptionControls{
        .label = label,
        .button = button,
    };
}

fn addOptionTrackbar(self: *OptionsState, name: []const u8, cb: anytype, initial_value: f32) !*ui.Trackbar {
    var label = try self.ui_root.createLabel();
    label.rect = Rect.init(0, self.next_option_y, option_width, option_height);
    label.rect.alignRight(Game.INTERNAL_WIDTH / 2);
    label.text = name;
    try self.ui_root.addChild(label.control());

    var tb = try self.ui_root.createTrackbar();
    tb.rect = label.rect;
    tb.rect.alignLeft(Game.INTERNAL_WIDTH / 2);
    tb.min_value = 0;
    tb.max_value = 100;
    tb.value = @as(u32, @intFromFloat(initial_value * 100.0));
    tb.ev_changed.setCallback(self, cb);
    try self.ui_root.addChild(tb.control());

    self.next_option_y += option_height;
    return tb;
}

pub fn create(game: *Game) !*OptionsState {
    var self = try game.allocator.create(OptionsState);
    self.* = .{
        .game = game,
        .fontspec = undefined,
        .ui_root = ui.Root.init(game.allocator, &game.sdl_backend),
        // Initialized below
        .btn_fullscreen = undefined,
        .tb_music = undefined,
        .tb_sound = undefined,
    };

    var b_back = try self.ui_root.createButton();
    b_back.ev_click.setCallback(self, onBackClick);
    b_back.rect = Rect.init(0, 0, 32, 32);
    b_back.rect.alignLeft(0);
    b_back.rect.alignBottom(Game.INTERNAL_HEIGHT);
    b_back.rect.translate(8, -8);
    b_back.text = "<<";
    b_back.setTexture(self.game.texman.getNamedTexture("button_base.png"));
    try self.ui_root.addChild(b_back.control());

    const music_coef = self.game.audio.mix_music_coef.load(.SeqCst);
    const sound_coef = self.game.audio.mix_sound_coef.load(.SeqCst);

    var fullscreen = try self.addOption("Fullscreen", onFullscreenChange, "no", "Alt+Enter anywhere");
    self.btn_fullscreen = fullscreen.button;
    _ = try self.addOption("Scale", onScaleChange, "2", "Windowed only");
    self.tb_music = try self.addOptionTrackbar("Music", onMusicVolumeChange, music_coef);
    self.tb_sound = try self.addOptionTrackbar("Sound", onSoundVolumeChange, sound_coef);
    var meme = try self.addOption("Jump", onScaleChange, "Alt", "Nice corndog");
    meme.button.state = .disabled;

    self.updateAudioTooltips();

    self.fontspec = try bmfont.BitmapFontSpec.loadFromFile(self.game.allocator, "assets/tables/CommonCase.json");
    return self;
}

fn onBackClick(button: *ui.Button, self: *OptionsState) void {
    _ = button;
    self.game.audio.playSound("assets/sounds/click.ogg", .{}).release();
    self.game.changeState(self.entered_from.?);
}

fn onFullscreenChange(button: *ui.Button, self: *OptionsState) void {
    _ = button;
    self.game.audio.playSound("assets/sounds/click.ogg", .{}).release();
    self.game.toggleFullscreen();
    self.ui_root.backend.client_rect = self.game.output_rect;
    self.ui_root.backend.coord_scale_x = self.game.output_scale_x;
    self.ui_root.backend.coord_scale_y = self.game.output_scale_y;
}

fn onScaleChange(button: *ui.Button, self: *OptionsState) void {
    self.game.audio.playSound("assets/sounds/click.ogg", .{}).release();
    self.scale_index = (self.scale_index + 1) % scales.len;
    const new_scale = scales[self.scale_index];
    self.game.setOutputScale(@as(f32, @floatFromInt(new_scale)));
    self.ui_root.backend.client_rect = self.game.output_rect;
    self.ui_root.backend.coord_scale_x = self.game.output_scale_x;
    self.ui_root.backend.coord_scale_y = self.game.output_scale_y;
    button.text = std.fmt.bufPrint(&self.scale_text, "{d}", .{new_scale}) catch |err| {
        std.log.err("onScaleChange: bufPrint failed: {!}", .{err});
        return;
    };
}

fn onMusicVolumeChange(trackbar: *ui.Trackbar, self: *OptionsState) void {
    self.game.audio.mix_music_coef.store(trackbar.valueAsPercent(), .SeqCst);
    self.updateAudioTooltips();
}

fn onSoundVolumeChange(trackbar: *ui.Trackbar, self: *OptionsState) void {
    self.game.audio.mix_sound_coef.store(trackbar.valueAsPercent(), .SeqCst);
    self.updateAudioTooltips();
}

fn updateAudioTooltips(self: *OptionsState) void {
    if (self.tb_music.value > 0) {
        self.tb_music.tooltip_text = std.fmt.bufPrint(&self.music_tooltip, "{d}% ({d:.1}db)", .{
            @as(u32, @intFromFloat(self.tb_music.valueAsPercent() * 100)),
            mathutil.ampScalarToDb(f32, self.tb_music.valueAsPercent()),
        }) catch unreachable;
    } else {
        self.tb_music.tooltip_text = std.fmt.bufPrint(&self.music_tooltip, "muted", .{}) catch unreachable;
    }

    if (self.tb_sound.value > 0) {
        self.tb_sound.tooltip_text = std.fmt.bufPrint(&self.sound_tooltip, "{d}% ({d:.1}db)", .{
            @as(u32, @intFromFloat(self.tb_sound.valueAsPercent() * 100)),
            mathutil.ampScalarToDb(f32, self.tb_sound.valueAsPercent()),
        }) catch unreachable;
    } else {
        self.tb_sound.tooltip_text = std.fmt.bufPrint(&self.sound_tooltip, "muted", .{}) catch unreachable;
    }
}

pub fn destroy(self: *OptionsState) void {
    self.fontspec.deinit();
    self.ui_root.deinit();
    self.game.allocator.destroy(self);
}

pub fn enter(self: *OptionsState, from: ?Game.StateId) void {
    self.entered_from = from;
}

pub fn leave(self: *OptionsState, to: ?Game.StateId) void {
    _ = to;
    self.ui_root.clearTransientState();
}

pub fn update(self: *OptionsState) void {
    // hehe
    self.game.st_menu.updateBackground();
    self.btn_fullscreen.text = if (self.game.isFullscreen()) "yes" else "no";
}

pub fn render(self: *OptionsState, alpha: f64) void {
    self.game.renderers.r_batch.setOutputDimensions(Game.INTERNAL_WIDTH, Game.INTERNAL_HEIGHT);

    self.game.st_menu.renderBackground(alpha);

    self.game.renderers.r_font.begin(.{
        .texture = self.game.texman.getNamedTexture("CommonCase.png"),
        .spec = &self.fontspec,
    });
    self.game.renderers.r_font.drawText("Options", .{ .dest = Rect.init(0, 0, Game.INTERNAL_WIDTH, 50), .h_alignment = .center });
    self.game.renderers.r_font.end();

    ui.renderUI(.{
        .r_batch = &self.game.renderers.r_batch,
        .r_font = &self.game.renderers.r_font,
        .r_imm = &self.game.renderers.r_imm,
        .r_quad = &self.game.renderers.r_quad,
        .font_texture = self.game.texman.getNamedTexture("CommonCase.png"),
        .font_spec = &self.fontspec,
    }, self.ui_root);
}

pub fn handleEvent(self: *OptionsState, ev: sdl.SDL_Event) void {
    _ = self.ui_root.backend.dispatchEvent(ev, &self.ui_root);
}
