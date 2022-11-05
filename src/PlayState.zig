const PlayState = @This();

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
const FrameTimer = @import("timing.zig").FrameTimer;

const DEFAULT_CAMERA = Camera{
    .view = Rect.init(0, 0, Game.INTERNAL_WIDTH - gui_panel_width, Game.INTERNAL_HEIGHT),
};
const max_onscreen_tiles = 33 * 17;
const camera_move_speed = 8;
const gui_panel_width = 16 * 6;

const WaterDraw = struct {
    dest: Rect,
    world_xy: zm.Vec,
};

const FoamDraw = struct {
    dest: Rect,
    left: bool,
    right: bool,
    top: bool,
    bottom: bool,
};

const ButtonData = struct {
    state: *PlayState,
    spec: *const wo.TowerSpec,
};

const button_specs = [8]*const wo.TowerSpec{
    &wo.t_wall,
    &wo.tspec_test,
    &wo.t_wall,
    &wo.t_wall,
    &wo.t_wall,
    &wo.t_wall,
    &wo.t_wall,
    &wo.t_wall,
};

const InteractStateBuild = struct {
    /// What the player will build when he clicks
    tower_spec: *const wo.TowerSpec,
};

const InteractState = union(enum) {
    none: void,
    build: InteractStateBuild,
};

const Substate = enum {
    none,
    gameover_fadeout,
};

const FingerRenderer = @import("FingerRenderer.zig");

game: *Game,
camera: Camera = DEFAULT_CAMERA,
prev_camera: Camera = DEFAULT_CAMERA,
r_batch: SpriteBatch,
r_quad: QuadBatch,
r_font: BitmapFont,
r_water: WaterRenderer,
water_buf: []WaterDraw,
n_water: usize = 0,
foam_buf: []FoamDraw,
foam_anim_l: anim.Animator,
foam_anim_r: anim.Animator,
foam_anim_u: anim.Animator,
foam_anim_d: anim.Animator,
heart_anim: anim.Animator = anim.a_goal_heart.animationSet().createAnimator("default"),
world: wo.World,
fontspec: bmfont.BitmapFontSpec,
fontspec_numbers: bmfont.BitmapFontSpec,
r_finger: FingerRenderer,
frame_arena: std.heap.ArenaAllocator,
ui_root: ui.Root,
ui_buttons: [8]*ui.Button,
ui_minimap: *ui.Minimap,
t_minimap: *Texture,
interact_state: InteractState = .none,
sub: Substate = .none,
fade_timer: FrameTimer = .{},

deb_render_tile_collision: bool = false,

rng: std.rand.DefaultPrng = std.rand.DefaultPrng.init(0),

pub fn create(game: *Game) !*PlayState {
    var self = try game.allocator.create(PlayState);
    self.* = .{
        .game = game,
        .r_batch = SpriteBatch.create(),
        .r_water = WaterRenderer.create(),
        .water_buf = try game.allocator.alloc(WaterDraw, max_onscreen_tiles),
        .foam_buf = try game.allocator.alloc(FoamDraw, max_onscreen_tiles),
        .foam_anim_l = anim.a_foam.animationSet().createAnimator("l"),
        .foam_anim_r = anim.a_foam.animationSet().createAnimator("r"),
        .foam_anim_u = anim.a_foam.animationSet().createAnimator("u"),
        .foam_anim_d = anim.a_foam.animationSet().createAnimator("d"),
        .world = wo.World.init(self.game.allocator),
        .r_font = undefined,
        .fontspec = undefined,
        .fontspec_numbers = undefined,
        .r_finger = FingerRenderer.create(),
        .r_quad = QuadBatch.create(),
        // Created/destroyed in update()
        .frame_arena = undefined,
        .ui_root = ui.Root.init(game.allocator),
        .ui_buttons = undefined,
        .ui_minimap = undefined,
        .t_minimap = game.texman.createInMemory(),
    };
    self.r_font = BitmapFont.init(&self.r_batch);

    const t_panel = self.game.texman.getNamedTexture("ui_panel.png");
    var ui_panel = try self.ui_root.createPanel();
    ui_panel.rect = Rect.init(0, 0, @intCast(i32, t_panel.width), @intCast(i32, t_panel.height));
    ui_panel.rect.alignRight(Game.INTERNAL_WIDTH);
    ui_panel.texture = t_panel;
    try self.ui_root.addChild(ui_panel.control());
    for (self.ui_buttons) |*b, i| {
        b.* = try self.ui_root.createButton();
        try ui_panel.addChild(b.*.control());

        const x: i32 = if (i % 2 == 0) 18 else 50;
        const y: i32 = 114 + @intCast(i32, i / 2) * 32;

        b.*.texture = self.game.texman.getNamedTexture("ui_iconframe.png");
        b.*.rect = Rect.init(x, y, 28, 28);

        var userdata_ptr = try self.game.allocator.create(ButtonData);
        userdata_ptr.state = self;
        userdata_ptr.spec = button_specs[i];
        b.*.setCallback(userdata_ptr, onButtonClick);
    }
    self.ui_minimap = try self.ui_root.createMinimap();
    self.ui_minimap.rect = Rect.init(16, 16, 64, 64);
    self.ui_minimap.texture = self.t_minimap;
    self.ui_minimap.setPanCallback(self, onMinimapPan);
    try ui_panel.addChild(self.ui_minimap.control());

    // TODO probably want a better way to manage this, direct IO shouldn't be here
    // TODO undefined minefield, need to be more careful. Can't deinit an undefined thing.
    self.fontspec = try loadFontSpec(self.game.allocator, "assets/tables/text16.json");
    self.fontspec_numbers = try loadFontSpec(self.game.allocator, "assets/tables/number3x5.json");
    return self;
}

