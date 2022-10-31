const tmod = @import("tilemap.zig");
const std = @import("std");
const Allocator = std.mem.Allocator;
const anim = @import("animation.zig");
const Direction = @import("direction.zig").Direction;
const zm = @import("zmath");
const timing = @import("timing.zig");
const particle = @import("particle.zig");
const audio = @import("audio.zig");
const Rect = @import("Rect.zig");
const mu = @import("mathutil.zig");
const SlotMap = @import("slotmap.zig").SlotMap;

const Tile = tmod.Tile;
const TileBank = tmod.TileBank;
const Tilemap = tmod.Tilemap;
const TileLayer = tmod.TileLayer;
const TileCoord = tmod.TileCoord;

const AudioSystem = @import("audio.zig").AudioSystem;

pub const MoveState = enum {
    idle,
    left,
    right,
    up,
    down,
};

pub const RotationBehavior = enum {
    no_rotation,
    rotation_from_velocity,
};

pub const ProjectileSpec = struct {
    anim_set: ?anim.AnimationSet = null,
    rotation: RotationBehavior = .no_rotation,
    spawnFn: ?*const fn (*Projectile, u64) void = null,
    updateFn: ?*const fn (*Projectile, u64) void = null,
};

pub const proj_arrow = ProjectileSpec{
    .anim_set = anim.a_proj_arrow.animationSet(),
    .rotation = .rotation_from_velocity,
};

pub const Projectile = struct {
    world: *World,
    spec: *const ProjectileSpec,
    animator: ?anim.Animator = null,
    p_world_x: f32 = 0,
    p_world_y: f32 = 0,
    world_x: f32 = 0,
    world_y: f32 = 0,
    vel_x: f32 = 0,
    vel_y: f32 = 0,
    angle: f32 = 0,
    // storage that ProjectileSpecs can use
    userbuf: [16]u8 align(16) = undefined,

    fn spawn(self: *Projectile, frame: u64) void {
        if (self.spec.anim_set) |as| {
            self.animator = as.createAnimator("default");
        }
        if (self.spec.spawnFn) |spawnFn| {
            spawnFn(self, frame);
        }
    }

    fn update(self: *Projectile, frame: u64) void {
        self.p_world_x = self.world_x;
        self.p_world_y = self.world_y;
        self.world_x += self.vel_x;
        self.world_y += self.vel_y;
        if (self.animator) |*an| {
            an.update();
        }
        if (self.spec.updateFn) |updateFn| {
            updateFn(self, frame);
        }
        if (self.spec.rotation == .rotation_from_velocity) {
            self.angle = std.math.atan2(f32, self.vel_y, self.vel_x);
        }
    }

    pub fn getWorldCollisionRect(self: Projectile) Rect {
        var r = Rect.init(@floatToInt(i32, self.world_x), @floatToInt(i32, self.world_y), 0, 0);
        // TODO: replace with projectile size?
        r.inflate(4, 4);
        return r;
    }

    // TODO proper return value
    // This function returns a signed integer because it's valid for projectiles
    // to go off the edge of the world (e.g. negative X)
    pub fn getInterpWorldPosition(self: Projectile, t: f64) [2]i32 {
        const ix = zm.lerpV(self.p_world_x, self.world_x, @floatCast(f32, t));
        const iy = zm.lerpV(self.p_world_y, self.world_y, @floatCast(f32, t));
        return [2]i32{ @floatToInt(i32, ix), @floatToInt(i32, iy) };
    }
};

