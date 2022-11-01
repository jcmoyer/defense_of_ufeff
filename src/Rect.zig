const Rect = @This();

const std = @import("std");
const Rectf = @import("Rectf.zig");

x: i32 = 0,
y: i32 = 0,
w: i32 = 0,
h: i32 = 0,

pub fn init(x: i32, y: i32, w: i32, h: i32) Rect {
    return Rect{
        .x = x,
        .y = y,
        .w = w,
        .h = h,
    };
}

pub fn right(self: Rect) i32 {
    return self.x + self.w;
}

pub fn bottom(self: Rect) i32 {
    return self.y + self.h;
}

pub fn left(self: Rect) i32 {
    return self.x;
}

pub fn top(self: Rect) i32 {
    return self.y;
}

pub fn translate(self: *Rect, dx: i32, dy: i32) void {
    self.x += dx;
    self.y += dy;
}

pub fn alignLeft(self: *Rect, x: i32) void {
    self.x = x;
}

pub fn alignRight(self: *Rect, x: i32) void {
    self.x = x - self.w;
}

pub fn alignTop(self: *Rect, y: i32) void {
    self.y = y;
}

pub fn alignBottom(self: *Rect, y: i32) void {
    self.y = y - self.h;
}

pub fn centerOn(self: *Rect, x: c_int, y: c_int) void {
    self.x = x - @divFloor(self.w, 2);
    self.y = y - @divFloor(self.h, 2);
}

pub fn centerPoint(self: Rect) [2]i32 {
    return .{
        @divFloor(self.right() - self.left(), 2),
        @divFloor(self.bottom() - self.top(), 2),
    };
}

pub fn inflate(self: *Rect, dx: c_int, dy: c_int) void {
    self.x -= dx;
    self.y -= dy;
    self.w += 2 * dx;
    self.h += 2 * dy;
}

pub fn intersect(self: Rect, other: Rect, subrect: ?*Rect) bool {
    const xmin = std.math.max(self.x, other.x);
    const ymin = std.math.max(self.y, other.y);
    const xmax = std.math.min(self.right(), other.right());
    const ymax = std.math.min(self.bottom(), other.bottom());
    if (xmax < xmin or ymax < ymin) {
        return false;
    } else {
        if (subrect) |ptr| {
            ptr.* = Rect.init(xmin, ymin, xmax - xmin, ymax - ymin);
        }
        return true;
    }
}

pub fn toRectf(self: Rect) Rectf {
    return Rectf.init(
        @intToFloat(f32, self.x),
        @intToFloat(f32, self.y),
        @intToFloat(f32, self.w),
        @intToFloat(f32, self.h),
    );
}
