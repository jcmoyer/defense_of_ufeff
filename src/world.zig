const tmod = @import("tilemap.zig");
const std = @import("std");
const Allocator = std.mem.Allocator;
const anim = @import("animation.zig");
const Direction = @import("direction.zig").Direction;
const zm = @import("zmath");
const timing = @import("timing.zig");
const FrameTimer = timing.FrameTimer;
const particle = @import("particle.zig");
const audio = @import("audio.zig");
const Rect = @import("Rect.zig");
const mu = @import("mathutil.zig");
const SlotMap = @import("slotmap.zig").SlotMap;
const IntrusiveSlotMap = @import("slotmap.zig").IntrusiveSlotMap;
const IntrusiveGenSlotMap = @import("slotmap.zig").IntrusiveGenSlotMap;
const GenHandle = @import("slotmap.zig").GenHandle;

const Tile = tmod.Tile;
const TileBank = tmod.TileBank;
const Tilemap = tmod.Tilemap;
const TileLayer = tmod.TileLayer;
const TileCoord = tmod.TileCoord;
const TileRange = tmod.TileRange;

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
    angular_velocity,
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

pub const proj_bullet = ProjectileSpec{
    .anim_set = anim.a_proj_bullet.animationSet(),
};

pub const proj_star = ProjectileSpec{
    .anim_set = anim.a_proj_star.animationSet(),
    .rotation = .angular_velocity,
};

