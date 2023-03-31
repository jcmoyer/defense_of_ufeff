const PlayState = @This();

const std = @import("std");
const Game = @import("Game.zig");
const gl = @import("gl33");
const tilemap = @import("tilemap.zig");
const TileRange = tilemap.TileRange;
const Rect = @import("Rect.zig");
const Rectf = @import("Rectf.zig");
const Camera = @import("Camera.zig");
const SpriteBatch = @import("SpriteBatch.zig");

const zm = @import("zmath");
const anim = @import("animation.zig");
const wo = @import("world.zig");
const World = wo.World;
const RenderServices = rend.RenderServices;
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
const GenHandle = @import("slotmap.zig").GenHandle;
const WorldRenderer = @import("WorldRenderer.zig");
const mathutil = @import("mathutil.zig");
const builtin = @import("builtin");
const is_debug = builtin.mode == .Debug;

const DEFAULT_CAMERA = Camera{
    .view = Rect.init(0, 0, Game.INTERNAL_WIDTH - gui_panel_width, Game.INTERNAL_HEIGHT),
};
const max_onscreen_tiles = 33 * 17;
const camera_move_speed = 8;
const gui_panel_width = 16 * 6;

const InteractStateBuild = struct {
    /// What the player will build when he clicks
    tower_spec: *const wo.TowerSpec,
};

const InteractStateSelect = struct {
    selected_tower: wo.TowerId,
    hovered_spec: ?*const wo.TowerSpec = null,
};

const InteractState = union(enum) {
    none,
    build: InteractStateBuild,
    select: InteractStateSelect,
    demolish,
};

const UpgradeButtonState = struct {
    play_state: *PlayState,
    tower_id: wo.TowerId,
    tower_spec: ?*const wo.TowerSpec,
    slot: u8,
};

const Substate = enum {
    none,
    wipe_fadein,
    gamelose_fadeout,
    gamewin_fadeout,
};

const NextWaveTimerState = enum {
    middle_screen,
    move_to_corner,
    corner,
};

const NextWaveTimer = struct {
    state: NextWaveTimerState = .middle_screen,
    state_timer: FrameTimer = .{},
    wave_timer_text_buf: [24]u8 = undefined,
    wave_timer_text: []u8 = &[_]u8{},
    text_measure: Rect = Rect.init(0, 0, 0, 0),
    fontspec: *const bmfont.BitmapFontSpec,

    fn setTimerText(self: *NextWaveTimer, sec: f32) void {
        const mod_sec = @floatToInt(u32, sec) % 60;
        const min = @floatToInt(u32, sec) / 60;
        std.debug.assert(mod_sec < 60);
        std.debug.assert(min <= 99);

        self.wave_timer_text = std.fmt.bufPrint(&self.wave_timer_text_buf, "Next wave in {d:0>2}:{d:0>2}", .{ min, mod_sec }) catch unreachable;
        if (self.text_measure.w == 0) {
            self.text_measure = self.fontspec.measureText(self.wave_timer_text);
        }
    }
};

const DrawQuadCommand = struct {
    opts: SpriteBatch.DrawQuadOptions,
};
const DrawQueue = []DrawQuadCommand;

game: *Game,
camera: Camera = DEFAULT_CAMERA,
prev_camera: Camera = DEFAULT_CAMERA,
r_world: *WorldRenderer,
world: ?*wo.World = null,
fontspec: bmfont.BitmapFontSpec,
fontspec_numbers: bmfont.BitmapFontSpec,
frame_arena: std.heap.ArenaAllocator,
ui_root: ui.Root,
ui_buttons: [8]*ui.Button,
btn_pause_resume: *ui.Button,
btn_demolish: *ui.Button,
btn_fastforward: *ui.Button,
ui_minimap: *ui.Minimap,
t_minimap: *Texture,
interact_state: InteractState = .none,
sub: Substate = .none,
fade_timer: FrameTimer = .{},
gold_text: [32]u8 = undefined,
lives_text: [32]u8 = undefined,
ui_gold: *ui.Label,
ui_lives: *ui.Label,
ui_upgrade_panel: *ui.Panel,
ui_upgrade_buttons: [4]*ui.Button,
ui_upgrade_states: [3]UpgradeButtonState,
fast: bool = false,
music_params: ?*audio.AudioParameters = null,
wave_timer: NextWaveTimer,

paused: bool = false,

// UI textures, generated at runtime
button_generator: ButtonTextureGenerator,
t_wall: *Texture,
t_soldier: *Texture,
t_fast_off: *Texture,
t_fast_on: *Texture,
t_pause: *Texture,
t_resume: *Texture,
t_demolish: *Texture,
t_call_wave: *Texture,
upgrade_texture_cache: std.AutoHashMapUnmanaged(*const wo.TowerSpec, *Texture) = .{},
b_wall: *ui.Button,
b_recruit: *ui.Button,
b_call_wave: *ui.Button,

tooltip_cache: std.AutoArrayHashMapUnmanaged(*const wo.TowerSpec, []const u8) = .{},

wipe_scanlines: [Game.INTERNAL_HEIGHT]i32 = undefined,

deb_render_tile_collision: bool = false,

rng: std.rand.DefaultPrng = std.rand.DefaultPrng.init(0),
current_mapid: ?u32 = null,

minimap_elements: std.ArrayListUnmanaged(ui.MinimapElement) = .{},

const wipe_scanline_width = Game.INTERNAL_WIDTH / 4;

fn makeStandardButtonRects(x: i32, y: i32) [4]Rect {
    return [4]Rect{
        Rect.init(x, y, 32, 32),
        Rect.init(x, y + 32, 32, 32),
        Rect.init(x, y + 64, 32, 32),
        Rect.init(x, y + 96, 32, 32),
    };
}

