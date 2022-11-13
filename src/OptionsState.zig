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

game: *Game,
r_batch: SpriteBatch,
r_font: BitmapFont,
fontspec: bmfont.BitmapFontSpec,
ui_root: ui.Root,

next_option_y: i32 = 50,

btn_fullscreen: *ui.Button,
scale_index: usize = 1,
scale_text: [1]u8 = undefined,

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

pub fn create(game: *Game) !*OptionsState {
    var self = try game.allocator.create(OptionsState);
    self.* = .{
        .game = game,
        .r_batch = SpriteBatch.create(),
        .r_font = undefined,
        .fontspec = undefined,
        .ui_root = ui.Root.init(game.allocator, &game.sdl_backend),
        // Initialized below
        .btn_fullscreen = undefined,
    };
    self.r_font = BitmapFont.init(&self.r_batch);

    var b_back = try self.ui_root.createButton();
    b_back.ev_click.setCallback(self, onBackClick);
    b_back.rect = Rect.init(0, 0, 32, 32);
    b_back.rect.alignLeft(0);
    b_back.rect.alignBottom(Game.INTERNAL_HEIGHT);
    b_back.rect.translate(8, -8);
    b_back.text = "<<";
    b_back.setTexture(self.game.texman.getNamedTexture("button_base.png"));
    try self.ui_root.addChild(b_back.control());

    var fullscreen = try self.addOption("Fullscreen", onFullscreenChange, "no", "Alt+Enter anywhere");
    self.btn_fullscreen = fullscreen.button;
    _ = try self.addOption("Scale", onScaleChange, "2", "Windowed only");
    var meme = try self.addOption("Jump", onScaleChange, "Alt", "Nice corndog");
    meme.button.state = .disabled;

    // TODO probably want a better way to manage this, direct IO shouldn't be here
    // TODO undefined minefield, need to be more careful. Can't deinit an undefined thing.
    self.fontspec = try loadFontSpec(self.game.allocator, "assets/tables/CommonCase.json");
    return self;
}

fn onBackClick(button: *ui.Button, self: *OptionsState) void {
    _ = button;
    self.game.audio.playSound("assets/sounds/click.ogg", .{}).release();
    self.game.changeState(.menu);
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
    self.game.setOutputScale(@intToFloat(f32, new_scale));
    self.ui_root.backend.client_rect = self.game.output_rect;
    self.ui_root.backend.coord_scale_x = self.game.output_scale_x;
    self.ui_root.backend.coord_scale_y = self.game.output_scale_y;
    button.text = std.fmt.bufPrint(&self.scale_text, "{d}", .{new_scale}) catch |err| {
        std.log.err("onScaleChange: bufPrint failed: {!}", .{err});
        return;
    };
}

fn loadFontSpec(allocator: std.mem.Allocator, filename: []const u8) !bmfont.BitmapFontSpec {
    var font_file = try std.fs.cwd().openFile(filename, .{});
    defer font_file.close();
    var spec_json = try font_file.readToEndAlloc(allocator, 1024 * 1024);
    defer allocator.free(spec_json);
    return try bmfont.BitmapFontSpec.initJson(allocator, spec_json);
}

pub fn destroy(self: *OptionsState) void {
    self.fontspec.deinit();
    self.r_batch.destroy();
    self.ui_root.deinit();
    self.game.allocator.destroy(self);
}

pub fn enter(self: *OptionsState, from: ?Game.StateId) void {
    _ = self;
    _ = from;
}

pub fn leave(self: *OptionsState, to: ?Game.StateId) void {
    _ = self;
    _ = to;
}

pub fn update(self: *OptionsState) void {
    // hehe
    self.game.st_menu.update();
    self.btn_fullscreen.text = if (self.game.isFullscreen()) "yes" else "no";
}

pub fn render(self: *OptionsState, alpha: f64) void {
    self.r_batch.setOutputDimensions(Game.INTERNAL_WIDTH, Game.INTERNAL_HEIGHT);

    self.game.st_menu.renderBackground(alpha);

    self.r_font.begin(.{
        .texture = self.game.texman.getNamedTexture("CommonCase.png"),
        .spec = &self.fontspec,
    });
    self.r_font.drawText("Options", .{ .dest = Rect.init(0, 0, Game.INTERNAL_WIDTH, 50), .h_alignment = .center });
    self.r_font.end();

    ui.renderUI(.{
        .r_batch = &self.r_batch,
        .r_font = &self.r_font,
        .r_imm = &self.game.imm,
        .font_texture = self.game.texman.getNamedTexture("CommonCase.png"),
        .font_spec = &self.fontspec,
    }, self.ui_root);
}

pub fn handleEvent(self: *OptionsState, ev: sdl.SDL_Event) void {
    _ = self.ui_root.backend.dispatchEvent(ev, &self.ui_root);
}