pub const Projectile = struct {
    id: u32 = undefined,
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
    angle_vel: f32 = 0,
    scale: f32 = 1,
    dead: bool = false,
    damage: u32 = 1,
    /// For delayed projectiles, a timer that must expire before the effect plays.
    delay: ?FrameTimer = null,
    activated: bool = false,
    activate_sound: SoundId = .none,
    spawn_x: f32 = 0,
    spawn_y: f32 = 0,
    max_distance: ?f32 = null,
    fadeout_timer: ?FrameTimer = null,

    fn spawn(self: *Projectile, frame: u64) void {
        if (self.spec.anim_set) |as| {
            self.animator = as.createAnimator("default");
        }
        if (self.spec.spawnFn) |spawnFn| {
            spawnFn(self, frame);
        }
    }

    fn update(self: *Projectile, frame: u64) void {
        if (self.delay) |delay| {
            if (!delay.expired(frame)) {
                return;
            }
        }
        if (!self.activated) {
            self.world.playPositionalSoundId(self.activate_sound, @floatToInt(i32, self.world_x), @floatToInt(i32, self.world_y));
            self.activated = true;
        }
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
        } else if (self.spec.rotation == .angular_velocity) {
            self.angle += self.angle_vel;
        }
        if (!self.world.safe_zone.containsRect(self.getWorldCollisionRect())) {
            self.dead = true;
        }
        if (self.fadeout_timer) |timer| {
            if (timer.expired(self.world.world_frame)) {
                self.dead = true;
            }
        } else {
            if (self.max_distance) |max_dist| {
                const dist = mu.dist(.{ self.world_x, self.world_y }, .{ self.spawn_x, self.spawn_y });
                if (dist > max_dist) {
                    self.fadeout_timer = FrameTimer.initSeconds(self.world.world_frame, 1);
                }
            }
        }
    }

    fn hit(self: *Projectile, monster: *Monster) void {
        monster.hurtDirectionalGenericDamage(self.damage, [2]f32{ self.vel_x, self.vel_y });
        self.dead = true;
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

pub const MonsterSpec = struct {
    anim_set: ?anim.AnimationSet = null,
    spawnFn: ?*const fn (*Monster, u64) void = null,
    updateFn: ?*const fn (*Monster, u64) void = null,
    color: [4]u8 = .{ 255, 255, 255, 255 },
    max_hp: u32,
    gold: u32,
    speed: u32 = 625,
};

pub const m_human = MonsterSpec{
    .anim_set = anim.a_human1.animationSet(),
    .max_hp = 5,
    .gold = 1,
    .speed = 625,
};

pub const m_slime = MonsterSpec{
    .anim_set = anim.a_slime.animationSet(),
    .max_hp = 5,
    .gold = 1,
    .speed = 625,
};

pub const m_blue_slime = MonsterSpec{
    .anim_set = anim.a_slime.animationSet(),
    .color = .{ 100, 100, 255, 255 },
    .max_hp = 15,
    .gold = 3,
    .speed = 500,
};

pub const m_red_slime = MonsterSpec{
    .anim_set = anim.a_slime.animationSet(),
    .color = .{ 255, 100, 100, 255 },
    .max_hp = 25,
    .gold = 5,
    .speed = 500,
};

pub const m_black_slime = MonsterSpec{
    .anim_set = anim.a_slime.animationSet(),
    .color = .{ 80, 80, 80, 255 },
    .max_hp = 50,
    .gold = 15,
    .speed = 400,
};

pub const m_skeleton = MonsterSpec{
    .anim_set = anim.a_skeleton.animationSet(),
    .max_hp = 10,
    .gold = 3,
    .speed = 625,
};

pub const m_dark_skeleton = MonsterSpec{
    .anim_set = anim.a_skeleton.animationSet(),
    .color = .{ 80, 80, 80, 255 },
    .max_hp = 125,
    .gold = 20,
    .speed = 500,
};

pub const m_mole = MonsterSpec{
    .anim_set = anim.a_mole.animationSet(),
    .max_hp = 20,
    .gold = 5,
    .speed = 300,
};

pub const MonsterId = GenHandle(Monster);

const HurtOptions = struct {
    amount: u32,
    direction: [2]f32 = [2]f32{ 0, -1 },
    damage_type: DamageType,
};

pub const Monster = struct {
    const PathingState = enum {
        /// Used when there is no goal in the world; monster spawns and does not move
        none,
        to_goal,
        to_spawn,
    };

    id: MonsterId = undefined,
    spawn_id: u32,
    world: *World,
    spec: *const MonsterSpec,
    p_world_x: u32 = 0,
    p_world_y: u32 = 0,
    world_x: u32 = 0,
    world_y: u32 = 0,
    /// Updated immediately on move
    tile_pos: TileCoord = .{ .x = 0, .y = 0 },
    last_tile_pos: TileCoord = .{ .x = 0, .y = 0 },
    face: Direction = .down,
    animator: ?anim.Animator = null,
    path: []TileCoord = &[_]TileCoord{},
    path_index: usize = 0,
    flash_frames: u32 = 0,
    hp: u32 = 0,
    dead: bool = false,
    pathing_state: PathingState = .to_goal,
    carrying_life: bool = false,
    slow_frames: u32 = 0,
    moved_amount: u32 = 0,

    const tile_distance = 10000;

    pub fn setTilePosition(self: *Monster, coord: TileCoord) void {
        self.setWorldPosition(@intCast(u32, coord.x * 16), @intCast(u32, coord.y * 16));
    }

    pub fn setWorldPosition(self: *Monster, new_x: u32, new_y: u32) void {
        self.world_x = new_x;
        self.world_y = new_y;
        self.p_world_x = self.world_x;
        self.p_world_y = self.world_y;
        self.tile_pos = TileCoord.initWorld(new_x, new_y);
        self.last_tile_pos = self.tile_pos;
        self.moved_amount = tile_distance;
    }

    pub fn getTilePosition(self: Monster) TileCoord {
        return self.tile_pos;
    }

    fn computePath(self: *Monster) void {
        self.path = switch (self.pathing_state) {
            .none => &[_]TileCoord{},
            .to_goal => self.world.findPath(self.getTilePosition(), self.world.goal.?.getTilePosition()).?,
            .to_spawn => self.world.findPath(self.getTilePosition(), self.world.getSpawnPosition(self.spawn_id)).?,
        };
        self.path_index = 0;
    }

    fn atEndOfPath(self: *Monster) bool {
        const steps_remaining = self.path.len - (self.path_index + 1);
        return steps_remaining == 0;
    }

    /// Calls beginMove() with the direction needed to continue along the current path
    fn beginPathingMove(self: *Monster) void {
        std.debug.assert(std.meta.eql(self.path[self.path_index], self.getTilePosition()));
        self.beginMove(self.path[self.path_index].directionToAdjacent(self.path[self.path_index + 1]));
        self.path_index += 1;
    }

    fn warpToSpawn(self: *Monster) void {
        self.world.goal.?.emitWarpParticles();
        self.world.playPositionalSoundId(.warp, @intCast(i32, self.world.goal.?.world_x), @intCast(i32, self.world.goal.?.world_y));
        self.setTilePosition(self.world.getSpawnPosition(self.spawn_id));
        self.computePath();
        self.path_index = 0;
    }

    fn updatePathingState(self: *Monster) void {
        switch (self.pathing_state) {
            .none => {},
            .to_goal => {
                if (self.atEndOfPath()) {
                    if (self.world.lives_at_goal > 0) {
                        self.carrying_life = true;
                        self.world.lives_at_goal -= 1;
                        self.pathing_state = .to_spawn;
                        self.computePath();
                    } else {
                        self.warpToSpawn();
                    }
                }
                self.beginPathingMove();
            },
            .to_spawn => {
                if (self.atEndOfPath()) {
                    self.carrying_life = false;
                    self.world.recoverable_lives -= 1;
                    self.pathing_state = .to_goal;
                    self.computePath();
                }
                self.beginPathingMove();
            },
        }
    }

    fn spawn(self: *Monster, frame: u64) void {
        self.hp = self.spec.max_hp;
        if (self.spec.spawnFn) |spawnFn| {
            spawnFn(self, frame);
        }
        if (self.spec.anim_set) |as| {
            self.animator = as.createAnimator("down");
        }
    }

    fn doMovement(self: *Monster) void {
        const move_amount = if (self.slow_frames > 0)
            self.spec.speed - (self.spec.speed / 3)
        else
            self.spec.speed;

        const progress_f = @intToFloat(f32, self.moved_amount) / @intToFloat(f32, tile_distance);

        const x0 = @intToFloat(f32, self.last_tile_pos.worldX());
        const x1 = @intToFloat(f32, self.tile_pos.worldX());
        const y0 = @intToFloat(f32, self.last_tile_pos.worldY());
        const y1 = @intToFloat(f32, self.tile_pos.worldY());

        self.world_x = @floatToInt(u32, zm.lerpV(x0, x1, progress_f));
        self.world_y = @floatToInt(u32, zm.lerpV(y0, y1, progress_f));

        self.moved_amount += move_amount;
    }

    pub fn update(self: *Monster, frame: u64) void {
        self.slow_frames -|= 1;
        self.flash_frames -|= 1;
        self.p_world_x = self.world_x;
        self.p_world_y = self.world_y;

        if (self.moved_amount >= tile_distance) {
            self.moved_amount -= tile_distance;
            self.updatePathingState();
        }

        self.doMovement();

        if (self.spec.updateFn) |updateFn| {
            updateFn(self, frame);
        }

        if (self.animator) |*animator| {
            animator.update();
        }
    }

    pub fn beginMove(self: *Monster, f: Direction) void {
        self.last_tile_pos = self.tile_pos;
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
    pub fn getInterpWorldPosition(self: Monster, t: f64) [2]i32 {
        const ix = zm.lerpV(@intToFloat(f64, self.p_world_x), @intToFloat(f64, self.world_x), t);
        const iy = zm.lerpV(@intToFloat(f64, self.p_world_y), @intToFloat(f64, self.world_y), t);
        return [2]i32{ @floatToInt(i32, ix), @floatToInt(i32, iy) };
    }

    pub fn getWorldCollisionRect(self: Monster) Rect {
        // TODO: origin is top left, this may change
        return Rect.init(@intCast(i32, self.world_x), @intCast(i32, self.world_y), 16, 16);
    }

    pub fn hurt(self: *Monster, opts: HurtOptions) void {
        switch (opts.damage_type) {
            .generic => self.hurtDirectionalGenericDamage(opts.amount, opts.direction),
            .slash => self.hurtDirectionalSlashDamage(opts.amount, opts.direction),
            .fire => self.hurtFireDamage(opts),
        }
    }

    pub fn slow(self: *Monster, amt: u32) void {
        self.slow_frames = std.math.max(self.slow_frames, amt);
    }

    pub fn hurtDirectional(self: *Monster, amt: u32, dir: [2]f32) void {
        std.debug.assert(self.dead == false);
        self.flash_frames +|= 1;
        self.hp -|= amt;
        if (self.hp == 0) {
            self.kill();
        }
        const p = self.getWorldCollisionRect().centerPoint();
        const text_id = self.world.spawnPrintFloatingText("{d}", .{amt}, p[0], p[1]) catch unreachable;
        var text = self.world.floating_text.getPtr(text_id);
        text.vel_x = dir[0];
        text.vel_y = dir[1];
    }

    pub fn hurtDirectionalGenericDamage(self: *Monster, amt: u32, dir: [2]f32) void {
        const p = self.getWorldCollisionRect().centerPoint();
        self.world.playPositionalSound("assets/sounds/hit.ogg", p[0], p[1]);
        self.hurtDirectional(amt, dir);
        const se_id = self.world.spawnSpriteEffect(&se_hurt_generic, p[0], p[1]) catch unreachable;
        self.world.sprite_effects.getPtr(se_id).angle = std.math.atan2(f32, dir[1], dir[0]);
        self.world.sprite_effects.getPtr(se_id).world_x -= std.math.cos(self.world.sprite_effects.getPtr(se_id).angle) * 8.0;
        self.world.sprite_effects.getPtr(se_id).world_y -= std.math.sin(self.world.sprite_effects.getPtr(se_id).angle) * 8.0;
    }

    pub fn hurtDirectionalSlashDamage(self: *Monster, amt: u32, dir: [2]f32) void {
        const p = self.getWorldCollisionRect().centerPoint();
        self.world.playPositionalSound("assets/sounds/slash_hit.ogg", p[0], p[1]);
        self.hurtDirectional(amt, dir);
        _ = self.world.spawnSpriteEffect(&se_hurt_slash, p[0], p[1]) catch unreachable;
    }

    pub fn hurtFireDamage(self: *Monster, hopts: HurtOptions) void {
        const p = self.getWorldCollisionRect().centerPoint();
        self.world.playPositionalSound("assets/sounds/burn.ogg", p[0], p[1]);
        self.hurtDirectional(hopts.amount, hopts.direction);
        _ = self.world.spawnSpriteEffect(&se_hurt_fire, p[0], p[1]) catch unreachable;
    }

    pub fn hurtDelayed(self: *Monster, hopts: HurtOptions, frame_count: u32) void {
        var dd = self.world.createDelayedDamage();
        dd.* = DelayedDamage{
            .monster = self.id,
            .hurt_options = hopts,
            .timer = FrameTimer.initFrames(self.world.world_frame, frame_count),
        };
    }

    pub fn kill(self: *Monster) void {
        self.dead = true;
        if (self.carrying_life) {
            self.world.lives_at_goal += 1;
        }
        const pos = self.getWorldCollisionRect().centerPoint();
        self.world.spawnGoldGain(self.spec.gold, pos[0], pos[1]) catch unreachable;
    }
};

pub const TowerSpec = struct {
    anim_set: ?anim.AnimationSet = null,
    spawnFn: ?*const fn (*Tower, u64) void = null,
    updateFn: ?*const fn (*Tower, u64) void = null,
    cooldown: f32,
    min_range: f32 = 0,
    max_range: f32,
    gold_cost: u32 = 0,
    upgrades: [3]?*const TowerSpec = [3]?*const TowerSpec{ null, null, null },
    tooltip: ?[]const u8 = null,
    tint_rgba: [4]u8 = .{ 255, 255, 255, 255 },
};

pub const t_wall = TowerSpec{
    .cooldown = 0,
    .max_range = 0,
    .gold_cost = 1,
    .tooltip = "Build Wall\n$%gold_cost%\n\nBlocks monster movement.\nCan be built over.",
    .upgrades = [3]?*const TowerSpec{ &t_recruit, null, null },
};

pub const t_recruit = TowerSpec{
    .cooldown = 2,
    .gold_cost = 5,
    .tooltip = "Train Recruit\n$%gold_cost%\n\nWeak melee attack.\nBlocks monster movement.\nUpgrades into other units.",
    .upgrades = [3]?*const TowerSpec{ &t_soldier, &t_rogue, &t_magician },
    .anim_set = anim.a_human1.animationSet(),
    .updateFn = recruitUpdate,
    .max_range = 24,
};

fn recruitUpdate(self: *Tower, frame: u64) void {
    if (self.cooldown.expired(frame)) {
        const m = self.pickMonsterGeneric() orelse return;
        const p = self.world.monsters.getPtr(m).getWorldCollisionRect().centerPoint();
        const r = self.angleTo(p[0], p[1]);

        self.world.monsters.getPtr(m).hurtDirectionalGenericDamage(1, [2]f32{ std.math.cos(r), std.math.sin(r) });
        const target = self.world.monsters.getPtr(m).getWorldCollisionRect().centerPoint();
        self.lookTowards(target[0], target[1]);
        self.cooldown.restart(frame);
    }
}

pub const t_magician = TowerSpec{
    .cooldown = 2,
    .gold_cost = 5,
    .tooltip = "Upgrade to Magician\n$%gold_cost%\n\nMelee attack.\nElemental specializations.",
    .upgrades = [3]?*const TowerSpec{ &t_pyromancer, &t_cryomancer, null },
    .anim_set = anim.a_human3.animationSet(),
    .updateFn = magicianUpdate,
    .max_range = 24,
};

fn magicianUpdate(self: *Tower, frame: u64) void {
    if (self.cooldown.expired(frame)) {
        const m = self.pickMonsterGeneric() orelse return;
        const p = self.world.monsters.getPtr(m).getWorldCollisionRect().centerPoint();
        const r = self.angleTo(p[0], p[1]);
        self.swingEffect(&se_staff, r, 10, 0.3);

        self.world.playPositionalSound("assets/sounds/slash.ogg", @intCast(i32, self.world_x), @intCast(i32, self.world_y));

        const ho = HurtOptions{
            .amount = 1,
            .direction = [2]f32{ std.math.cos(r), std.math.sin(r) },
            .damage_type = .generic,
        };
        self.world.monsters.getPtr(m).hurtDelayed(ho, 3);
        self.lookTowards(p[0], p[1]);
        self.cooldown.restart(frame);
    }
}

pub const t_pyromancer = TowerSpec{
    .cooldown = 10,
    .gold_cost = 25,
    .tooltip = "Upgrade to Pyromancer\n$%gold_cost%\n\nAoE DoT effect.\nLong cooldown.",
    .upgrades = [3]?*const TowerSpec{ null, null, null },
    .anim_set = anim.a_human3.animationSet(),
    .updateFn = pyroUpdate,
    .max_range = 75,
    .tint_rgba = .{ 255, 100, 100, 255 },
};

fn pyroUpdate(self: *Tower, frame: u64) void {
    if (self.cooldown.expired(frame)) {
        const m = self.pickMonsterGeneric() orelse return;
        const p = self.world.monsters.getPtr(m).getWorldCollisionRect().centerPoint();
        const r = self.angleTo(p[0], p[1]);
        self.stabEffect(&se_staff, r, 10, 5, 1);
        self.lookTowards(p[0], p[1]);
        self.cooldown.restart(frame);
        _ = self.world.spawnField(.{
            .position = .{ @intToFloat(f32, p[0]), @intToFloat(f32, p[1]) },
            .radius = 30,
            .duration_sec = 5,
            .tick_rate_sec = 1,
            .tickFn = pyroFieldTick,
            .particle_kind = .fire,
        }) catch unreachable;
        self.world.playPositionalSoundId(.flame, p[0], p[1]);
    }
}

fn pyroFieldTick(self: *Field) void {
    self.world.hurtMonstersInRadius(.{ self.world_x, self.world_y }, self.radius, .{
        .amount = 3,
        .damage_type = .fire,
    });
}

pub const t_cryomancer = TowerSpec{
    .cooldown = 8,
    .gold_cost = 25,
    .tooltip = "Upgrade to Cryomancer\n$%gold_cost%\n\nAoE slow effect\ncentered on caster.",
    .upgrades = [3]?*const TowerSpec{ null, null, null },
    .anim_set = anim.a_human3.animationSet(),
    .updateFn = cryoUpdate,
    .max_range = 50,
    .tint_rgba = .{ 100, 100, 255, 255 },
};

fn cryoUpdate(self: *Tower, frame: u64) void {
    if (self.cooldown.expired(frame)) {
        const m = self.pickMonsterGeneric() orelse return;
        const p = self.world.monsters.getPtr(m).getWorldCollisionRect().centerPoint();
        const r = self.angleTo(p[0], p[1]);
        self.stabEffect(&se_staff, r, 10, 5, 1);
        self.lookTowards(p[0], p[1]);
        self.cooldown.restart(frame);

        const q = self.getWorldCollisionRect().centerPoint();

        _ = self.world.spawnField(.{
            .position = .{ @intToFloat(f32, q[0]), @intToFloat(f32, q[1]) },
            .radius = 50,
            .duration_sec = 5,
            .tick_rate_sec = 1,
            .tickFn = cryoFieldTick,
            .particle_kind = .frost,
        }) catch unreachable;

        self.world.playPositionalSoundId(.frost, q[0], q[1]);
    }
}

fn cryoFieldTick(self: *Field) void {
    self.world.slowMonstersInRadius(.{ self.world_x, self.world_y }, self.radius, 30);
}

pub const t_soldier = TowerSpec{
    .cooldown = 2,
    .gold_cost = 5,
    .tooltip = "Upgrade to Soldier\n$%gold_cost%\n\nMelee attack.",
    .upgrades = [3]?*const TowerSpec{ &t_berserker, &t_lancer, null },
    .anim_set = anim.a_human2.animationSet(),
    .updateFn = soldierUpdate,
    .max_range = 24,
};

fn soldierUpdate(self: *Tower, frame: u64) void {
    if (self.cooldown.expired(frame)) {
        const m = self.pickMonsterGeneric() orelse return;
        const p = self.world.monsters.getPtr(m).getWorldCollisionRect().centerPoint();
        const r = self.angleTo(p[0], p[1]);
        self.swingEffect(&se_sword, r, 10, 0.3);

        self.world.playPositionalSound("assets/sounds/slash.ogg", @intCast(i32, self.world_x), @intCast(i32, self.world_y));

        const ho = HurtOptions{
            .amount = 3,
            .direction = [2]f32{ std.math.cos(r), std.math.sin(r) },
            .damage_type = .slash,
        };
        self.world.monsters.getPtr(m).hurtDelayed(ho, 2);
        self.lookTowards(p[0], p[1]);
        self.cooldown.restart(frame);
    }
}

pub const t_berserker = TowerSpec{
    .cooldown = 2,
    .gold_cost = 20,
    .tooltip = "Upgrade to Berserker\n$%gold_cost%\n\nAoE melee attack.",
    .upgrades = [3]?*const TowerSpec{ null, null, null },
    .anim_set = anim.a_human2.animationSet(),
    .updateFn = berserkerUpdate,
    .max_range = 28,
    .tint_rgba = .{ 255, 120, 120, 255 },
};

fn berserkerUpdate(self: *Tower, frame: u64) void {
    if (self.cooldown.expired(frame)) {
        const m = self.pickMonsterGeneric() orelse return;
        const p = self.world.monsters.getPtr(m).getWorldCollisionRect().centerPoint();
        const r = self.angleTo(p[0], p[1]);
        self.swingEffect(&se_battleaxe, r, 10, 0.4);

        self.world.playPositionalSound("assets/sounds/slash.ogg", @intCast(i32, self.world_x), @intCast(i32, self.world_y));

        self.world.hurtMonstersInRadiusDelay(.{ @intToFloat(f32, p[0]), @intToFloat(f32, p[1]) }, 16, 5, .slash, 4);
        self.lookTowards(p[0], p[1]);
        self.cooldown.restart(frame);
    }
}

pub const t_rogue = TowerSpec{
    .cooldown = 1,
    .gold_cost = 10,
    .tooltip = "Upgrade to Rogue\n$%gold_cost%\n\nMelee attack.\nHas ranged specializations.",

    .anim_set = anim.a_human4.animationSet(),
    .updateFn = rogueUpdate,
    .max_range = 24,
    .upgrades = [3]?*const TowerSpec{ &t_archer, &t_ninja, null },
};

fn rogueUpdate(self: *Tower, frame: u64) void {
    if (self.cooldown.expired(frame)) {
        const m = self.pickMonsterGeneric() orelse return;
        const p = self.world.monsters.getPtr(m).getWorldCollisionRect().centerPoint();
        const r = self.angleTo(p[0], p[1]);
        self.stabEffect(&se_dagger, r, 10, 0.3, 0.9);

        self.world.playPositionalSound("assets/sounds/stab.ogg", @intCast(i32, self.world_x), @intCast(i32, self.world_y));

        self.world.monsters.getPtr(m).hurtDirectional(2, [2]f32{ std.math.cos(r), std.math.sin(r) });
        self.lookTowards(p[0], p[1]);
        self.cooldown.restart(frame);
    }
}

pub const t_ninja = TowerSpec{
    .cooldown = 1,
    .gold_cost = 25,
    .tooltip = "Upgrade to Ninja\n$%gold_cost%\n\nFan projectile attack.",

    .anim_set = anim.a_human4.animationSet(),
    .updateFn = ninjaUpdate,
    .max_range = 90,
    .upgrades = [3]?*const TowerSpec{ null, null, null },
    .tint_rgba = .{ 128, 128, 128, 255 },
};

fn ninjaUpdate(self: *Tower, frame: u64) void {
    if (self.cooldown.expired(frame)) {
        const m = self.pickMonsterGeneric() orelse {
            return;
        };
        const target = self.world.monsters.getPtr(m).getWorldCollisionRect().centerPoint();
        const r = self.angleTo(target[0], target[1]);

        var i: i8 = -1;
        var num: u8 = 0;
        while (i <= 1) : (i += 1) {
            const angle_diff = (std.math.pi / 8.0) * @intToFloat(f32, i);
            var proj = self.world.spawnProjectileDelayed(&proj_star, @intCast(i32, self.world_x + 8), @intCast(i32, self.world_y + 8), 3 * num) catch unreachable;
            proj.activate_sound = .bow;
            const cos_r = std.math.cos(r + angle_diff);
            const sin_r = std.math.sin(r + angle_diff);
            const mag = 2;
            proj.vel_x = cos_r * mag;
            proj.vel_y = sin_r * mag;
            proj.damage = 4;
            proj.angle_vel = std.math.pi / 16.0;
            proj.max_distance = self.spec.max_range;
            num += 1;
        }

        self.lookTowards(target[0], target[1]);
        self.cooldown.restart(frame);
    }
}

pub const t_lancer = TowerSpec{
    .cooldown = 1.2,
    .gold_cost = 25,
    .tooltip = "Upgrade to Lancer\n$%gold_cost%\n\nMelee multi-hit attack.\nExcels at single target.",

    .anim_set = anim.a_human2.animationSet(),
    .updateFn = lancerUpdate,
    .max_range = 24,
    .upgrades = [3]?*const TowerSpec{ null, null, null },
    .tint_rgba = .{ 255, 255, 80, 255 },
};

fn lancerUpdate(self: *Tower, frame: u64) void {
    if (self.cooldown.expired(frame)) {
        const m = self.pickMonsterGeneric() orelse return;
        const p = self.world.monsters.getPtr(m).getWorldCollisionRect().centerPoint();
        const r = self.angleTo(p[0], p[1]);
        self.stabEffect(&se_spear, r, 10, 0.3, 0.9);

        var random = self.world.rng.random();
        const random_angle = std.math.pi / 8.0;

        self.stabEffectDelayed(&se_spear, r + random.float(f32) * random_angle, 9, 0.25, 5);
        self.stabEffectDelayed(&se_spear, r + random.float(f32) * random_angle, 8, 0.20, 10);
        self.stabEffectDelayed(&se_spear, r + random.float(f32) * random_angle, 7, 0.15, 15);
        self.stabEffectDelayed(&se_spear, r + random.float(f32) * random_angle, 6, 0.10, 20);

        self.world.playPositionalSound("assets/sounds/stab.ogg", @intCast(i32, self.world_x), @intCast(i32, self.world_y));

        const ho = HurtOptions{
            .amount = 2,
            .direction = [2]f32{ std.math.cos(r), std.math.sin(r) },
            .damage_type = .generic,
        };

        self.world.monsters.getPtr(m).hurt(ho);
        self.world.monsters.getPtr(m).hurtDelayed(ho, 5);
        self.world.monsters.getPtr(m).hurtDelayed(ho, 10);
        self.world.monsters.getPtr(m).hurtDelayed(ho, 15);
        self.world.monsters.getPtr(m).hurtDelayed(ho, 20);

        self.lookTowards(p[0], p[1]);
        self.cooldown.restart(frame);
    }
}

pub const t_archer = TowerSpec{
    .cooldown = 1.5,
    .gold_cost = 10,
    .tooltip = "Upgrade to Archer\n$%gold_cost%\n\nFires slow moving projectiles\nthat have a minimum range.",

    .anim_set = anim.a_human4.animationSet(),
    .updateFn = archerUpdate,
    .min_range = 50,
    .max_range = 100,
    .upgrades = [3]?*const TowerSpec{ &t_gunner, null, null },
};

fn archerUpdate(self: *Tower, frame: u64) void {
    if (self.cooldown.expired(frame)) {
        const m = self.pickMonsterGeneric() orelse {
            self.killAssocEffect();
            return;
        };
        const target = self.world.monsters.getPtr(m).getWorldCollisionRect().centerPoint();

        self.world.playPositionalSound("assets/sounds/bow.ogg", @intCast(i32, self.world_x), @intCast(i32, self.world_y));

        self.setAssocEffectAimed(&se_bow, target[0], target[1], 6, 1);
        var proj = self.fireProjectileTowards(&proj_arrow, target[0], target[1]);
        proj.damage = 2;
        self.lookTowards(target[0], target[1]);
        self.cooldown.restart(frame);
    }
}

pub const t_gunner = TowerSpec{
    .cooldown = 3,
    .gold_cost = 15,
    .tooltip = "Upgrade to Gunner\n$%gold_cost%\n\nHigh damage projectiles.\nHigh cooldown.",

    .anim_set = anim.a_human4.animationSet(),
    .updateFn = gunnerUpdate,
    .min_range = 50,
    .max_range = 100,
    .upgrades = [3]?*const TowerSpec{ &t_shotgunner, null, null },
};

fn gunnerUpdate(self: *Tower, frame: u64) void {
    if (self.cooldown.expired(frame)) {
        const m = self.pickMonsterGeneric() orelse {
            self.killAssocEffect();
            return;
        };
        const target = self.world.monsters.getPtr(m).getWorldCollisionRect().centerPoint();

        self.world.playPositionalSound("assets/sounds/gun.ogg", @intCast(i32, self.world_x), @intCast(i32, self.world_y));

        self.setAssocEffectAimed(&se_gun, target[0], target[1], 6, 1);
        var proj = self.fireProjectileTowards(&proj_bullet, target[0], target[1]);
        proj.damage = 5;
        self.lookTowards(target[0], target[1]);
        self.cooldown.restart(frame);
    }
}

pub const t_shotgunner = TowerSpec{
    .cooldown = 8,
    .gold_cost = 35,
    .tooltip = "Upgrade to Shotgunner\n$%gold_cost%\n\nAoE projectile spread.\nHigh cooldown.",

    .anim_set = anim.a_human4.animationSet(),
    .updateFn = shotgunnerUpdate,
    .min_range = 25,
    .max_range = 65,
    .upgrades = [3]?*const TowerSpec{ null, null, null },
};

fn shotgunnerUpdate(self: *Tower, frame: u64) void {
    if (self.cooldown.expired(frame)) {
        var random = self.world.rng.random();

        const m = self.pickMonsterGeneric() orelse {
            self.killAssocEffect();
            return;
        };
        const target = self.world.monsters.getPtr(m).getWorldCollisionRect().centerPoint();
        const r = self.angleTo(target[0], target[1]);

        self.world.playPositionalSoundId(.shotgun, @intCast(i32, self.world_x), @intCast(i32, self.world_y));
        self.setAssocEffectAimed(&se_biggun, target[0], target[1], 6, 1);

        var i: u8 = 0;
        while (i < 8) : (i += 1) {
            const angle_diff = (random.float(f32) * std.math.pi / 4.0) - std.math.pi / 8.0;
            var proj = self.world.spawnProjectile(&proj_bullet, @intCast(i32, self.world_x + 8), @intCast(i32, self.world_y + 8)) catch unreachable;
            proj.scale = 0.5 + random.float(f32) * 0.5;
            const cos_r = std.math.cos(r + angle_diff);
            const sin_r = std.math.sin(r + angle_diff);
            const mag = 2 + random.float(f32);
            proj.vel_x = cos_r * mag;
            proj.vel_y = sin_r * mag;
            proj.damage = 2;
            proj.max_distance = self.spec.max_range;
        }

        self.lookTowards(target[0], target[1]);
        self.cooldown.restart(frame);
    }
}

pub const TowerId = GenHandle(Tower);

pub const Tower = struct {
    id: TowerId = undefined,
    world: *World,
    spec: *const TowerSpec,
    animator: ?anim.Animator = null,
    world_x: u32,
    world_y: u32,
    target_mobid: ?MonsterId = null,
    cooldown: FrameTimer = .{},
    assoc_effect: ?SpriteEffectId = null,
    invested_gold: u32 = 0,

    fn pickMonsterGeneric(self: *Tower) ?MonsterId {
        const p = self.getWorldCollisionRect().centerPoint();
        if (self.target_mobid) |id| {
            if (self.world.monsters.getPtrWeak(id)) |m| {
                if (!m.dead) {
                    const q = m.getWorldCollisionRect().centerPoint();
                    const d = mu.dist(p, q);
                    if (d >= self.spec.min_range and d <= self.spec.max_range) {
                        return id;
                    }
                }
            }
        }
        self.target_mobid = self.world.pickClosestMonster(p[0], p[1], self.spec.min_range, self.spec.max_range);
        return self.target_mobid;
    }

    pub fn setWorldPosition(self: *Tower, new_x: u32, new_y: u32) void {
        self.world_x = new_x;
        self.world_y = new_y;
    }

    pub fn getTilePosition(self: Tower) TileCoord {
        return TileCoord.initWorld(self.world_x, self.world_y);
    }

    pub fn getWorldCollisionRect(self: Tower) Rect {
        return Rect.init(@intCast(i32, self.world_x), @intCast(i32, self.world_y), 16, 16);
    }

    pub fn swingEffect(self: *Tower, se_spec: *const SpriteEffectSpec, r: f32, offset: f32, effect_life_sec: f32) void {
        if (std.math.cos(r) > 0) {
            self.setAssocEffectAngle(se_spec, r - std.math.pi / 2.0, offset, effect_life_sec);
            var effect = self.world.sprite_effects.getPtr(self.assoc_effect.?);
            effect.angular_vel = 1.0 / 4.0;
        } else {
            self.setAssocEffectAngle(se_spec, r + std.math.pi / 2.0, offset, effect_life_sec);
            var effect = self.world.sprite_effects.getPtr(self.assoc_effect.?);
            effect.angular_vel = -1.0 / 4.0;
        }
    }

    pub fn stabEffect(self: *Tower, se_spec: *const SpriteEffectSpec, r: f32, offset: f32, effect_life_sec: f32, offset_mul: f32) void {
        self.setAssocEffectAngle(se_spec, r, offset, effect_life_sec);
        var effect = self.world.sprite_effects.getPtr(self.assoc_effect.?);
        effect.offset_coef = offset_mul;
    }

    pub fn stabEffectDelayed(self: *Tower, se_spec: *const SpriteEffectSpec, r: f32, offset: f32, effect_life_sec: f32, frame_count: u32) void {
        const basis_x = self.world_x + 8;
        const basis_y = self.world_y + 8;
        const eid = self.world.spawnSpriteEffect(se_spec, @intCast(i32, basis_x), @intCast(i32, basis_y)) catch unreachable;
        var effect = self.world.sprite_effects.getPtr(eid);
        const delay = FrameTimer.initFrames(self.world.world_frame, frame_count);
        effect.delay = delay;
        effect.setAngleOffset(r, offset);
        effect.lifetime = self.world.createTimerSeconds(effect_life_sec);
        const life_frames = effect.lifetime.?.durationFrames();
        effect.lifetime.?.frame_start = delay.frame_end;
        effect.lifetime.?.frame_end = delay.frame_end + life_frames;
        effect.offset_coef = 0.9;
        effect.activate_sound = .stab;
    }

    pub fn setAssocEffectAngle(self: *Tower, se_spec: *const SpriteEffectSpec, r: f32, offset: f32, effect_life_sec: f32) void {
        const basis_x = self.world_x + 8;
        const basis_y = self.world_y + 8;

        if (self.assoc_effect == null or self.world.sprite_effects.getPtrWeak(self.assoc_effect.?) == null) {
            self.assoc_effect = self.world.spawnSpriteEffect(se_spec, @intCast(i32, basis_x), @intCast(i32, basis_y)) catch unreachable;
        }
        self.world.sprite_effects.getPtr(self.assoc_effect.?).setAngleOffset(r, offset);
        self.world.sprite_effects.getPtr(self.assoc_effect.?).lifetime = self.world.createTimerSeconds(effect_life_sec);
    }

    pub fn setAssocEffectAimed(self: *Tower, se_spec: *const SpriteEffectSpec, world_x: i32, world_y: i32, offset: f32, effect_life_sec: f32) void {
        const r = self.angleTo(world_x, world_y);
        self.setAssocEffectAngle(se_spec, r, offset, effect_life_sec);
    }

    pub fn killAssocEffect(self: *Tower) void {
        if (self.assoc_effect) |eid| {
            if (self.world.sprite_effects.getPtrWeak(eid)) |se| {
                se.dead = true;
            }
            self.assoc_effect = null;
        }
    }

    pub fn fireProjectileTowards(self: *Tower, pspec: *const ProjectileSpec, world_x: i32, world_y: i32) *Projectile {
        var proj = self.world.spawnProjectile(pspec, @intCast(i32, self.world_x + 8), @intCast(i32, self.world_y + 8)) catch unreachable;

        const r = self.angleTo(world_x, world_y);
        const cos_r = std.math.cos(r);
        const sin_r = std.math.sin(r);

        proj.vel_x = cos_r * 2;
        proj.vel_y = sin_r * 2;
        proj.max_distance = self.spec.max_range;

        return proj;
    }

    pub fn angleTo(self: *Tower, world_x: i32, world_y: i32) f32 {
        var r = mu.angleBetween(
            @Vector(2, f32){ @intToFloat(f32, self.world_x + 8), @intToFloat(f32, self.world_y + 8) },
            @Vector(2, f32){ @intToFloat(f32, world_x), @intToFloat(f32, world_y) },
        );
        return r;
    }

    pub fn lookTowards(self: *Tower, world_x: i32, world_y: i32) void {
        const r = self.angleTo(world_x, world_y);
        const cos_r = std.math.cos(r);
        const sin_r = std.math.sin(r);

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
    }

    fn spawn(self: *Tower, frame: u64) void {
        if (self.spec.anim_set) |as| {
            self.animator = as.createAnimator("down");
        }
        if (self.spec.spawnFn) |spawnFn| {
            spawnFn(self, frame);
        }
        self.invested_gold += self.spec.gold_cost;
        self.cooldown = FrameTimer.initSeconds(frame, self.spec.cooldown);
    }

    fn update(self: *Tower, frame: u64) void {
        if (self.spec.updateFn) |updateFn| {
            updateFn(self, frame);
        }
        if (self.animator) |*animator| {
            animator.update();
        }
    }

    fn sell(self: *Tower) void {
        self.killAssocEffect();
    }

    pub fn upgradeInto(self: *Tower, spec: *const TowerSpec) void {
        self.spec = spec;
        if (self.spec.anim_set) |as| {
            self.animator = as.createAnimator("down");
        }
        self.killAssocEffect();
        self.spawn(self.world.world_frame);
    }
};

pub const Spawn = struct {
    var rng = std.rand.Xoshiro256.init(0);

    id: u32 = undefined,
    coord: TileCoord,
    /// If spawn is outside of playable area, this will be null
    emitter: ?particle.PointEmitter = null,

    fn emitWarpParticles(self: *Spawn, frame: u64) void {
        if (self.emitter) |*em| {
            em.emitCount(.warp, frame, 16);
        }
    }
};

const se_bow = SpriteEffectSpec{
    .anim_set = anim.a_bow.animationSet(),
};

const se_gun = SpriteEffectSpec{
    .anim_set = anim.a_gun.animationSet(),
};

const se_biggun = SpriteEffectSpec{
    .anim_set = anim.a_biggun.animationSet(),
};

const se_sword = SpriteEffectSpec{
    .anim_set = anim.a_sword.animationSet(),
};

const se_battleaxe = SpriteEffectSpec{
    .anim_set = anim.a_battleaxe.animationSet(),
};

const se_spear = SpriteEffectSpec{
    .anim_set = anim.a_spear.animationSet(),
};

const se_staff = SpriteEffectSpec{
    .anim_set = anim.a_staff.animationSet(),
};

const se_dagger = SpriteEffectSpec{
    .anim_set = anim.a_dagger.animationSet(),
};

const se_hurt_generic = SpriteEffectSpec{
    .anim_set = anim.a_hurt_generic.animationSet(),
};

const se_hurt_slash = SpriteEffectSpec{
    .anim_set = anim.a_hurt_slash.animationSet(),
};

const se_hurt_fire = SpriteEffectSpec{
    .anim_set = anim.a_hurt_fire.animationSet(),
};

pub const SpriteEffectSpec = struct {
    anim_set: ?anim.AnimationSet = null,
    spawnFn: ?*const fn (*SpriteEffect, u64) void = null,
    updateFn: ?*const fn (*SpriteEffect, u64) void = null,
};

pub const SpriteEffectId = GenHandle(SpriteEffect);

const SoundId = enum {
    none,
    stab,
    flame,
    frost,
    warp,
    shotgun,
    bow,
};

pub const SpriteEffect = struct {
    id: SpriteEffectId = undefined,
    world: *World,
    spec: *const SpriteEffectSpec,
    animator: ?anim.Animator = null,
    /// Basis
    p_world_x: f32 = 0,
    p_world_y: f32 = 0,
    world_x: f32,
    world_y: f32,
    /// Offset after pre-rotation
    p_offset_x: f32 = 0,
    p_offset_y: f32 = 0,
    offset_x: f32 = 0,
    offset_y: f32 = 0,
    /// Pre-rotation
    p_angle: f32 = 0,
    angle: f32 = 0,
    /// Post-rotation
    p_post_angle: f32 = 0,
    post_angle: f32 = 0,
    dead: bool = false,
    activated: bool = false,
    /// For delayed effects, a timer that must expire before the effect plays.
    delay: ?FrameTimer = null,
    lifetime: ?FrameTimer = null,
    angular_vel: f32 = 0,
    offset_coef: f32 = 1,
    activate_sound: SoundId = .none,

    fn spawn(self: *SpriteEffect, frame: u64) void {
        self.p_world_x = self.world_x;
        self.p_world_y = self.world_y;

        if (self.spec.anim_set) |as| {
            self.animator = as.createAnimator("default");
        }
        if (self.spec.spawnFn) |spawnFn| {
            spawnFn(self, frame);
        }
    }

    fn update(self: *SpriteEffect, frame: u64) void {
        if (self.delay) |delay| {
            if (!delay.expired(frame)) {
                return;
            }
        }
        if (!self.activated) {
            self.world.playPositionalSoundId(self.activate_sound, @floatToInt(i32, self.world_x), @floatToInt(i32, self.world_y));
            self.activated = true;
        }
        self.p_world_x = self.world_x;
        self.p_world_y = self.world_y;
        self.p_offset_x = self.offset_x;
        self.p_offset_y = self.offset_y;
        self.p_angle = self.angle;
        self.p_post_angle = self.post_angle;
        self.post_angle += self.angular_vel;
        self.offset_x *= self.offset_coef;
        self.offset_y *= self.offset_coef;

        if (self.animator) |*animator| {
            animator.update();
            if (animator.done) {
                self.dead = true;
            }
        }
        if (self.lifetime) |lifetime| {
            if (lifetime.expired(frame)) {
                self.dead = true;
            }
        }
        if (self.spec.updateFn) |updateFn| {
            updateFn(self, frame);
        }
    }

    fn setAngleOffset(self: *SpriteEffect, angle: f32, distance: f32) void {
        const cos_a = std.math.cos(angle);
        const sin_a = std.math.sin(angle);
        self.offset_x = cos_a * distance;
        self.offset_y = sin_a * distance;
        self.angle = angle;
    }
};

pub const FloatingText = struct {
    id: u32 = undefined,
    world: *World,
    text: [16]u8,
    textlen: u8 = 0,
    p_world_x: f32,
    p_world_y: f32,
    world_x: f32,
    world_y: f32,
    vel_x: f32,
    vel_y: f32,
    max_life: u32 = 30,
    life: u32 = 30,
    dead: bool = false,
    color: @Vector(4, u8) = @splat(4, @as(u8, 255)),

    fn update(self: *FloatingText) void {
        self.p_world_x = self.world_x;
        self.p_world_y = self.world_y;
        self.world_x += self.vel_x;
        self.world_y += self.vel_y;
        self.vel_x *= 0.9;
        self.vel_y *= 0.9;
        self.life -|= 1;
        if (self.life == 0) {
            self.dead = true;
        }
    }

    pub fn textSlice(self: *const FloatingText) []const u8 {
        return self.text[0..self.textlen];
    }

    // TODO proper return value
    pub fn getInterpWorldPosition(self: FloatingText, t: f64) [2]i32 {
        const ix = zm.lerpV(self.p_world_x, self.world_x, @floatCast(f32, t));
        const iy = zm.lerpV(self.p_world_y, self.world_y, @floatCast(f32, t));
        return [2]i32{ @floatToInt(i32, ix), @floatToInt(i32, iy) };
    }

    pub fn lifePercent(self: FloatingText) f32 {
        return @intToFloat(f32, self.life) / @intToFloat(f32, self.max_life);
    }

    /// 0 at start, 1 at end
    pub fn invLifePercent(self: FloatingText) f32 {
        return 1 - self.lifePercent();
    }
};

pub const Goal = struct {
    world: *World,
    world_x: u32,
    world_y: u32,
    animator: anim.Animator = anim.a_goal.animationSet().createAnimator("default"),
    emitter: particle.PointEmitter,

    fn init(world: *World, world_x: u32, world_y: u32) Goal {
        var self = Goal{
            .world = world,
            .world_x = world_x,
            .world_y = world_y,
            .emitter = .{
                .parent = &world.particle_sys,
                .pos = .{ @intToFloat(f32, world_x + 8), @intToFloat(f32, world_y + 16) },
                .params = particle.warp_params,
            },
        };
        return self;
    }

    fn getTilePosition(self: Goal) TileCoord {
        return TileCoord.initWorld(self.world_x, self.world_y);
    }

    fn update(self: *Goal, frame: u64) void {
        _ = frame;
        self.animator.update();
    }

    fn emitWarpParticles(self: *Goal) void {
        self.emitter.emitCount(.warp, self.world.world_frame, 16);
    }
};

const EventSpawn = struct {
    monster_spec: *const MonsterSpec,
    time: u32,
    repeat: u32,
};

const EventWait = struct {
    time: u32,
};

pub const WaveEvent = union(enum) {
    spawn: EventSpawn,
    wait: EventWait,
};

pub const WaveEventList = struct {
    current_event: usize,
    events: []WaveEvent,
    next_event_timer: FrameTimer,

    fn deinit(self: *WaveEventList, allocator: Allocator) void {
        allocator.free(self.events);
    }

    fn start(self: *WaveEventList, frame: u64) void {
        if (self.events.len == 0) {
            return;
        }
        self.setTimerFromEvent(frame, self.events[0]);
    }

    fn setTimerFromEvent(self: *WaveEventList, frame: u64, ev: WaveEvent) void {
        switch (ev) {
            .spawn => |s| {
                self.next_event_timer = FrameTimer.initSeconds(frame, @intToFloat(f32, s.time));
            },
            .wait => |w| {
                self.next_event_timer = FrameTimer.initSeconds(frame, @intToFloat(f32, w.time));
            },
        }
    }

    fn advance(self: *WaveEventList, frame: u64) void {
        switch (self.events[self.current_event]) {
            .spawn => |*s| {
                if (s.repeat > 0) {
                    s.repeat -= 1;
                } else {
                    self.current_event += 1;
                }
            },
            .wait => {
                self.current_event += 1;
            },
        }
        if (self.current_event < self.events.len) {
            self.setTimerFromEvent(frame, self.events[self.current_event]);
        }
    }

    fn getCurrentEvent(self: *WaveEventList, frame: u64) ?WaveEvent {
        if (self.current_event < self.events.len and self.next_event_timer.expired(frame)) {
            return self.events[self.current_event];
        } else {
            return null;
        }
    }

    // TODO: not totally accurate, repeats should probably count as multiple events
    fn remainingEventCount(self: WaveEventList) usize {
        return self.events.len - self.current_event;
    }

    fn getDuration(self: WaveEventList) f32 {
        var total: f32 = 0;
        for (self.events) |e| {
            switch (e) {
                .spawn => |s| {
                    total += @intToFloat(f32, s.repeat * s.time);
                },
                .wait => |w| {
                    total += @intToFloat(f32, w.time);
                },
            }
        }
        return total;
    }
};

pub const Wave = struct {
    // map spawn ID to event list
    spawn_events: std.AutoArrayHashMapUnmanaged(u32, WaveEventList),

    fn start(self: *Wave, frame: u64) void {
        for (self.spawn_events.values()) |*list| {
            list.start(frame);
        }
    }

    fn getReadyEvent(self: Wave, spawn_point_id: u32, frame: u64) ?WaveEvent {
        if (self.spawn_events.getPtr(spawn_point_id)) |events_for_spawn| {
            if (events_for_spawn.getCurrentEvent(frame)) |e| {
                events_for_spawn.advance(frame);
                return e;
            }
        }
        return null;
    }

    fn anyRemainingEvents(self: Wave) bool {
        for (self.spawn_events.values()) |evlist| {
            if (evlist.remainingEventCount() != 0) {
                return true;
            }
        }
        return false;
    }

    fn deinit(self: *Wave, allocator: Allocator) void {
        for (self.spawn_events.values()) |*evlist| {
            evlist.deinit(allocator);
        }
        self.spawn_events.deinit(allocator);
    }
};

pub const WaveList = struct {
    waves: []Wave = &[_]Wave{},

    fn startWave(self: WaveList, num: usize, frame: u64) void {
        self.waves[num].start(frame);
    }

    fn getWaveDuration(self: WaveList, num: usize) f32 {
        var max: f32 = 0;
        for (self.waves[num].spawn_events.values()) |list| {
            max = std.math.max(max, list.getDuration());
        }
        return max;
    }

    fn deinit(self: *WaveList, allocator: Allocator) void {
        if (self.waves.len == 0) {
            return;
        }
        for (self.waves) |*wave| {
            wave.deinit(allocator);
        }
        allocator.free(self.waves);
    }
};

const DamageType = enum {
    generic,
    slash,
    fire,
};

const DelayedDamage = struct {
    monster: MonsterId,
    hurt_options: HurtOptions,
    timer: FrameTimer,
};

const EffectType = enum {
    swing,
    stab,
};

const DelayedEffect = struct {
    tower: TowerId,
    amount: u32,
    direction: [2]f32,
    damage_type: DamageType,
    timer: FrameTimer,
};

const FieldId = GenHandle(Field);

const Field = struct {
    id: FieldId = undefined,
    world: *World,
    world_x: f32,
    world_y: f32,
    radius: f32,
    dead: bool = false,
    tickFn: *const fn (*Field) void,
    life_timer: FrameTimer,
    tick_timer: FrameTimer,
    kind: particle.ParticleKind,
    emitter: particle.CircleEmitter,

    fn update(self: *Field) void {
        self.emitter.emit(self.kind, self.world.world_frame);
        if (self.tick_timer.expired(self.world.world_frame)) {
            self.tickFn(self);
            self.tick_timer.restart(self.world.world_frame);
        }
        if (self.life_timer.expired(self.world.world_frame)) {
            self.dead = true;
        }
    }
};

pub const World = struct {
    allocator: Allocator,
    map: Tilemap = .{},
    scratch_map: Tilemap = .{},
    scratch_cache: PathfindingCache,
    monsters: IntrusiveGenSlotMap(Monster) = .{},
    towers: IntrusiveGenSlotMap(Tower) = .{},
    /// Tile coordinates for tower -> slot map handle
    tower_map: std.AutoHashMapUnmanaged(TileCoord, TowerId) = .{},
    spawns: IntrusiveSlotMap(Spawn) = .{},
    spawn_map: std.StringArrayHashMapUnmanaged(u32) = .{},
    projectiles: IntrusiveSlotMap(Projectile) = .{},
    pending_projectiles: std.ArrayListUnmanaged(Projectile) = .{},
    sprite_effects: IntrusiveGenSlotMap(SpriteEffect) = .{},
    fields: IntrusiveGenSlotMap(Field) = .{},
    floating_text: IntrusiveSlotMap(FloatingText) = .{},
    delayed_damage: std.ArrayListUnmanaged(DelayedDamage) = .{},
    waves: WaveList = .{},
    active_waves: std.ArrayListUnmanaged(usize) = .{},
    pathfinder: PathfindingState,
    path_cache: PathfindingCache,
    goal: ?Goal = null,
    view: Rect = .{},
    play_area: ?Rect = null,
    custom_rects: std.StringArrayHashMapUnmanaged(Rect) = .{},
    lives_at_goal: u32 = 30,
    recoverable_lives: u32 = 30,
    player_gold: u32 = 50,
    world_frame: u64 = 0,
    next_wave: usize = 0,
    player_won: bool = false,
    music_filename: ?[:0]const u8 = null,
    /// `null` when there are no more waves.
    next_wave_timer: ?FrameTimer = null,
    rng: std.rand.DefaultPrng,
    particle_sys: particle.ParticleSystem,
    safe_zone: Rect = Rect.init(0, 0, 0, 0),
    fast_tpathing: bool = true,

    pub fn destroy(self: *World) void {
        self.particle_sys.deinit();
        self.path_cache.deinit();
        self.fields.deinit(self.allocator);
        self.spawns.deinit(self.allocator);
        self.monsters.deinit(self.allocator);
        self.towers.deinit(self.allocator);
        self.projectiles.deinit(self.allocator);
        self.map.deinit(self.allocator);
        self.scratch_map.deinit(self.allocator);
        self.scratch_cache.deinit();
        self.pathfinder.deinit();
        self.floating_text.deinit(self.allocator);
        self.pending_projectiles.deinit(self.allocator);
        self.sprite_effects.deinit(self.allocator);
        self.tower_map.deinit(self.allocator);
        self.delayed_damage.deinit(self.allocator);
        for (self.custom_rects.keys()) |k| {
            self.allocator.free(k);
        }
        self.custom_rects.clearAndFree(self.allocator);
        for (self.spawn_map.keys()) |k| {
            self.allocator.free(k);
        }
        self.spawn_map.deinit(self.allocator);
        self.waves.deinit(self.allocator);
        self.active_waves.deinit(self.allocator);
        if (self.music_filename) |s| {
            self.allocator.free(s);
        }
        self.allocator.destroy(self);
    }

    /// Happens after successful load from json
    fn finalizeInit(self: *World) void {
        self.safe_zone = Rect.init(0, 0, @intCast(i32, self.getWidth() * 16), @intCast(i32, self.getHeight() * 16));
        self.safe_zone.inflate(256, 256);

        const range = self.getPlayableRange();
        for (self.spawns.slice()) |*spawn| {
            if (range.contains(spawn.coord)) {
                spawn.emitter = particle.PointEmitter{
                    .parent = &self.particle_sys,
                    .pos = .{ @intToFloat(f32, spawn.coord.worldX() + 8), @intToFloat(f32, spawn.coord.worldY() + 16) },
                    .params = particle.warp_params,
                };
            }
        }
    }

    fn addCustomRect(self: *World, name: []const u8, rect: Rect) !void {
        const name_dup = try self.allocator.dupe(u8, name);
        errdefer self.allocator.free(name_dup);
        try self.custom_rects.put(self.allocator, name_dup, rect);
    }

    pub fn getCustomRectByName(self: *World, name: []const u8) ?Rect {
        return self.custom_rects.get(name);
    }

    fn createTimerSeconds(self: *World, sec: f32) FrameTimer {
        return FrameTimer.initSeconds(self.world_frame, sec);
    }

    pub fn setNextWaveTimer(self: *World, time_sec: f32) void {
        self.next_wave_timer = FrameTimer.initSeconds(self.world_frame, time_sec);
    }

    pub fn getPlayableRange(self: World) TileRange {
        if (self.play_area) |area| {
            return TileRange{
                .min = TileCoord.initSignedWorld(area.left(), area.top()),
                .max = TileCoord.initSignedWorld(area.right() - 16, area.bottom() - 16),
            };
        } else {
            return TileRange{
                .min = TileCoord{ .x = 0, .y = 0 },
                .max = TileCoord{ .x = @intCast(u16, self.getWidth() - 1), .y = @intCast(u16, self.getHeight() - 1) },
            };
        }
    }

    pub fn getWidth(self: World) usize {
        return self.map.width;
    }

    pub fn getHeight(self: World) usize {
        return self.map.height;
    }

    fn setGoal(self: *World, coord: TileCoord) void {
        self.goal = Goal.init(self, coord.worldX(), coord.worldY());
    }

    fn createSpawn(self: *World, name: []const u8, coord: TileCoord) !void {
        const s_id = try self.spawns.put(self.allocator, Spawn{
            .coord = coord,
        });
        const name_dup = try self.allocator.dupe(u8, name);
        try self.spawn_map.put(self.allocator, name_dup, s_id);
    }

    pub fn canAfford(self: *World, spec: *const TowerSpec) bool {
        return self.player_gold >= spec.gold_cost;
    }

    pub fn canBuildAt(self: *World, coord: TileCoord) bool {
        const collision_flags = self.map.getCollisionFlags2D(coord.x, coord.y);
        if (collision_flags.all()) {
            return false;
        }
        if (self.goal) |goal| {
            if (std.meta.eql(coord, goal.getTilePosition())) {
                return false;
            }
        }
        const tile_flags = self.map.at2DPtr(.base, coord.x, coord.y).flags;
        if (tile_flags.construction_blocked) {
            return false;
        }
        if (tile_flags.contains_tower) {
            if (self.tower_map.get(coord)) |id| {
                if (self.towers.get(id).spec == &t_wall) {
                    return true;
                }
            }
            return false;
        }
        const tile_world_rect = Rect.init(
            @intCast(i32, coord.worldX()),
            @intCast(i32, coord.worldY()),
            16,
            16,
        );
        for (self.monsters.slice()) |m| {
            if (m.getWorldCollisionRect().intersect(tile_world_rect, null)) {
                return false;
            }
            if (std.meta.eql(coord, m.getTilePosition())) {
                return false;
            }
        }
        self.map.copyInto(&self.scratch_map);
        self.scratch_map.at2DPtr(.base, coord.x, coord.y).flags.contains_tower = true;
        self.scratch_cache.clear();

        // (2022-11-02) Q: do we actually need to path from all monsters? it seems spawn points should be enough
        // (2022-11-18) A: Yes, you can wall a monster in that would stray from the spawn->goal path with the newly placed tile.
        var timer = std.time.Timer.start() catch unreachable;

        if (self.goal) |goal| {
            for (self.spawns.slice()) |*s| {
                if (!self.findTheoreticalPath(s.coord, goal.getTilePosition())) {
                    return false;
                }
            }
            for (self.monsters.slice()) |*m| {
                if (!self.findTheoreticalPath(m.getTilePosition(), goal.getTilePosition())) {
                    return false;
                }
            }
        }

        std.debug.print("canBuildAt took {d}ms\n", .{timer.read() / std.time.ns_per_ms});

        return true;
    }

    fn createDelayedDamage(self: *World) *DelayedDamage {
        return self.delayed_damage.addOne(self.allocator) catch unreachable;
    }

    pub fn spawnFloatingText(self: *World, text: []const u8, world_x: i32, world_y: i32) !u32 {
        if (text.len > 16) {
            return error.TextTooLong;
        }
        const id = try self.floating_text.put(self.allocator, FloatingText{
            .world = self,
            .text = undefined,
            .world_x = @intToFloat(f32, world_x),
            .world_y = @intToFloat(f32, world_y),
            .p_world_x = @intToFloat(f32, world_x),
            .p_world_y = @intToFloat(f32, world_y),
            .vel_x = 0,
            .vel_y = 0,
        });
        var ptr = self.floating_text.getPtr(id);
        std.mem.copy(u8, &ptr.text, text);
        ptr.textlen = @intCast(u8, text.len);
        return id;
    }

    pub fn spawnPrintFloatingText(self: *World, comptime fmt: []const u8, args: anytype, world_x: i32, world_y: i32) !u32 {
        var buf: [16]u8 = undefined;
        var s = std.io.fixedBufferStream(&buf);
        var w = s.writer();
        try w.print(fmt, args);
        return self.spawnFloatingText(s.getWritten(), world_x, world_y);
    }

    pub fn spawnGoldGain(self: *World, amt: u32, world_x: i32, world_y: i32) !void {
        const text_id = try self.spawnPrintFloatingText("+{d}", .{amt}, world_x, world_y);
        var text_obj = self.floating_text.getPtr(text_id);
        text_obj.color = @Vector(4, u8){ 255, 255, 0, 255 };
        text_obj.vel_y = -1;
        self.player_gold += amt;
    }

    pub fn spawnTower(self: *World, spec: *const TowerSpec, coord: TileCoord) !TowerId {
        // if we're building over a wall, delete it first so we're not bloating the towers slotmap
        if (self.tower_map.get(coord)) |id| {
            const wall = self.towers.getPtr(id);
            std.debug.assert(wall.spec == &t_wall);
            self.towers.erase(id);
        }
        self.map.at2DPtr(.base, coord.x, coord.y).flags.contains_tower = true;
        var id = try self.spawnTowerWorld(
            spec,
            @intCast(u32, coord.x * 16),
            @intCast(u32, coord.y * 16),
        );
        try self.tower_map.put(self.allocator, coord, id);
        self.invalidatePathCache();
        return id;
    }

    pub fn sellTower(self: *World, id: TowerId) void {
        const tower = self.towers.getPtr(id);
        const gold = std.math.max(1, tower.invested_gold / 2);
        const p = tower.getWorldCollisionRect().centerPoint();
        self.spawnGoldGain(gold, p[0], p[1]) catch unreachable;
        self.playPositionalSound("assets/sounds/coindrop.ogg", p[0], p[1]);
        const coord = tower.getTilePosition();
        const removed = self.tower_map.remove(coord);
        std.debug.assert(removed);
        tower.sell();
        self.map.at2DPtr(.base, coord.x, coord.y).flags.contains_tower = false;
        self.towers.erase(id);
        self.invalidatePathCache();
    }

    pub fn spawnSpriteEffect(self: *World, spec: *const SpriteEffectSpec, world_x: i32, world_y: i32) !SpriteEffectId {
        const id = try self.sprite_effects.put(self.allocator, SpriteEffect{
            .world = self,
            .spec = spec,
            .world_x = @intToFloat(f32, world_x),
            .world_y = @intToFloat(f32, world_y),
        });
        self.sprite_effects.getPtr(id).spawn(self.world_frame);
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
            .spawn_x = @intToFloat(f32, world_x),
            .spawn_y = @intToFloat(f32, world_y),
        };
        return ptr;
    }

    pub fn spawnProjectileDelayed(self: *World, spec: *const ProjectileSpec, world_x: i32, world_y: i32, frames: u32) !*Projectile {
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
            .delay = FrameTimer.initFrames(self.world_frame, frames),
            .spawn_x = @intToFloat(f32, world_x),
            .spawn_y = @intToFloat(f32, world_y),
        };
        return ptr;
    }

    pub fn slowMonstersInRadius(self: *World, pos: [2]f32, radius: f32, amt: u32) void {
        for (self.monsters.slice()) |*m| {
            if (m.dead) {
                continue;
            }
            const p = m.getWorldCollisionRect().toRectf().centerPoint();
            const d = mu.dist(p, pos);
            if (d <= radius) {
                m.slow(amt);
            }
        }
    }

    pub fn hurtMonstersInRadius(self: *World, pos: [2]f32, radius: f32, hopts: HurtOptions) void {
        for (self.monsters.slice()) |*m| {
            if (m.dead) {
                continue;
            }
            const p = m.getWorldCollisionRect().toRectf().centerPoint();
            const d = mu.dist(p, pos);
            if (d <= radius) {
                m.hurt(hopts);
            }
        }
    }

    pub fn hurtMonstersInRadiusDelay(self: *World, pos: [2]f32, radius: f32, amt: u32, dtype: DamageType, frame_count: u32) void {
        for (self.monsters.slice()) |*m| {
            if (m.dead) {
                continue;
            }
            const p = m.getWorldCollisionRect().toRectf().centerPoint();
            const d = mu.dist(p, pos);
            if (d <= radius) {
                const V2 = @Vector(2, f32);
                const r = mu.angleBetween(@as(V2, p), @as(V2, pos));
                m.hurtDelayed(.{ .amount = amt, .direction = .{ @cos(r), @sin(r) }, .damage_type = dtype }, frame_count);
            }
        }
    }

    pub fn pickClosestMonster(self: World, world_x: i32, world_y: i32, range_min: f32, range_max: f32) ?MonsterId {
        if (self.monsters.slice().len == 0) {
            return null;
        }
        var closest: ?MonsterId = null;
        var best_dist = std.math.inf_f32;
        const fx = @intToFloat(f32, world_x);
        const fy = @intToFloat(f32, world_y);
        for (self.monsters.slice()) |m| {
            if (m.dead) {
                continue;
            }
            const p = m.getWorldCollisionRect().centerPoint();
            const mx = @intToFloat(f32, p[0]);
            const my = @intToFloat(f32, p[1]);
            const dist = mu.dist([2]f32{ fx, fy }, [2]f32{ mx, my });
            if (dist >= range_min and dist <= range_max and dist < best_dist) {
                closest = m.id;
                best_dist = dist;
            }
        }
        return closest;
    }

    fn invalidatePathCache(self: *World) void {
        var timer = std.time.Timer.start() catch unreachable;
        self.path_cache.clear();
        for (self.monsters.slice()) |*m| {
            m.computePath();
        }
        std.log.info("invalidatePathCache took {d}ms", .{timer.read() / std.time.ns_per_ms});
    }

    fn spawnTowerWorld(self: *World, spec: *const TowerSpec, world_x: u32, world_y: u32) !TowerId {
        var id = try self.towers.put(self.allocator, Tower{
            .world = self,
            .spec = spec,
            .world_x = world_x,
            .world_y = world_y,
        });
        self.towers.getPtr(id).spawn(self.world_frame);
        return id;
    }

    const FieldOptions = struct {
        position: [2]f32,
        radius: f32,
        duration_sec: f32,
        tick_rate_sec: f32,
        particle_kind: particle.ParticleKind,
        tickFn: *const fn (*Field) void,
    };

    pub fn spawnField(self: *World, opts: FieldOptions) !FieldId {
        return try self.fields.put(self.allocator, Field{
            .world = self,
            .world_x = opts.position[0],
            .world_y = opts.position[1],
            .radius = opts.radius,
            .life_timer = FrameTimer.initSeconds(self.world_frame, opts.duration_sec),
            .tick_timer = FrameTimer.initSeconds(self.world_frame, opts.tick_rate_sec),
            .tickFn = opts.tickFn,
            .kind = opts.particle_kind,
            .emitter = .{ .parent = &self.particle_sys, .pos = opts.position, .radius = opts.radius },
        });
    }

    pub fn spawnMonster(self: *World, spec: *const MonsterSpec, spawn_id: u32) !MonsterId {
        var spawn = self.spawns.getPtr(spawn_id);
        spawn.emitWarpParticles(self.world_frame);

        var mon = Monster{
            .world = self,
            .spec = spec,
            .spawn_id = spawn_id,
        };
        mon.setTilePosition(spawn.coord);
        mon.computePath();

        const id = try self.monsters.put(self.allocator, mon);
        self.monsters.getPtr(id).spawn(self.world_frame);

        const sound_pos = mon.getWorldCollisionRect().centerPoint();
        self.playPositionalSound("assets/sounds/spawn.ogg", sound_pos[0], sound_pos[1]);
        return id;
    }

    pub fn getTowerAt(self: *World, coord: TileCoord) ?TowerId {
        if (self.tower_map.get(coord)) |id| {
            return id;
        } else {
            return null;
        }
    }

    pub fn getSpawnPosition(self: *World, spawn_id: u32) TileCoord {
        return self.getSpawnPtr(spawn_id).coord;
    }

    pub fn getSpawnPtr(self: *World, spawn_id: u32) *Spawn {
        return self.spawns.getPtr(spawn_id);
    }

    pub fn getSpawnId(self: *World, name: []const u8) ?u32 {
        return self.spawn_map.get(name);
    }

    pub fn startWave(self: *World, wave_num: usize) void {
        self.waves.startWave(wave_num, self.world_frame);
        self.active_waves.append(self.allocator, wave_num) catch unreachable;
    }

    /// Returns true if next wave could be started, false means all waves are finished.
    pub fn startNextWave(self: *World) bool {
        if (self.remainingWaveCount() > 0) {
            self.startWave(self.next_wave);
            self.next_wave += 1;
            if (self.remainingWaveCount() > 0) {
                self.next_wave_timer = FrameTimer.initSeconds(self.world_frame, self.waves.getWaveDuration(self.next_wave));
            } else {
                self.next_wave_timer = null;
            }
            return true;
        } else {
            return false;
        }
    }

    pub fn remainingWaveCount(self: *World) usize {
        return self.waves.waves.len - self.next_wave;
    }

    pub fn update(self: *World, frame_arena: Allocator) void {
        var new_projectile_ids = std.ArrayListUnmanaged(u32){};
        var proj_pending_removal = std.ArrayListUnmanaged(u32){};
        var mon_pending_removal = std.ArrayListUnmanaged(MonsterId){};
        var effect_pending_removal = std.ArrayListUnmanaged(SpriteEffectId){};
        var text_pending_removal = std.ArrayListUnmanaged(u32){};
        var active_waves_pending_removal = std.ArrayListUnmanaged(usize){};
        var fields_pending_removal = std.ArrayListUnmanaged(FieldId){};

        if (self.goal) |*goal| {
            goal.update(self.world_frame);
        }

        for (self.active_waves.items) |wave_id, active_wave_index| {
            if (!self.waves.waves[wave_id].anyRemainingEvents()) {
                active_waves_pending_removal.append(frame_arena, active_wave_index) catch unreachable;
            }

            for (self.spawns.slice()) |*sp| {
                if (self.waves.waves[wave_id].getReadyEvent(sp.id, self.world_frame)) |e| {
                    switch (e) {
                        .spawn => |spawn_event| {
                            _ = self.spawnMonster(spawn_event.monster_spec, sp.id) catch unreachable;
                        },
                        .wait => {},
                    }
                }
            }
        }

        for (self.monsters.slice()) |*m| {
            m.update(self.world_frame);
            if (m.dead) {
                self.monsters.erase(m.id);
            }
        }

        // we process delayed damage here so that it applies flash frames, but
        // before processing towers because if a monster dies to delayed damage,
        // we don't want towers to target it this frame
        var damage_id: usize = self.delayed_damage.items.len -% 1;
        while (damage_id < self.delayed_damage.items.len) : (damage_id -%= 1) {
            const dd = self.delayed_damage.items[damage_id];
            if (dd.timer.expired(self.world_frame)) {
                if (self.monsters.getPtrWeak(dd.monster)) |m| {
                    m.hurt(dd.hurt_options);
                    if (m.dead) {
                        self.monsters.erase(m.id);
                    }
                }
                _ = self.delayed_damage.swapRemove(damage_id);
            }
        }

        for (self.fields.slice()) |*f| {
            f.update();
            if (f.dead) {
                fields_pending_removal.append(frame_arena, f.id) catch unreachable;
            }
        }

        for (self.towers.slice()) |*t| {
            t.update(self.world_frame);
        }
        for (self.sprite_effects.slice()) |*e| {
            e.update(self.world_frame);
            if (e.dead) {
                effect_pending_removal.append(frame_arena, e.id) catch unreachable;
            }
        }
        for (self.floating_text.slice()) |*t| {
            t.update();
            if (t.dead) {
                text_pending_removal.append(frame_arena, t.id) catch unreachable;
            }
        }

        // We have to be very careful here, spawning new projectiles can invalidate pointers into self.projectiles.
        // This can happen if a projectile spawns a projectile. Since this seems like a cool feature, we will support
        // it. Projectiles cannot get spawned projectile handles, but if it turns out to be a feature we need, slotmap
        // API is designed to support this use case with a couple changes.
        for (self.projectiles.slice()) |*p| {
            p.update(self.world_frame);
            if (p.dead) {
                proj_pending_removal.append(frame_arena, p.id) catch unreachable;
                continue;
            }
            for (self.monsters.slice()) |*m| {
                if (p.getWorldCollisionRect().intersect(m.getWorldCollisionRect(), null)) {
                    if (m.dead) {
                        continue;
                    }
                    // take care to not double-delete
                    if (!p.dead) {
                        p.hit(m);
                        if (m.dead) {
                            mon_pending_removal.append(frame_arena, m.id) catch unreachable;
                        }
                        if (p.dead) {
                            proj_pending_removal.append(frame_arena, p.id) catch unreachable;
                            break;
                        }
                    }
                }
            }
        }

        for (proj_pending_removal.items) |id| {
            self.projectiles.erase(id);
        }

        for (mon_pending_removal.items) |id| {
            self.monsters.erase(id);
        }

        for (effect_pending_removal.items) |id| {
            self.sprite_effects.erase(id);
        }

        for (text_pending_removal.items) |id| {
            self.floating_text.erase(id);
        }

        for (fields_pending_removal.items) |id| {
            self.fields.erase(id);
        }

        new_projectile_ids.ensureTotalCapacity(frame_arena, self.pending_projectiles.items.len) catch unreachable;
        for (self.pending_projectiles.items) |proj| {
            const id = self.projectiles.put(self.allocator, proj) catch unreachable;
            new_projectile_ids.append(frame_arena, id) catch unreachable;
        }
        for (new_projectile_ids.items) |id| {
            self.projectiles.getPtr(id).spawn(self.world_frame);
        }
        self.pending_projectiles.clearRetainingCapacity();

        // tricky: we can iterate active_waves_pending_removal in reverse and swap-remove from active_waves
        // because it is sorted by index ascending. Removing higher indices does not invalidate lower ones.
        var wave_remove_index: usize = active_waves_pending_removal.items.len -% 1;
        while (wave_remove_index < active_waves_pending_removal.items.len) : (wave_remove_index -%= 1) {
            _ = self.active_waves.swapRemove(active_waves_pending_removal.items[wave_remove_index]);
        }

        if (self.active_waves.items.len == 0) {
            if (self.next_wave_timer) |timer| {
                if (timer.expired(self.world_frame)) {
                    _ = self.startNextWave();
                }
            } else {
                // wait for all monsters to be finished
                if (self.monsters.slice().len == 0) {
                    self.player_won = true;
                }
            }
        }

        self.particle_sys.update(self.world_frame);

        self.world_frame += 1;
    }

    pub fn tryMove(self: *World, mobid: u32, dir: Direction) bool {
        var m = self.monsters.getPtr(mobid);

        m.setFacing(dir);

        // cannot interrupt an object that is already moving
        if (self.move_frames > 0) {
            return false;
        }

        if (!self.map.isValidMove(m.getTilePosition(), dir)) {
            return false;
        }

        m.beginMove(dir);

        return true;
    }

    pub fn findPath(self: *World, start: TileCoord, end: TileCoord) ?[]TileCoord {
        const pc = PathingCoords.init(start, end);
        if (self.path_cache.get(pc)) |existing_path| {
            return existing_path;
        }
        const has_path = self.pathfinder.findPath(pc, &self.map, &self.path_cache) catch |err| {
            std.log.err("findPath failed: {!}", .{err});
            std.process.exit(1);
        };

        if (has_path) {
            return self.path_cache.get(pc).?;
        } else {
            return null;
        }
    }

    pub fn findTheoreticalPath(self: *World, start: TileCoord, end: TileCoord) bool {
        const pc = PathingCoords.init(start, end);
        if (self.scratch_cache.hasPathFrom(pc)) {
            return true;
        }
        if (self.fast_tpathing) {
            return self.pathfinder.findAnyPathFast(pc, &self.scratch_map, &self.scratch_cache) catch |err| {
                std.log.err("findTheoreticalPath failed: {!}", .{err});
                std.process.exit(1);
            };
        } else {
            return self.pathfinder.findPath(pc, &self.scratch_map, &self.scratch_cache) catch |err| {
                std.log.err("findTheoreticalPath failed: {!}", .{err});
                std.process.exit(1);
            };
        }
    }

    fn playPositionalSound(self: World, sound: [:0]const u8, world_x: i32, world_y: i32) void {
        const sound_position = [2]i32{ world_x, world_y };
        var params = audio.AudioSystem.instance.playSound(sound, audio.computePositionalOptions(self.view, sound_position));
        defer params.release();
    }

    fn playPositionalSoundId(self: World, sound: SoundId, world_x: i32, world_y: i32) void {
        switch (sound) {
            .none => {},
            .stab => self.playPositionalSound("assets/sounds/stab.ogg", world_x, world_y),
            .flame => self.playPositionalSound("assets/sounds/flame.ogg", world_x, world_y),
            .frost => self.playPositionalSound("assets/sounds/frost.ogg", world_x, world_y),
            .warp => self.playPositionalSound("assets/sounds/warp.ogg", world_x, world_y),
            .shotgun => self.playPositionalSound("assets/sounds/shotgun.ogg", world_x, world_y),
            .bow => self.playPositionalSound("assets/sounds/bow.ogg", world_x, world_y),
        }
    }
};