pub fn create(game: *Game) !*PlayState {
    var self = try game.allocator.create(PlayState);
    self.* = .{
        .game = game,
        .ui_root = ui.Root.init(game.allocator, &game.sdl_backend),
        .t_minimap = game.texman.createInMemory(),
        // Initialized below
        .frame_arena = undefined,
        .fontspec = undefined,
        .fontspec_numbers = undefined,
        .ui_buttons = undefined,
        .ui_minimap = undefined,
        .ui_gold = undefined,
        .ui_lives = undefined,
        .btn_pause_resume = undefined,
        .btn_demolish = undefined,
        .btn_fastforward = undefined,
        .ui_upgrade_panel = undefined,
        .ui_upgrade_buttons = undefined,
        .ui_upgrade_states = undefined,
        .t_wall = undefined,
        .t_soldier = undefined,
        .t_fast_off = undefined,
        .t_fast_on = undefined,
        .t_pause = undefined,
        .t_resume = undefined,
        .t_demolish = undefined,
        .t_call_wave = undefined,
        .button_generator = undefined,
        .wave_timer = undefined,
        .r_world = undefined,
        .b_wall = undefined,
        .b_recruit = undefined,
        .b_call_wave = undefined,
    };

    self.frame_arena = std.heap.ArenaAllocator.init(game.allocator);
    errdefer self.frame_arena.deinit();

    self.r_world = try WorldRenderer.create(game.allocator, &game.renderers);
    errdefer self.r_world.destroy(game.allocator);

    self.button_generator = ButtonTextureGenerator.init(&game.texman, &self.game.renderers.r_batch);

    var button_base = self.game.texman.getNamedTexture("button_base.png");
    var button_badges = self.game.texman.getNamedTexture("button_badges.png");
    const white = .{ 255, 255, 255, 255 };
    self.t_demolish = self.button_generator.createButtonWithBadge(button_base, button_badges, Rect.init(0, 0, 32, 32), white);
    self.t_fast_off = self.button_generator.createButtonWithBadge(button_base, button_badges, Rect.init(32, 0, 32, 32), white);
    self.t_pause = self.button_generator.createButtonWithBadge(button_base, button_badges, Rect.init(64, 0, 32, 32), white);
    self.t_resume = self.button_generator.createButtonWithBadge(button_base, button_badges, Rect.init(96, 0, 32, 32), white);
    self.t_wall = self.button_generator.createButtonWithBadge(button_base, button_badges, Rect.init(128, 0, 32, 32), white);
    self.t_soldier = self.button_generator.createButtonWithBadge(button_base, button_badges, Rect.init(160, 0, 32, 32), white);
    self.t_fast_on = self.button_generator.createButtonWithBadge(button_base, button_badges, Rect.init(192, 0, 32, 32), white);
    self.t_call_wave = self.button_generator.createButtonWithBadge(button_base, button_badges, Rect.init(224, 0, 32, 32), white);

    const t_panel = self.game.texman.getNamedTexture("ui_panel.png");
    var ui_panel = try self.ui_root.createPanel();
    ui_panel.rect = Rect.init(0, 0, @intCast(i32, t_panel.width), @intCast(i32, t_panel.height));
    ui_panel.rect.alignRight(Game.INTERNAL_WIDTH);
    ui_panel.background = .{ .texture = .{ .texture = t_panel } };
    try self.ui_root.addChild(ui_panel.control());

    self.b_wall = try self.ui_root.createButton();
    self.b_wall.tooltip_text = self.getCachedTooltip(&wo.t_wall);
    self.b_wall.rect = Rect.init(16, 144, 32, 32);
    self.b_wall.texture_rects = makeStandardButtonRects(0, 0);
    self.b_wall.setTexture(self.t_wall);
    self.b_wall.ev_click.setCallback(self, onWallClick);
    try ui_panel.addChild(self.b_wall.control());

    self.b_recruit = try self.ui_root.createButton();
    self.b_recruit.tooltip_text = self.getCachedTooltip(&wo.t_recruit);
    self.b_recruit.rect = Rect.init(48, 144, 32, 32);
    self.b_recruit.texture_rects = makeStandardButtonRects(0, 0);
    self.b_recruit.setTexture(self.t_soldier);
    self.b_recruit.ev_click.setCallback(self, onTowerClick);
    try ui_panel.addChild(self.b_recruit.control());

    self.b_call_wave = try self.ui_root.createButton();
    self.b_call_wave.tooltip_text = "Call next wave (G)";
    self.b_call_wave.rect = Rect.init(48, 176, 32, 32);
    self.b_call_wave.setTexture(self.t_call_wave);
    self.b_call_wave.ev_click.setCallback(self, onCallWaveClick);
    try ui_panel.addChild(self.b_call_wave.control());

    self.ui_minimap = try self.ui_root.createMinimap();
    self.ui_minimap.rect = Rect.init(16, 16, 64, 64);
    self.ui_minimap.texture = self.t_minimap;
    self.ui_minimap.setPanCallback(self, onMinimapPan);
    try ui_panel.addChild(self.ui_minimap.control());

    self.ui_gold = try self.ui_root.createLabel();
    self.ui_gold.rect = Rect.init(16, 96, 4 * 16, 16);
    self.ui_gold.text = "$0";
    self.ui_gold.background = .{ .color = ui.ControlColor.black };
    try ui_panel.addChild(self.ui_gold.control());

    self.ui_lives = try self.ui_root.createLabel();
    self.ui_lives.rect = Rect.init(16, 112, 4 * 16, 16);
    self.ui_lives.text = "\x030";
    self.ui_lives.background = .{ .color = ui.ControlColor.black };
    try ui_panel.addChild(self.ui_lives.control());

    self.btn_pause_resume = try self.ui_root.createButton();
    self.btn_pause_resume.setTexture(self.t_pause);
    self.btn_pause_resume.rect = Rect.init(16, 208, 32, 32);
    self.btn_pause_resume.texture_rects = makeStandardButtonRects(0, 0);
    self.btn_pause_resume.tooltip_text = "Pause (Space)";
    try ui_panel.addChild(self.btn_pause_resume.control());
    self.btn_pause_resume.ev_click.setCallback(self, onPauseClick);

    self.btn_fastforward = try self.ui_root.createButton();
    self.btn_fastforward.setTexture(self.t_fast_off);
    self.btn_fastforward.rect = Rect.init(48, 208, 32, 32);
    self.btn_fastforward.texture_rects = makeStandardButtonRects(0, 0);
    self.btn_fastforward.tooltip_text = "Fast-forward (Q)";
    self.btn_fastforward.ev_click.setCallback(self, onFastForwardClick);
    try ui_panel.addChild(self.btn_fastforward.control());

    self.btn_demolish = try self.ui_root.createButton();
    self.btn_demolish.setTexture(self.t_demolish);
    self.btn_demolish.rect = Rect.init(16, 176, 32, 32);
    self.btn_demolish.tooltip_text = "Demolish (R)\n\nReturns 50% of the total gold\ninvested into the tower.";
    self.btn_demolish.ev_click.setCallback(self, onDemolishClick);
    try ui_panel.addChild(self.btn_demolish.control());

    self.ui_upgrade_panel = try self.ui_root.createPanel();
    self.ui_upgrade_panel.rect = Rect.init(0, 0, 4 * 32, 32);
    self.ui_upgrade_panel.rect.centerOn(Game.INTERNAL_WIDTH / 2, 0);
    self.ui_upgrade_panel.rect.alignBottom(Game.INTERNAL_HEIGHT);
    self.ui_upgrade_panel.background = .{ .color = ui.ControlColor.black };
    try self.ui_root.addChild(self.ui_upgrade_panel.control());

    for (&self.ui_upgrade_buttons, 0..) |*b, i| {
        b.* = try self.ui_root.createButton();
        b.*.texture_rects = makeStandardButtonRects(0, 0);
        b.*.rect = Rect.init(@intCast(i32, i) * 32, 0, 32, 32);
        try self.ui_upgrade_panel.addChild(b.*.control());
        // only first 3 buttons are upgrades, 4th is demolish
        if (i < 3) {
            b.*.setTexture(button_base);
            b.*.ev_click.setCallback(&self.ui_upgrade_states[i], onUpgradeClick);
            b.*.ev_mouse_enter.setCallback(&self.ui_upgrade_states[i], onUpgradeMouseEnter);
            b.*.ev_mouse_leave.setCallback(&self.ui_upgrade_states[i], onUpgradeMouseLeave);
        } else if (i == 3) {
            b.*.setTexture(self.t_demolish);
            b.*.tooltip_text = "Demolish (4)\n\nReturns 50% of the total gold\ninvested into the tower.";
            b.*.ev_click.setCallback(self, onUpgradeDemolishClick);
        }
    }

    self.fontspec = try bmfont.BitmapFontSpec.loadFromFile(self.game.allocator, "assets/tables/CommonCase.json");
    self.fontspec_numbers = try bmfont.BitmapFontSpec.loadFromFile(self.game.allocator, "assets/tables/floating_text.json");

    self.wave_timer = .{
        .fontspec = &self.fontspec,
    };

    return self;
}

fn onWallClick(button: *ui.Button, self: *PlayState) void {
    _ = button;
    self.enterBuildWallMode();
}

fn onTowerClick(button: *ui.Button, self: *PlayState) void {
    _ = button;
    self.enterBuildTowerMode();
}

fn onCallWaveClick(button: *ui.Button, self: *PlayState) void {
    _ = button;
    self.callWave();
}

fn onPauseClick(button: *ui.Button, self: *PlayState) void {
    _ = button;
    self.togglePause();
}

fn onFastForwardClick(button: *ui.Button, self: *PlayState) void {
    _ = button;
    self.toggleFast();
}

fn onUpgradeClick(button: *ui.Button, upgrade: *UpgradeButtonState) void {
    _ = button;
    std.debug.assert(upgrade.play_state.interact_state == .select);
    upgrade.play_state.upgradeSelectedTower(upgrade.slot);
}

fn onUpgradeMouseEnter(button: *ui.Button, upgrade: *UpgradeButtonState) void {
    _ = button;
    upgrade.play_state.interact_state.select.hovered_spec = upgrade.tower_spec;
}

fn onUpgradeMouseLeave(button: *ui.Button, upgrade: *UpgradeButtonState) void {
    _ = button;
    upgrade.play_state.interact_state.select.hovered_spec = null;
}

fn onUpgradeDemolishClick(button: *ui.Button, self: *PlayState) void {
    _ = button;
    std.debug.assert(self.interact_state == .select);
    self.sellSelectedTower();
}

fn onDemolishClick(button: *ui.Button, self: *PlayState) void {
    _ = button;
    self.enterDemolishMode();
}

fn onMinimapPan(_: *ui.Minimap, self: *PlayState, x: f32, y: f32) void {
    self.camera.view.centerOn(
        @floatToInt(i32, x * @intToFloat(f32, self.camera.bounds.w)) + self.camera.bounds.x,
        @floatToInt(i32, y * @intToFloat(f32, self.camera.bounds.h)) + self.camera.bounds.y,
    );
    self.camera.clampToBounds();
}

pub fn destroy(self: *PlayState) void {
    self.frame_arena.deinit();
    if (self.music_params) |params| {
        params.release();
    }
    self.r_world.destroy(self.game.allocator);
    self.upgrade_texture_cache.deinit(self.game.allocator);
    for (self.tooltip_cache.values()) |str| {
        self.game.allocator.free(str);
    }
    self.tooltip_cache.deinit(self.game.allocator);
    self.button_generator.deinit();
    self.fontspec.deinit();
    self.fontspec_numbers.deinit();
    if (self.world) |world| {
        world.destroy();
        self.world = null;
    }
    self.ui_root.deinit();
    self.minimap_elements.deinit(self.game.allocator);
    self.game.allocator.destroy(self);
}

pub fn enter(self: *PlayState, from: ?Game.StateId) void {
    self.interact_state = .none;
    if (from != Game.StateId.playmenu) {
        self.setInitialUIState();
        self.beginWipe();
    }
    if (self.music_params) |params| {
        params.paused.store(false, .SeqCst);
    }
}

pub fn leave(self: *PlayState, to: ?Game.StateId) void {
    _ = to;
    self.ui_root.clearTransientState();
}

