const Rect = @This();

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
    self.x = x - self.w / 2;
    self.y = y - self.h / 2;
}

pub fn inflate(self: *Rect, dx: c_int, dy: c_int) void {
    self.x -= dx;
    self.y -= dy;
    self.w += 2 * dx;
    self.h += 2 * dy;
}