const PathingCoords = struct {
    start: TileCoord,
    end: TileCoord,

    fn init(start: TileCoord, end: TileCoord) PathingCoords {
        return .{
            .start = start,
            .end = end,
        };
    }
};

const PathfindingCache = struct {
    arena: std.heap.ArenaAllocator,
    entries: std.AutoArrayHashMapUnmanaged(PathingCoords, []TileCoord) = .{},

    fn init(allocator: Allocator) PathfindingCache {
        _ = allocator;
        var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
        return .{
            .arena = arena,
        };
    }

    fn deinit(self: *PathfindingCache) void {
        self.arena.deinit();
    }

    fn reserve(self: *PathfindingCache, coord_count: usize) !void {
        var allocator = self.arena.allocator();
        try self.entries.ensureTotalCapacity(allocator, coord_count);
    }

    fn clear(self: *PathfindingCache) void {
        const my_cap = self.entries.capacity();
        self.arena.deinit();
        self.arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
        var allocator = self.arena.allocator();
        self.entries = .{};
        self.entries.ensureTotalCapacity(allocator, my_cap) catch unreachable;
    }

    fn setExpandPath(self: *PathfindingCache, coords: PathingCoords, path: []TileCoord) void {
        if (path.len == 0) {
            self.entries.putAssumeCapacity(coords, &[_]TileCoord{});
            return;
        }

        var my_path = self.copyPath(path) catch unreachable;
        for (my_path) |start, i| {
            const key = PathingCoords{
                .start = start,
                .end = coords.end,
            };
            var gop = self.entries.getOrPutAssumeCapacity(key);
            if (!gop.found_existing) {
                gop.value_ptr.* = my_path[i..];
            }
        }
    }

    fn get(self: *PathfindingCache, coords: PathingCoords) ?[]TileCoord {
        return self.entries.get(coords);
    }

    fn hasPathFrom(self: *PathfindingCache, coords: PathingCoords) bool {
        return self.entries.contains(coords);
    }

    fn copyPath(self: *PathfindingCache, path: []TileCoord) ![]TileCoord {
        var allocator = self.arena.allocator();
        return try allocator.dupe(TileCoord, path);
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

    fn findPath(self: *PathfindingState, coords: PathingCoords, map: *const Tilemap, cache: ?*PathfindingCache) !bool {
        const width = map.width;

        // sus, upstream interface needs some love
        self.frontier.len = 0;
        self.frontier.context = Context{
            .map = map,
            .score_map = self.score_map,
        };

        self.frontier_set.clearRetainingCapacity();

        // Micro optimization: we search from end to start rather than start to end
        // so we don't have to reverse the coord list at the end.
        try self.frontier.add(coords.end);
        try self.frontier_set.put(self.allocator, coords.end, {});
        std.mem.set(Score, self.score_map, Score.infinity);

        self.score_map[coords.end.toScalarCoord(map.width)] = .{
            .fscore = 0,
            .gscore = 0,
            .from = undefined,
        };

        while (self.frontier.removeOrNull()) |current| {
            if (std.meta.eql(current, coords.start)) {
                if (cache) |c| {
                    self.result.clearRetainingCapacity();
                    var coord = coords.start;
                    while (!std.meta.eql(coord, coords.end)) {
                        try self.result.append(self.allocator, coord);
                        coord = self.score_map[coord.toScalarCoord(width)].from;
                    }
                    try self.result.append(self.allocator, coord);
                    c.setExpandPath(coords, self.result.items);
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
                            .fscore = tentative_score + self.heuristic(neighbor, coords.start),
                        };
                        if (!self.frontier_set.contains(neighbor)) {
                            try self.frontier_set.put(self.allocator, neighbor, {});
                            try self.frontier.add(neighbor);
                        }
                    }
                }
            }
        }

        std.log.debug("no path: {any}", .{coords});
        if (cache) |c| {
            c.setExpandPath(coords, &[_]TileCoord{});
        }

        return false;
    }

    fn findAnyPathFast(self: *PathfindingState, coords: PathingCoords, map: *const Tilemap, cache: ?*PathfindingCache) !bool {
        const width = map.width;

        // sus, upstream interface needs some love
        self.frontier.len = 0;
        self.frontier.context = Context{
            .map = map,
            .score_map = self.score_map,
        };

        self.frontier_set.clearRetainingCapacity();

        try self.frontier.add(coords.start);
        try self.frontier_set.put(self.allocator, coords.start, {});
        std.mem.set(Score, self.score_map, Score.infinity);

        self.score_map[coords.start.toScalarCoord(map.width)] = .{
            .fscore = 0,
            .gscore = 0,
            .from = undefined,
        };

        while (self.frontier.removeOrNull()) |current| {
            if (cache) |c| {
                const fast_path = PathingCoords{ .start = current, .end = coords.end };
                if (c.get(fast_path)) |following_path| {
                    self.result.clearRetainingCapacity();
                    var coord = current;
                    while (!std.meta.eql(coord, coords.start)) {
                        try self.result.append(self.allocator, coord);
                        coord = self.score_map[coord.toScalarCoord(width)].from;
                    }
                    try self.result.append(self.allocator, coord);
                    std.mem.reverse(TileCoord, self.result.items);
                    try self.result.appendSlice(self.allocator, following_path[1..]);
                    c.setExpandPath(coords, self.result.items);
                    return true;
                }

                if (std.meta.eql(current, coords.end)) {
                    self.result.clearRetainingCapacity();
                    var coord = coords.end;
                    while (!std.meta.eql(coord, coords.start)) {
                        try self.result.append(self.allocator, coord);
                        coord = self.score_map[coord.toScalarCoord(width)].from;
                    }
                    try self.result.append(self.allocator, coord);
                    std.mem.reverse(TileCoord, self.result.items);
                    c.setExpandPath(coords, self.result.items);
                    return true;
                }
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
                            .fscore = tentative_score + self.heuristic(neighbor, coords.end),
                        };
                        if (!self.frontier_set.contains(neighbor)) {
                            try self.frontier_set.put(self.allocator, neighbor, {});
                            try self.frontier.add(neighbor);
                        }
                    }
                }
            }
        }

        std.log.debug("no path: {any}", .{coords});
        if (cache) |c| {
            c.setExpandPath(coords, &[_]TileCoord{});
        }

        return false;
    }

    fn heuristic(self: *PathfindingState, from: TileCoord, to: TileCoord) f32 {
        _ = self;
        return from.euclideanDistance(to);
    }
};

