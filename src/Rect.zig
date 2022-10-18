const Rect = @This();

x: i32,
y: i32,
w: i32,
h: i32,

pub fn right(self: Rect) i32 {
    return self.x + self.w;
}

pub fn bottom(self: Rect) i32 {
    return self.y + self.h;
}
