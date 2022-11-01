const Rect = @import("Rect.zig");
const std = @import("std");
const Allocator = std.mem.Allocator;

pub const Frame = struct {
    rect: Rect,
    time: u32,
};

pub const Animation = struct {
    frames: []const Frame,
    next: ?[]const u8 = null,
    loop: bool = true,
};

pub const AnimationSetVtbl = struct {
    getAnimationFn: *const fn (self: *const anyopaque, name: []const u8) ?Animation,
    hasAnimationFn: *const fn (self: *const anyopaque, name: []const u8) bool,
};

pub const AnimationSet = struct {
    ptr: *const anyopaque,
    vtbl: AnimationSetVtbl,

    pub fn getAnimation(self: AnimationSet, name: []const u8) ?Animation {
        return self.vtbl.getAnimationFn(self.ptr, name);
    }

    pub fn hasAnimation(self: AnimationSet, name: []const u8) bool {
        return self.vtbl.hasAnimationFn(self.ptr, name);
    }

    pub fn createAnimator(self: AnimationSet, name: []const u8) Animator {
        return Animator{
            .anim_set = self,
            .current_anim = name,
        };
    }
};

pub const MappedAnimationSet = struct {
    allocator: Allocator,
    anims: std.StringArrayHashMapUnmanaged(Animation) = .{},

    fn deinit(self: *AnimationSet) void {
        self.anims.deinit(self.allocator);
    }

    pub fn getAnimation(self: AnimationSet, name: []const u8) ?Animation {
        return self.anims.get(name);
    }

    pub fn addAnimation(self: *AnimationSet, name: []const u8, anim: Animation) !void {
        var gop = try self.anims.getOrPut(self.allocator, name);
        if (gop.found_existing) {
            return error.AlreadyExists;
        } else {
            gop.value_ptr = anim;
        }
    }

    pub fn hasAnimation(self: AnimationSet, name: []const u8) bool {
        return self.anims.contains(name);
    }

    pub fn createAnimator(self: *const AnimationSet, name: []const u8) Animator {
        return Animator{
            .aset = self,
            .aset_vtbl = .{
                .getAnimationFn = vGetAnimation,
                .hasAnimationFn = vHasAnimation,
            },
            .current_anim = name,
        };
    }

    fn vGetAnimation(ptr: *const anyopaque, name: []const u8) ?Animation {
        const this = @ptrCast(*const AnimationSet, @alignCast(@alignOf(*AnimationSet), ptr));
        return getAnimation(this.*, name);
    }
    fn vHasAnimation(ptr: *const anyopaque, name: []const u8) bool {
        const this = @ptrCast(*const AnimationSet, @alignCast(@alignOf(*AnimationSet), ptr));
        return hasAnimation(this.*, name);
    }
};

pub const StaticAnimationDef = struct {
    name: []const u8,
    animation: Animation,
};

pub fn StaticAnimationSet(comptime defs: []const StaticAnimationDef) type {
    return struct {
        const Self = @This();

        pub fn animationSet(self: *const Self) AnimationSet {
            return .{
                .ptr = self,
                .vtbl = .{
                    .getAnimationFn = vGetAnimation,
                    .hasAnimationFn = vHasAnimation,
                },
            };
        }

        pub fn getAnimation(self: Self, name: []const u8) ?Animation {
            _ = self;
            inline for (defs) |a| {
                if (std.mem.eql(u8, name, a.name)) {
                    return a.animation;
                }
            }
            return null;
        }

        pub fn hasAnimation(self: Self, name: []const u8) bool {
            _ = self;
            inline for (defs) |a| {
                if (std.mem.eql(u8, name, a.name)) {
                    return true;
                }
            }
            return false;
        }

        fn vGetAnimation(ptr: *const anyopaque, name: []const u8) ?Animation {
            const this = @ptrCast(*const Self, ptr);
            return getAnimation(this.*, name);
        }
        fn vHasAnimation(ptr: *const anyopaque, name: []const u8) bool {
            const this = @ptrCast(*const Self, ptr);
            return hasAnimation(this.*, name);
        }
    };
}