pub const Monster = struct {
    p_world_x: u32 = 0,
    p_world_y: u32 = 0,
    world_x: u32 = 0,
    world_y: u32 = 0,
    /// Updated immediately on move
    tile_pos: TileCoord = .{ .x = 0, .y = 0 },
    mspeed: u32 = 1,
    mstate: MoveState = .idle,
    face: Direction = .down,
    animator: ?anim.Animator = null,
    path: []TileCoord,
    path_index: usize = 0,
    path_forward: bool = true,

    pub fn setTilePosition(self: *Monster, coord: TileCoord) void {
        self.setWorldPosition(@intCast(u32, coord.x * 16), @intCast(u32, coord.y * 16));
    }

    pub fn setWorldPosition(self: *Monster, new_x: u32, new_y: u32) void {
        self.world_x = new_x;
        self.world_y = new_y;
        self.p_world_x = self.world_x;
        self.p_world_y = self.world_y;
        self.tile_pos = .{ .x = new_x / 16, .y = new_y / 16 };
    }

    pub fn getTilePosition(self: Monster) TileCoord {
        return self.tile_pos;
    }

    pub fn update(self: *Monster) void {
        self.p_world_x = self.world_x;
        self.p_world_y = self.world_y;

        if (self.mstate == .idle) {
            const steps_remaining = self.path.len - (self.path_index + 1);
            if (steps_remaining > 0) {
                std.debug.assert(std.meta.eql(self.path[self.path_index], self.getTilePosition()));
                self.beginMove(self.path[self.path_index].directionToAdjacent(self.path[self.path_index + 1]));
                self.path_index += 1;
            }
        }

        switch (self.mstate) {
            .idle => {},
            .left => self.world_x -= self.mspeed,
            .right => self.world_x += self.mspeed,
            .up => self.world_y -= self.mspeed,
            .down => self.world_y += self.mspeed,
        }

        switch (self.mstate) {
            .idle => {},
            .left, .right => {
                if (self.world_x % 16 == 0) {
                    self.mstate = .idle;
                }
            },
            .up, .down => {
                if (self.world_y % 16 == 0) {
                    self.mstate = .idle;
                }
            },
        }

        self.animator.?.update();
    }

    pub fn beginMove(self: *Monster, f: Direction) void {
        self.mstate = switch (f) {
            .left => .left,
            .up => .up,
            .right => .right,
            .down => .down,
        };
        self.tile_pos = self.tile_pos.offset(f);
        self.setFacing(f);
    }

    pub fn setFacing(self: *Monster, f: Direction) void {
        self.face = f;
        self.setAnimationFromFacing();
    }

    pub fn setAnimationFromFacing(self: *Monster) void {
        if (self.animator) |*a| {
            const anim_name = @tagName(self.face);
            a.setAnimation(anim_name);
        }
    }

    // TODO: this return type is bad, need a proper vec abstraction
    pub fn getInterpWorldPosition(self: Monster, t: f64) [2]u32 {
        const ix = zm.lerpV(@intToFloat(f64, self.p_world_x), @intToFloat(f64, self.world_x), t);
        const iy = zm.lerpV(@intToFloat(f64, self.p_world_y), @intToFloat(f64, self.world_y), t);
        return [2]u32{ @floatToInt(u32, ix), @floatToInt(u32, iy) };
    }

    pub fn getWorldCollisionRect(self: Monster) Rect {
        // TODO: origin is top left, this may change
        return Rect.init(@intCast(i32, self.world_x), @intCast(i32, self.world_y), 16, 16);
    }
};

pub const TowerSpec = struct {
    anim_set: ?anim.AnimationSet = null,
    spawnFn: ?*const fn (*Tower, u64) void = null,
    updateFn: *const fn (*Tower, u64) void,
};

pub const tspec_test = TowerSpec{
    .anim_set = anim.a_chara.animationSet(),
    .spawnFn = tspecTestSpawn,
    .updateFn = tspecTestUpdate,
};

fn tspecTestSpawn(self: *Tower, frame: u64) void {
    _ = self;
    _ = frame;
}

fn tspecTestUpdate(self: *Tower, frame: u64) void {
    if (self.cooldown.expired(frame)) {
        self.world.playPositionalSound("assets/sounds/bow.ogg", @intCast(i32, self.world_x), @intCast(i32, self.world_y));
        self.fireProjectile(frame);
        self.cooldown.restart(frame);
    }
}

pub const Tower = struct {
    world: *World,
    spec: *const TowerSpec,
    animator: ?anim.Animator = null,
    world_x: u32,
    world_y: u32,
    target_mobid: usize = 0,
    cooldown: timing.FrameTimer = .{},
    assoc_effect: ?u32 = null,

    pub fn setWorldPosition(self: *Tower, new_x: u32, new_y: u32) void {
        self.world_x = new_x;
        self.world_y = new_y;
    }

    pub fn getTilePosition(self: Tower) TileCoord {
        return TileCoord.initWorld(self.world_x, self.world_y);
    }

    pub fn fireProjectile(self: *Tower, frame: u64) void {
        const id = self.world.pickClosestMonster(self.world_x, self.world_y, 100) orelse return;
        var proj = self.world.spawnProjectile(&proj_arrow, @intCast(i32, self.world_x + 8), @intCast(i32, self.world_y + 8)) catch unreachable;
        var r = mu.angleBetween(
            @Vector(2, f32){ @intToFloat(f32, self.world_x), @intToFloat(f32, self.world_y) },
            @Vector(2, f32){ @intToFloat(f32, self.world.monsters.get(id).world_x), @intToFloat(f32, self.world.monsters.get(id).world_y) },
        );

        const cos_r = std.math.cos(r);
        const sin_r = std.math.sin(r);

        proj.vel_x = cos_r;
        proj.vel_y = sin_r;

        if (self.animator) |*animator| {
            if (std.math.fabs(sin_r) < 0.7) {
                if (cos_r < 0) {
                    animator.setAnimation("left");
                } else {
                    animator.setAnimation("right");
                }
            } else {
                // Flipped because we're Y-down
                if (sin_r > 0) {
                    animator.setAnimation("down");
                } else {
                    animator.setAnimation("up");
                }
            }
        }

        const ex = @floatToInt(i32, (cos_r * 6) + @intToFloat(f32, self.world_x + 8));
        const ey = @floatToInt(i32, (sin_r * 6) + @intToFloat(f32, self.world_y + 8));

        if (self.assoc_effect == null) {
            self.assoc_effect = self.world.spawnSpriteEffect(&se_bow, ex, ey, frame) catch unreachable;
        }

        self.world.sprite_effects.getPtr(self.assoc_effect.?).angle = r;
        self.world.sprite_effects.getPtr(self.assoc_effect.?).world_x = @intToFloat(f32, ex);
        self.world.sprite_effects.getPtr(self.assoc_effect.?).world_y = @intToFloat(f32, ey);
    }

    fn spawn(self: *Tower, frame: u64) void {
        if (self.spec.anim_set) |as| {
            self.animator = as.createAnimator("down");
        }
        if (self.spec.spawnFn) |spawnFn| {
            spawnFn(self, frame);
        }
    }

    fn update(self: *Tower, frame: u64) void {
        self.spec.updateFn(self, frame);
        if (self.animator) |*animator| {
            animator.update();
        }
    }
};