const JsonWaveDoc = struct {
    waves: []JsonWave,
};
const JsonWave = struct {
    spawn_points: []JsonSpawnPoint,
};
const JsonSpawnPoint = struct {
    spawn_point: []const u8,
    events: []JsonSpawnPointEvent,
};
const JsonSpawnPointEventType = enum {
    spawn,
    wait,
};
const JsonSpawnPointEvent = union(JsonSpawnPointEventType) {
    spawn: JsonSpawnPointSpawnEvent,
    wait: JsonSpawnPointWaitEvent,
};
const JsonSpawnPointSpawnEvent = struct {
    type: []const u8,
    time: u32,
    name: []const u8,
    repeat: ?u32 = 1,
};
const JsonSpawnPointWaitEvent = struct {
    type: []const u8,
    time: u32,
};

pub fn loadWavesFromJson(allocator: Allocator, filename: []const u8, world: *World) !WaveList {
    var arena = std.heap.ArenaAllocator.init(allocator);
    var arena_allocator = arena.allocator();
    defer arena.deinit();

    var file = try std.fs.cwd().openFile(filename, .{});
    defer file.close();

    const buffer = try file.readToEndAlloc(arena_allocator, 1024 * 1024);

    var tokens = std.json.TokenStream.init(buffer);
    var doc = try std.json.parse(JsonWaveDoc, &tokens, .{ .allocator = arena_allocator, .ignore_unknown_fields = true });

    var waves = try allocator.alloc(Wave, doc.waves.len);
    errdefer allocator.free(waves);

    for (doc.waves) |doc_wave, wave_index| {
        waves[wave_index] = Wave{
            .spawn_events = std.AutoArrayHashMapUnmanaged(u32, WaveEventList){},
        };

        for (doc_wave.spawn_points) |doc_sp| {
            const world_spawn_id = world.getSpawnId(doc_sp.spawn_point) orelse return error.InvalidSpawnPoint;
            var event_list = try allocator.alloc(WaveEvent, doc_sp.events.len);
            for (doc_sp.events) |doc_event, event_index| {
                switch (doc_event) {
                    .spawn => |spawn| {
                        event_list[event_index] = .{ .spawn = EventSpawn{
                            .monster_spec = nameToMonsterSpec(spawn.name) orelse return error.InvalidMonsterName,
                            .time = spawn.time,
                            .repeat = spawn.repeat.?,
                        } };
                    },
                    .wait => |wait| {
                        event_list[event_index] = .{ .wait = EventWait{
                            .time = wait.time,
                        } };
                    },
                }
            }

            try waves[wave_index].spawn_events.put(allocator, world_spawn_id, WaveEventList{
                .current_event = 0,
                .events = event_list,
                .next_event_timer = .{},
            });
        }
    }

    return WaveList{
        .waves = waves,
    };
}