fn onButtonClick(button: *ui.Button, data: *ButtonData) void {
    _ = button;
    data.state.game.audio.playSound("assets/sounds/click.ogg").release();
    data.state.interact_state = .{ .build = InteractStateBuild{
        .tower_spec = data.spec,
    } };
}

fn onMinimapPan(_: *ui.Minimap, self: *PlayState, x: f32, y: f32) void {
    self.camera.view.centerOn(
        @floatToInt(i32, x * @intToFloat(f32, self.camera.bounds.w)),
        @floatToInt(i32, y * @intToFloat(f32, self.camera.bounds.h)),
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
    for (self.ui_buttons) |b| {
        var data = @ptrCast(*ButtonData, @alignCast(@alignOf(ButtonData), b.userdata));
        self.game.allocator.destroy(data);
    }
    self.fontspec.deinit();
    self.fontspec_numbers.deinit();
    self.r_quad.destroy();
    self.game.allocator.free(self.water_buf);
    self.game.allocator.free(self.foam_buf);
    self.r_batch.destroy();
    self.world.deinit();
    self.ui_root.deinit();
    self.game.allocator.destroy(self);
}

pub fn enter(self: *PlayState, from: ?Game.StateId) void {
    _ = from;
    self.sub = .none;
    self.loadWorld("map01");
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

    self.foam_anim_l.update();
    self.foam_anim_r.update();
    self.foam_anim_u.update();
    self.foam_anim_d.update();
    self.heart_anim.update();

    self.world.view = self.camera.view;
    self.world.update(self.game.frame_counter, arena);

    if (self.sub == .none and self.world.recoverable_lives == 0) {
        self.beginTransitionGameOver();
    }

    if (self.sub == .gameover_fadeout and self.fade_timer.expired(self.game.frame_counter)) {
        self.game.changeState(.menu);
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

    self.renderTilemap(cam_interp);
    self.renderMonsters(cam_interp, alpha);
    self.renderStolenHearts(cam_interp, alpha);
    self.renderGoal(cam_interp, alpha);
    self.renderTowers(cam_interp);
    self.renderSpriteEffects(cam_interp, alpha);
    self.renderProjectiles(cam_interp, alpha);
    self.renderHealthBars(cam_interp, alpha);
    self.renderFloatingText(cam_interp, alpha);
    self.renderBlockedConstructionRects(cam_interp);
    self.renderGrid(cam_interp);
    if (!self.ui_root.isMouseOnElement(mouse_p[0], mouse_p[1])) {
        self.renderPlacementIndicator(cam_interp);
    }
    ui.renderUI(.{
        .r_batch = &self.r_batch,
        .r_font = &self.r_font,
        .r_imm = &self.game.imm,
        .font_texture = self.game.texman.getNamedTexture("CommonCase.png"),
        .font_spec = &self.fontspec,
    }, self.ui_root);

    if (self.deb_render_tile_collision) {
        self.debugRenderTileCollision(cam_interp);
    }

    self.r_quad.setOutputDimensions(Game.INTERNAL_WIDTH, Game.INTERNAL_HEIGHT);
    for (self.world.spawns.items) |*s| {
        s.emitter.render(&self.r_quad, @floatCast(f32, alpha));
    }

    self.renderFade();
}

pub fn handleEvent(self: *PlayState, ev: sdl.SDL_Event) void {
    // stop accepting input
    if (self.sub == .gameover_fadeout) {
        return;
    }

    if (ev.type == .SDL_KEYDOWN) {
        switch (ev.key.keysym.sym) {
            sdl.SDLK_F1 => self.deb_render_tile_collision = !self.deb_render_tile_collision,
            sdl.SDLK_F6 => self.beginTransitionGameOver(),
            sdl.SDLK_ESCAPE => if (self.interact_state == .build) {
                self.interact_state = .none;
            },
            else => {},
        }
    }

    if (ev.type == .SDL_MOUSEMOTION) {
        const mouse_p = self.game.unproject(
            self.game.input.mouse.client_x,
            self.game.input.mouse.client_y,
        );
        const ui_args = ui.MouseEventArgs{
            .x = mouse_p[0],
            .y = mouse_p[1],
            .buttons = ui.SDLBackend.mouseEventToButtons(ev),
        };
        self.ui_root.handleMouseMove(ui_args);
    }

    if (ev.type == .SDL_MOUSEBUTTONDOWN) {
        if (ev.button.button == sdl.SDL_BUTTON_LEFT) {
            const mouse_p = self.game.unproject(
                self.game.input.mouse.client_x,
                self.game.input.mouse.client_y,
            );
            const ui_args = ui.MouseEventArgs{
                .x = mouse_p[0],
                .y = mouse_p[1],
                .buttons = ui.SDLBackend.mouseEventToButtons(ev),
            };
            if (!self.ui_root.handleMouseDown(ui_args)) {
                if (self.interact_state == .build) {
                    const tile_coord = self.mouseToTile();
                    if (self.world.canBuildAt(tile_coord)) {
                        _ = self.world.spawnTower(self.interact_state.build.tower_spec, tile_coord, self.game.frame_counter) catch unreachable;
                        if (sdl.SDL_GetModState() & sdl.KMOD_SHIFT == 0) {
                            self.interact_state = .none;
                        }
                    }
                }
            }
        } else if (ev.button.button == sdl.SDL_BUTTON_RIGHT) {
            if (self.interact_state == .build) {
                self.interact_state = .none;
            }
        }
    }

    if (ev.type == .SDL_MOUSEBUTTONUP) {
        const mouse_p = self.game.unproject(
            self.game.input.mouse.client_x,
            self.game.input.mouse.client_y,
        );
        const ui_args = ui.MouseEventArgs{
            .x = mouse_p[0],
            .y = mouse_p[1],
            .buttons = ui.SDLBackend.mouseEventToButtons(ev),
        };
        _ = self.ui_root.handleMouseUp(ui_args);
    }
}

fn renderSpriteEffects(
    self: *PlayState,
    cam: Camera,
    alpha: f64,
) void {
    _ = alpha;
    const t_special = self.game.texman.getNamedTexture("special.png");
    self.r_batch.begin(.{
        .texture = t_special,
    });
    for (self.world.sprite_effects.slice()) |t| {
        var animator = t.animator orelse continue;
        self.r_batch.drawQuadRotated(
            animator.getCurrentRect(),
            t.world_x - @intToFloat(f32, cam.view.left()),
            t.world_y - @intToFloat(f32, cam.view.top()),
            16,
            16,
            t.angle,
        );
    }
    self.r_batch.end();
}

fn renderProjectiles(
    self: *PlayState,
    cam: Camera,
    alpha: f64,
) void {
    const t_special = self.game.texman.getNamedTexture("special.png");
    self.r_batch.begin(.{
        .texture = t_special,
    });
    for (self.world.projectiles.slice()) |t| {
        var animator = t.animator orelse continue;
        const dest = t.getInterpWorldPosition(alpha);

        if (t.spec.rotation == .no_rotation) {
            // TODO: use non-rotated variant
            self.r_batch.drawQuadRotated(
                animator.getCurrentRect(),
                @intToFloat(f32, dest[0] - cam.view.left()),
                @intToFloat(f32, dest[1] - cam.view.top()),
                16,
                16,
                0,
            );
        } else {
            self.r_batch.drawQuadRotated(
                animator.getCurrentRect(),
                @intToFloat(f32, dest[0] - cam.view.left()),
                @intToFloat(f32, dest[1] - cam.view.top()),
                16,
                16,
                t.angle,
            );
        }
    }
    self.r_batch.end();
}

fn renderFloatingText(
    self: *PlayState,
    cam: Camera,
    alpha: f64,
) void {
    self.r_font.begin(.{
        .texture = self.game.texman.getNamedTexture("text16.png"),
        .spec = &self.fontspec_numbers,
    });
    for (self.world.floating_text.slice()) |*t| {
        // const dims = self.r_font.measureText(t.textSlice());
        // const text_center = dims.centerPoint();
        const dest_pos = t.getInterpWorldPosition(alpha);
        var dest = Rect.init(dest_pos[0], dest_pos[1], 0, 0);
        dest.inflate(16, 16);
        dest.translate(-cam.view.left(), -cam.view.top());
        // a nice curve that fades rapidly around 70%
        const a_coef = 1 - std.math.pow(f32, t.invLifePercent(), 5);
        self.r_font.drawText(
            t.textSlice(),
            .{
                .dest = dest,
                .color = @Vector(4, u8){
                    255,
                    255,
                    255,
                    @floatToInt(u8, 255 * a_coef),
                },
                .v_alignment = .middle,
                .h_alignment = .center,
            },
        );
    }
    self.r_font.end();
}

fn renderTowers(
    self: *PlayState,
    cam: Camera,
) void {
    const t_special = self.game.texman.getNamedTexture("special.png");
    const t_characters = self.game.texman.getNamedTexture("characters.png");

    // render tower bases
    self.r_batch.begin(.{
        .texture = t_special,
    });
    for (self.world.towers.slice()) |*t| {
        self.r_batch.drawQuad(
            Rect.init(0, 7 * 16, 16, 16),
            Rect.init(@intCast(i32, t.world_x) - cam.view.left(), @intCast(i32, t.world_y) - cam.view.top(), 16, 16),
        );
    }
    self.r_batch.end();

    // render tower characters
    self.r_batch.begin(.{
        .texture = t_characters,
    });
    for (self.world.towers.slice()) |*t| {
        if (t.animator) |animator| {
            // shift up on Y so the character is standing in the center of the tile
            self.r_batch.drawQuad(
                animator.getCurrentRect(),
                Rect.init(@intCast(i32, t.world_x) - cam.view.left(), @intCast(i32, t.world_y) - 4 - cam.view.top(), 16, 16),
            );
        }
    }
    self.r_batch.end();
}

fn renderMonsters(
    self: *PlayState,
    cam: Camera,
    a: f64,
) void {
    const t_chara = self.game.texman.getNamedTexture("characters.png");
    self.r_batch.begin(.{
        .texture = t_chara,
    });
    for (self.world.monsters.slice()) |m| {
        const w = m.getInterpWorldPosition(a);
        self.r_batch.drawQuadFlash(
            m.animator.?.getCurrentRect(),
            Rect.init(@intCast(i32, w[0]) - cam.view.left(), @intCast(i32, w[1]) - cam.view.top(), 16, 16),
            m.flash_frames > 0,
        );
    }
    self.r_batch.end();
}

fn renderGoal(
    self: *PlayState,
    cam: Camera,
    a: f64,
) void {
    _ = a;
    self.r_batch.begin(.{
        .texture = self.game.texman.getNamedTexture("special.png"),
    });
    const dest = Rect.init(
        @intCast(i32, self.world.goal.world_x) - cam.view.left(),
        @intCast(i32, self.world.goal.world_y) - cam.view.top(),
        16,
        16,
    );
    self.r_batch.drawQuad(self.world.goal.animator.getCurrentRect(), dest);
    self.r_batch.end();
}

fn renderHealthBars(
    self: *PlayState,
    cam: Camera,
    a: f64,
) void {
    self.r_quad.begin(.{});
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
        self.r_quad.drawQuadRGBA(dest_border, 0, 0, 0, 255);
        self.r_quad.drawQuadRGBA(dest_red, 255, 0, 0, 255);
    }
    self.r_quad.end();
}

fn renderStolenHearts(
    self: *PlayState,
    cam: Camera,
    a: f64,
) void {
    self.r_batch.begin(.{
        .texture = self.game.texman.getNamedTexture("special.png"),
    });
    for (self.world.monsters.slice()) |m| {
        const w = m.getInterpWorldPosition(a);
        if (m.carrying_life) {
            var src = self.heart_anim.getCurrentRect();
            var dest = Rect.init(w[0] - cam.view.left(), w[1] - cam.view.top(), 16, 16);
            self.r_batch.drawQuad(src, dest);
        }
    }
    self.r_batch.end();
}

fn renderTilemapLayer(
    self: *PlayState,
    layer: tilemap.TileLayer,
    bank: tilemap.TileBank,
    min_tile_x: usize,
    max_tile_x: usize,
    min_tile_y: usize,
    max_tile_y: usize,
    translate_x: i32,
    translate_y: i32,
) void {
    const map = self.world.map;

    const source_texture = switch (bank) {
        .none => return,
        .terrain => self.game.texman.getNamedTexture("terrain.png"),
        .special => self.game.texman.getNamedTexture("special.png"),
    };
    const n_tiles_wide = @intCast(u16, source_texture.width / 16);
    self.r_batch.begin(SpriteBatch.SpriteBatchParams{
        .texture = source_texture,
    });
    var y: usize = min_tile_y;
    var x: usize = 0;
    var ty: u8 = 0;
    while (y < max_tile_y) : (y += 1) {
        x = min_tile_x;
        var tx: u8 = 0;
        while (x < max_tile_x) : (x += 1) {
            const t = map.at2DPtr(layer, x, y);
            if (t.isWater()) {
                const dest = Rect{
                    .x = @intCast(i32, x * 16) + translate_x,
                    .y = @intCast(i32, y * 16) + translate_y,
                    .w = 16,
                    .h = 16,
                };
                self.water_buf[self.n_water] = WaterDraw{
                    .dest = dest,
                    .world_xy = zm.f32x4(
                        @intToFloat(f32, x * 16),
                        @intToFloat(f32, y * 16),
                        0,
                        0,
                    ),
                };

                self.foam_buf[self.n_water] = FoamDraw{
                    .dest = dest,
                    .left = x > 0 and map.isValidIndex(x - 1, y) and !map.at2DPtr(layer, x - 1, y).isWater(),
                    .right = map.isValidIndex(x + 1, y) and !map.at2DPtr(layer, x + 1, y).isWater(),
                    .top = y > 0 and map.isValidIndex(x, y - 1) and !map.at2DPtr(layer, x, y - 1).isWater(),
                    .bottom = map.isValidIndex(x, y + 1) and !map.at2DPtr(layer, x, y + 1).isWater(),
                };
                // self.foam_buf[self.n_water].dest.inflate(1, 1);

                self.n_water += 1;
            } else if (t.bank == bank) {
                const src = Rect{
                    .x = (t.id % n_tiles_wide) * 16,
                    .y = (t.id / n_tiles_wide) * 16,
                    .w = 16,
                    .h = 16,
                };
                const dest = Rect{
                    .x = @intCast(i32, x * 16) + translate_x,
                    .y = @intCast(i32, y * 16) + translate_y,
                    .w = 16,
                    .h = 16,
                };
                self.r_batch.drawQuad(
                    src,
                    dest,
                );
            }
            tx += 1;
        }
        ty += 1;
    }
    self.r_batch.end();
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

    self.game.imm.beginUntextured();
    var y: f32 = 16;
    var x: f32 = 16;
    while (y < viewf.h + 16) : (y += 16) {
        const p0 = zm.mul(zm.f32x4(0, y, 0, 1), m);
        const p1 = zm.mul(zm.f32x4(Game.INTERNAL_WIDTH, y, 0, 1), m);
        self.game.imm.drawLine(p0, p1, grid_color);
    }

    while (x < viewf.w + 16) : (x += 16) {
        const p0 = zm.mul(zm.f32x4(x, 0, 0, 1), m);
        const p1 = zm.mul(zm.f32x4(x, Game.INTERNAL_HEIGHT, 0, 1), m);
        self.game.imm.drawLine(p0, p1, grid_color);
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

    self.r_quad.begin(.{});
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
            self.r_quad.drawQuadRGBA(dest, 255, 0, 0, @floatToInt(u8, a * 255.0));
        }
    }
    self.r_quad.end();
}