pub fn update(self: *PlayState) void {
    var world = self.world orelse @panic("update with no world");

    const arena_was_reset = self.frame_arena.reset(.retain_capacity);
    if (!arena_was_reset) {
        std.log.warn("PlayState.update: frame_arena not reset!", .{});
    }
    var arena = self.frame_arena.allocator();

    self.prev_camera = self.camera;

    if (self.game.input.isKeyDown(sdl.SDL_SCANCODE_A)) {
        self.camera.view.x -= camera_move_speed;
    }
    if (self.game.input.isKeyDown(sdl.SDL_SCANCODE_D)) {
        self.camera.view.x += camera_move_speed;
    }

    if (self.game.input.isKeyDown(sdl.SDL_SCANCODE_W)) {
        self.camera.view.y -= camera_move_speed;
    }
    if (self.game.input.isKeyDown(sdl.SDL_SCANCODE_S)) {
        self.camera.view.y += camera_move_speed;
    }

    self.camera.clampToBounds();
    self.ui_minimap.view = self.camera.view;
    self.ui_minimap.bounds = self.camera.bounds;

    self.r_world.updateAnimations();

    world.view = self.camera.view;
    if (self.sub == .none and !self.paused) {
        world.update(arena);
        if (self.fast) {
            world.update(arena);
        }
    }
    self.updateUI();

    if (self.sub == .none and world.recoverable_lives == 0) {
        self.beginTransitionGameOver();
    }

    if (self.sub == .none and world.player_won) {
        self.beginTransitionGameWin();
    }

    if (self.sub == .gamelose_fadeout or self.sub == .gamewin_fadeout) {
        if (self.music_params) |params| {
            params.volume.store(self.fade_timer.invProgressClamped(self.game.frame_counter), .SeqCst);
        }
        if (self.fade_timer.expired(self.game.frame_counter)) {
            if (self.music_params) |params| {
                params.done.store(true, .SeqCst);
                params.release();
                self.music_params = null;
            }
            if (self.sub == .gamelose_fadeout) {
                self.game.st_levelresult.setResultKind(.lose);
            } else {
                self.game.st_levelresult.setResultKind(.win);
            }
            self.game.changeState(.levelresult);
        }
    }

    if (self.music_params) |params| {
        if (is_debug) {} else {
            if (self.sub == .wipe_fadein and !params.loaded.load(.SeqCst)) {
                self.beginWipe();
            }
        }
    }

    if (self.sub == .wipe_fadein and self.fade_timer.expired(self.game.frame_counter)) {
        self.sub = .none;
        self.endWipe();
    }
}

fn updateUI(self: *PlayState) void {
    // unreachable because called from context where world has already been null-checked
    var world = self.world orelse unreachable;

    self.ui_gold.text = std.fmt.bufPrint(&self.gold_text, "${d}", .{world.player_gold}) catch unreachable;
    self.ui_lives.text = std.fmt.bufPrint(&self.lives_text, "\x03{d}", .{world.lives_at_goal}) catch unreachable;
    if (world.next_wave_timer) |timer| {
        self.wave_timer.setTimerText(timer.remainingSeconds(world.world_frame));
    }
    self.updateUpgradeButtons();
    if (self.wave_timer.state == .middle_screen and self.wave_timer.state_timer.expired(world.world_frame)) {
        self.wave_timer.state = .move_to_corner;
        self.wave_timer.state_timer = FrameTimer.initSeconds(world.world_frame, 2);
    } else if (self.wave_timer.state == .move_to_corner and self.wave_timer.state_timer.expired(world.world_frame)) {
        self.wave_timer.state = .corner;
    }
    if (world.canAfford(&wo.t_wall) and self.b_wall.state == .disabled) {
        self.b_wall.state = .normal;
    } else if (!world.canAfford(&wo.t_wall)) {
        self.b_wall.state = .disabled;
    }
    if (world.canAfford(&wo.t_recruit) and self.b_recruit.state == .disabled) {
        self.b_recruit.state = .normal;
    } else if (!world.canAfford(&wo.t_recruit)) {
        self.b_recruit.state = .disabled;
    }
    if (world.remainingWaveCount() == 0) {
        self.b_call_wave.state = .disabled;
    } else {
        if (self.b_call_wave.state == .disabled) {
            self.b_call_wave.state = .normal;
        }
    }

    self.minimap_elements.clearRetainingCapacity();
    for (world.monsters.slice()) |*m| {
        var p = m.getWorldCollisionRect().centerPoint();
        self.addMinimapElement(@intCast(u32, p[0]), @intCast(u32, p[1]), .{ 255, 0, 0, 255 });
    }
    for (world.towers.slice()) |*t| {
        var p = t.getWorldCollisionRect().centerPoint();
        self.addMinimapElement(@intCast(u32, p[0]), @intCast(u32, p[1]), .{ 0, 255, 0, 255 });
    }
    self.ui_minimap.elements = self.minimap_elements.items;
}

fn addMinimapElement(self: *PlayState, world_x: u32, world_y: u32, color: [4]u8) void {
    var world = self.world orelse unreachable;

    const tile_pos = tilemap.TileCoord.initWorld(world_x, world_y);

    const range = world.getPlayableRange();
    if (!range.contains(tile_pos)) {
        return;
    }

    const tx = @intToFloat(f32, range.min.x * 16);
    const ty = @intToFloat(f32, range.min.y * 16);
    const ox = @intToFloat(f32, world_x) - tx;
    const oy = @intToFloat(f32, world_y) - ty;
    const ww = @intToFloat(f32, range.getWidth() * 16);
    const wh = @intToFloat(f32, range.getHeight() * 16);
    const nx = ox / ww;
    const ny = oy / wh;

    var element = self.minimap_elements.addOne(self.game.allocator) catch |err| {
        std.log.err("Failed to allocate minimap_elements: {!}\n", .{err});
        std.process.exit(1);
    };
    element.* = ui.MinimapElement{
        .normalized_pos = .{ nx, ny },
        .color = color,
    };
}

fn sortDrawQueueY(q: DrawQueue) void {
    const SortImpl = struct {
        fn less(_: void, a: DrawQuadCommand, b: DrawQuadCommand) bool {
            return a.opts.dest.y < b.opts.dest.y;
        }
    };
    std.sort.sort(DrawQuadCommand, q, {}, SortImpl.less);
}

fn execDrawQueue(renderers: *RenderServices, q: DrawQueue) void {
    // TODO: make this configurable
    renderers.r_batch.begin(.{
        .texture = renderers.texman.getNamedTexture("characters.png"),
    });
    for (q) |cmd| {
        renderers.r_batch.drawQuad(cmd.opts);
    }
    renderers.r_batch.end();
}

pub fn render(self: *PlayState, alpha: f64) void {
    var world = self.world orelse @panic("render with no world");

    const arena_was_reset = self.frame_arena.reset(.retain_capacity);
    if (!arena_was_reset) {
        std.log.warn("PlayState.render: frame_arena not reset!", .{});
    }
    var arena = self.frame_arena.allocator();

    var draw_queue = arena.alloc(DrawQuadCommand, world.monsters.slice().len) catch |err| {
        std.log.err("Failed to allocate draw_queue storage: {!}", .{err});
        std.process.exit(1);
    };

    const world_interp = if (self.paused or self.sub != .none) @as(f64, 0) else alpha;

    self.game.renderers.r_quad.setOutputDimensions(Game.INTERNAL_WIDTH, Game.INTERNAL_HEIGHT);
    self.game.renderers.r_batch.setOutputDimensions(Game.INTERNAL_WIDTH, Game.INTERNAL_HEIGHT);
    self.game.renderers.r_imm.setOutputDimensions(Game.INTERNAL_WIDTH, Game.INTERNAL_HEIGHT);

    var cam_interp = Camera.lerp(self.prev_camera, self.camera, alpha);
    cam_interp.clampToBounds();

    self.r_world.renderTilemap(cam_interp, &self.world.?.map, self.game.frame_counter);
    renderGoal(&self.game.renderers, world, cam_interp, world_interp);
    renderTowerBases(&self.game.renderers, world, cam_interp, if (self.interact_state == .select) self.interact_state.select.selected_tower else null);

    renderMonsters(world, cam_interp, world_interp, draw_queue);
    sortDrawQueueY(draw_queue);
    execDrawQueue(&self.game.renderers, draw_queue);

    renderTowers(&self.game.renderers, world, cam_interp, if (self.interact_state == .select) self.interact_state.select.selected_tower else null);
    renderStolenHearts(&self.game.renderers, world, cam_interp, world_interp, self.r_world.heart_anim);
    renderFields(&self.game.renderers, world, cam_interp, world_interp);
    renderSpriteEffects(&self.game.renderers, world, cam_interp, world_interp);
    renderProjectiles(&self.game.renderers, world, cam_interp, world_interp);
    renderHealthBars(&self.game.renderers, world, cam_interp, world_interp);
    renderFloatingText(&self.game.renderers, world, cam_interp, world_interp, .{
        .texture = self.game.texman.getNamedTexture("floating_text.png"),
        .spec = &self.fontspec_numbers,
    });
    switch (self.interact_state) {
        .build => |b| {
            renderBlockedConstructionRects(&self.game.renderers, world, cam_interp);
            renderGrid(&self.game.renderers, cam_interp);
            const tile_coord = self.mouseToTile();
            const tower_center_x = @intCast(i32, tile_coord.worldX() + 8);
            const tower_center_y = @intCast(i32, tile_coord.worldY() + 8);
            renderPlacementIndicator(&self.game.renderers, world, cam_interp, tile_coord);
            renderRangeIndicatorForTower(&self.game.renderers, cam_interp, b.tower_spec, tower_center_x, tower_center_y);
        },
        .demolish => {
            self.renderDemolishIndicator(cam_interp);
        },
        .select => |s| {
            const selected_tower = world.towers.getPtr(s.selected_tower);
            const selected_spec = if (s.hovered_spec) |hovered| hovered else selected_tower.spec;
            const p = selected_tower.getWorldCollisionRect().centerPoint();
            renderRangeIndicatorForTower(&self.game.renderers, cam_interp, selected_spec, p[0], p[1]);
        },
        else => {},
    }
    self.renderWaveTimer(world_interp);

    if (self.deb_render_tile_collision) {
        self.debugRenderTileCollision(cam_interp);
    }

    ui.renderUI(.{
        .r_batch = &self.game.renderers.r_batch,
        .r_font = &self.game.renderers.r_font,
        .r_imm = &self.game.renderers.r_imm,
        .r_quad = &self.game.renderers.r_quad,
        .font_texture = self.game.texman.getNamedTexture("CommonCase.png"),
        .font_spec = &self.fontspec,
    }, self.ui_root);

    self.renderWipe(alpha);
    self.renderFade();
}