pub const Spawn = struct {
    var rng = std.rand.Xoshiro256.init(0);

    coord: TileCoord,
    emitter: particle.Emitter,
    timer: timing.FrameTimer,
    spawn_interval: f32,

    fn emit(self: *Spawn) void {
        self.emitter.emitFunc(16, emitGen, null);
    }

    fn updatePart(p: *particle.Particle) void {
        const a = std.math.min(1.0, @intToFloat(f32, 60 -| p.frames_alive) / 60.0);
        p.color_a = @floatToInt(u8, a * 255);
        p.size *= 0.97;
        p.vel[1] *= 0.95;
        p.vel[0] *= 0.9;
    }

    fn emitGen(p: *particle.Particle, ctx: *const particle.GeneratorContext) void {
        _ = ctx;
        p.vel = [2]f32{
            rng.random().float(f32) * 4 - rng.random().float(f32) * 4,
            -rng.random().float(f32) * 2,
        };
        p.size = rng.random().float(f32) * 7;
        p.color_a = 255;
        p.updateFn = updatePart;
    }
};

const se_bow = SpriteEffectSpec{
    .anim_set = anim.a_proj_bow.animationSet(),
};

pub const SpriteEffectSpec = struct {
    anim_set: ?anim.AnimationSet = null,
    spawnFn: ?*const fn (*SpriteEffect, u64) void = null,
    updateFn: ?*const fn (*SpriteEffect, u64) void = null,
};

pub const SpriteEffect = struct {
    world: *World,
    spec: *const SpriteEffectSpec,
    animator: ?anim.Animator = null,
    world_x: f32,
    world_y: f32,
    angle: f32 = 0,

    fn spawn(self: *SpriteEffect, frame: u64) void {
        if (self.spec.anim_set) |as| {
            self.animator = as.createAnimator("default");
        }
        if (self.spec.spawnFn) |spawnFn| {
            spawnFn(self, frame);
        }
    }

    fn update(self: *SpriteEffect, frame: u64) void {
        if (self.spec.updateFn) |updateFn| {
            updateFn(self, frame);
        }
    }
};

