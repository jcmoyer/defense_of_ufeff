const std = @import("std");

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

pub fn angleBetween(v0: anytype, v1: anytype) f32 {
    const d = v1 - v0;
    return std.math.atan2(f32, d[1], d[0]);
}

pub fn colorMulU8Scalar(a: u8, b: u8) u8 {
    return @intCast(u8, (@as(u16, a) * @as(u16, b) + 255) >> 8);
}

pub fn colorMulU8(comptime N: usize, a: [N]u8, b: [N]u8) [N]u8 {
    var result: [N]u8 = undefined;
    for (a) |a_i, i| {
        const b_i = b[i];
        result[i] = @intCast(u8, (@as(u16, a_i) * @as(u16, b_i) + 255) >> 8);
    }
    return result;
}