pub fn handleEvent(self: *PlayState, ev: sdl.SDL_Event) void {
    // stop accepting input
    if (self.sub != .none) {
        return;
    }

    if (self.ui_root.backend.dispatchEvent(ev, &self.ui_root)) {
        return;
    }

    var world = self.world orelse return;

    if (ev.type == .SDL_KEYDOWN) {
        switch (ev.key.keysym.sym) {
            sdl.SDLK_F1 => self.deb_render_tile_collision = !self.deb_render_tile_collision,
            sdl.SDLK_F2 => if (is_debug) {
                self.world.?.player_gold += 200;
            },
            sdl.SDLK_F3 => if (is_debug) {
                for (self.world.?.monsters.slice()) |*m| {
                    m.hurt(.{ .amount = m.hp });
                }
            },
            sdl.SDLK_F4 => if (is_debug) {
                self.beginTransitionGameWin();
            },
            sdl.SDLK_ESCAPE => {
                if (self.interact_state == .none) {
                    self.game.changeState(.playmenu);
                } else if (self.interact_state == .build) {
                    self.interact_state = .none;
                }
            },
            sdl.SDLK_1 => if (self.interact_state == .select) self.upgradeSelectedTower(0) else self.enterBuildWallMode(),
            sdl.SDLK_2 => if (self.interact_state == .select) self.upgradeSelectedTower(1) else self.enterBuildTowerMode(),
            sdl.SDLK_3 => self.upgradeSelectedTower(2),
            sdl.SDLK_4 => self.sellSelectedTower(),
            sdl.SDLK_SPACE => self.togglePause(),
            sdl.SDLK_q => self.toggleFast(),
            sdl.SDLK_g => self.callWave(),
            sdl.SDLK_r => self.enterDemolishMode(),
            else => {},
        }
    }

    if (ev.type == .SDL_MOUSEMOTION) {
        const tile_coord = self.mouseToTile();
        if (world.getTowerAt(tile_coord) != null) {
            self.game.sdl_backend.setCursorForHint(.clickable);
        } else {
            self.game.sdl_backend.setCursorForHint(.none);
        }
    }

    if (ev.type == .SDL_MOUSEBUTTONDOWN) {
        if (ev.button.button == sdl.SDL_BUTTON_LEFT) {
            if (self.interact_state == .build) {
                const spec = self.interact_state.build.tower_spec;
                const tile_coord = self.mouseToTile();
                if (world.canBuildAt(tile_coord) and world.canAfford(spec)) {
                    self.game.audio.playSound("assets/sounds/build.ogg", .{}).release();
                    _ = world.spawnTower(spec, tile_coord) catch unreachable;
                    world.player_gold -= spec.gold_cost;
                    if (sdl.SDL_GetModState() & sdl.KMOD_SHIFT == 0) {
                        self.interact_state = .none;
                    }
                }
            } else if (self.interact_state == .demolish) {
                const tile_coord = self.mouseToTile();
                if (world.getTowerAt(tile_coord)) |id| {
                    world.sellTower(id);
                    if (sdl.SDL_GetModState() & sdl.KMOD_SHIFT == 0) {
                        self.interact_state = .none;
                    }
                } else {
                    self.interact_state = .none;
                }
            } else {
                const tile_coord = self.mouseToTile();
                if (world.getTowerAt(tile_coord)) |id| {
                    self.game.audio.playSound("assets/sounds/click.ogg", .{}).release();
                    std.log.debug("Selected {any}", .{id});
                    self.interact_state = .{
                        .select = InteractStateSelect{
                            .selected_tower = id,
                        },
                    };
                    self.updateUpgradeButtons();
                } else {
                    self.interact_state = .none;
                }
            }
        } else if (ev.button.button == sdl.SDL_BUTTON_RIGHT) {
            if (self.interact_state == .build or self.interact_state == .select) {
                self.interact_state = .none;
            }
        }
    }
}

const particle_rects = [@typeInfo(particle.ParticleKind).Enum.fields.len]Rectf{
    Rectf.init(0, 240, 16, 16),
    Rect.init(11 * 16, 0, 16, 16).toRectf(),
    Rectf.init(0, 240, 4, 4),
    Rect.init(13 * 16, 0, 16, 16).toRectf(),
};

fn renderFields(
    renderers: *RenderServices,
    world: *World,
    cam: Camera,
    alpha: f64,
) void {
    const viewf = cam.view.toRectf();

    renderers.r_batch.begin(.{
        .texture = renderers.texman.getNamedTexture("special.png"),
    });

    var sys = world.particle_sys;

    const pos = sys.particles.items(.pos);
    const prev_pos = sys.particles.items(.prev_pos);

    var i: usize = 0;

    while (i < sys.num_alive) : (i += 1) {
        const src = particle_rects[@enumToInt(sys.particles.items(.kind)[i])];
        const s = sys.particles.items(.scale)[i];
        const c = sys.particles.items(.rgba)[i];
        const r = sys.particles.items(.rotation)[i];

        const V2 = @Vector(2, f32);

        const p = zm.lerp(@bitCast(V2, prev_pos[i]), @bitCast(V2, pos[i]), @floatCast(f32, alpha));

        var t = zm.mul(zm.scaling(s, s, 1), zm.rotationZ(r));
        t = zm.mul(t, zm.translation(p[0] - viewf.left(), p[1] - viewf.top(), 0));

        renderers.r_batch.drawQuadTransformed(.{
            .src = src,
            .color = c,
            .transform = t,
        });
    }
    renderers.r_batch.end();
}

fn renderSpriteEffects(
    renderers: *RenderServices,
    world: *World,
    cam: Camera,
    alpha: f64,
) void {
    const t_special = renderers.texman.getNamedTexture("special.png");
    renderers.r_batch.begin(.{
        .texture = t_special,
    });
    for (world.sprite_effects.slice()) |t| {
        var animator = t.animator orelse continue;
        if (t.delay) |delay| {
            if (!delay.expired(world.world_frame)) {
                continue;
            }
        }

        const angle = zm.lerpV(t.p_angle, t.angle, @floatCast(f32, alpha));
        const post_angle = zm.lerpV(t.p_post_angle, t.post_angle, @floatCast(f32, alpha));

        const interp = zm.lerp(
            zm.f32x4(t.p_offset_x, t.p_offset_y, t.p_world_x, t.p_world_y),
            zm.f32x4(t.offset_x, t.offset_y, t.world_x, t.world_y),
            @floatCast(f32, alpha),
        );

        const offset_x = interp[0];
        const offset_y = interp[1];
        const world_x = interp[2];
        const world_y = interp[3];

        var transform = zm.mul(zm.rotationZ(angle), zm.translation(offset_x, offset_y, 0));
        transform = zm.mul(transform, zm.rotationZ(post_angle));
        transform = zm.mul(transform, zm.translation(world_x - @intToFloat(f32, cam.view.left()), world_y - @intToFloat(f32, cam.view.top()), 0));

        renderers.r_batch.drawQuadTransformed(.{
            .src = animator.getCurrentRect().toRectf(),
            .transform = transform,
        });
    }
    renderers.r_batch.end();
}

fn renderProjectiles(
    renderers: *RenderServices,
    world: *World,
    cam: Camera,
    alpha: f64,
) void {
    const t_special = renderers.texman.getNamedTexture("special.png");
    renderers.r_batch.begin(.{
        .texture = t_special,
    });
    for (world.projectiles.slice()) |p| {
        var animator = p.animator orelse continue;
        const dest = p.getInterpWorldPosition(alpha);
        const dx = @intToFloat(f32, dest[0] - cam.view.left());
        const dy = @intToFloat(f32, dest[1] - cam.view.top());
        var t: zm.Mat = zm.scaling(p.scale, p.scale, 1);
        if (p.spec.rotation == .no_rotation) {
            // do nothing
        } else {
            t = zm.mul(t, zm.rotationZ(p.angle));
        }
        t = zm.mul(t, zm.translation(dx, dy, 0));
        var color_a = if (p.fadeout_timer) |timer| @floatToInt(u8, timer.invProgressClamped(world.world_frame) * 255) else 255;
        renderers.r_batch.drawQuadTransformed(.{
            .src = animator.getCurrentRect().toRectf(),
            .transform = t,
            .color = .{ 255, 255, 255, color_a },
        });
    }
    renderers.r_batch.end();
}

