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
const bmfont = @import("bmfont.zig");
const QuadBatch = @import("QuadBatch.zig");
const BitmapFont = bmfont.BitmapFont;
const particle = @import("particle.zig");
const audio = @import("audio.zig");
// eventually should probably eliminate this dependency
const sdl = @import("sdl.zig");
const ui = @import("ui.zig");
const Texture = @import("texture.zig").Texture;
const FrameTimer = @import("timing.zig").FrameTimer;
const GenHandle = @import("slotmap.zig").GenHandle;
const WorldRenderer = @import("WorldRenderer.zig");
const mathutil = @import("mathutil.zig");

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
    none: void,
    build: InteractStateBuild,
    select: InteractStateSelect,
    demolish,
};

const UpgradeButtonState = struct {
    play_state: *PlayState,
    tower_id: wo.TowerId,
    tower_spec: *const wo.TowerSpec,
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

game: *Game,
camera: Camera = DEFAULT_CAMERA,
prev_camera: Camera = DEFAULT_CAMERA,
r_world: *WorldRenderer,
heart_anim: anim.Animator = anim.a_goal_heart.animationSet().createAnimator("default"),
world: wo.World,
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
upgrade_texture_cache: std.AutoHashMapUnmanaged(*const wo.TowerSpec, *Texture) = .{},

particle_sys: particle.ParticleSystem,

tooltip_cache: std.AutoArrayHashMapUnmanaged(*const wo.TowerSpec, []const u8) = .{},

wipe_scanlines: [Game.INTERNAL_HEIGHT]i32 = undefined,

deb_render_tile_collision: bool = false,

rng: std.rand.DefaultPrng = std.rand.DefaultPrng.init(0),

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
        .world = wo.World.init(game.allocator),
        .fontspec = undefined,
        .fontspec_numbers = undefined,
        .ui_root = ui.Root.init(game.allocator, &game.sdl_backend),
        .t_minimap = game.texman.createInMemory(),
        // Created/destroyed in update()
        .frame_arena = undefined,
        // Initialized below
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
        .button_generator = undefined,
        .wave_timer = undefined,
        .r_world = undefined,
        .particle_sys = undefined,
    };

    self.particle_sys = try particle.ParticleSystem.initCapacity(game.allocator, 1024);
    errdefer self.particle_sys.deinit();

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

    const t_panel = self.game.texman.getNamedTexture("ui_panel.png");
    var ui_panel = try self.ui_root.createPanel();
    ui_panel.rect = Rect.init(0, 0, @intCast(i32, t_panel.width), @intCast(i32, t_panel.height));
    ui_panel.rect.alignRight(Game.INTERNAL_WIDTH);
    ui_panel.background = .{ .texture = .{ .texture = t_panel } };
    try self.ui_root.addChild(ui_panel.control());

    var b_wall = try self.ui_root.createButton();
    b_wall.tooltip_text = self.getCachedTooltip(&wo.t_wall);
    b_wall.rect = Rect.init(16, 144, 32, 32);
    b_wall.texture_rects = makeStandardButtonRects(0, 0);
    b_wall.setTexture(self.t_wall);
    b_wall.ev_click.setCallback(self, onWallClick);
    try ui_panel.addChild(b_wall.control());

    var b_tower = try self.ui_root.createButton();
    b_tower.tooltip_text = self.getCachedTooltip(&wo.t_recruit);
    b_tower.rect = Rect.init(48, 144, 32, 32);
    b_tower.texture_rects = makeStandardButtonRects(0, 0);
    b_tower.setTexture(self.t_soldier);
    b_tower.ev_click.setCallback(self, onTowerClick);
    try ui_panel.addChild(b_tower.control());

    self.ui_minimap = try self.ui_root.createMinimap();
    self.ui_minimap.rect = Rect.init(16, 16, 64, 64);
    self.ui_minimap.texture = self.t_minimap;
    self.ui_minimap.setPanCallback(self, onMinimapPan);
    try ui_panel.addChild(self.ui_minimap.control());

    // TODO: replace with label-type control
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
    self.btn_pause_resume.tooltip_text = "Pause";
    try ui_panel.addChild(self.btn_pause_resume.control());
    self.btn_pause_resume.ev_click.setCallback(self, onPauseClick);

    self.btn_fastforward = try self.ui_root.createButton();
    self.btn_fastforward.setTexture(self.t_fast_off);
    self.btn_fastforward.rect = Rect.init(48, 208, 32, 32);
    self.btn_fastforward.texture_rects = makeStandardButtonRects(0, 0);
    self.btn_fastforward.tooltip_text = "Fast-forward";
    self.btn_fastforward.ev_click.setCallback(self, onFastForwardClick);
    try ui_panel.addChild(self.btn_fastforward.control());

    self.btn_demolish = try self.ui_root.createButton();
    self.btn_demolish.setTexture(self.t_demolish);
    self.btn_demolish.rect = Rect.init(16, 176, 32, 32);
    self.btn_demolish.tooltip_text = "Demolish\n\nReturns 50% of the total gold\ninvested into the tower.";
    self.btn_demolish.ev_click.setCallback(self, onDemolishClick);
    try ui_panel.addChild(self.btn_demolish.control());

    self.ui_upgrade_panel = try self.ui_root.createPanel();
    self.ui_upgrade_panel.rect = Rect.init(0, 0, 4 * 32, 32);
    self.ui_upgrade_panel.rect.centerOn(Game.INTERNAL_WIDTH / 2, 0);
    self.ui_upgrade_panel.rect.alignBottom(Game.INTERNAL_HEIGHT);
    self.ui_upgrade_panel.background = .{ .color = ui.ControlColor.black };
    try self.ui_root.addChild(self.ui_upgrade_panel.control());

    for (self.ui_upgrade_buttons) |*b, i| {
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
            b.*.tooltip_text = "Demolish\n\nReturns 50% of the total gold\ninvested into the tower.";
            b.*.ev_click.setCallback(self, onUpgradeDemolishClick);
        }
    }

    // TODO probably want a better way to manage this, direct IO shouldn't be here
    // TODO undefined minefield, need to be more careful. Can't deinit an undefined thing.
    self.fontspec = try loadFontSpec(self.game.allocator, "assets/tables/CommonCase.json");
    self.fontspec_numbers = try loadFontSpec(self.game.allocator, "assets/tables/floating_text.json");

    self.wave_timer = .{
        .fontspec = &self.fontspec,
    };

    return self;
}