pub const World = struct {
    allocator: Allocator,
    map: Tilemap = .{},
    scratch_map: Tilemap = .{},
    scratch_cache: PathfindingCache,
    monsters: SlotMap(Monster) = .{},
    towers: std.ArrayListUnmanaged(Tower) = .{},
    spawns: std.ArrayListUnmanaged(Spawn) = .{},
    projectiles: SlotMap(Projectile) = .{},
    pending_projectiles: std.ArrayListUnmanaged(Projectile) = .{},
    sprite_effects: SlotMap(SpriteEffect) = .{},
    pathfinder: PathfindingState,
    path_cache: PathfindingCache,
    goal: ?TileCoord = null,
    view: Rect = .{},

    pub fn init(allocator: Allocator) World {
        return .{
            .allocator = allocator,
            .pathfinder = PathfindingState.init(allocator),
            .path_cache = PathfindingCache.init(allocator),
            .scratch_cache = PathfindingCache.init(allocator),
        };
    }

    pub fn deinit(self: *World) void {
        self.path_cache.deinit();
        for (self.spawns.items) |*s| {
            s.emitter.deinit(self.allocator);
        }
        self.spawns.deinit(self.allocator);
        self.monsters.deinit(self.allocator);
        self.towers.deinit(self.allocator);
        self.projectiles.deinit(self.allocator);
        self.map.deinit(self.allocator);
        self.scratch_map.deinit(self.allocator);
        self.scratch_cache.deinit();
        self.pathfinder.deinit();
        self.pending_projectiles.deinit(self.allocator);
        self.sprite_effects.deinit(self.allocator);
    }

    pub fn getWidth(self: World) usize {
        return self.map.width;
    }

    pub fn getHeight(self: World) usize {
        return self.map.height;
    }

    fn setGoal(self: *World, coord: TileCoord) void {
        self.goal = coord;
    }

    fn createSpawn(self: *World, coord: TileCoord) !void {
        try self.spawns.append(self.allocator, Spawn{
            .coord = coord,
            .timer = timing.FrameTimer.initSeconds(0, 1),
            .spawn_interval = 1,
            .emitter = try particle.Emitter.initCapacity(self.allocator, 16),
        });
        self.spawns.items[self.spawns.items.len - 1].emitter.pos = [2]f32{
            @intToFloat(f32, coord.x * 16) + 8,
            @intToFloat(f32, coord.y * 16) + 16,
        };
    }

    pub fn canBuildAt(self: *World, coord: TileCoord) bool {
        const collision_flags = self.map.getCollisionFlags2D(coord.x, coord.y);
        if (collision_flags.all()) {
            return false;
        }
        const tile_flags = self.map.at2DPtr(.base, coord.x, coord.y).flags;
        if (tile_flags.construction_blocked or tile_flags.contains_tower) {
            return false;
        }
        for (self.monsters.slice()) |m| {
            const blocked_coord = m.getTilePosition();
            if (std.meta.eql(coord, blocked_coord)) {
                return false;
            }
        }
        self.map.copyInto(&self.scratch_map);
        self.scratch_map.at2DPtr(.base, coord.x, coord.y).flags.contains_tower = true;
        self.scratch_cache.clear();
        for (self.monsters.slice()) |*m| {
            if (!self.findTheoreticalPath(m.getTilePosition(), self.goal.?)) {
                return false;
            }
        }

        return true;
    }

    pub fn spawnTower(self: *World, spec: *const TowerSpec, coord: TileCoord, frame: u64) !void {
        self.map.at2DPtr(.base, coord.x, coord.y).flags.contains_tower = true;
        try self.spawnTowerWorld(
            spec,
            @intCast(u32, coord.x * 16),
            @intCast(u32, coord.y * 16),
            frame,
        );
        self.invalidatePathCache();
    }

    pub fn spawnSpriteEffect(self: *World, spec: *const SpriteEffectSpec, world_x: i32, world_y: i32, frame: u64) !u32 {
        const id = try self.sprite_effects.put(self.allocator, SpriteEffect{
            .world = self,
            .spec = spec,
            .world_x = @intToFloat(f32, world_x),
            .world_y = @intToFloat(f32, world_y),
        });
        self.sprite_effects.getPtr(id).spawn(frame);
        return id;
    }

    /// Returned pointer is valid for the current frame only.
    pub fn spawnProjectile(self: *World, spec: *const ProjectileSpec, world_x: i32, world_y: i32) !*Projectile {
        var ptr = try self.pending_projectiles.addOne(self.allocator);
        ptr.* = Projectile{
            .world = self,
            .spec = spec,
            .world_x = @intToFloat(f32, world_x),
            .world_y = @intToFloat(f32, world_y),
            .p_world_x = @intToFloat(f32, world_x),
            .p_world_y = @intToFloat(f32, world_y),
            .vel_x = @intToFloat(f32, 0),
            .vel_y = @intToFloat(f32, 0),
        };
        return ptr;
    }

    pub fn pickClosestMonster(self: World, world_x: u32, world_y: u32, range: f32) ?u32 {
        if (self.monsters.slice().len == 0) {
            return null;
        }
        var closest: ?u32 = null;
        var best_dist = std.math.inf_f32;
        const fx = @intToFloat(f32, world_x);
        const fy = @intToFloat(f32, world_y);
        var mslice = self.monsters.items.slice();
        for (mslice.items(.value)) |m, i| {
            const mx = @intToFloat(f32, m.world_x);
            const my = @intToFloat(f32, m.world_y);
            const dist = mu.dist([2]f32{ fx, fy }, [2]f32{ mx, my });
            if (dist <= range and dist < best_dist) {
                closest = mslice.items(.handle)[i];
                best_dist = dist;
            }
        }
        return closest;
    }

    fn invalidatePathCache(self: *World) void {
        self.path_cache.clear();
        for (self.monsters.slice()) |*m| {
            const coord = m.getTilePosition();
            m.path_index = 0;
            m.path = self.findPath(coord, self.goal.?).?;
        }
    }

    fn spawnTowerWorld(self: *World, spec: *const TowerSpec, world_x: u32, world_y: u32, frame: u64) !void {
        var ptr = try self.towers.addOne(self.allocator);
        ptr.* = Tower{
            .world = self,
            .spec = spec,
            .world_x = world_x,
            .world_y = world_y,
            .cooldown = timing.FrameTimer.initSeconds(frame, 0.3),
        };
        ptr.spawn(frame);
    }

    fn spawnMonsterWorld(self: *World, world_x: u32, world_y: u32) !void {
        try self.monsters.append(self.allocator, Monster{
            .world_x = world_x,
            .world_y = world_y,
            .animator = anim.a_chara.createAnimator("down"),
        });
    }

    pub fn spawnMonster(self: *World, spawn_id: usize) !void {
        const pos = self.getSpawnPosition(spawn_id);
        self.getSpawn(spawn_id).emit();
        var mon = Monster{
            .path = self.findPath(pos, self.goal.?).?,
            .animator = anim.a_chara.animationSet().createAnimator("down"),
        };
        mon.setTilePosition(pos);
        _ = try self.monsters.put(self.allocator, mon);

        self.playPositionalSound("assets/sounds/spawn.ogg", @intCast(i32, pos.worldX()), @intCast(i32, pos.worldY()));
    }

    pub fn getSpawnPosition(self: *World, spawn_id: usize) TileCoord {
        return self.spawns.items[spawn_id].coord;
    }

    pub fn getSpawn(self: *World, spawn_id: usize) *Spawn {
        return &self.spawns.items[spawn_id];
    }

    pub fn update(self: *World, frame: u64, frame_arena: Allocator) void {
        var new_projectile_ids = std.ArrayListUnmanaged(u32){};

        for (self.spawns.items) |*s, id| {
            if (s.timer.expired(frame)) {
                s.timer.restart(frame);
                self.spawnMonster(id) catch unreachable;
            }
            s.emitter.update();
        }
        for (self.towers.items) |*t| {
            t.update(frame);
        }
        for (self.monsters.slice()) |*m| {
            m.update();
        }
        for (self.sprite_effects.slice()) |*e| {
            e.update(frame);
        }

        // We have to be very careful here, spawning new projectiles can invalidate pointers into self.projectiles.
        // This can happen if a projectile spawns a projectile. Since this seems like a cool feature, we will support
        // it. Projectiles cannot get spawned projectile handles, but if it turns out to be a feature we need, slotmap
        // API is designed to support this use case with a couple changes.
        for (self.projectiles.slice()) |*p| {
            p.update(frame);
            // var mob_index: usize = self.monsters.items.len -% 1;
            // while (mob_index < self.monsters.items.len) : (mob_index -%= 1) {
            //     // kinda nasty, maybe we do want an intrusive slotmap
            //     var monster = &self.monsters.items.items(.value)[mob_index];
            //     var monster_id = self.monsters.items.items(.handle)[mob_index];
            //     if (p.getWorldCollisionRect().intersect(monster.getWorldCollisionRect(), null)) {
            //         self.monsters.erase(monster_id);
            //     }
            // }
        }

        new_projectile_ids.ensureTotalCapacity(frame_arena, self.pending_projectiles.items.len) catch unreachable;
        for (self.pending_projectiles.items) |proj| {
            const id = self.projectiles.put(self.allocator, proj) catch unreachable;
            new_projectile_ids.append(frame_arena, id) catch unreachable;
        }
        for (new_projectile_ids.items) |id| {
            self.projectiles.getPtr(id).spawn(frame);
        }
        self.pending_projectiles.clearRetainingCapacity();
    }

    pub fn tryMove(self: *World, mobid: u32, dir: Direction) bool {
        var m = self.monsters.getPtr(mobid);

        m.setFacing(dir);

        // cannot interrupt an object that is already moving
        if (m.mstate != .idle) {
            return false;
        }

        if (!self.map.isValidMove(m.getTilePosition(), dir)) {
            return false;
        }

        m.beginMove(dir);

        return true;
    }

    pub fn findPath(self: *World, start: TileCoord, end: TileCoord) ?[]TileCoord {
        if (self.path_cache.get(start)) |existing_path| {
            return existing_path;
        }
        var timer = std.time.Timer.start() catch unreachable;
        const has_path = self.pathfinder.findPath(start, end, &self.map, &self.path_cache) catch |err| {
            std.log.err("findPath failed: {!}", .{err});
            std.process.exit(1);
        };
        std.log.debug("Pathfinding {any}->{any} took {d}us", .{ start, end, timer.read() / std.time.ns_per_us });

        if (has_path) {
            return self.path_cache.get(start).?;
        } else {
            return null;
        }
    }

    pub fn findTheoreticalPath(self: *World, start: TileCoord, end: TileCoord) bool {
        if (self.scratch_cache.hasPathFrom(start)) {
            return true;
        }
        const has_path = self.pathfinder.findPath(start, end, &self.scratch_map, &self.scratch_cache) catch |err| {
            std.log.err("findTheoreticalPath failed: {!}", .{err});
            std.process.exit(1);
        };
        return has_path;
    }

    fn playPositionalSound(self: World, sound: [:0]const u8, world_x: i32, world_y: i32) void {
        var params = audio.AudioSystem.instance.playSound(sound);
        defer params.release();

        const sound_position = [2]i32{ world_x, world_y };
        audio.computePositionalParameters(self.view, sound_position, params);
    }
};