fn renderFloatingText(
    renderers: *RenderServices,
    world: *World,
    cam: Camera,
    alpha: f64,
    params: bmfont.BitmapFontParams,
) void {
    renderers.r_font.begin(params);
    for (world.floating_text.slice()) |*t| {
        const dest_pos = t.getInterpWorldPosition(alpha);
        var dest = Rect.init(dest_pos[0], dest_pos[1], 0, 0);
        dest.inflate(16, 16);
        dest.translate(-cam.view.left(), -cam.view.top());
        // a nice curve that fades rapidly around 70%
        const a_coef = 1 - std.math.pow(f32, t.invLifePercent(), 5);
        renderers.r_font.drawText(
            t.textSlice(),
            .{
                .dest = dest,
                .color = .{
                    t.color[0],
                    t.color[1],
                    t.color[2],
                    @floatToInt(u8, 255 * a_coef),
                },
                .v_alignment = .middle,
                .h_alignment = .center,
            },
        );
    }
    renderers.r_font.end();
}

fn renderTowerBases(
    renderers: *RenderServices,
    world: *World,
    cam: Camera,
    selected_tower: ?wo.TowerId,
) void {
    const t_special = renderers.texman.getNamedTexture("special.png");
    var highlight_mag = @floatCast(f32, 0.5 * (1.0 + std.math.sin(@intToFloat(f64, std.time.milliTimestamp()) / 500.0)));

    // render tower bases
    renderers.r_batch.begin(.{
        .texture = t_special,
        .flash_r = 0,
        .flash_g = 255,
        .flash_b = 0,
    });
    for (world.towers.slice()) |*t| {
        renderers.r_batch.drawQuad(.{
            .src = Rectf.init(0, 7 * 16, 16, 16),
            .dest = Rect.init(@intCast(i32, t.world_x) - cam.view.left(), @intCast(i32, t.world_y) - cam.view.top(), 16, 16).toRectf(),
            .flash = t.id.eql(selected_tower),
            .flash_mag = highlight_mag,
        });
    }
    renderers.r_batch.end();
}

fn renderTowers(
    renderers: *RenderServices,
    world: *World,
    cam: Camera,
    selected_tower: ?wo.TowerId,
) void {
    const t_characters = renderers.texman.getNamedTexture("characters.png");

    var highlight_mag = @floatCast(f32, 0.5 * (1.0 + std.math.sin(@intToFloat(f64, std.time.milliTimestamp()) / 500.0)));

    // render tower characters
    renderers.r_batch.begin(.{
        .texture = t_characters,
        .flash_r = 0,
        .flash_g = 255,
        .flash_b = 0,
    });
    for (world.towers.slice()) |*t| {
        if (t.animator) |animator| {
            // shift up on Y so the character is standing in the center of the tile
            renderers.r_batch.drawQuad(.{
                .src = animator.getCurrentRect().toRectf(),
                .dest = Rect.init(@intCast(i32, t.world_x) - cam.view.left(), @intCast(i32, t.world_y) - 4 - cam.view.top(), 16, 16).toRectf(),
                .flash = t.id.eql(selected_tower),
                .flash_mag = highlight_mag,
                .color = t.spec.tint_rgba,
            });
        }
    }
    renderers.r_batch.end();
}

fn renderMonsters(
    world: *World,
    cam: Camera,
    a: f64,
    buf: DrawQueue,
) void {
    for (world.monsters.slice(), 0..) |*m, i| {
        const animator = m.animator orelse continue;
        var color: [4]u8 = m.spec.color;
        if (m.slow_frames > 0) {
            color = mathutil.colorMulU8(4, color, .{ 0x80, 0x80, 0xFF, 0xFF });
        }
        const w = m.getInterpWorldPosition(a);
        buf[i] = .{
            .opts = .{
                .src = animator.getCurrentRect().toRectf(),
                .dest = Rect.init(@intCast(i32, w[0]) - cam.view.left(), @intCast(i32, w[1]) - cam.view.top(), 16, 16).toRectf(),
                .flash = m.flash_frames > 0,
                .color = color,
            },
        };
    }
}

fn renderGoal(
    renderers: *RenderServices,
    world: *World,
    cam: Camera,
    a: f64,
) void {
    _ = a;

    const goal = world.goal orelse return;

    renderers.r_batch.begin(.{
        .texture = renderers.texman.getNamedTexture("special.png"),
    });
    const dest = Rect.init(
        @intCast(i32, goal.world_x) - cam.view.left(),
        @intCast(i32, goal.world_y) - cam.view.top(),
        16,
        16,
    );
    renderers.r_batch.drawQuad(.{ .src = goal.animator.getCurrentRect().toRectf(), .dest = dest.toRectf() });
    renderers.r_batch.end();
}

fn renderHealthBars(
    renderers: *RenderServices,
    world: *World,
    cam: Camera,
    a: f64,
) void {
    renderers.r_quad.begin(.{});
    for (world.monsters.slice()) |m| {
        // no health bar for healthy enemies
        if (m.hp == m.spec.max_hp) {
            continue;
        }
        const w = m.getInterpWorldPosition(a);
        var dest_red = Rect.init(w[0] - cam.view.left(), w[1] - 4 - cam.view.top(), 16, 1);
        var dest_border = dest_red;
        dest_border.inflate(1, 1);
        dest_red.w = @floatToInt(i32, @intToFloat(f32, dest_red.w) * @intToFloat(f32, m.hp) / @intToFloat(f32, m.spec.max_hp));
        renderers.r_quad.drawQuadRGBA(dest_border, 0, 0, 0, 255);
        renderers.r_quad.drawQuadRGBA(dest_red, 255, 0, 0, 255);
    }
    renderers.r_quad.end();
}

fn renderStolenHearts(
    renderers: *RenderServices,
    world: *World,
    cam: Camera,
    a: f64,
    heart_animator: anim.Animator,
) void {
    renderers.r_batch.begin(.{
        .texture = renderers.texman.getNamedTexture("special.png"),
    });
    for (world.monsters.slice()) |m| {
        const w = m.getInterpWorldPosition(a);
        if (m.carrying_life) {
            var src = heart_animator.getCurrentRect();
            var dest = Rect.init(w[0] - cam.view.left(), w[1] - cam.view.top(), 16, 16);
            renderers.r_batch.drawQuad(.{ .src = src.toRectf(), .dest = dest.toRectf() });
        }
    }
    renderers.r_batch.end();
}

fn renderGrid(
    renderers: *RenderServices,
    cam: Camera,
) void {
    var offset_x = @intToFloat(f32, @mod(cam.view.x, 16));
    var offset_y = @intToFloat(f32, @mod(cam.view.y, 16));
    var viewf = cam.view.toRectf();

    const width = @intToFloat(f32, renderers.output_width);
    const height = @intToFloat(f32, renderers.output_height);

    const grid_color = [4]u8{ 0, 0, 0, 50 };

    renderers.r_imm.beginUntextured();
    var y: f32 = 16;
    var x: f32 = 16;
    while (y < viewf.h + 16) : (y += 16) {
        const p0 = zm.f32x4(0 - offset_x, y - offset_y, 0, 1);
        const p1 = zm.f32x4(width - offset_x, y - offset_y, 0, 1);
        renderers.r_imm.drawLine(p0, p1, grid_color);
    }

    while (x < viewf.w + 16) : (x += 16) {
        const p0 = zm.f32x4(x - offset_x, 0 - offset_y, 0, 1);
        const p1 = zm.f32x4(x - offset_x, height - offset_y, 0, 1);
        renderers.r_imm.drawLine(p0, p1, grid_color);
    }
}

fn renderBlockedConstructionRects(
    renderers: *RenderServices,
    world: *World,
    cam: Camera,
) void {
    const min_tile_x = @intCast(usize, cam.view.left()) / 16;
    const min_tile_y = @intCast(usize, cam.view.top()) / 16;
    const max_tile_x = std.math.min(
        world.getWidth(),
        1 + @intCast(usize, cam.view.right()) / 16,
    );
    const max_tile_y = std.math.min(
        world.getHeight(),
        1 + @intCast(usize, cam.view.bottom()) / 16,
    );
    const map = world.map;

    renderers.r_quad.begin(.{});
    var y: usize = min_tile_y;
    var x: usize = 0;
    while (y < max_tile_y) : (y += 1) {
        x = min_tile_x;
        while (x < max_tile_x) : (x += 1) {
            const t = map.at2DPtr(.base, x, y);
            if (!t.flags.construction_blocked) {
                continue;
            }
            const dest = Rect{
                .x = @intCast(i32, x * 16) - cam.view.left(),
                .y = @intCast(i32, y * 16) - cam.view.top(),
                .w = 16,
                .h = 16,
            };
            var a = 0.3 * @sin(@intToFloat(f64, std.time.milliTimestamp()) / 500.0);
            a = std.math.max(a, 0);
            renderers.r_quad.drawQuadRGBA(dest, 255, 0, 0, @floatToInt(u8, a * 255.0));
        }
    }
    renderers.r_quad.end();
}

fn mouseToWorld(self: *PlayState) [2]i32 {
    const p = self.game.unproject(
        self.game.input.mouse.client_x,
        self.game.input.mouse.client_y,
    );
    return [2]i32{
        p[0] + self.camera.view.left(),
        p[1] + self.camera.view.top(),
    };
}

fn mouseToTile(self: *PlayState) tilemap.TileCoord {
    const p = self.mouseToWorld();
    return tilemap.TileCoord.initSignedWorld(p[0], p[1]);
}