pub fn loadWorldFromJson(allocator: Allocator, filename: []const u8) !*World {
    var arena = std.heap.ArenaAllocator.init(allocator);
    var arena_allocator = arena.allocator();
    defer arena.deinit();

    var file = try std.fs.cwd().openFile(filename, .{});
    defer file.close();

    const buffer = try file.readToEndAlloc(arena_allocator, 1024 * 1024);
    var tokens = std.json.TokenStream.init(buffer);
    var doc = try std.json.parse(TiledDoc, &tokens, .{ .allocator = arena_allocator, .ignore_unknown_fields = true });

    var world = try allocator.create(World);
    errdefer allocator.destroy(world);

    world.* = .{
        .allocator = allocator,
        .pathfinder = PathfindingState.init(allocator),
        .path_cache = PathfindingCache.init(allocator),
        .scratch_cache = PathfindingCache.init(allocator),
        .rng = std.rand.DefaultPrng.init(@intCast(u64, std.time.milliTimestamp())),
        // Initialized below (failure to do so is an error)
        .particle_sys = undefined,
        .goal = undefined,
    };

    world.map = try Tilemap.init(allocator, doc.width, doc.height);
    errdefer world.map.deinit(allocator);

    world.scratch_map = try Tilemap.init(allocator, doc.width, doc.height);
    errdefer world.scratch_map.deinit(allocator);

    try world.pathfinder.reserve(world.map.tileCount());
    errdefer world.pathfinder.deinit();

    try world.path_cache.reserve(world.map.tileCount());
    errdefer world.path_cache.deinit();

    try world.scratch_cache.reserve(world.map.tileCount());
    errdefer world.scratch_cache.deinit();

    world.particle_sys = try particle.ParticleSystem.initCapacity(allocator, 1024);
    errdefer world.particle_sys.deinit();

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
            .world = world,
            .classifier = &classifier,
        };
        switch (layer) {
            .tilelayer => |x| try loadTileLayer(x, ctx),
            .objectgroup => |x| try loadObjectGroup(x, ctx),
        }
    }

    const map_dirname = std.fs.path.dirname(filename) orelse "";

    if (doc.getProperty("wave_file")) |wave_file| {
        if (!wave_file.isFile()) {
            std.log.err("wave_file must have type `file`", .{});
            std.process.exit(1);
        }
        const wave_filename = try std.fs.path.resolve(arena_allocator, &[_][]const u8{ map_dirname, wave_file.toString() });
        std.log.debug("Load wave_file from `{s}`", .{wave_filename});
        world.waves = try loadWavesFromJson(allocator, wave_filename, world);
    }

    if (doc.getProperty("music")) |music| {
        if (!music.isFile()) {
            std.log.err("music must have type `file`", .{});
            std.process.exit(1);
        }
        const music_filename = try std.fs.path.resolve(arena_allocator, &[_][]const u8{ map_dirname, music.toString() });
        std.log.debug("music_filename is `{s}`", .{music_filename});
        world.music_filename = try allocator.dupeZ(u8, music_filename);
    }

    if (doc.getProperty("starting_gold")) |g| {
        if (!g.isInt()) {
            std.log.err("starting_gold must have type `int`", .{});
            std.process.exit(1);
        }
        world.player_gold = @intCast(u32, g.toInt());
    }

    world.finalizeInit();
    return world;
}