const PathfindingCache = struct {
    allocator: Allocator,
    entries: std.AutoArrayHashMap(TileCoord, []TileCoord),

    fn init(allocator: Allocator) PathfindingCache {
        return .{
            .allocator = allocator,
            .entries = std.AutoArrayHashMap(TileCoord, []TileCoord).init(allocator),
        };
    }

    fn deinit(self: *PathfindingCache) void {
        for (self.entries.values()) |v| {
            self.allocator.free(v);
        }
        self.entries.deinit();
    }

    fn reserve(self: *PathfindingCache, coord_count: usize) !void {
        try self.entries.ensureTotalCapacity(coord_count);
    }

    fn clear(self: *PathfindingCache) void {
        for (self.entries.values()) |v| {
            self.allocator.free(v);
        }
        self.entries.clearRetainingCapacity();
    }

    fn set(self: *PathfindingCache, from: TileCoord, path: []TileCoord) void {
        self.entries.putAssumeCapacityNoClobber(from, path);
    }

    fn get(self: *PathfindingCache, from: TileCoord) ?[]TileCoord {
        return self.entries.get(from);
    }

    fn hasPathFrom(self: *PathfindingCache, from: TileCoord) bool {
        return self.entries.contains(from);
    }
};

// Reusable storage
const PathfindingState = struct {
    const Score = struct {
        fscore: f32,
        gscore: f32,
        from: TileCoord,

        const infinity = Score{
            .fscore = std.math.inf_f32,
            .gscore = std.math.inf_f32,
            .from = undefined,
        };
    };

    const Context = struct {
        map: *const Tilemap,
        score_map: []Score,
    };

    allocator: Allocator,
    frontier: std.PriorityQueue(TileCoord, Context, orderFScore),
    frontier_set: std.AutoArrayHashMapUnmanaged(TileCoord, void),
    score_map: []Score,
    // won't know length until we walk the result, though upper bound is tile map size
    result: std.ArrayListUnmanaged(TileCoord),

    fn init(allocator: Allocator) PathfindingState {
        return PathfindingState{
            .allocator = allocator,
            .frontier = std.PriorityQueue(TileCoord, Context, orderFScore).init(allocator, undefined),
            .frontier_set = .{},
            .score_map = &[_]Score{},
            .result = .{},
        };
    }

    fn deinit(self: *PathfindingState) void {
        self.frontier.deinit();
        self.frontier_set.deinit(self.allocator);
        if (self.score_map.len != 0) {
            self.allocator.free(self.score_map);
        }
        self.result.deinit(self.allocator);
    }

    fn reserve(self: *PathfindingState, count: usize) !void {
        try self.frontier.ensureTotalCapacity(count);
        try self.frontier_set.ensureTotalCapacity(self.allocator, count);
        if (self.score_map.len != 0) {
            self.allocator.free(self.score_map);
        }
        self.score_map = try self.allocator.alloc(Score, count);
    }

    fn orderFScore(ctx: Context, lhs: TileCoord, rhs: TileCoord) std.math.Order {
        const w = ctx.map.width;
        return std.math.order(
            ctx.score_map[lhs.toScalarCoord(w)].fscore,
            ctx.score_map[rhs.toScalarCoord(w)].fscore,
        );
    }

    fn findPath(self: *PathfindingState, start: TileCoord, end: TileCoord, map: *const Tilemap, cache: ?*PathfindingCache) !bool {
        const width = map.width;

        // sus, upstream interface needs some love
        self.frontier.len = 0;
        self.frontier.context = Context{
            .map = map,
            .score_map = self.score_map,
        };

        self.frontier_set.clearRetainingCapacity();

        try self.frontier.add(start);
        try self.frontier_set.put(self.allocator, start, {});
        std.mem.set(Score, self.score_map, Score.infinity);

        self.score_map[start.toScalarCoord(map.width)] = .{
            .fscore = 0,
            .gscore = 0,
            .from = undefined,
        };

        while (self.frontier.removeOrNull()) |current| {
            if (std.meta.eql(current, end)) {
                if (cache != null) {
                    self.result.clearRetainingCapacity();
                    var coord = end;
                    while (!std.meta.eql(coord, start)) {
                        try self.result.append(self.allocator, coord);
                        coord = self.score_map[coord.toScalarCoord(width)].from;
                    }
                    try self.result.append(self.allocator, coord);
                    std.mem.reverse(TileCoord, self.result.items);
                    // return self.result.items;
                    cache.?.set(start, self.result.toOwnedSlice(self.allocator));
                }

                return true;
            }

            // examine neighbors
            var d_int: u8 = 0;
            while (d_int < 4) : (d_int += 1) {
                const dir = @intToEnum(Direction, d_int);
                if (map.isValidMove(current, dir)) {
                    // 1 here is the graph edge weight, basically hardcoding manhattan distance
                    const tentative_score = self.score_map[current.toScalarCoord(width)].gscore + 1;
                    const neighbor = current.offset(dir);
                    const neighbor_score = self.score_map[neighbor.toScalarCoord(width)].gscore;
                    if (tentative_score < neighbor_score) {
                        self.score_map[neighbor.toScalarCoord(width)] = .{
                            .from = current,
                            .gscore = tentative_score,
                            .fscore = tentative_score + self.heuristic(neighbor, end),
                        };
                        if (!self.frontier_set.contains(neighbor)) {
                            try self.frontier_set.put(self.allocator, neighbor, {});
                            try self.frontier.add(neighbor);
                        }
                    }
                }
            }
        }

        std.log.debug("no path {any} to {any}", .{ start, end });
        if (cache) |c| {
            c.set(start, &[_]TileCoord{});
        }

        return false;
    }

    fn heuristic(self: *PathfindingState, from: TileCoord, to: TileCoord) f32 {
        _ = self;
        return from.euclideanDistance(to);
    }
};

