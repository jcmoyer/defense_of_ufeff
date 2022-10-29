const PlayState = @This();

const std = @import("std");
const Game = @import("Game.zig");
const gl = @import("gl33");
const tilemap = @import("tilemap.zig");
const Rect = @import("Rect.zig");
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

const DEFAULT_CAMERA = Camera{
    .view = Rect.init(0, 0, Game.INTERNAL_WIDTH, Game.INTERNAL_HEIGHT),
};
const max_onscreen_tiles = 33 * 17;

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
world: wo.World,
fontspec: bmfont.BitmapFontSpec,
r_finger: FingerRenderer,

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
        .foam_anim_l = anim.a_foam.createAnimator("l"),
        .foam_anim_r = anim.a_foam.createAnimator("r"),
        .foam_anim_u = anim.a_foam.createAnimator("u"),
        .foam_anim_d = anim.a_foam.createAnimator("d"),
        .world = wo.World.init(self.game.allocator),
        .r_font = undefined,
        .fontspec = undefined,
        .r_finger = FingerRenderer.create(),
        .r_quad = QuadBatch.create(),
    };
    self.r_font = BitmapFont.init(&self.r_batch);

    // TODO probably want a better way to manage this, direct IO shouldn't be here
    // TODO undefined minefield, need to be more careful. Can't deinit an undefined thing.
    var font_file = try std.fs.cwd().openFile("assets/tables/text16.json", .{});
    defer font_file.close();
    var spec_json = try font_file.readToEndAlloc(self.game.allocator, 1024 * 1024);
    defer self.game.allocator.free(spec_json);
    self.fontspec = try bmfont.BitmapFontSpec.initJson(self.game.allocator, spec_json);
    return self;
}

pub fn destroy(self: *PlayState) void {
    self.fontspec.deinit();
    self.r_quad.destroy();
    self.game.allocator.free(self.water_buf);
    self.game.allocator.free(self.foam_buf);
    self.r_batch.destroy();
    self.world.deinit();
    self.game.allocator.destroy(self);
}

pub fn enter(self: *PlayState, from: ?Game.StateId) void {
    _ = from;
    self.loadWorld("map01");
}

pub fn leave(self: *PlayState, to: ?Game.StateId) void {
    _ = self;
    _ = to;
}

pub fn update(self: *PlayState) void {
    self.prev_camera = self.camera;
    self.foam_anim_l.update();
    self.foam_anim_r.update();
    self.foam_anim_u.update();
    self.foam_anim_d.update();

    // TODO: for testing collision, remove eventually
    // var m = &self.world.monsters.items[0];
    if (self.game.input.isKeyDown(sdl.SDL_SCANCODE_LEFT)) {
        _ = self.world.tryMove(0, .left);
    }
    if (self.game.input.isKeyDown(sdl.SDL_SCANCODE_RIGHT)) {
        _ = self.world.tryMove(0, .right);
    }
    if (self.game.input.isKeyDown(sdl.SDL_SCANCODE_UP)) {
        _ = self.world.tryMove(0, .up);
    }
    if (self.game.input.isKeyDown(sdl.SDL_SCANCODE_DOWN)) {
        _ = self.world.tryMove(0, .down);
    }

    self.world.view = self.camera.view;
    self.world.update(self.game.frame_counter);
}

pub fn render(self: *PlayState, alpha: f64) void {
    gl.clearColor(0x64.0 / 255.0, 0x95.0 / 255.0, 0xED.0 / 255.0, 1);
    gl.clear(gl.COLOR_BUFFER_BIT);

    var cam_interp = Camera.lerp(self.prev_camera, self.camera, alpha);
    cam_interp.clampToBounds();

    self.renderTilemap(cam_interp);
    self.renderMonsters(cam_interp, alpha);
    self.renderTowers(cam_interp);
    self.renderBlockedConstructionRects(cam_interp);
    self.renderPlacementIndicator(cam_interp);

    if (self.deb_render_tile_collision) {
        self.debugRenderTileCollision(cam_interp);
    }

    self.r_font.begin(.{
        .texture = self.game.texman.getNamedTexture("text16.png"),
        .spec = &self.fontspec,
    });
    self.r_font.drawText("HELLO WORLD", 0, 0);
    self.r_font.end();

    self.r_finger.beginTextured(.{
        .texture = self.game.texman.getNamedTexture("finger.png"),
    });
    self.r_finger.setOutputDimensions(Game.INTERNAL_WIDTH, Game.INTERNAL_HEIGHT);
    self.r_finger.drawFinger(64, 64, @intToFloat(f32, self.game.frame_counter) / 8.0);

    self.r_quad.setOutputDimensions(Game.INTERNAL_WIDTH, Game.INTERNAL_HEIGHT);
    for (self.world.spawns.items) |*s| {
        s.emitter.render(&self.r_quad, @floatCast(f32, alpha));
    }
}

