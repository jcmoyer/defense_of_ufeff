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

pub fn centerOnPoint(self: *Rect, p: [2]i32) void {
    self.centerOn(p[0], p[1]);
}

pub fn centerPoint(self: Rect) [2]i32 {
    return .{
        @divFloor(self.right() + self.left(), 2),
        @divFloor(self.bottom() + self.top(), 2),
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
    // TODO: need to figure out if we want inclusive or exclusive width/height
    // (maybe just provide both?) This routine produces undesirable results in
    // some circumstances without the subtraction by one. For example, on a grid
    // where each square is 16x16, the cells at [2,2] (32,32,48,48) and [2,3]
    // (32,48,48,64) would "intersect" because the bottom edge of [2,2] touches
    // the top edge of [2,3]. But such an intersection would produce a
    // zero-height rectangle which seems wrong. So we fudge the numbers such
    // that the above example becomes (32,32,47,47) and (32,48,47,63).
    const xmax = std.math.min(self.right() - 1, other.right() - 1);
    const ymax = std.math.min(self.bottom() - 1, other.bottom() - 1);
    if (xmax < xmin or ymax < ymin) {
        return false;
    } else {
        if (subrect) |ptr| {
            ptr.* = Rect.init(xmin, ymin, xmax - xmin, ymax - ymin);
        }
        return true;
    }
}

pub fn contains(self: Rect, x: i32, y: i32) bool {
    return x >= self.left() and x < self.right() and y >= self.top() and y < self.bottom();
}

pub fn containsRect(self: Rect, r: Rect) bool {
    return r.left() >= self.left() and r.right() < self.right() and r.top() >= self.top() and r.bottom() < self.bottom();
}

pub fn clampPoint(self: Rect, x: i32, y: i32) [2]i32 {
    return [2]i32{
        std.math.clamp(x, self.left(), self.right()),
        std.math.clamp(y, self.top(), self.bottom()),
    };
}

pub fn toRectf(self: Rect) Rectf {
    return Rectf.init(
        @intToFloat(f32, self.x),
        @intToFloat(f32, self.y),
        @intToFloat(f32, self.w),
        @intToFloat(f32, self.h),
    );
}