fn renderTilemap(self: *PlayState, cam: Camera) void {
    self.n_water = 0;

    const min_tile_x = @intCast(usize, cam.view.left()) / 16;
    const min_tile_y = @intCast(usize, cam.view.top()) / 16;
    const max_tile_x = std.math.min(
        self.world.getWidth(),
        // +1 to account for partially transparent UI panel
        1 + 1 + @intCast(usize, cam.view.right()) / 16,
    );
    const max_tile_y = std.math.min(
        self.world.getHeight(),
        1 + @intCast(usize, cam.view.bottom()) / 16,
    );

    self.r_batch.setOutputDimensions(Game.INTERNAL_WIDTH, Game.INTERNAL_HEIGHT);
    self.renderTilemapLayer(.base, .terrain, min_tile_x, max_tile_x, min_tile_y, max_tile_y, -cam.view.left(), -cam.view.top());
    self.renderTilemapLayer(.base, .special, min_tile_x, max_tile_x, min_tile_y, max_tile_y, -cam.view.left(), -cam.view.top());

    // water_direction, water_drift, speed set on a per-map basis?
    var water_params = WaterRenderer.WaterRendererParams{
        .water_base = self.game.texman.getNamedTexture("water.png"),
        .water_blend = self.game.texman.getNamedTexture("water.png"),
        .blend_amount = 0.3,
        .global_time = @intToFloat(f32, self.game.frame_counter) / 30.0,
        .water_direction = zm.f32x4(0.3, 0.2, 0, 0),
        .water_drift_range = zm.f32x4(0.2, 0.05, 0, 0),
        .water_drift_scale = zm.f32x4(32, 16, 0, 0),
        .water_speed = 1,
    };

    self.r_water.setOutputDimensions(Game.INTERNAL_WIDTH, Game.INTERNAL_HEIGHT);
    self.r_water.begin(water_params);
    for (self.water_buf[0..self.n_water]) |cmd| {
        self.r_water.drawQuad(cmd.dest, cmd.world_xy);
    }
    self.r_water.end();

    // render foam
    self.renderFoam();

    // detail layer rendered on top of water
    self.renderTilemapLayer(.detail, .terrain, min_tile_x, max_tile_x, min_tile_y, max_tile_y, -cam.view.left(), -cam.view.top());
    self.renderTilemapLayer(.detail, .special, min_tile_x, max_tile_x, min_tile_y, max_tile_y, -cam.view.left(), -cam.view.top());
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
    self.game.imm.beginUntextured();
    self.game.imm.drawQuadRGBA(dest, color);

    self.game.imm.drawCircle(
        32,
        zm.f32x4(@intToFloat(f32, dest.x + 8), @intToFloat(f32, dest.y + 8), 0, 0),
        self.interact_state.build.tower_spec.min_range,
        zm.f32x4(1, 0, 0, 1),
    );
    self.game.imm.drawCircle(
        32,
        zm.f32x4(@intToFloat(f32, dest.x + 8), @intToFloat(f32, dest.y + 8), 0, 0),
        self.interact_state.build.tower_spec.max_range,
        zm.f32x4(0, 1, 0, 1),
    );
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

    self.game.imm.beginUntextured();
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
                self.game.imm.drawQuadRGBA(dest, [_]f32{ 1, 0, 0, 0.6 });
                continue;
            }

            if (t.from_left) {
                var left_rect = dest;
                left_rect.w = 4;
                self.game.imm.drawQuadRGBA(left_rect, [_]f32{ 1, 0, 0, 0.6 });
            }

            if (t.from_top) {
                var top_rect = dest;
                top_rect.h = 4;
                self.game.imm.drawQuadRGBA(top_rect, [_]f32{ 1, 0, 0, 0.6 });
            }

            if (t.from_bottom) {
                var bot_rect = dest;
                bot_rect.translate(0, bot_rect.h - 4);
                bot_rect.h = 4;
                self.game.imm.drawQuadRGBA(bot_rect, [_]f32{ 1, 0, 0, 0.6 });
            }

            if (t.from_right) {
                var right_rect = dest;
                right_rect.translate(right_rect.w - 4, 0);
                right_rect.w = 4;
                self.game.imm.drawQuadRGBA(right_rect, [_]f32{ 1, 0, 0, 0.6 });
            }
        }
    }

    self.game.imm.beginUntextured();
    for (self.world.monsters.slice()) |m| {
        var wc = m.getWorldCollisionRect();
        wc.translate(-cam.view.left(), -cam.view.top());
        self.game.imm.drawQuadRGBA(
            wc,
            [4]f32{ 0, 0, 1, 0.5 },
        );
    }
    for (self.world.projectiles.slice()) |p| {
        var wc = p.getWorldCollisionRect();
        wc.translate(-cam.view.left(), -cam.view.top());
        self.game.imm.drawQuadRGBA(
            wc,
            [4]f32{ 0, 0, 1, 0.5 },
        );
    }
}