pub fn loadWorldFromJson(allocator: Allocator, filename: []const u8) !World {
    var arena = std.heap.ArenaAllocator.init(allocator);
    var arena_allocator = arena.allocator();
    defer arena.deinit();

    var file = try std.fs.cwd().openFile(filename, .{});
    defer file.close();

    const buffer = try file.readToEndAlloc(arena_allocator, 1024 * 1024);

    var tokens = std.json.TokenStream.init(buffer);
    var doc = try std.json.parse(TiledDoc, &tokens, .{ .allocator = arena_allocator, .ignore_unknown_fields = true });

    var world = World.init(allocator);
    world.map = try Tilemap.init(allocator, doc.width, doc.height);
    world.scratch_map = try Tilemap.init(allocator, doc.width, doc.height);
    errdefer world.map.deinit(allocator);
    try world.pathfinder.reserve(world.map.tileCount());
    try world.path_cache.reserve(world.map.tileCount());
    try world.scratch_cache.reserve(world.map.tileCount());

    var classifier = BankClassifier{};
    defer classifier.deinit(arena_allocator);

    for (doc.tilesets) |t_tileset| {
        if (std.mem.eql(u8, t_tileset.source, "terrain.tsx")) {
            try classifier.addRange(arena_allocator, .terrain, t_tileset.firstgid);
        } else if (std.mem.eql(u8, t_tileset.source, "special.tsx")) {
            try classifier.addRange(arena_allocator, .special, t_tileset.firstgid);
        } else {
            std.log.err("Unrecognized tileset source: '{s}' from '{s}'", .{ t_tileset.source, filename });
            std.process.exit(1);
        }
    }

    for (doc.layers) |layer| {
        const ctx = LoadContext{
            .arena = arena_allocator,
            .world = &world,
            .classifier = &classifier,
        };
        switch (layer) {
            .tilelayer => |x| try loadTileLayer(x, ctx),
            .objectgroup => |x| try loadObjectGroup(x, ctx),
        }
    }

    return world;
}