pub const Animator = struct {
    anim_set: AnimationSet,
    current_anim: []const u8,
    frame_index: usize = 0,
    counter: u32 = 0,
    done: bool = false,

    pub fn getCurrentAnimation(self: Animator) Animation {
        return self.anim_set.getAnimation(self.current_anim).?;
    }

    pub fn getCurrentFrame(self: Animator) Frame {
        return self.getCurrentAnimation().frames[self.frame_index];
    }

    pub fn getCurrentRect(self: Animator) Rect {
        return self.getCurrentFrame().rect;
    }

    pub fn update(self: *Animator) void {
        self.counter += 1;
        if (self.counter >= self.getCurrentFrame().time) {
            self.counter = 0;
            self.frame_index += 1;

            if (self.frame_index == self.getCurrentAnimation().frames.len) {
                self.frame_index = 0;
                if (self.getCurrentAnimation().next) |next_name| {
                    if (self.anim_set.hasAnimation(next_name)) {
                        self.current_anim = next_name;
                    }
                } else {
                    if (!self.getCurrentAnimation().loop) {
                        self.done = true;
                    }
                }
            }
        }
    }

    pub fn reset(self: *Animator) void {
        self.counter = 0;
        self.frame_index = 0;
    }

    pub fn setAnimation(self: *Animator, name: []const u8) void {
        if (std.mem.eql(u8, self.current_anim, name)) {
            return;
        }

        if (self.anim_set.hasAnimation(name)) {
            self.current_anim = name;
            self.reset();
        }
    }
};

//
// Animation data
//

fn makeFoamAnimation(comptime x0: i32, comptime y0: i32) Animation {
    return Animation{
        .frames = &[_]Frame{
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

pub const a_foam_left = makeFoamAnimation(0, 0);
pub const a_foam_right = makeFoamAnimation(16, 0);
pub const a_foam_top = makeFoamAnimation(32, 0);
pub const a_foam_bottom = makeFoamAnimation(48, 0);
pub const a_foam = StaticAnimationSet(&[_]StaticAnimationDef{
    .{ .name = "l", .animation = a_foam_left },
    .{ .name = "r", .animation = a_foam_right },
    .{ .name = "u", .animation = a_foam_top },
    .{ .name = "d", .animation = a_foam_bottom },
}){};

fn makeStandardCharacterTwoFrame(comptime x0: i32, comptime y0: i32) Animation {
    return Animation{
        .frames = &[_]Frame{
            .{
                .rect = Rect.init(x0, y0, 16, 16),
                .time = 8,
            },
            .{
                .rect = Rect.init(x0, y0 + 16, 16, 16),
                .time = 8,
            },
        },
    };
}

fn makeStandardCharacter(comptime x0: i32, comptime y0: i32) [4]StaticAnimationDef {
    return [4]StaticAnimationDef{
        .{ .name = "down", .animation = makeStandardCharacterTwoFrame(x0, y0) },
        .{ .name = "up", .animation = makeStandardCharacterTwoFrame(x0 + 16, y0) },
        .{ .name = "right", .animation = makeStandardCharacterTwoFrame(x0 + 32, y0) },
        .{ .name = "left", .animation = makeStandardCharacterTwoFrame(x0 + 48, y0) },
    };
}

pub const a_chara = StaticAnimationSet(&makeStandardCharacter(0, 0)){};

pub const a_proj_arrow = StaticAnimationSet(&[1]StaticAnimationDef{.{
    .name = "default",
    .animation = Animation{
        .frames = &[_]Frame{
            .{
                .rect = Rect.init(10 * 16, 0, 16, 16),
                .time = 8,
            },
        },
    },
}}){};

pub const a_proj_bow = StaticAnimationSet(&[1]StaticAnimationDef{.{
    .name = "default",
    .animation = Animation{
        .frames = &[_]Frame{
            .{
                .rect = Rect.init(7 * 16, 8 * 16, 16, 16),
                .time = 8,
            },
        },
    },
}}){};

pub const a_hurt_generic = StaticAnimationSet(&[1]StaticAnimationDef{.{
    .name = "default",
    .animation = Animation{
        .loop = false,
        .frames = &[_]Frame{
            .{
                .rect = Rect.init(16, 128, 16, 16),
                .time = 1,
            },
            .{
                .rect = Rect.init(32, 128, 16, 16),
                .time = 1,
            },
            .{
                .rect = Rect.init(48, 128, 16, 16),
                .time = 1,
            },
        },
    },
}}){};
