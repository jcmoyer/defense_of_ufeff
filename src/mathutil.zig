/// Exact euclidean distance between two vector-likes.
pub fn dist(v0: anytype, v1: anytype) f32 {
    comptime if (v0.len != v1.len) {
        @compileError("vectors need to be same length");
    };
    const info = @typeInfo(@TypeOf(v0[0], v1[0]));
    const ints = info == .Int or info == .ComptimeInt;

    var r: f32 = 0;
    inline for (v0) |_, i| {
        var d = v1[i] - v0[i];
        if (d < 0) {
            d *= -1;
        }
        if (ints) {
            r += @intToFloat(f32, d * d);
        } else {
            r += d * d;
        }
    }

    return @sqrt(r);
}
