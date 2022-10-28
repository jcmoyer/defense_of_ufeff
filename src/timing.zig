const std = @import("std");
const Allocator = std.mem.Allocator;

pub const FrameTimer = struct {
    frame_start: u64,
    frame_end: u64,

    pub fn initSeconds(current_frame: u64, sec: f32) FrameTimer {
        return FrameTimer{
            .frame_start = current_frame,
            .frame_end = current_frame + @floatToInt(u64, 30.0 * sec),
        };
    }

    pub fn expired(self: FrameTimer, current_frame: u64) bool {
        return current_frame >= self.frame_end;
    }

    pub fn restart(self: *FrameTimer, current_frame: u64) void {
        const d = self.frame_end - self.frame_start;
        self.frame_start = current_frame;
        self.frame_end = current_frame + d;
    }
};

const TimerPool = struct {
    allocator: Allocator,
    timers: std.ArrayListUnmanaged(FrameTimer) = .{},

    pub fn init(allocator: Allocator) TimerPool {
        return .{
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *TimerPool) void {
        self.allocator.free(self.timers);
    }
};
