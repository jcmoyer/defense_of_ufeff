const Rect = @import("Rect.zig");
const std = @import("std");
const Allocator = std.mem.Allocator;

pub const Frame = struct {
    rect: Rect,
    time: u32,
};

pub const Animation = struct {
    frames: []const Frame,
    next: []const u8,
};

pub const AnimationSet = struct {
    anims: std.StringArrayHashMapUnmanaged(Animation) = .{},

    fn deinit(self: *AnimationSet, allocator: Allocator) void {
        self.anims.deinit(allocator);
    }

    pub fn hasAnimation(self: AnimationSet, name: []const u8) bool {
        return self.anims.contains(name);
    }

    pub fn createAnimator(self: *const AnimationSet) Animator {
        return Animator{
            .aset = self,
            .current_anim = "",
        };
    }
};

pub const Animator = struct {
    aset: *const AnimationSet,
    current_anim: []const u8,
    frame_index: usize = 0,
    counter: u32 = 0,

    pub fn getCurrentAnimation(self: Animator) Animation {
        return self.aset.anims.get(self.current_anim).?;
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
                if (self.aset.anims.contains(self.getCurrentAnimation().next)) {
                    self.current_anim = self.getCurrentAnimation().next;
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

        if (self.aset.hasAnimation(name)) {
            self.current_anim = name;
            self.reset();
        }
    }
};

pub const AnimationManager = struct {
    allocator: Allocator,
    asets: std.ArrayListUnmanaged(*AnimationSet),

    pub fn init(allocator: Allocator) AnimationManager {
        return .{
            .allocator = allocator,
            .asets = .{},
        };
    }

    pub fn deinit(self: *AnimationManager) void {
        for (self.asets.items) |p| {
            p.deinit(self.allocator);
            self.allocator.destroy(p);
        }
        self.asets.deinit(self.allocator);
    }

    pub fn createAnimationSet(self: *AnimationManager) !*AnimationSet {
        var aset = try self.allocator.create(AnimationSet);
        aset.* = .{};
        try self.asets.append(self.allocator, aset);
        return aset;
    }
};
