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

    fn makeFoamAnimation(comptime x0: i32, comptime y0: i32) anim.Animation {
        return anim.Animation{
            .next = "",
            .frames = &[_]anim.Frame{
                .{
                    .rect = Rect.init(x0, y0, 16, 16),
                    .time = 8,
                },
                .{
                    .rect = Rect.init(x0, y0 + 16, 16, 16),
                    .time = 8,
                },
                .{
                    .rect = Rect.init(x0, y0 + 32, 16, 16),
                    .time = 8,
                },
                .{
                    .rect = Rect.init(x0, y0 + 16, 16, 16),
                    .time = 8,
                },
            },
        };
    }

    const a_left = makeFoamAnimation(0, 0);
    const a_right = makeFoamAnimation(16, 0);
    const a_top = makeFoamAnimation(32, 0);
    const a_bottom = makeFoamAnimation(48, 0);
};

game: *Game,
camera: Camera = DEFAULT_CAMERA,
prev_camera: Camera = DEFAULT_CAMERA,
r_batch: SpriteBatch,
r_water: WaterRenderer,
water_buf: []WaterDraw,
n_water: usize = 0,
foam_buf: []FoamDraw,
aman: anim.AnimationManager,
foam_anim_l: anim.Animator,
foam_anim_r: anim.Animator,
foam_anim_u: anim.Animator,
foam_anim_d: anim.Animator,
world: wo.World,

deb_render_tile_collision: bool = false,

pub fn create(game: *Game) !*PlayState {
    var self = try game.allocator.create(PlayState);
    self.* = .{
        .game = game,
        .r_batch = SpriteBatch.create(),
        .r_water = WaterRenderer.create(),
        .water_buf = try game.allocator.alloc(WaterDraw, max_onscreen_tiles),
        .foam_buf = try game.allocator.alloc(FoamDraw, max_onscreen_tiles),
        .aman = anim.AnimationManager.init(game.allocator),
        .foam_anim_l = undefined,
        .foam_anim_r = undefined,
        .foam_anim_u = undefined,
        .foam_anim_d = undefined,
        .world = wo.World.init(self.game.allocator),
    };
    var foam_aset = try self.aman.createAnimationSet();
    try foam_aset.anims.put(self.aman.allocator, "l", FoamDraw.a_left);
    try foam_aset.anims.put(self.aman.allocator, "r", FoamDraw.a_right);
    try foam_aset.anims.put(self.aman.allocator, "u", FoamDraw.a_top);
    try foam_aset.anims.put(self.aman.allocator, "d", FoamDraw.a_bottom);
    self.foam_anim_l = foam_aset.createAnimator();
    self.foam_anim_l.setAnimation("l");
    self.foam_anim_r = foam_aset.createAnimator();
    self.foam_anim_r.setAnimation("r");
    self.foam_anim_u = foam_aset.createAnimator();
    self.foam_anim_u.setAnimation("u");
    self.foam_anim_d = foam_aset.createAnimator();
    self.foam_anim_d.setAnimation("d");
    return self;
}

pub fn destroy(self: *PlayState) void {
    self.aman.deinit();
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
    var m = &self.world.monsters.items[0];
    if (self.game.input_state.isKeyDown(sdl.SDL_SCANCODE_LEFT)) {
        m.beginMove(.left);
    }
    if (self.game.input_state.isKeyDown(sdl.SDL_SCANCODE_RIGHT)) {
        m.beginMove(.right);
    }
    if (self.game.input_state.isKeyDown(sdl.SDL_SCANCODE_UP)) {
        m.beginMove(.up);
    }
    if (self.game.input_state.isKeyDown(sdl.SDL_SCANCODE_DOWN)) {
        m.beginMove(.down);
    }

    self.world.update();
}

pub fn render(self: *PlayState, alpha: f64) void {
    gl.clearColor(0x64.0 / 255.0, 0x95.0 / 255.0, 0xED.0 / 255.0, 1);
    gl.clear(gl.COLOR_BUFFER_BIT);

    var cam_interp = Camera.lerp(self.prev_camera, self.camera, alpha);
    cam_interp.clampToBounds();

    self.renderTilemap(cam_interp);
    self.renderMonsters(cam_interp);

    if (self.deb_render_tile_collision) {
        self.debugRenderTileCollision(cam_interp);
    }
}

pub fn handleEvent(self: *PlayState, ev: sdl.SDL_Event) void {
    if (ev.type == .SDL_KEYDOWN and ev.key.keysym.sym == sdl.SDLK_F1) {
        self.deb_render_tile_collision = !self.deb_render_tile_collision;
    }
}

fn renderMonsters(
    self: *PlayState,
    cam: Camera,
) void {
    const t_chara = self.game.texman.getNamedTexture("characters.png");
    self.r_batch.begin(.{
        .texture_manager = &self.game.texman,
        .texture = t_chara,
    });
    for (self.world.monsters.items) |m| {
        self.r_batch.drawQuad(
            Rect.init(0, 0, 16, 16),
            Rect.init(@intCast(i32, m.world_x) - cam.view.left(), @intCast(i32, m.world_y) - cam.view.top(), 16, 16),
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
    const source_texture_state = self.game.texman.getTextureState(source_texture);
    const n_tiles_wide = @intCast(u16, source_texture_state.width / 16);
    self.r_batch.begin(SpriteBatch.SpriteBatchParams{
        .texture_manager = &self.game.texman,
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
        .texture_manager = &self.game.texman,
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
    self.world.animan = &self.aman;

    // Init camera for this map

    self.camera.bounds = Rect.init(
        0,
        0,
        @intCast(i32, self.world.getWidth() * 16),
        @intCast(i32, self.world.getHeight() * 16),
    );
    self.prev_camera = self.camera;
}

fn renderFoam(
    self: *PlayState,
) void {
    const t_foam = self.game.texman.getNamedTexture("water_foam.png");
    self.r_batch.begin(.{
        .texture_manager = &self.game.texman,
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