pub fn loadWorldRawJson(allocator: Allocator, filename: []const u8) !TiledDoc {
    var arena = std.heap.ArenaAllocator.init(allocator);
    var arena_allocator = arena.allocator();
    defer arena.deinit();

    var file = try std.fs.cwd().openFile(filename, .{});
    defer file.close();

    const buffer = try file.readToEndAlloc(arena_allocator, 1024 * 1024);

    var tokens = std.json.TokenStream.init(buffer);
    var doc = try std.json.parse(TiledDoc, &tokens, .{ .allocator = allocator, .ignore_unknown_fields = true });

    return doc;
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
            try ctx.world.createSpawn(obj.name, TileCoord.initSignedWorld(obj.x, obj.y));
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
        } else if (std.mem.eql(u8, obj.class, "play_area")) {
            ctx.world.play_area = Rect.init(obj.x, obj.y, obj.width, obj.height);
        } else if (std.mem.eql(u8, obj.class, "custom_rect")) {
            try ctx.world.addCustomRect(obj.name, Rect.init(obj.x, obj.y, obj.width, obj.height));
        } else if (std.mem.eql(u8, obj.class, "pathable")) {
            const tile_start = TileCoord.initSignedWorld(obj.x, obj.y);
            const tile_end = TileCoord.initSignedWorld(obj.x + obj.width, obj.y + obj.height);
            var ty: usize = tile_start.y;
            while (ty < tile_end.y) : (ty += 1) {
                var tx: usize = tile_start.x;
                while (tx < tile_end.x) : (tx += 1) {
                    ctx.world.map.at2DPtr(.base, tx, ty).flags.pathable_override = true;
                    ctx.world.map.at2DPtr(.detail, tx, ty).flags.pathable_override = true;
                }
            }
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
    properties: ?[]TiledMapProperty = null,

    pub fn getProperty(self: TiledDoc, name: []const u8) ?TiledMapProperty {
        if (self.properties) |props| {
            for (props) |prop| {
                if (std.mem.eql(u8, prop.name, name)) {
                    return prop;
                }
            }
        }
        return null;
    }
};