fn loadWorld(self: *PlayState, mapid: []const u8) void {
    self.world.deinit();

    const filename = std.fmt.allocPrint(self.game.allocator, "assets/maps/{s}.tmj", .{mapid}) catch |err| {
        std.log.err("Failed to allocate world path: {!}", .{err});
        std.process.exit(1);
    };
    defer self.game.allocator.free(filename);

    self.world = wo.loadWorldFromJson(self.game.allocator, filename) catch |err| {
        std.log.err("failed to load tilemap {!}", .{err});
        std.process.exit(1);
    };

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

    self.prev_camera = self.camera;

    // must be set before calling spawnMonster since it's used for audio parameters...
    // should probably clean this up eventually
    self.world.view = self.camera.view;
}

fn createMinimap(self: *PlayState) !void {
    const range = self.world.getPlayableRange();
    self.t_minimap.width = @intCast(u32, range.getWidth());
    self.t_minimap.height = @intCast(u32, range.getHeight());

    var fbo: gl.GLuint = 0;
    gl.genFramebuffers(1, &fbo);
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
    self.r_batch.setOutputDimensions(self.t_minimap.width, self.t_minimap.height);
    self.renderMinimapLayer(.base, .terrain, range);
    self.renderMinimapLayer(.base, .special, range);
    self.renderMinimapLayer(.detail, .terrain, range);
    self.renderMinimapLayer(.detail, .special, range);
}