pub fn handleEvent(self: *PlayState, ev: sdl.SDL_Event) void {
    if (ev.type == .SDL_KEYDOWN and ev.key.keysym.sym == sdl.SDLK_F1) {
        self.deb_render_tile_collision = !self.deb_render_tile_collision;
    }

    if (ev.type == .SDL_MOUSEBUTTONDOWN and ev.button.button == sdl.SDL_BUTTON_LEFT) {
        const loc = self.game.unproject(
            ev.button.x,
            ev.button.y,
        );
        const tile_x = @divFloor(loc[0], 16);
        const tile_y = @divFloor(loc[1], 16);
        const tile_coord = tilemap.TileCoord{ .x = @intCast(usize, tile_x), .y = @intCast(usize, tile_y) };
        if (self.world.canBuildAt(tile_coord)) {
            self.world.spawnTower(tile_coord) catch unreachable;
        }
    }
}

fn renderTowers(
    self: *PlayState,
    cam: Camera,
) void {
    const t_special = self.game.texman.getNamedTexture("special.png");
    const t_characters = self.game.texman.getNamedTexture("characters.png");
    _ = t_characters;
    // render tower bases
    self.r_batch.begin(.{
        .texture = t_special,
    });
    for (self.world.towers.items) |t| {
        self.r_batch.drawQuad(
            Rect.init(0, 7 * 16, 16, 16),
            Rect.init(@intCast(i32, t.world_x) - cam.view.left(), @intCast(i32, t.world_y) - cam.view.top(), 16, 16),
        );
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
    for (self.world.monsters.items) |m| {
        const w = m.getInterpWorldPosition(a);
        self.r_batch.drawQuad(
            m.animator.?.getCurrentRect(),
            Rect.init(@intCast(i32, w[0]) - cam.view.left(), @intCast(i32, w[1]) - cam.view.top(), 16, 16),
        );
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

fn renderBlockedConstructionRects(
    self: *PlayState,
    cam: Camera,
) void {
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
            self.game.imm.drawQuadRGBA(dest, [_]f32{ 1, 0, 0, a });
        }
    }
}

fn renderTilemap(self: *PlayState, cam: Camera) void {
    self.n_water = 0;

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

fn renderPlacementIndicator(self: *PlayState, cam: Camera) void {
    var m = self.game.unproject(
        self.game.input.mouse.client_x,
        self.game.input.mouse.client_y,
    );
    var tc = tilemap.TileCoord{
        .x = @intCast(usize, @divFloor(m[0], 16)),
        .y = @intCast(usize, @divFloor(m[1], 16)),
    };
    const color = if (self.world.canBuildAt(tc)) [4]f32{ 0, 1, 0, 0.5 } else [4]f32{ 1, 0, 0, 0.5 };
    const dest = Rect.init(
        @intCast(i32, tc.x * 16) - cam.view.left(),
        @intCast(i32, tc.y * 16) - cam.view.top(),
        16,
        16,
    );
    self.game.imm.drawQuadRGBA(dest, color);
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
    for (self.world.monsters.items) |m| {
        const wx = m.getTilePosition().x * 16;
        const wy = m.getTilePosition().y * 16;
        self.game.imm.drawQuadRGBA(
            Rect.init(
                @intCast(i32, wx) - cam.view.left(),
                @intCast(i32, wy) - cam.view.top(),
                16,
                16,
            ),
            [4]f32{ 0, 0, 1, 0.5 },
        );
    }
}

fn loadWorld(self: *PlayState, mapid: []const u8) void {
    const filename = std.fmt.allocPrint(self.game.allocator, "assets/maps/{s}.tmj", .{mapid}) catch |err| {
        std.log.err("Failed to allocate world path: {!}", .{err});
        std.process.exit(1);
    };
    defer self.game.allocator.free(filename);

    self.world = wo.loadWorldFromJson(self.game.allocator, filename) catch |err| {
        std.log.err("failed to load tilemap {!}", .{err});
        std.process.exit(1);
    };
    // self.world.animan = &self.aman;

    // Init camera for this map

    self.camera.bounds = Rect.init(
        0,
        0,
        @intCast(i32, self.world.getWidth() * 16),
        @intCast(i32, self.world.getHeight() * 16),
    );
    self.prev_camera = self.camera;

    // must be set before calling spawnMonster since it's used for audio parameters...
    // should probably clean this up eventually
    self.world.view = self.camera.view;

    // TODO: just for testing
    self.world.spawnMonster(0) catch unreachable;
    self.world.spawnMonster(1) catch unreachable;
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