fn renderRangeIndicatorForTower(renderers: *RenderServices, cam: Camera, spec: *const wo.TowerSpec, world_x: i32, world_y: i32) void {
    renderers.r_imm.beginUntextured();
    renderers.r_imm.drawCircle(
        32,
        zm.f32x4(@intToFloat(f32, world_x - cam.view.left()), @intToFloat(f32, world_y - cam.view.top()), 0, 0),
        spec.min_range,
        .{ 255, 0, 0, 255 },
    );
    renderers.r_imm.drawCircle(
        32,
        zm.f32x4(@intToFloat(f32, world_x - cam.view.left()), @intToFloat(f32, world_y - cam.view.top()), 0, 0),
        spec.max_range,
        .{ 0, 255, 0, 255 },
    );
}

fn renderPlacementIndicator(renderers: *RenderServices, world: *World, cam: Camera, tile_coord: tilemap.TileCoord) void {
    const color: [4]u8 = if (world.canBuildAt(tile_coord)) .{ 0, 255, 0, 128 } else .{ 255, 0, 0, 128 };
    const dest = Rect.init(
        @intCast(i32, tile_coord.worldX()) - cam.view.left(),
        @intCast(i32, tile_coord.worldY()) - cam.view.top(),
        16,
        16,
    );
    renderers.r_imm.beginUntextured();
    renderers.r_imm.drawQuadRGBA(dest, color);
}

fn renderDemolishIndicator(self: *PlayState, cam: Camera) void {
    if (self.interact_state != .demolish) {
        return;
    }

    const tc = self.mouseToTile();
    if (self.world.?.getTowerAt(tc) != null) {
        const dest = Rect.init(
            @intCast(i32, tc.x * 16) - cam.view.left(),
            @intCast(i32, tc.y * 16) - cam.view.top(),
            16,
            16,
        );
        self.game.renderers.r_imm.beginUntextured();
        self.game.renderers.r_imm.drawQuadRGBA(dest, .{ 255, 0, 0, 128 });
    }
}

fn debugRenderTileCollision(self: *PlayState, cam: Camera) void {
    const min_tile_x = @intCast(usize, cam.view.left()) / 16;
    const min_tile_y = @intCast(usize, cam.view.top()) / 16;
    const max_tile_x = std.math.min(
        self.world.?.getWidth(),
        1 + @intCast(usize, cam.view.right()) / 16,
    );
    const max_tile_y = std.math.min(
        self.world.?.getHeight(),
        1 + @intCast(usize, cam.view.bottom()) / 16,
    );
    const map = self.world.?.map;

    self.game.renderers.r_quad.begin(.{});
    var y: usize = min_tile_y;
    var x: usize = 0;
    while (y < max_tile_y) : (y += 1) {
        x = min_tile_x;
        while (x < max_tile_x) : (x += 1) {
            const t = map.getCollisionFlags2D(x, y);
            const dest = Rect{
                .x = @intCast(i32, x * 16) - cam.view.left(),
                .y = @intCast(i32, y * 16) - cam.view.top(),
                .w = 16,
                .h = 16,
            };
            if (t.all()) {
                self.game.renderers.r_quad.drawQuadRGBA(dest, 255, 0, 0, 150);
                continue;
            }

            if (t.from_left) {
                var left_rect = dest;
                left_rect.w = 4;
                self.game.renderers.r_quad.drawQuadRGBA(left_rect, 255, 0, 0, 150);
            }

            if (t.from_top) {
                var top_rect = dest;
                top_rect.h = 4;
                self.game.renderers.r_quad.drawQuadRGBA(top_rect, 255, 0, 0, 150);
            }

            if (t.from_bottom) {
                var bot_rect = dest;
                bot_rect.translate(0, bot_rect.h - 4);
                bot_rect.h = 4;
                self.game.renderers.r_quad.drawQuadRGBA(bot_rect, 255, 0, 0, 150);
            }

            if (t.from_right) {
                var right_rect = dest;
                right_rect.translate(right_rect.w - 4, 0);
                right_rect.w = 4;
                self.game.renderers.r_quad.drawQuadRGBA(right_rect, 255, 0, 0, 150);
            }
        }
    }

    for (self.world.?.monsters.slice()) |m| {
        var wc = m.getWorldCollisionRect();
        wc.translate(-cam.view.left(), -cam.view.top());
        self.game.renderers.r_quad.drawQuadRGBA(
            wc,
            0,
            0,
            255,
            150,
        );
    }
    for (self.world.?.projectiles.slice()) |p| {
        var wc = p.getWorldCollisionRect();
        wc.translate(-cam.view.left(), -cam.view.top());
        self.game.renderers.r_quad.drawQuadRGBA(
            wc,
            0,
            0,
            255,
            150,
        );
    }
    self.game.renderers.r_quad.end();

    const tile_coord = self.mouseToTile();
    const t0 = self.world.?.map.at2DPtr(.base, tile_coord.x, tile_coord.y);
    const t1 = self.world.?.map.at2DPtr(.detail, tile_coord.x, tile_coord.y);
    var textbuf: [256]u8 = undefined;
    const slice = std.fmt.bufPrint(&textbuf, "coord: {d},{d}\nbase: {d}\ndetail: {d}", .{ tile_coord.x, tile_coord.y, t0.id, t1.id }) catch unreachable;
    self.game.renderers.r_font.begin(.{
        .texture = self.game.texman.getNamedTexture("CommonCase.png"),
        .spec = &self.fontspec,
    });
    self.game.renderers.r_font.drawText(slice, .{
        .dest = Rect.init(0, 0, Game.INTERNAL_WIDTH, Game.INTERNAL_HEIGHT),
        .color = .{ 255, 255, 255, 255 },
        .h_alignment = .left,
        .v_alignment = .top,
    });
    self.game.renderers.r_font.end();
}

pub fn restartCurrentWorld(self: *PlayState) void {
    if (self.current_mapid) |mapid| {
        self.loadWorld(mapid);
    } else {
        std.log.err("Tried to restart current world but current_mapid is null", .{});
        std.process.exit(1);
    }
}

pub fn loadWorld(self: *PlayState, mapid: u32) void {
    if (self.world) |world| {
        world.destroy();
        self.world = null;
    }
    if (self.music_params) |params| {
        params.done.store(true, .SeqCst);
        params.release();
        self.music_params = null;
    }

    var filename_buf: [32]u8 = undefined;
    const filename = wo.bufPrintWorldFilename(&filename_buf, mapid) catch unreachable;

    var world = wo.loadWorldFromJson(self.game.allocator, filename) catch |err| {
        std.log.err("Failed to load world: {!}", .{err});
        std.process.exit(1);
    };

    // get this loading asap
    if (world.music_filename) |music_filename| {
        self.music_params = self.game.audio.playMusic(music_filename, .{
            .start_paused = true,
        });
    }

    createMinimap(&self.game.renderers, world, self.t_minimap) catch |err| {
        std.log.err("Failed to create minimap: {!}", .{err});
        std.process.exit(1);
    };

    self.current_mapid = mapid;

    // Init camera for this map

    if (world.play_area) |area| {
        self.camera.bounds = area;
    } else {
        self.camera.bounds = Rect.init(
            0,
            0,
            @intCast(i32, world.getWidth() * 16),
            @intCast(i32, world.getHeight() * 16),
        );
    }

    if (world.goal) |goal| {
        self.camera.view.centerOn(@intCast(i32, goal.world_x), @intCast(i32, goal.world_y));
    } else {
        self.camera.view.x = 0;
        self.camera.view.y = 0;
    }
    self.camera.clampToBounds();

    self.prev_camera = self.camera;

    // must be set before calling spawnMonster since it's used for audio parameters...
    // should probably clean this up eventually
    world.view = self.camera.view;
    world.setNextWaveTimer(15);

    if (world.remainingWaveCount() == 0) {
        // We will stay in this state, just nothing will happen
        std.log.warn("World `{s}` has no waves", .{filename});
    }

    self.world = world;
}

fn createMinimap(
    renderers: *RenderServices,
    world: *World,
    t_minimap: *Texture,
) !void {
    const range = world.getPlayableRange();
    // TODO: probably should handle this in texture manager
    if (t_minimap.handle != 0) {
        gl.deleteTextures(1, &t_minimap.handle);
        gl.genTextures(1, &t_minimap.handle);
    }
    t_minimap.width = @intCast(u32, range.getWidth());
    t_minimap.height = @intCast(u32, range.getHeight());

    var fbo: gl.GLuint = 0;
    gl.genFramebuffers(1, &fbo);
    defer gl.deleteFramebuffers(1, &fbo);
    gl.bindFramebuffer(gl.FRAMEBUFFER, fbo);

    gl.bindTexture(gl.TEXTURE_2D, t_minimap.handle);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.REPEAT);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.REPEAT);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.NEAREST);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.NEAREST);
    gl.texImage2D(gl.TEXTURE_2D, 0, gl.RGBA, @intCast(gl.GLsizei, t_minimap.width), @intCast(gl.GLsizei, t_minimap.height), 0, gl.RGBA, gl.UNSIGNED_BYTE, null);
    gl.framebufferTexture2D(gl.FRAMEBUFFER, gl.COLOR_ATTACHMENT0, gl.TEXTURE_2D, t_minimap.handle, 0);
    if (gl.checkFramebufferStatus(gl.FRAMEBUFFER) != gl.FRAMEBUFFER_COMPLETE) {
        std.log.err("createMinimap: failed to create framebuffer", .{});
        std.process.exit(1);
    }
    gl.viewport(0, 0, @intCast(c_int, t_minimap.width), @intCast(c_int, t_minimap.height));
    renderers.r_batch.setOutputDimensions(t_minimap.width, t_minimap.height);
    renderers.r_quad.setOutputDimensions(t_minimap.width, t_minimap.height);
    renderMinimapLayer(renderers, world.map, .base, .terrain, range);
    renderMinimapLayer(renderers, world.map, .base, .special, range);
    renderMinimapLayer(renderers, world.map, .detail, .terrain, range);
    renderMinimapLayer(renderers, world.map, .detail, .special, range);
    renderMinimapBlockage(renderers, world.map, range);
}