fn renderMinimapLayer(
    self: *PlayState,
    layer: tilemap.TileLayer,
    bank: tilemap.TileBank,
    range: wo.TileRange,
) void {
    const map = self.world.map;
    const source_texture = switch (bank) {
        .none => return,
        .terrain => self.game.texman.getNamedTexture("terrain.png"),
        .special => self.game.texman.getNamedTexture("special.png"),
    };
    const n_tiles_wide = @intCast(u16, source_texture.width / 16);
    self.r_batch.begin(SpriteBatch.SpriteBatchParams{
        .texture = source_texture,
    });
    var y: usize = range.min.y;
    var x: usize = 0;
    while (y <= range.max.y) : (y += 1) {
        std.debug.print("{d}\n", .{y});
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
            self.r_batch.drawQuadOptions(.{
                .src = src.toRectf(),
                .dest = dest,
            });
        }
    }
    self.r_batch.end();
}

fn renderFoam(
    self: *PlayState,
) void {
    const t_foam = self.game.texman.getNamedTexture("water_foam.png");
    self.r_batch.begin(.{
        .texture = t_foam,
    });
    for (self.foam_buf[0..self.n_water]) |f| {
        if (f.left) {
            self.r_batch.drawQuad(self.foam_anim_l.getCurrentRect(), f.dest);
        }
        if (f.top) {
            self.r_batch.drawQuad(self.foam_anim_u.getCurrentRect(), f.dest);
        }
        if (f.bottom) {
            self.r_batch.drawQuad(self.foam_anim_d.getCurrentRect(), f.dest);
        }
        if (f.right) {
            self.r_batch.drawQuad(self.foam_anim_r.getCurrentRect(), f.dest);
        }
    }
    self.r_batch.end();
}

fn beginTransitionGameOver(self: *PlayState) void {
    self.sub = .gameover_fadeout;
    self.fade_timer = FrameTimer.initSeconds(self.game.frame_counter, 2);
}

fn renderFade(self: *PlayState) void {
    if (self.sub != .gameover_fadeout) {
        return;
    }

    const a = self.fade_timer.progressClamped(self.game.frame_counter);

    self.game.imm.beginUntextured();
    self.game.imm.drawQuadRGBA(Rect.init(0, 0, Game.INTERNAL_WIDTH, Game.INTERNAL_HEIGHT), zm.f32x4(0, 0, 0, a));
}
