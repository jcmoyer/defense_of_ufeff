const gl = @import("gl33");
const std = @import("std");
const log = std.log.scoped(.shader);

pub const ShaderBase = struct {
    handle: gl.GLuint = 0,

    fn create(shader_type: gl.GLenum, src: []const u8) ShaderBase {
        const handle = gl.createShader(shader_type);

        const srcs = [_][*]const u8{src.ptr};
        const lens = [_]gl.GLint{@as(gl.GLint, @intCast(src.len))};

        gl.shaderSource(handle, 1, &srcs, &lens);
        gl.compileShader(handle);

        var status: gl.GLint = 0;
        gl.getShaderiv(handle, gl.COMPILE_STATUS, &status);
        if (status == 0) {
            var info: [1024]u8 = undefined;
            var log_len: gl.GLsizei = 0;
            gl.getShaderInfoLog(handle, info.len, &log_len, &info);
            log.err("Failed to compile shader: {s}", .{info[0..@as(usize, @intCast(log_len))]});
            std.process.exit(1);
        }

        return ShaderBase{
            .handle = handle,
        };
    }

    fn destroy(self: *ShaderBase) void {
        if (self.handle != 0) {
            gl.deleteShader(self.handle);
            self.handle = 0;
        }
    }
};

pub const VertexShader = struct {
    base: ShaderBase,

    fn create(src: []const u8) VertexShader {
        return VertexShader{
            .base = ShaderBase.create(gl.VERTEX_SHADER, src),
        };
    }

    fn destroy(self: *VertexShader) void {
        self.base.destroy();
    }
};

pub const FragmentShader = struct {
    base: ShaderBase,

    fn create(src: []const u8) FragmentShader {
        return FragmentShader{
            .base = ShaderBase.create(gl.FRAGMENT_SHADER, src),
        };
    }

    fn destroy(self: *FragmentShader) void {
        self.base.destroy();
    }
};

pub const Program = struct {
    handle: gl.GLuint,

    /// Shaders may be destroyed after this function returns.
    fn create(vs: VertexShader, fs: FragmentShader) Program {
        const handle = gl.createProgram();
        gl.attachShader(handle, vs.base.handle);
        gl.attachShader(handle, fs.base.handle);
        gl.linkProgram(handle);

        var status: gl.GLint = 0;
        gl.getProgramiv(handle, gl.LINK_STATUS, &status);
        if (status == 0) {
            var info: [1024]u8 = undefined;
            var log_len: gl.GLsizei = 0;
            gl.getProgramInfoLog(handle, info.len, &log_len, &info);
            log.err("Failed to link program: {s}", .{info[0..@as(usize, @intCast(log_len))]});
            std.process.exit(1);
        }

        return Program{
            .handle = handle,
        };
    }

    fn destroy(self: *Program) void {
        if (self.handle != 0) {
            gl.deleteProgram(self.handle);
            self.handle = 0;
        }
    }
};

pub fn createProgramFromSource(vssrc: []const u8, fssrc: []const u8) Program {
    var vs = VertexShader.create(vssrc);
    defer vs.destroy();

    var fs = FragmentShader.create(fssrc);
    defer fs.destroy();

    return Program.create(vs, fs);
}

pub fn getUniformLocations(comptime T: type, p: Program) T {
    var uniforms: T = undefined;
    inline for (std.meta.fields(T)) |field| {
        if (field.type != gl.GLint) {
            @compileError("type of " ++ @typeName(T) ++ "." ++ @typeName(field.type) ++ " must be GLint");
        }
        // field.name has no sentinel
        const field_name_z: [:0]const u8 = field.name ++ "";
        @field(uniforms, field.name) = gl.getUniformLocation(p.handle, field_name_z.ptr);
    }
    return uniforms;
}
