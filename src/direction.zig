pub const Direction = enum {
    left,
    right,
    up,
    down,

    pub fn invert(self: Direction) Direction {
        return switch (self) {
            .left => .right,
            .right => .left,
            .up => .down,
            .down => .up,
        };
    }
};
