const Rectf = @This();

const std = @import("std");
const Rect = @import("Rect.zig");

x: f32 = 0,
y: f32 = 0,
w: f32 = 0,
h: f32 = 0,

pub fn init(x: f32, y: f32, w: f32, h: f32) Rectf {
    return Rectf{
        .x = x,
        .y = y,
        .w = w,
        .h = h,
    };
}

pub fn right(self: Rectf) f32 {
    return self.x + self.w;
}

pub fn bottom(self: Rectf) f32 {
    return self.y + self.h;
}

pub fn left(self: Rectf) f32 {
    return self.x;
}

pub fn top(self: Rectf) f32 {
    return self.y;
}

pub fn translate(self: *Rectf, dx: f32, dy: f32) void {
    self.x += dx;
    self.y += dy;
}

pub fn alignLeft(self: *Rectf, x: f32) void {
    self.x = x;
}

pub fn alignRight(self: *Rectf, x: f32) void {
    self.x = x - self.w;
}

pub fn alignTop(self: *Rectf, y: f32) void {
    self.y = y;
}

pub fn alignBottom(self: *Rectf, y: f32) void {
    self.y = y - self.h;
}

pub fn centerOn(self: *Rectf, x: f32, y: f32) void {
    self.x = x - @divFloor(self.w, 2);
    self.y = y - @divFloor(self.h, 2);
}

pub fn centerPoint(self: Rectf) [2]f32 {
    return .{
        (self.right() - self.left()) / 2,
        (self.bottom() - self.top()) / 2,
    };
}

pub fn inflate(self: *Rectf, dx: f32, dy: f32) void {
    self.x -= dx;
    self.y -= dy;
    self.w += 2 * dx;
    self.h += 2 * dy;
}

pub fn intersect(self: Rectf, other: Rectf, subRectf: ?*Rectf) bool {
    const xmin = std.math.max(self.x, other.x);
    const ymin = std.math.max(self.y, other.y);
    const xmax = std.math.min(self.right(), other.right());
    const ymax = std.math.min(self.bottom(), other.bottom());
    if (xmax < xmin or ymax < ymin) {
        return false;
    } else {
        if (subRectf) |ptr| {
            ptr.* = Rectf.init(xmin, ymin, xmax - xmin, ymax - ymin);
        }
        return true;
    }
}

pub fn toRect(self: Rectf) Rect {
    return Rect.init(
        @floatToInt(i32, self.x),
        @floatToInt(i32, self.y),
        @floatToInt(i32, self.w),
        @floatToInt(i32, self.h),
    );
}