const TiledMapPropertyType = enum {
    file,
    string,
    int,
};

const TiledMapPropertyValue = union(enum) {
    string: []const u8,
    integer: i64,
};

const TiledMapProperty = struct {
    name: []const u8,
    type: TiledMapPropertyType,
    value: TiledMapPropertyValue,

    pub fn isInt(self: TiledMapProperty) bool {
        return self.type == .int;
    }

    pub fn isString(self: TiledMapProperty) bool {
        return self.type == .string;
    }

    pub fn isFile(self: TiledMapProperty) bool {
        return self.type == .file;
    }

    pub fn toString(self: TiledMapProperty) []const u8 {
        return self.value.string;
    }
    pub fn toInt(self: TiledMapProperty) i64 {
        return self.value.integer;
    }
};

fn nameToMonsterSpec(name: []const u8) ?*const MonsterSpec {
    if (std.mem.eql(u8, "m_human", name)) {
        return &m_human;
    }
    if (std.mem.eql(u8, "m_slime", name)) {
        return &m_slime;
    }
    if (std.mem.eql(u8, "m_blue_slime", name)) {
        return &m_blue_slime;
    }
    if (std.mem.eql(u8, "m_red_slime", name)) {
        return &m_red_slime;
    }
    if (std.mem.eql(u8, "m_black_slime", name)) {
        return &m_black_slime;
    }
    if (std.mem.eql(u8, "m_skeleton", name)) {
        return &m_skeleton;
    }
    if (std.mem.eql(u8, "m_dark_skeleton", name)) {
        return &m_dark_skeleton;
    }
    if (std.mem.eql(u8, "m_mole", name)) {
        return &m_mole;
    }
    return null;
}

/// `assets/maps/mapXX.tmj` - buffer should be at least 21 chars
pub fn bufPrintWorldFilename(buf: []u8, mapid: u32) ![]u8 {
    std.debug.assert(buf.len >= 21);
    std.debug.assert(mapid < 99);
    return std.fmt.bufPrint(buf, "assets/maps/map{d:0>2}.tmj", .{mapid + 1});
}