fn onWallClick(button: *ui.Button, self: *PlayState) void {
    _ = button;
    self.game.audio.playSound("assets/sounds/click.ogg", .{}).release();
    self.interact_state = .{ .build = InteractStateBuild{
        .tower_spec = &wo.t_wall,
    } };
}

fn onTowerClick(button: *ui.Button, self: *PlayState) void {
    _ = button;
    self.game.audio.playSound("assets/sounds/click.ogg", .{}).release();
    self.interact_state = .{ .build = InteractStateBuild{
        .tower_spec = &wo.t_recruit,
    } };
}

fn onPauseClick(button: *ui.Button, self: *PlayState) void {
    self.game.audio.playSound("assets/sounds/click.ogg", .{}).release();
    self.paused = !self.paused;
    if (!self.paused) {
        button.tooltip_text = "Pause";
        button.setTexture(self.t_pause);
    } else {
        button.tooltip_text = "Resume";
        button.setTexture(self.t_resume);
    }
}

fn onFastForwardClick(button: *ui.Button, self: *PlayState) void {
    self.game.audio.playSound("assets/sounds/click.ogg", .{}).release();
    self.fast = !self.fast;
    if (!self.fast) {
        button.setTexture(self.t_fast_off);
    } else {
        button.setTexture(self.t_fast_on);
    }
}

fn onUpgradeClick(button: *ui.Button, upgrade: *UpgradeButtonState) void {
    _ = button;
    upgrade.play_state.game.audio.playSound("assets/sounds/coindrop.ogg", .{}).release();
    if (upgrade.play_state.world.canAfford(upgrade.tower_spec)) {
        upgrade.play_state.world.player_gold -= upgrade.tower_spec.gold_cost;
        upgrade.play_state.world.towers.getPtr(upgrade.tower_id).upgradeInto(upgrade.tower_spec);
        upgrade.play_state.updateUpgradeButtons();
    }
}

fn onUpgradeMouseEnter(button: *ui.Button, upgrade: *UpgradeButtonState) void {
    if (button.state == .disabled) {
        return;
    }
    upgrade.play_state.interact_state.select.hovered_spec = upgrade.tower_spec;
}

fn onUpgradeMouseLeave(button: *ui.Button, upgrade: *UpgradeButtonState) void {
    if (button.state == .disabled) {
        return;
    }
    upgrade.play_state.interact_state.select.hovered_spec = null;
}

fn onUpgradeDemolishClick(button: *ui.Button, self: *PlayState) void {
    std.debug.assert(self.interact_state == .select);
    _ = button;
    self.world.sellTower(self.interact_state.select.selected_tower);
    self.interact_state = .none;
}

fn onDemolishClick(button: *ui.Button, self: *PlayState) void {
    _ = button;
    self.game.audio.playSound("assets/sounds/click.ogg", .{}).release();
    self.interact_state = .demolish;
}

fn onMinimapPan(_: *ui.Minimap, self: *PlayState, x: f32, y: f32) void {
    self.camera.view.centerOn(
        @floatToInt(i32, x * @intToFloat(f32, self.camera.bounds.w)) + self.camera.bounds.x,
        @floatToInt(i32, y * @intToFloat(f32, self.camera.bounds.h)) + self.camera.bounds.y,
    );
    self.camera.clampToBounds();
}

fn loadFontSpec(allocator: std.mem.Allocator, filename: []const u8) !bmfont.BitmapFontSpec {
    var font_file = try std.fs.cwd().openFile(filename, .{});
    defer font_file.close();
    var spec_json = try font_file.readToEndAlloc(allocator, 1024 * 1024);
    defer allocator.free(spec_json);
    return try bmfont.BitmapFontSpec.initJson(allocator, spec_json);
}

pub fn destroy(self: *PlayState) void {
    if (self.music_params) |params| {
        params.release();
    }
    self.particle_sys.deinit();
    self.r_world.destroy(self.game.allocator);
    self.upgrade_texture_cache.deinit(self.game.allocator);
    for (self.tooltip_cache.values()) |str| {
        self.game.allocator.free(str);
    }
    self.tooltip_cache.deinit(self.game.allocator);
    self.button_generator.deinit();
    self.fontspec.deinit();
    self.fontspec_numbers.deinit();
    self.world.deinit();
    self.ui_root.deinit();
    self.game.allocator.destroy(self);
}

