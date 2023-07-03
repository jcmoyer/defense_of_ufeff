const std = @import("std");

/// Exact euclidean distance between two vector-likes.
pub fn dist(v0: anytype, v1: anytype) f32 {
    comptime if (v0.len != v1.len) {
        @compileError("vectors need to be same length");
    };
    const info = @typeInfo(@TypeOf(v0[0], v1[0]));
    const ints = info == .Int or info == .ComptimeInt;

    var r: f32 = 0;
    inline for (v0, 0..) |_, i| {
        var d = v1[i] - v0[i];
        if (d < 0) {
            d *= -1;
        }
        if (ints) {
            r += @as(f32, @floatFromInt(d * d));
        } else {
            r += d * d;
        }
    }

    return @sqrt(r);
}

pub fn angleBetween(v0: anytype, v1: anytype) f32 {
    const dy = v1[1] - v0[1];
    const dx = v1[0] - v0[0];
    return std.math.atan2(f32, dy, dx);
}

pub fn colorMulU8Scalar(a: u8, b: u8) u8 {
    return @as(u8, @intCast((@as(u16, a) * @as(u16, b) + 255) >> 8));
}

pub fn colorMulU8(comptime N: usize, a: [N]u8, b: [N]u8) [N]u8 {
    var result: [N]u8 = undefined;
    for (a, 0..) |a_i, i| {
        const b_i = b[i];
        result[i] = @as(u8, @intCast((@as(u16, a_i) * @as(u16, b_i) + 255) >> 8));
    }
    return result;
}

pub fn ampDbToScalar(comptime T: type, db: T) T {
    return std.math.pow(T, 10, db / 20);
}

pub fn ampScalarToDb(comptime T: type, scalar: T) T {
    return @as(T, 20) * std.math.log10(scalar);
}
