const Camera = @This();
const std = @import("std");
const zm = @import("zmath");
const Rect = @import("Rect.zig");

view: Rect = .{},
bounds: Rect = .{},

pub fn clampToBounds(self: *Camera) void {
    if (self.view.left() < self.bounds.left()) {
        self.view.alignLeft(self.bounds.left());
    }
    if (self.view.top() < self.bounds.top()) {
        self.view.alignTop(self.bounds.top());
    }
    if (self.view.right() > self.bounds.right()) {
        self.view.alignRight(self.bounds.right());
    }
    if (self.view.bottom() > self.bounds.bottom()) {
        self.view.alignBottom(self.bounds.bottom());
    }
}

pub fn lerp(a: Camera, b: Camera, alpha: f64) Camera {
    std.debug.assert(a.view.w == b.view.w);
    std.debug.assert(a.view.h == b.view.h);
    std.debug.assert(std.meta.eql(a.bounds, b.bounds));

    const fx = zm.lerpV(@as(f64, @floatFromInt(a.view.x)), @as(f64, @floatFromInt(b.view.x)), alpha);
    const fy = zm.lerpV(@as(f64, @floatFromInt(a.view.y)), @as(f64, @floatFromInt(b.view.y)), alpha);
    return Camera{
        .view = Rect.init(@intFromFloat(fx), @intFromFloat(fy), a.view.w, a.view.h),
        .bounds = a.bounds,
    };
}