pub fn enter(self: *PlayState, from: ?Game.StateId) void {
    _ = from;
    self.setInitialUIState();
    self.beginWipe();
    // self.loadWorld("map01");
}

pub fn leave(self: *PlayState, to: ?Game.StateId) void {
    _ = self;
    _ = to;
}

pub fn update(self: *PlayState) void {
    self.frame_arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer self.frame_arena.deinit();
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

    self.heart_anim.update();
    self.particle_sys.update(self.world.world_frame);

    self.world.view = self.camera.view;
    if (self.sub == .none and !self.paused) {
        self.world.update(arena);
        if (self.fast) {
            self.world.update(arena);
        }
    }
    self.updateUI();

    if (self.sub == .none and self.world.recoverable_lives == 0) {
        self.beginTransitionGameOver();
    }

    if (self.sub == .none and self.world.player_won) {
        self.beginTransitionGameWin();
    }

    if ((self.sub == .gamelose_fadeout or self.sub == .gamewin_fadeout) and self.fade_timer.expired(self.game.frame_counter)) {
        self.game.changeState(.levelselect);
    }

    if (self.music_params) |params| {
        const builtin = @import("builtin");
        if (builtin.mode == .Debug) {} else {
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
    self.ui_gold.text = std.fmt.bufPrint(&self.gold_text, "${d}", .{self.world.player_gold}) catch unreachable;
    self.ui_lives.text = std.fmt.bufPrint(&self.lives_text, "\x03{d}", .{self.world.lives_at_goal}) catch unreachable;
    self.wave_timer.setTimerText(self.world.next_wave_timer.remainingSeconds(self.world.world_frame));
    self.updateUpgradeButtons();
    if (self.wave_timer.state == .middle_screen and self.wave_timer.state_timer.expired(self.world.world_frame)) {
        self.wave_timer.state = .move_to_corner;
        self.wave_timer.state_timer = FrameTimer.initSeconds(self.world.world_frame, 2);
    } else if (self.wave_timer.state == .move_to_corner and self.wave_timer.state_timer.expired(self.world.world_frame)) {
        self.wave_timer.state = .corner;
    }
}

pub fn render(self: *PlayState, alpha: f64) void {
    const mouse_p = self.game.unproject(
        self.game.input.mouse.client_x,
        self.game.input.mouse.client_y,
    );

    gl.clearColor(0x64.0 / 255.0, 0x95.0 / 255.0, 0xED.0 / 255.0, 1);
    gl.clear(gl.COLOR_BUFFER_BIT);

    var cam_interp = Camera.lerp(self.prev_camera, self.camera, alpha);
    cam_interp.clampToBounds();

    self.r_world.renderTilemap(cam_interp, &self.world.map, self.game.frame_counter);
    self.renderGoal(cam_interp, alpha);
    self.renderMonsters(cam_interp, alpha);
    self.renderStolenHearts(cam_interp, alpha);
    self.renderTowers(cam_interp);
    self.renderFields(cam_interp, alpha);
    self.renderSpriteEffects(cam_interp, alpha);
    self.renderProjectiles(cam_interp, alpha);
    self.renderHealthBars(cam_interp, alpha);
    self.renderFloatingText(cam_interp, alpha);
    self.renderBlockedConstructionRects(cam_interp);
    self.renderGrid(cam_interp);
    // self.renderSelection(cam_interp);
    self.renderRangeIndicator(cam_interp);
    self.renderWaveTimer(alpha);
    if (!self.ui_root.isMouseOnElement(mouse_p[0], mouse_p[1])) {
        self.renderPlacementIndicator(cam_interp);
        self.renderDemolishIndicator(cam_interp);
    }

    if (self.deb_render_tile_collision) {
        self.debugRenderTileCollision(cam_interp);
    }

    ui.renderUI(.{
        .r_batch = &self.game.renderers.r_batch,
        .r_font = &self.game.renderers.r_font,
        .r_imm = &self.game.renderers.r_imm,
        .font_texture = self.game.texman.getNamedTexture("CommonCase.png"),
        .font_spec = &self.fontspec,
    }, self.ui_root);

    self.game.renderers.r_quad.setOutputDimensions(Game.INTERNAL_WIDTH, Game.INTERNAL_HEIGHT);
    for (self.world.spawns.slice()) |*s| {
        s.emitter.render(&self.game.renderers.r_quad, @floatCast(f32, alpha));
    }

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

    if (ev.type == .SDL_KEYDOWN) {
        switch (ev.key.keysym.sym) {
            sdl.SDLK_F1 => self.deb_render_tile_collision = !self.deb_render_tile_collision,
            sdl.SDLK_ESCAPE => if (self.interact_state == .build) {
                self.interact_state = .none;
            },
            else => {},
        }
    }

    if (ev.type == .SDL_MOUSEMOTION) {
        const tile_coord = self.mouseToTile();
        if (self.world.getTowerAt(tile_coord) != null) {
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
                if (self.world.canBuildAt(tile_coord) and self.world.canAfford(spec)) {
                    self.game.audio.playSound("assets/sounds/build.ogg", .{}).release();
                    _ = self.world.spawnTower(spec, tile_coord) catch unreachable;
                    self.world.player_gold -= spec.gold_cost;
                    if (sdl.SDL_GetModState() & sdl.KMOD_SHIFT == 0) {
                        self.interact_state = .none;
                    }
                }
            } else if (self.interact_state == .demolish) {
                const tile_coord = self.mouseToTile();
                if (self.world.getTowerAt(tile_coord)) |id| {
                    self.world.sellTower(id);
                    if (sdl.SDL_GetModState() & sdl.KMOD_SHIFT == 0) {
                        self.interact_state = .none;
                    }
                } else {
                    self.interact_state = .none;
                }
            } else {
                const tile_coord = self.mouseToTile();
                if (self.world.getTowerAt(tile_coord)) |id| {
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

fn renderFields(
    self: *PlayState,
    cam: Camera,
    alpha: f64,
) void {
    _ = alpha;
    const viewf = cam.view.toRectf();

    self.game.renderers.r_batch.begin(.{
        .texture = self.game.texman.getNamedTexture("special.png"),
    });

    const pos = self.particle_sys.particles.items(.pos);

    var i: usize = 0;

    while (i < self.particle_sys.num_alive) : (i += 1) {
        const s = self.particle_sys.particles.items(.scale)[i];
        const c = self.particle_sys.particles.items(.rgba)[i];
        var rf = Rectf.init(0, 0, 16, 16);
        rf.centerOn(pos[i][0], pos[i][1]);
        self.game.renderers.r_batch.drawQuadTransformed(.{
            .src = Rect.init(11 * 16, 0, 16, 16).toRectf(),
            .color = c,
            .transform = zm.mul(zm.scaling(s, s, 1), zm.translation(pos[i][0] - viewf.left(), pos[i][1] - viewf.top(), 0)),
        });
    }
    self.game.renderers.r_batch.end();
}

fn renderSpriteEffects(
    self: *PlayState,
    cam: Camera,
    alpha: f64,
) void {
    const t_special = self.game.texman.getNamedTexture("special.png");
    self.game.renderers.r_batch.begin(.{
        .texture = t_special,
    });
    for (self.world.sprite_effects.slice()) |t| {
        var animator = t.animator orelse continue;
        if (t.delay) |delay| {
            if (!delay.expired(self.world.world_frame)) {
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

        self.game.renderers.r_batch.drawQuadTransformed(.{
            .src = animator.getCurrentRect().toRectf(),
            .transform = transform,
        });
    }
    self.game.renderers.r_batch.end();
}

fn renderProjectiles(
    self: *PlayState,
    cam: Camera,
    alpha: f64,
) void {
    const t_special = self.game.texman.getNamedTexture("special.png");
    self.game.renderers.r_batch.begin(.{
        .texture = t_special,
    });
    for (self.world.projectiles.slice()) |t| {
        var animator = t.animator orelse continue;
        const dest = t.getInterpWorldPosition(alpha);

        if (t.spec.rotation == .no_rotation) {
            // TODO: use non-rotated variant
            self.game.renderers.r_batch.drawQuadRotated(
                animator.getCurrentRect(),
                @intToFloat(f32, dest[0] - cam.view.left()),
                @intToFloat(f32, dest[1] - cam.view.top()),
                0,
            );
        } else {
            self.game.renderers.r_batch.drawQuadRotated(
                animator.getCurrentRect(),
                @intToFloat(f32, dest[0] - cam.view.left()),
                @intToFloat(f32, dest[1] - cam.view.top()),
                t.angle,
            );
        }
    }
    self.game.renderers.r_batch.end();
}

fn renderFloatingText(
    self: *PlayState,
    cam: Camera,
    alpha: f64,
) void {
    self.game.renderers.r_font.begin(.{
        .texture = self.game.texman.getNamedTexture("floating_text.png"),
        .spec = &self.fontspec_numbers,
    });
    for (self.world.floating_text.slice()) |*t| {
        const dest_pos = t.getInterpWorldPosition(alpha);
        var dest = Rect.init(dest_pos[0], dest_pos[1], 0, 0);
        dest.inflate(16, 16);
        dest.translate(-cam.view.left(), -cam.view.top());
        // a nice curve that fades rapidly around 70%
        const a_coef = 1 - std.math.pow(f32, t.invLifePercent(), 5);
        self.game.renderers.r_font.drawText(
            t.textSlice(),
            .{
                .dest = dest,
                .color = @Vector(4, u8){
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
    self.game.renderers.r_font.end();
}

fn renderTowers(
    self: *PlayState,
    cam: Camera,
) void {
    const t_special = self.game.texman.getNamedTexture("special.png");
    const t_characters = self.game.texman.getNamedTexture("characters.png");

    var highlight_tower: ?wo.TowerId = null;
    var highlight_mag: f32 = 0.5 * (1.0 + std.math.sin(@intToFloat(f32, self.game.frame_counter) / 15.0));
    if (self.interact_state == .select) {
        highlight_tower = self.interact_state.select.selected_tower;
    }

    // render tower bases
    self.game.renderers.r_batch.begin(.{
        .texture = t_special,
        .flash_r = 0,
        .flash_g = 255,
        .flash_b = 0,
    });
    for (self.world.towers.slice()) |*t| {
        self.game.renderers.r_batch.drawQuad(.{
            .src = Rectf.init(0, 7 * 16, 16, 16),
            .dest = Rect.init(@intCast(i32, t.world_x) - cam.view.left(), @intCast(i32, t.world_y) - cam.view.top(), 16, 16).toRectf(),
            .flash = t.id.eql(highlight_tower),
            .flash_mag = highlight_mag,
        });
    }
    self.game.renderers.r_batch.end();

    // render tower characters
    self.game.renderers.r_batch.begin(.{
        .texture = t_characters,
        .flash_r = 0,
        .flash_g = 255,
        .flash_b = 0,
    });
    for (self.world.towers.slice()) |*t| {
        if (t.animator) |animator| {
            // shift up on Y so the character is standing in the center of the tile
            self.game.renderers.r_batch.drawQuad(.{
                .src = animator.getCurrentRect().toRectf(),
                .dest = Rect.init(@intCast(i32, t.world_x) - cam.view.left(), @intCast(i32, t.world_y) - 4 - cam.view.top(), 16, 16).toRectf(),
                .flash = t.id.eql(highlight_tower),
                .flash_mag = highlight_mag,
                .color = t.spec.tint_rgba,
            });
        }
    }
    self.game.renderers.r_batch.end();
}

fn renderMonsters(
    self: *PlayState,
    cam: Camera,
    a: f64,
) void {
    const t_chara = self.game.texman.getNamedTexture("characters.png");
    self.game.renderers.r_batch.begin(.{
        .texture = t_chara,
    });
    for (self.world.monsters.slice()) |m| {
        const w = m.getInterpWorldPosition(a);
        self.game.renderers.r_batch.drawQuadFlash(
            m.animator.?.getCurrentRect(),
            Rect.init(@intCast(i32, w[0]) - cam.view.left(), @intCast(i32, w[1]) - cam.view.top(), 16, 16),
            m.flash_frames > 0,
        );
    }
    self.game.renderers.r_batch.end();
}

fn renderGoal(
    self: *PlayState,
    cam: Camera,
    a: f64,
) void {
    _ = a;
    self.game.renderers.r_batch.begin(.{
        .texture = self.game.texman.getNamedTexture("special.png"),
    });
    const dest = Rect.init(
        @intCast(i32, self.world.goal.world_x) - cam.view.left(),
        @intCast(i32, self.world.goal.world_y) - cam.view.top(),
        16,
        16,
    );
    self.game.renderers.r_batch.drawQuad(.{ .src = self.world.goal.animator.getCurrentRect().toRectf(), .dest = dest.toRectf() });
    self.game.renderers.r_batch.end();
}

fn renderHealthBars(
    self: *PlayState,
    cam: Camera,
    a: f64,
) void {
    self.game.renderers.r_quad.begin(.{});
    for (self.world.monsters.slice()) |m| {
        // no health bar for healthy enemies
        if (m.hp == m.spec.max_hp) {
            continue;
        }
        const w = m.getInterpWorldPosition(a);
        var dest_red = Rect.init(w[0] - cam.view.left(), w[1] - 4 - cam.view.top(), 16, 1);
        var dest_border = dest_red;
        dest_border.inflate(1, 1);
        dest_red.w = @floatToInt(i32, @intToFloat(f32, dest_red.w) * @intToFloat(f32, m.hp) / @intToFloat(f32, m.spec.max_hp));
        self.game.renderers.r_quad.drawQuadRGBA(dest_border, 0, 0, 0, 255);
        self.game.renderers.r_quad.drawQuadRGBA(dest_red, 255, 0, 0, 255);
    }
    self.game.renderers.r_quad.end();
}

fn renderStolenHearts(
    self: *PlayState,
    cam: Camera,
    a: f64,
) void {
    self.game.renderers.r_batch.begin(.{
        .texture = self.game.texman.getNamedTexture("special.png"),
    });
    for (self.world.monsters.slice()) |m| {
        const w = m.getInterpWorldPosition(a);
        if (m.carrying_life) {
            var src = self.heart_anim.getCurrentRect();
            var dest = Rect.init(w[0] - cam.view.left(), w[1] - cam.view.top(), 16, 16);
            self.game.renderers.r_batch.drawQuad(.{ .src = src.toRectf(), .dest = dest.toRectf() });
        }
    }
    self.game.renderers.r_batch.end();
}

fn renderGrid(
    self: *PlayState,
    cam: Camera,
) void {
    if (self.interact_state != .build) {
        return;
    }

    var offset_x = @mod(cam.view.x, 16);
    var offset_y = @mod(cam.view.y, 16);
    var viewf = cam.view.toRectf();

    const m = zm.translation(@intToFloat(f32, -offset_x), @intToFloat(f32, -offset_y), 0);
    const grid_color = zm.f32x4(0, 0, 0, 0.2);

    self.game.renderers.r_imm.beginUntextured();
    var y: f32 = 16;
    var x: f32 = 16;
    while (y < viewf.h + 16) : (y += 16) {
        const p0 = zm.mul(zm.f32x4(0, y, 0, 1), m);
        const p1 = zm.mul(zm.f32x4(Game.INTERNAL_WIDTH, y, 0, 1), m);
        self.game.renderers.r_imm.drawLine(p0, p1, grid_color);
    }

    while (x < viewf.w + 16) : (x += 16) {
        const p0 = zm.mul(zm.f32x4(x, 0, 0, 1), m);
        const p1 = zm.mul(zm.f32x4(x, Game.INTERNAL_HEIGHT, 0, 1), m);
        self.game.renderers.r_imm.drawLine(p0, p1, grid_color);
    }
}

fn renderBlockedConstructionRects(
    self: *PlayState,
    cam: Camera,
) void {
    if (self.interact_state != .build) {
        return;
    }

    const min_tile_x = @intCast(usize, cam.view.left()) / 16;
    const min_tile_y = @intCast(usize, cam.view.top()) / 16;
    const max_tile_x = std.math.min(
        self.world.getWidth(),
        1 + @intCast(usize, cam.view.right()) / 16,
    );
    const max_tile_y = std.math.min(
        self.world.getHeight(),
        1 + @intCast(usize, cam.view.bottom()) / 16,
    );
    const map = self.world.map;

    self.game.renderers.r_quad.begin(.{});
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
            var a = 0.3 * @sin(@intToFloat(f32, self.game.frame_counter) / 15.0);
            a = std.math.max(a, 0);
            self.game.renderers.r_quad.drawQuadRGBA(dest, 255, 0, 0, @floatToInt(u8, a * 255.0));
        }
    }
    self.game.renderers.r_quad.end();
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

fn renderRangeIndicatorForTower(self: *PlayState, cam: Camera, spec: *const wo.TowerSpec, world_x: i32, world_y: i32) void {
    self.game.renderers.r_imm.beginUntextured();
    self.game.renderers.r_imm.drawCircle(
        32,
        zm.f32x4(@intToFloat(f32, world_x - cam.view.left()), @intToFloat(f32, world_y - cam.view.top()), 0, 0),
        spec.min_range,
        zm.f32x4(1, 0, 0, 1),
    );
    self.game.renderers.r_imm.drawCircle(
        32,
        zm.f32x4(@intToFloat(f32, world_x - cam.view.left()), @intToFloat(f32, world_y - cam.view.top()), 0, 0),
        spec.max_range,
        zm.f32x4(0, 1, 0, 1),
    );
}

fn renderRangeIndicator(self: *PlayState, cam: Camera) void {
    if (self.interact_state != .select) {
        return;
    }
    const selected_tower = self.world.towers.getPtr(self.interact_state.select.selected_tower);
    const selected_spec = if (self.interact_state.select.hovered_spec) |hovered| hovered else selected_tower.spec;
    const p = selected_tower.getWorldCollisionRect().centerPoint();
    self.renderRangeIndicatorForTower(cam, selected_spec, p[0], p[1]);
}

fn renderPlacementIndicator(self: *PlayState, cam: Camera) void {
    if (self.interact_state != .build) {
        return;
    }

    const tc = self.mouseToTile();
    const color = if (self.world.canBuildAt(tc)) [4]f32{ 0, 1, 0, 0.5 } else [4]f32{ 1, 0, 0, 0.5 };
    const dest = Rect.init(
        @intCast(i32, tc.x * 16) - cam.view.left(),
        @intCast(i32, tc.y * 16) - cam.view.top(),
        16,
        16,
    );
    self.game.renderers.r_imm.beginUntextured();
    self.game.renderers.r_imm.drawQuadRGBA(dest, color);

    const tower_center_x = @intCast(i32, tc.worldX() + 8);
    const tower_center_y = @intCast(i32, tc.worldY() + 8);
    self.renderRangeIndicatorForTower(cam, self.interact_state.build.tower_spec, tower_center_x, tower_center_y);
}

fn renderDemolishIndicator(self: *PlayState, cam: Camera) void {
    if (self.interact_state != .demolish) {
        return;
    }

    const tc = self.mouseToTile();
    if (self.world.getTowerAt(tc) != null) {
        const dest = Rect.init(
            @intCast(i32, tc.x * 16) - cam.view.left(),
            @intCast(i32, tc.y * 16) - cam.view.top(),
            16,
            16,
        );
        self.game.renderers.r_imm.beginUntextured();
        self.game.renderers.r_imm.drawQuadRGBA(dest, [4]f32{ 1, 0, 0, 0.5 });
    }
}

fn renderSelection(self: *PlayState, cam: Camera) void {
    if (self.interact_state != .select) {
        return;
    }

    const t = self.world.towers.getPtr(self.interact_state.select.selected_tower);
    var r = t.getWorldCollisionRect().toRectf();
    const cf = cam.view.toRectf();
    r.translate(-cf.left(), -cf.top());

    self.game.renderers.r_imm.beginUntextured();
    self.game.renderers.r_imm.drawRectangle(zm.f32x4(r.left(), r.top(), 0, 0), zm.f32x4(r.right(), r.bottom(), 0, 0), zm.f32x4(0, 1, 0, 1));
}

fn debugRenderTileCollision(self: *PlayState, cam: Camera) void {
    const min_tile_x = @intCast(usize, cam.view.left()) / 16;
    const min_tile_y = @intCast(usize, cam.view.top()) / 16;
    const max_tile_x = std.math.min(
        self.world.getWidth(),
        1 + @intCast(usize, cam.view.right()) / 16,
    );
    const max_tile_y = std.math.min(
        self.world.getHeight(),
        1 + @intCast(usize, cam.view.bottom()) / 16,
    );
    const map = self.world.map;

    self.game.renderers.r_imm.beginUntextured();
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
                self.game.renderers.r_imm.drawQuadRGBA(dest, [_]f32{ 1, 0, 0, 0.6 });
                continue;
            }

            if (t.from_left) {
                var left_rect = dest;
                left_rect.w = 4;
                self.game.renderers.r_imm.drawQuadRGBA(left_rect, [_]f32{ 1, 0, 0, 0.6 });
            }

            if (t.from_top) {
                var top_rect = dest;
                top_rect.h = 4;
                self.game.renderers.r_imm.drawQuadRGBA(top_rect, [_]f32{ 1, 0, 0, 0.6 });
            }

            if (t.from_bottom) {
                var bot_rect = dest;
                bot_rect.translate(0, bot_rect.h - 4);
                bot_rect.h = 4;
                self.game.renderers.r_imm.drawQuadRGBA(bot_rect, [_]f32{ 1, 0, 0, 0.6 });
            }

            if (t.from_right) {
                var right_rect = dest;
                right_rect.translate(right_rect.w - 4, 0);
                right_rect.w = 4;
                self.game.renderers.r_imm.drawQuadRGBA(right_rect, [_]f32{ 1, 0, 0, 0.6 });
            }
        }
    }

    self.game.renderers.r_imm.beginUntextured();
    for (self.world.monsters.slice()) |m| {
        var wc = m.getWorldCollisionRect();
        wc.translate(-cam.view.left(), -cam.view.top());
        self.game.renderers.r_imm.drawQuadRGBA(
            wc,
            [4]f32{ 0, 0, 1, 0.5 },
        );
    }
    for (self.world.projectiles.slice()) |p| {
        var wc = p.getWorldCollisionRect();
        wc.translate(-cam.view.left(), -cam.view.top());
        self.game.renderers.r_imm.drawQuadRGBA(
            wc,
            [4]f32{ 0, 0, 1, 0.5 },
        );
    }
}

pub fn loadWorld(self: *PlayState, mapid: []const u8) void {
    if (self.music_params) |params| {
        params.done.store(true, .SeqCst);
        params.release();
    }
    self.world.deinit();
    self.particle_sys.clear();

    const filename = std.fmt.allocPrint(self.game.allocator, "assets/maps/{s}.tmj", .{mapid}) catch |err| {
        std.log.err("Failed to allocate world path: {!}", .{err});
        std.process.exit(1);
    };
    defer self.game.allocator.free(filename);

    self.world = wo.loadWorldFromJson(self.game.allocator, filename) catch |err| {
        std.log.err("failed to load tilemap {!}", .{err});
        std.process.exit(1);
    };

    // get this loading asap
    if (self.world.music_filename) |music_filename| {
        self.music_params = self.game.audio.playMusic(music_filename, .{});
    }

    self.createMinimap() catch |err| {
        std.log.err("Failed to create minimap: {!}", .{err});
        std.process.exit(1);
    };
    // self.world.animan = &self.aman;

    // Init camera for this map

    if (self.world.play_area) |area| {
        self.camera.bounds = area;
    } else {
        self.camera.bounds = Rect.init(
            0,
            0,
            @intCast(i32, self.world.getWidth() * 16),
            @intCast(i32, self.world.getHeight() * 16),
        );
    }

    self.camera.view.centerOn(@intCast(i32, self.world.goal.world_x), @intCast(i32, self.world.goal.world_y));

    self.prev_camera = self.camera;

    // must be set before calling spawnMonster since it's used for audio parameters...
    // should probably clean this up eventually
    self.world.view = self.camera.view;
    self.world.particle_sys = &self.particle_sys;

    self.world.setNextWaveTimer(15);
}

fn createMinimap(self: *PlayState) !void {
    const range = self.world.getPlayableRange();
    self.t_minimap.width = @intCast(u32, range.getWidth());
    self.t_minimap.height = @intCast(u32, range.getHeight());

    var fbo: gl.GLuint = 0;
    gl.genFramebuffers(1, &fbo);
    defer gl.deleteFramebuffers(1, &fbo);
    gl.bindFramebuffer(gl.FRAMEBUFFER, fbo);

    gl.bindTexture(gl.TEXTURE_2D, self.t_minimap.handle);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.REPEAT);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.REPEAT);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.NEAREST);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.NEAREST);
    gl.texImage2D(gl.TEXTURE_2D, 0, gl.RGBA, @intCast(gl.GLsizei, self.t_minimap.width), @intCast(gl.GLsizei, self.t_minimap.height), 0, gl.RGBA, gl.UNSIGNED_BYTE, null);
    gl.framebufferTexture2D(gl.FRAMEBUFFER, gl.COLOR_ATTACHMENT0, gl.TEXTURE_2D, self.t_minimap.handle, 0);
    if (gl.checkFramebufferStatus(gl.FRAMEBUFFER) != gl.FRAMEBUFFER_COMPLETE) {
        std.log.err("createMinimap: failed to create framebuffer", .{});
        std.process.exit(1);
    }
    gl.viewport(0, 0, @intCast(c_int, self.t_minimap.width), @intCast(c_int, self.t_minimap.height));
    self.game.renderers.r_batch.setOutputDimensions(self.t_minimap.width, self.t_minimap.height);
    self.renderMinimapLayer(.base, .terrain, range);
    self.renderMinimapLayer(.base, .special, range);
    self.renderMinimapLayer(.detail, .terrain, range);
    self.renderMinimapLayer(.detail, .special, range);
}

fn renderMinimapLayer(
    self: *PlayState,
    layer: tilemap.TileLayer,
    bank: tilemap.TileBank,
    range: TileRange,
) void {
    const map = self.world.map;
    const source_texture = switch (bank) {
        .none => return,
        .terrain => self.game.texman.getNamedTexture("terrain.png"),
        .special => self.game.texman.getNamedTexture("special.png"),
    };
    const n_tiles_wide = @intCast(u16, source_texture.width / 16);
    self.game.renderers.r_batch.begin(.{
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
            self.game.renderers.r_batch.drawQuad(.{
                .src = src.toRectf(),
                .dest = dest,
            });
        }
    }
    self.game.renderers.r_batch.end();
}

fn beginTransitionGameOver(self: *PlayState) void {
    self.sub = .gamelose_fadeout;
    self.fade_timer = FrameTimer.initSeconds(self.game.frame_counter, 2);
}

fn beginTransitionGameWin(self: *PlayState) void {
    self.sub = .gamewin_fadeout;
    self.fade_timer = FrameTimer.initSeconds(self.game.frame_counter, 2);
}

fn renderWipe(self: *PlayState, alpha: f64) void {
    if (self.sub != .wipe_fadein) {
        return;
    }

    const t0 = self.fade_timer.invProgressClamped(std.math.max(self.game.frame_counter -| 1, self.fade_timer.frame_start));
    const t1 = self.fade_timer.invProgressClamped(self.game.frame_counter);
    const tx = zm.lerpV(t0, t1, @floatCast(f32, alpha));

    const right = @floatToInt(i32, zm.lerpV(-wipe_scanline_width, Game.INTERNAL_WIDTH, tx));
    const a = tx;

    self.game.renderers.r_imm.beginUntextured();
    self.game.renderers.r_imm.drawQuadRGBA(Rect.init(0, 0, Game.INTERNAL_WIDTH, Game.INTERNAL_HEIGHT), zm.f32x4(0, 0, 0, a));

    self.game.renderers.r_quad.begin(.{});
    for (self.wipe_scanlines) |*sc, i| {
        const rect = Rect.init(0, @intCast(i32, i), right + sc.*, 1);
        self.game.renderers.r_quad.drawQuadRGBA(rect, 0, 0, 0, 255);
    }
    self.game.renderers.r_quad.end();

    self.game.renderers.r_font.begin(.{
        .texture = self.game.texman.getNamedTexture("CommonCase.png"),
        .spec = &self.fontspec,
    });
    const text_alpha = @floatToInt(u8, a * 255);
    self.game.renderers.r_font.drawText("Loading...", .{
        .dest = Rect.init(0, 0, Game.INTERNAL_WIDTH, Game.INTERNAL_HEIGHT),
        .color = @Vector(4, u8){ 255, 255, 255, text_alpha },
        .h_alignment = .center,
        .v_alignment = .middle,
    });
    self.game.renderers.r_font.end();
}

fn renderFade(self: *PlayState) void {
    if (self.sub != .gamewin_fadeout and self.sub != .gamelose_fadeout) {
        return;
    }

    const a = self.fade_timer.progressClamped(self.game.frame_counter);

    self.game.renderers.r_imm.beginUntextured();
    self.game.renderers.r_imm.drawQuadRGBA(Rect.init(0, 0, Game.INTERNAL_WIDTH, Game.INTERNAL_HEIGHT), zm.f32x4(0, 0, 0, a));
}

fn updateUpgradeButtons(self: *PlayState) void {
    self.ui_upgrade_panel.visible = self.interact_state == .select;
    if (!self.ui_upgrade_panel.visible) {
        return;
    }

    const t = self.world.towers.getPtr(self.interact_state.select.selected_tower);
    const s = t.spec;
    var i: usize = 0;
    while (i < 3) : (i += 1) {
        if (s.upgrades[i]) |spec| {
            self.ui_upgrade_buttons[i].tooltip_text = self.getCachedTooltip(spec);
            self.ui_upgrade_buttons[i].setTexture(self.getCachedUpgradeButtonTexture(spec));
            self.ui_upgrade_states[i].play_state = self;
            self.ui_upgrade_states[i].tower_spec = spec;
            self.ui_upgrade_states[i].tower_id = self.interact_state.select.selected_tower;
            if (self.world.canAfford(spec)) {
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
    for (self.wipe_scanlines) |*sc| {
        sc.* = r.intRangeLessThan(i32, 0, wipe_scanline_width);
    }
}

fn endWipe(self: *PlayState) void {
    self.wave_timer.state_timer = FrameTimer.initSeconds(self.world.world_frame, 2);
}

fn renderWaveTimer(self: *PlayState, alpha: f64) void {
    var rect = self.wave_timer.text_measure;
    var box_rect = rect;
    box_rect.inflate(4, 4);

    box_rect.x = @divFloor(Game.INTERNAL_WIDTH - box_rect.w, 2);
    box_rect.y = @divFloor(Game.INTERNAL_HEIGHT - box_rect.h, 2);

    switch (self.wave_timer.state) {
        .middle_screen => {},
        .move_to_corner => {
            const t0 = self.wave_timer.state_timer.invProgressClamped(std.math.max(self.world.world_frame -| 1, self.wave_timer.state_timer.frame_start));
            const t1 = self.wave_timer.state_timer.invProgressClamped(self.world.world_frame);
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
    const sec = self.world.next_wave_timer.remainingSecondsUnbounded(self.world.world_frame);
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
        .color = @Vector(4, u8){ 255, 255, 255, @floatToInt(u8, total_alpha * @intToFloat(f32, text_alpha)) },
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