fn renderMinimapBlockage(
    renderers: *RenderServices,
    map: tilemap.Tilemap,
    range: TileRange,
) void {
    renderers.r_quad.begin(.{});
    var y: usize = range.min.y;
    var x: usize = 0;
    while (y <= range.max.y) : (y += 1) {
        x = range.min.x;
        while (x <= range.max.x) : (x += 1) {
            const t = map.at2DPtr(.base, x, y);
            const dest = Rectf.init(
                @intToFloat(f32, x - range.min.x),
                @intToFloat(f32, y - range.min.y),
                1.0,
                1.0,
            );
            if (t.flags.construction_blocked) {
                renderers.r_quad.drawQuad(.{
                    .dest = dest,
                    .color = .{ 255, 0, 0, 128 },
                });
            }
        }
    }
    renderers.r_quad.end();
}

fn renderMinimapLayer(
    renderers: *RenderServices,
    map: tilemap.Tilemap,
    layer: tilemap.TileLayer,
    bank: tilemap.TileBank,
    range: TileRange,
) void {
    const source_texture = switch (bank) {
        .none => return,
        .terrain => renderers.texman.getNamedTexture("terrain.png"),
        .special => renderers.texman.getNamedTexture("special.png"),
    };
    const n_tiles_wide = @intCast(u16, source_texture.width / 16);
    renderers.r_batch.begin(.{
        .texture = source_texture,
    });
    var y: usize = range.min.y;
    var x: usize = 0;
    while (y <= range.max.y) : (y += 1) {
        x = range.min.x;
        while (x <= range.max.x) : (x += 1) {
            const t = map.at2DPtr(layer, x, y);
            if (t.bank != bank) {
                continue;
            }
            const src = Rect{
                .x = (t.id % n_tiles_wide) * 16,
                .y = (t.id / n_tiles_wide) * 16,
                .w = 16,
                .h = 16,
            };
            const dest = Rectf.init(
                @intToFloat(f32, x - range.min.x),
                @intToFloat(f32, y - range.min.y),
                1.0,
                1.0,
            );
            renderers.r_batch.drawQuad(.{
                .src = src.toRectf(),
                .dest = dest,
            });
        }
    }
    renderers.r_batch.end();
}

pub fn beginTransitionGameOver(self: *PlayState) void {
    self.sub = .gamelose_fadeout;
    self.fade_timer = FrameTimer.initSeconds(self.game.frame_counter, 1);
}

fn beginTransitionGameWin(self: *PlayState) void {
    self.sub = .gamewin_fadeout;
    self.fade_timer = FrameTimer.initSeconds(self.game.frame_counter, 1);
}

fn renderWipe(self: *PlayState, alpha: f64) void {
    if (self.sub != .wipe_fadein) {
        return;
    }

    const t0 = self.fade_timer.invProgressClamped(std.math.max(self.game.frame_counter -| 1, self.fade_timer.frame_start));
    const t1 = self.fade_timer.invProgressClamped(self.game.frame_counter);
    const tx = zm.lerpV(t0, t1, @floatCast(f32, alpha));

    const right = @floatToInt(i32, zm.lerpV(-wipe_scanline_width, Game.INTERNAL_WIDTH, tx));
    const a = @floatToInt(u8, 255.0 * tx);

    self.game.renderers.r_imm.beginUntextured();
    self.game.renderers.r_imm.drawQuadRGBA(Rect.init(0, 0, Game.INTERNAL_WIDTH, Game.INTERNAL_HEIGHT), .{ 0, 0, 0, a });

    self.game.renderers.r_quad.begin(.{});
    for (&self.wipe_scanlines, 0..) |*sc, i| {
        const rect = Rect.init(0, @intCast(i32, i), right + sc.*, 1);
        self.game.renderers.r_quad.drawQuadRGBA(rect, 0, 0, 0, 255);
    }
    self.game.renderers.r_quad.end();

    self.game.renderers.r_font.begin(.{
        .texture = self.game.texman.getNamedTexture("CommonCase.png"),
        .spec = &self.fontspec,
    });
    self.game.renderers.r_font.drawText("Loading...", .{
        .dest = Rect.init(0, 0, Game.INTERNAL_WIDTH, Game.INTERNAL_HEIGHT),
        .color = .{ 255, 255, 255, a },
        .h_alignment = .center,
        .v_alignment = .middle,
    });
    self.game.renderers.r_font.end();
}

fn renderFade(self: *PlayState) void {
    const d: rend.FadeDirection = switch (self.sub) {
        .gamewin_fadeout, .gamelose_fadeout => .out,
        else => return,
    };
    rend.renderLinearFade(self.game.renderers, d, self.fade_timer.progressClamped(self.game.frame_counter));
}

fn updateUpgradeButtons(self: *PlayState) void {
    self.ui_upgrade_panel.visible = self.interact_state == .select;
    if (!self.ui_upgrade_panel.visible) {
        return;
    }

    const t = self.world.?.towers.getPtr(self.interact_state.select.selected_tower);
    const s = t.spec;
    var i: usize = 0;
    while (i < 3) : (i += 1) {
        if (s.upgrades[i]) |spec| {
            self.ui_upgrade_buttons[i].tooltip_text = self.getCachedTooltip(spec);
            self.ui_upgrade_buttons[i].setTexture(self.getCachedUpgradeButtonTexture(spec));
            self.ui_upgrade_states[i].play_state = self;
            self.ui_upgrade_states[i].tower_spec = spec;
            self.ui_upgrade_states[i].tower_id = self.interact_state.select.selected_tower;
            self.ui_upgrade_states[i].slot = @intCast(u8, i);
            if (self.world.?.canAfford(spec)) {
                self.ui_upgrade_buttons[i].state = .normal;
            } else {
                self.ui_upgrade_buttons[i].state = .disabled;
            }
        } else {
            self.ui_upgrade_buttons[i].setTexture(self.game.texman.getNamedTexture("button_base.png"));
            self.ui_upgrade_buttons[i].tooltip_text = null;
            self.ui_upgrade_buttons[i].state = .disabled;
        }
    }
}

fn getCachedUpgradeButtonTexture(self: *PlayState, spec: *const wo.TowerSpec) *const Texture {
    var gop = self.upgrade_texture_cache.getOrPut(self.game.allocator, spec) catch unreachable;
    if (!gop.found_existing) {
        const base_texture = self.game.texman.getNamedTexture("button_base.png");
        const spec_texture = self.game.texman.getNamedTexture("characters.png");
        const spec_rect = spec.anim_set.?.createAnimator("down").getCurrentRect();
        gop.value_ptr.* = self.button_generator.createButtonWithBadge(base_texture, spec_texture, spec_rect, spec.tint_rgba);
    }
    return gop.value_ptr.*;
}

fn renderTooltipString(allocator: std.mem.Allocator, spec: *const wo.TowerSpec) ![]const u8 {
    const template = spec.tooltip orelse return "[no tooltip]";
    var rendered_tip = try std.ArrayListUnmanaged(u8).initCapacity(allocator, template.len);
    errdefer rendered_tip.deinit(allocator);
    var tip_writer = rendered_tip.writer(allocator);
    var i: usize = 0;
    while (i < template.len) {
        const ch = template[i];
        if (ch == '%') {
            const index_of_end = std.mem.indexOfScalarPos(u8, template, i + 1, '%');
            if (index_of_end) |j| {
                const var_name = template[i + 1 .. j];
                if (var_name.len == 0) {
                    try tip_writer.writeByte('%');
                } else if (std.mem.eql(u8, var_name, "gold_cost")) {
                    try tip_writer.print("{d}", .{spec.gold_cost});
                } else {
                    return error.UnknownVarName;
                }
                i = j + 1;
            } else {
                return error.UnmatchedPercent;
            }
        } else {
            try tip_writer.writeByte(ch);
            i += 1;
        }
    }
    return rendered_tip.toOwnedSlice(allocator);
}

fn getCachedTooltip(self: *PlayState, spec: *const wo.TowerSpec) []const u8 {
    var gop = self.tooltip_cache.getOrPut(self.game.allocator, spec) catch unreachable;
    if (!gop.found_existing) {
        gop.value_ptr.* = renderTooltipString(self.game.allocator, spec) catch |err| {
            std.log.warn("Failed to render tooltip string: {!}; template: `{s}`", .{ err, spec.tooltip orelse "[no tooltip]" });
            gop.value_ptr.* = "[tooltip error]";
            return gop.value_ptr.*;
        };
    }
    return gop.value_ptr.*;
}

