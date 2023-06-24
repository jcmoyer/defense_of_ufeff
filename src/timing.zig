const std = @import("std");
const Allocator = std.mem.Allocator;

pub const FrameTimer = struct {
    frame_start: u64 = std.math.maxInt(u64),
    frame_end: u64 = std.math.maxInt(u64),

    pub fn initSeconds(current_frame: u64, sec: f32) FrameTimer {
        return FrameTimer{
            .frame_start = current_frame,
            .frame_end = current_frame + @intFromFloat(u64, 30.0 * sec),
        };
    }

    pub fn initFrames(current_frame: u64, frame_count: u64) FrameTimer {
        return FrameTimer{
            .frame_start = current_frame,
            .frame_end = current_frame + frame_count,
        };
    }

    pub fn durationFrames(self: FrameTimer) u64 {
        return self.frame_end - self.frame_start;
    }

    pub fn durationSeconds(self: FrameTimer) f32 {
        return @floatFromInt(f32, self.durationFrames()) / 30.0;
    }

    pub fn remainingSeconds(self: FrameTimer, current_frame: u64) f32 {
        return self.invProgressClamped(current_frame) * self.durationSeconds();
    }

    pub fn remainingSecondsUnbounded(self: FrameTimer, current_frame: u64) f32 {
        return self.invProgress(current_frame) * self.durationSeconds();
    }

    pub fn expired(self: FrameTimer, current_frame: u64) bool {
        return current_frame >= self.frame_end;
    }

    pub fn restart(self: *FrameTimer, current_frame: u64) void {
        const d = self.durationFrames();
        self.frame_start = current_frame;
        self.frame_end = current_frame + d;
    }

    pub fn progress(self: FrameTimer, current_frame: u64) f32 {
        return @floatFromInt(f32, current_frame - self.frame_start) / @floatFromInt(f32, self.durationFrames());
    }

    pub fn progressClamped(self: FrameTimer, current_frame: u64) f32 {
        return std.math.clamp(self.progress(current_frame), 0.0, 1.0);
    }

    pub fn invProgress(self: FrameTimer, current_frame: u64) f32 {
        return 1 - self.progress(current_frame);
    }

    pub fn invProgressClamped(self: FrameTimer, current_frame: u64) f32 {
        return 1 - self.progressClamped(current_frame);
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