const LoadContext = struct {
    arena: Allocator,
    /// Loading data into this world
    world: *World,
    classifier: *const BankClassifier,
};

fn loadTileLayer(layer: TiledTileLayer, ctx: LoadContext) !void {
    var tilemap = ctx.world.map;

    if (layer.encoding == null or !std.mem.eql(u8, layer.encoding.?, "base64")) {
        std.log.err("Map layer is not encoded using base64", .{});
        std.process.exit(1);
    }
    if (layer.compression == null or !std.mem.eql(u8, layer.compression.?, "zlib")) {
        std.log.err("Map layer is not compressed using zlib", .{});
        std.process.exit(1);
    }

    const layer_ints = try b64decompressLayer(ctx.arena, layer.data);
    defer ctx.arena.free(layer_ints);

    if (layer_ints.len != tilemap.tileCount()) {
        std.log.err("Map layer has wrong tile count; got {d} expected {d}", .{ layer_ints, tilemap.tileCount() });
        std.process.exit(1);
    }

    const layer_id = std.meta.stringToEnum(TileLayer, layer.name) orelse {
        std.log.err("Map layer has unknown name; got '{s}'", .{layer.name});
        std.process.exit(1);
    };

    for (layer_ints) |t_tid, i| {
        const result = ctx.classifier.classify(@intCast(u16, t_tid));
        tilemap.atScalarPtr(layer_id, i).* = .{
            .bank = result.bank,
            .id = result.adjusted_tile_id,
        };
    }
}