const TextureManager = @import("texture.zig").TextureManager;
const ButtonTextureGenerator = struct {
    texman: *TextureManager,
    r_batch: *SpriteBatch,
    fbo: gl.GLuint,

    fn init(texman: *TextureManager, r_batch: *SpriteBatch) ButtonTextureGenerator {
        var fbo: gl.GLuint = 0;
        gl.genFramebuffers(1, &fbo);
        return .{
            .texman = texman,
            .r_batch = r_batch,
            .fbo = fbo,
        };
    }

    fn deinit(self: *ButtonTextureGenerator) void {
        gl.deleteFramebuffers(1, &self.fbo);
    }

    fn createButtonWithBadge(self: *ButtonTextureGenerator, button_base: *const Texture, badge: *const Texture, badge_rect: Rect, badge_color: [4]u8) *Texture {
        var t = self.texman.createInMemory();
        t.width = button_base.width;
        t.height = button_base.height;

        gl.bindFramebuffer(gl.FRAMEBUFFER, self.fbo);

        gl.bindTexture(gl.TEXTURE_2D, t.handle);
        gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.REPEAT);
        gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.REPEAT);
        gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.NEAREST);
        gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.NEAREST);
        gl.texImage2D(gl.TEXTURE_2D, 0, gl.RGBA, @intCast(gl.GLsizei, button_base.width), @intCast(gl.GLsizei, button_base.height), 0, gl.RGBA, gl.UNSIGNED_BYTE, null);
        gl.framebufferTexture2D(gl.FRAMEBUFFER, gl.COLOR_ATTACHMENT0, gl.TEXTURE_2D, t.handle, 0);
        if (gl.checkFramebufferStatus(gl.FRAMEBUFFER) != gl.FRAMEBUFFER_COMPLETE) {
            std.log.err("createButtonWithBadge: failed to create framebuffer", .{});
            std.process.exit(1);
        }
        gl.viewport(0, 0, @intCast(c_int, t.width), @intCast(c_int, t.height));
        self.r_batch.setOutputDimensions(t.width, t.height);
        self.r_batch.begin(.{
            .texture = button_base,
        });
        self.r_batch.drawQuad(.{
            .src = Rect.init(0, 0, @intCast(i32, button_base.width), @intCast(i32, button_base.height)).toRectf(),
            .dest = Rect.init(0, 0, @intCast(i32, t.width), @intCast(i32, t.height)).toRectf(),
        });
        self.r_batch.end();
        self.r_batch.begin(.{
            .texture = badge,
        });
        var i: u8 = 0;
        while (i < 4) : (i += 1) {
            const button_frame_rect = Rect.init(0, i * 32, 32, 32);
            const desired_center = button_frame_rect.centerPoint();
            var adjusted_dest = badge_rect;
            adjusted_dest.centerOn(desired_center[0], desired_center[1]);
            const color_mul = if (i == 3) [4]u8{ 128, 128, 128, 255 } else [4]u8{ 255, 255, 255, 255 };
            self.r_batch.drawQuad(.{
                .src = badge_rect.toRectf(),
                .dest = adjusted_dest.toRectf(),
                .color = mathutil.colorMulU8(4, badge_color, color_mul),
            });
        }
        self.r_batch.end();
        return t;
    }
};

fn beginWipe(self: *PlayState) void {
    self.sub = .wipe_fadein;
    self.fade_timer = FrameTimer.initSeconds(self.game.frame_counter, 2);

    var rng = std.rand.DefaultPrng.init(@intCast(u64, std.time.milliTimestamp()));
    var r = rng.random();
    for (&self.wipe_scanlines) |*sc| {
        sc.* = r.intRangeLessThan(i32, 0, wipe_scanline_width);
    }
}

fn endWipe(self: *PlayState) void {
    self.wave_timer.state_timer = FrameTimer.initSeconds(self.world.?.world_frame, 2);
}

fn renderWaveTimer(self: *PlayState, alpha: f64) void {
    const next_wave_timer = self.world.?.next_wave_timer orelse return;

    var rect = self.wave_timer.text_measure;
    var box_rect = rect;
    box_rect.inflate(4, 4);

    box_rect.x = @divFloor(Game.INTERNAL_WIDTH - box_rect.w, 2);
    box_rect.y = @divFloor(Game.INTERNAL_HEIGHT - box_rect.h, 2);

    switch (self.wave_timer.state) {
        .middle_screen => {},
        .move_to_corner => {
            const t0 = self.wave_timer.state_timer.invProgressClamped(std.math.max(self.world.?.world_frame -| 1, self.wave_timer.state_timer.frame_start));
            const t1 = self.wave_timer.state_timer.invProgressClamped(self.world.?.world_frame);
            const tx = zm.lerpV(t0, t1, @floatCast(f32, alpha));
            const k = 1 - std.math.pow(f32, tx, 3);
            box_rect.x = @floatToInt(i32, zm.lerpV(@intToFloat(f32, box_rect.x), 0.0, k));
            box_rect.y = @floatToInt(i32, zm.lerpV(@intToFloat(f32, box_rect.y), 0.0, k));
        },
        .corner => {
            box_rect.x = 0;
            box_rect.y = 0;
        },
    }

    rect.centerOn(box_rect.centerPoint()[0], box_rect.centerPoint()[1]);

    var total_alpha: f32 = 1.0;
    var text_alpha: u8 = 255;
    const sec = next_wave_timer.remainingSecondsUnbounded(self.world.?.world_frame);
    if (sec <= 5) {
        const diff = 5.0 - sec;
        text_alpha = @floatToInt(u8, (0.5 * (1.0 + std.math.cos(diff * 8.0))) * 255.0);
    }
    if (sec < 0) {
        total_alpha = 1.0 - std.math.clamp(-sec, 0, 2.0) / 2.0;
    }

    self.game.renderers.r_quad.begin(.{});
    self.game.renderers.r_quad.drawQuadRGBA(box_rect, 0, 0, 0, @floatToInt(u8, total_alpha * 128));
    self.game.renderers.r_quad.end();

    self.game.renderers.r_font.begin(.{
        .texture = self.game.texman.getNamedTexture("CommonCase.png"),
        .spec = &self.fontspec,
    });
    self.game.renderers.r_font.drawText(self.wave_timer.wave_timer_text, .{
        .dest = box_rect,
        .color = .{ 255, 255, 255, @floatToInt(u8, total_alpha * @intToFloat(f32, text_alpha)) },
        .h_alignment = .center,
        .v_alignment = .middle,
    });
    self.game.renderers.r_font.end();
}

fn setInitialUIState(self: *PlayState) void {
    self.paused = false;
    self.fast = false;
    self.btn_pause_resume.setTexture(self.t_pause);
    self.btn_fastforward.setTexture(self.t_fast_off);
    self.wave_timer = .{
        .fontspec = &self.fontspec,
    };
}

fn callWave(self: *PlayState) void {
    if (self.world) |world| {
        if (world.startNextWave()) {
            self.game.audio.playSound("assets/sounds/click.ogg", .{}).release();
        }
    } else {
        std.log.warn("Attempted to call wave with no world loaded", .{});
    }
}

fn togglePause(self: *PlayState) void {
    self.game.audio.playSound("assets/sounds/click.ogg", .{}).release();
    self.paused = !self.paused;
    if (!self.paused) {
        self.btn_pause_resume.tooltip_text = "Pause (Space)";
        self.btn_pause_resume.setTexture(self.t_pause);
    } else {
        self.btn_pause_resume.tooltip_text = "Resume (Space)";
        self.btn_pause_resume.setTexture(self.t_resume);
    }
}

fn toggleFast(self: *PlayState) void {
    self.game.audio.playSound("assets/sounds/click.ogg", .{}).release();
    self.fast = !self.fast;
    if (!self.fast) {
        self.btn_fastforward.setTexture(self.t_fast_off);
    } else {
        self.btn_fastforward.setTexture(self.t_fast_on);
    }
}

fn upgradeSelectedTower(self: *PlayState, slot: u8) void {
    if (self.interact_state == .select) {
        var tower_to_upgrade = self.world.?.towers.getPtr(self.interact_state.select.selected_tower);
        const upgrade_spec = tower_to_upgrade.spec.upgrades[slot];
        if (upgrade_spec) |spec| {
            if (self.world.?.canAfford(spec)) {
                self.game.audio.playSound("assets/sounds/coindrop.ogg", .{}).release();
                self.world.?.player_gold -= spec.gold_cost;
                tower_to_upgrade.upgradeInto(spec);
                self.updateUpgradeButtons();
            }
        }
    }
}

fn sellSelectedTower(self: *PlayState) void {
    if (self.interact_state == .select) {
        self.world.?.sellTower(self.interact_state.select.selected_tower);
        self.interact_state = .none;
    }
}

fn enterDemolishMode(self: *PlayState) void {
    self.game.audio.playSound("assets/sounds/click.ogg", .{}).release();
    self.interact_state = .demolish;
}

fn enterBuildWallMode(self: *PlayState) void {
    self.game.audio.playSound("assets/sounds/click.ogg", .{}).release();
    self.interact_state = .{ .build = InteractStateBuild{ .tower_spec = &wo.t_wall } };
}

fn enterBuildTowerMode(self: *PlayState) void {
    self.game.audio.playSound("assets/sounds/click.ogg", .{}).release();
    self.interact_state = .{ .build = InteractStateBuild{ .tower_spec = &wo.t_recruit } };
}