fn loadObjectGroup(layer: TiledObjectGroup, ctx: LoadContext) !void {
    for (layer.objects) |obj| {
        if (std.mem.eql(u8, obj.class, "spawn_point")) {
            try ctx.world.createSpawn(TileCoord.initSignedWorld(obj.x, obj.y));
        } else if (std.mem.eql(u8, obj.class, "construction_blocker")) {
            const tile_start = TileCoord.initSignedWorld(obj.x, obj.y);
            const tile_end = TileCoord.initSignedWorld(obj.x + obj.width, obj.y + obj.height);
            var ty: usize = tile_start.y;
            while (ty < tile_end.y) : (ty += 1) {
                var tx: usize = tile_start.x;
                while (tx < tile_end.x) : (tx += 1) {
                    ctx.world.map.at2DPtr(.base, tx, ty).flags.construction_blocked = true;
                }
            }
        } else if (std.mem.eql(u8, obj.class, "goal")) {
            ctx.world.setGoal(TileCoord.initSignedWorld(obj.x, obj.y));
        }
    }
}

fn b64decompressLayer(allocator: Allocator, data: []const u8) ![]u32 {
    const b64_decode_size = try std.base64.standard.Decoder.calcSizeForSlice(data);
    var b64_decode_buffer = try allocator.alloc(u8, b64_decode_size);
    defer allocator.free(b64_decode_buffer);

    try std.base64.standard.Decoder.decode(b64_decode_buffer, data);

    var fbs = std.io.fixedBufferStream(b64_decode_buffer);
    var b64_reader = fbs.reader();

    var zstream = try std.compress.zlib.zlibStream(allocator, b64_reader);
    var zreader = zstream.reader();

    // enough for a 512x512 map
    const layer_bytes = try zreader.readAllAlloc(allocator, 1024 * 1024);
    // TODO: looks weird, maybe we should explicitly allocate an aligned buffer instead of using readAllAlloc?
    return std.mem.bytesAsSlice(u32, @alignCast(4, layer_bytes));
}

// for tiled tilesets
const BankClassifier = struct {
    const Range = struct {
        bank: TileBank,
        first: u16,
        last: u16,

        /// [first,last)
        fn contains(self: Range, val: u16) bool {
            return val >= self.first and val < self.last;
        }
    };

    const ClassifyResult = struct {
        bank: TileBank,
        adjusted_tile_id: u16,
    };

    ranges: std.ArrayListUnmanaged(Range) = .{},

    fn addRange(self: *BankClassifier, allocator: Allocator, bank: TileBank, firstgid: u16) !void {
        if (self.getLastRange()) |ptr| {
            ptr.last = firstgid;
        }
        try self.ranges.append(allocator, Range{
            .bank = bank,
            .first = firstgid,
            .last = std.math.maxInt(u16),
        });
    }

    fn getLastRange(self: BankClassifier) ?*Range {
        if (self.ranges.items.len == 0) {
            return null;
        }
        return &self.ranges.items[self.ranges.items.len - 1];
    }

    fn classify(self: BankClassifier, id: u16) ClassifyResult {
        if (id == 0) {
            return ClassifyResult{
                .bank = .none,
                .adjusted_tile_id = 0,
            };
        }
        for (self.ranges.items) |r| {
            if (r.contains(id)) {
                return ClassifyResult{
                    .bank = r.bank,
                    .adjusted_tile_id = id - r.first,
                };
            }
        }
        std.log.err("No tile bank for tile {d}", .{id});
        std.process.exit(1);
    }

    fn deinit(self: *BankClassifier, allocator: Allocator) void {
        self.ranges.deinit(allocator);
    }
};

const TiledTileset = struct {
    firstgid: u16,
    source: []const u8,
};

const TiledLayerType = enum {
    tilelayer,
    objectgroup,
};

const TiledTileLayer = struct {
    name: []const u8,
    // Fields for base64 + zlib compressed layers. std.json.parse will fail
    // for uncompressed documents because tile IDs will overflow u8.
    // Need to do manual parsing to support both formats I guess?
    data: []const u8,
    compression: ?[]const u8 = null,
    encoding: ?[]const u8 = null,
};

const TiledObjectGroup = struct {
    name: []const u8,
    objects: []TiledObject,
};

const TiledObject = struct {
    name: []const u8,
    class: []const u8,
    x: i32,
    y: i32,
    width: i32,
    height: i32,
};

const TiledLayer = union(TiledLayerType) {
    tilelayer: TiledTileLayer,
    objectgroup: TiledObjectGroup,
};

const TiledDoc = struct {
    width: usize,
    height: usize,
    tilesets: []TiledTileset,
    layers: []TiledLayer,
};
