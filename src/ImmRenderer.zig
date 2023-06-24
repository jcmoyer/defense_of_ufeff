const ImmRenderer = @This();

const std = @import("std");
const log = std.log.scoped(.ImmRenderer);
const gl = @import("gl33");
const zm = @import("zmath");
const shader = @import("shader.zig");
const texture = @import("texture.zig");
const Rect = @import("Rect.zig");

const textured_vs = @embedFile("ImmRenderer.vert");
const textured_fs = @embedFile("ImmRenderer.frag");

const untextured_vs = @embedFile("ImmRendererUntextured.vert");
const untextured_fs = @embedFile("ImmRendererUntextured.frag");

pub const TexturedParams = struct {
    texture: *texture.Texture,
};

// Shared between textured/untextured; wastes 2 floats per vertex but it should be fine
const Vertex = extern struct {
    xyuv: zm.F32x4,
    rgba: [4]u8,
};

const TexturedUniforms = struct {
    uTransform: gl.GLint = -1,
    uSampler: gl.GLint = -1,
};

const UntexturedUniforms = struct {
    uTransform: gl.GLint = -1,
};

tex_prog: shader.Program,
tex_uniforms: TexturedUniforms = .{},

untex_prog: shader.Program,
untex_uniforms: UntexturedUniforms = .{},

// Shared
vao: gl.GLuint = 0,
buffer: gl.GLuint = 0,
transform: zm.Mat = zm.identity(),
tex_params: ?TexturedParams = null,

pub fn create() ImmRenderer {
    var self: ImmRenderer = .{
        .tex_prog = shader.createProgramFromSource(textured_vs, textured_fs),
        .untex_prog = shader.createProgramFromSource(untextured_vs, untextured_fs),
    };
    self.tex_uniforms = shader.getUniformLocations(TexturedUniforms, self.tex_prog);
    self.untex_uniforms = shader.getUniformLocations(UntexturedUniforms, self.untex_prog);

    gl.genVertexArrays(1, &self.vao);
    gl.genBuffers(1, &self.buffer);
    gl.bindVertexArray(self.vao);
    gl.bindBuffer(gl.ARRAY_BUFFER, self.buffer);
    gl.vertexAttribPointer(0, 4, gl.FLOAT, gl.FALSE, @sizeOf(Vertex), @ptrFromInt(?*anyopaque, @offsetOf(Vertex, "xyuv")));
    gl.vertexAttribPointer(1, 4, gl.UNSIGNED_BYTE, gl.TRUE, @sizeOf(Vertex), @ptrFromInt(?*anyopaque, @offsetOf(Vertex, "rgba")));
    gl.enableVertexAttribArray(0);
    gl.enableVertexAttribArray(1);

    return self;
}

pub fn destroy(self: *ImmRenderer) void {
    gl.deleteBuffers(1, &self.buffer);
    gl.deleteVertexArrays(1, &self.vao);
}

pub fn setOutputDimensions(self: *ImmRenderer, w: u32, h: u32) void {
    const wf = @floatFromInt(f32, w);
    const hf = @floatFromInt(f32, h);
    self.transform = zm.orthographicOffCenterRh(0, wf, 0, hf, 0, 1);
}

pub fn beginTextured(self: *ImmRenderer, params: TexturedParams) void {
    gl.useProgram(self.tex_prog.handle);
    gl.bindVertexArray(self.vao);
    gl.uniformMatrix4fv(self.tex_uniforms.uTransform, 1, gl.FALSE, zm.arrNPtr(&self.transform));
    gl.activeTexture(gl.TEXTURE0);
    gl.bindTexture(gl.TEXTURE_2D, params.texture.handle);
    self.tex_params = params;
}

pub fn beginUntextured(self: ImmRenderer) void {
    gl.useProgram(self.untex_prog.handle);
    gl.bindVertexArray(self.vao);
    gl.uniformMatrix4fv(self.untex_uniforms.uTransform, 1, gl.FALSE, zm.arrNPtr(&self.transform));
}

pub fn drawQuad(self: ImmRenderer, x: i32, y: i32, w: u32, h: u32, r: u8, g: u8, b: u8) void {
    const left = @floatFromInt(f32, x);
    const right = @floatFromInt(f32, x + @intCast(i32, w));
    const top = @floatFromInt(f32, y);
    const bottom = @floatFromInt(f32, y + @intCast(i32, h));
    const rgba = .{ r, g, b, 255 };

    const vertices = [4]Vertex{
        Vertex{ .xyuv = zm.f32x4(left, top, 0, 1), .rgba = rgba },
        Vertex{ .xyuv = zm.f32x4(left, bottom, 0, 0), .rgba = rgba },
        Vertex{ .xyuv = zm.f32x4(right, bottom, 1, 0), .rgba = rgba },
        Vertex{ .xyuv = zm.f32x4(right, top, 1, 1), .rgba = rgba },
    };

    gl.bindBuffer(gl.ARRAY_BUFFER, self.buffer);
    gl.bufferData(gl.ARRAY_BUFFER, 4 * @sizeOf(Vertex), &vertices, gl.STREAM_DRAW);
    gl.drawArrays(gl.TRIANGLE_FAN, 0, 4);
}

pub fn drawLine(self: ImmRenderer, p0: zm.Vec, p1: zm.Vec, rgba: [4]u8) void {
    const vertices = [2]Vertex{
        Vertex{ .xyuv = p0, .rgba = rgba },
        Vertex{ .xyuv = p1, .rgba = rgba },
    };

    gl.bindBuffer(gl.ARRAY_BUFFER, self.buffer);
    gl.bufferData(gl.ARRAY_BUFFER, 2 * @sizeOf(Vertex), &vertices, gl.STREAM_DRAW);
    gl.drawArrays(gl.LINES, 0, 2);
}

pub fn drawRectangle(self: ImmRenderer, p0: zm.Vec, p1: zm.Vec, rgba: [4]u8) void {
    const vertices = [4]Vertex{
        Vertex{ .xyuv = zm.f32x4(p0[0], p0[1], 0, 0), .rgba = rgba },
        Vertex{ .xyuv = zm.f32x4(p0[0], p1[1], 0, 0), .rgba = rgba },
        Vertex{ .xyuv = zm.f32x4(p1[0], p1[1], 0, 0), .rgba = rgba },
        Vertex{ .xyuv = zm.f32x4(p1[0], p0[1], 0, 0), .rgba = rgba },
    };

    gl.bindBuffer(gl.ARRAY_BUFFER, self.buffer);
    gl.bufferData(gl.ARRAY_BUFFER, vertices.len * @sizeOf(Vertex), &vertices, gl.STREAM_DRAW);
    gl.drawArrays(gl.LINE_LOOP, 0, vertices.len);
}

pub fn drawCircle(self: ImmRenderer, comptime segs: comptime_int, p0: zm.Vec, r: f32, rgba: [4]u8) void {
    var vertices: [segs]Vertex = undefined;
    inline for (&vertices, 0..) |*v, i| {
        const f = @floatFromInt(f32, i) + 1.0;
        const d = f / @floatFromInt(f32, segs);
        const offset = p0 + zm.f32x4(
            @cos(std.math.tau * d) * r,
            @sin(std.math.tau * d) * r,
            0,
            0,
        );
        v.* = .{ .xyuv = offset, .rgba = rgba };
    }
    gl.bindBuffer(gl.ARRAY_BUFFER, self.buffer);
    gl.bufferData(gl.ARRAY_BUFFER, vertices.len * @sizeOf(Vertex), &vertices, gl.STREAM_DRAW);
    gl.drawArrays(gl.LINE_LOOP, 0, vertices.len);
}

pub fn drawQuadRGBA(self: ImmRenderer, dest: Rect, rgba: [4]u8) void {
    const left = @floatFromInt(f32, dest.left());
    const right = @floatFromInt(f32, dest.right());
    const top = @floatFromInt(f32, dest.top());
    const bottom = @floatFromInt(f32, dest.bottom());

    const vertices = [4]Vertex{
        Vertex{ .xyuv = zm.f32x4(left, top, 0, 1), .rgba = rgba },
        Vertex{ .xyuv = zm.f32x4(left, bottom, 0, 0), .rgba = rgba },
        Vertex{ .xyuv = zm.f32x4(right, bottom, 1, 0), .rgba = rgba },
        Vertex{ .xyuv = zm.f32x4(right, top, 1, 1), .rgba = rgba },
    };

    gl.bindBuffer(gl.ARRAY_BUFFER, self.buffer);
    gl.bufferData(gl.ARRAY_BUFFER, 4 * @sizeOf(Vertex), &vertices, gl.STREAM_DRAW);
    gl.drawArrays(gl.TRIANGLE_FAN, 0, 4);
}

pub fn drawQuadTextured(self: ImmRenderer, src: Rect, dest: Rect) void {
    const params = self.tex_params orelse {
        log.warn("Tried to draw textured quad without tex_params", .{});
        return;
    };

    const t = params.texture_manager.getTextureState(params.texture);

    const uv_left = @floatFromInt(f32, src.x) / @floatFromInt(f32, t.width);
    const uv_right = @floatFromInt(f32, src.right()) / @floatFromInt(f32, t.width);
    const uv_top = 1 - @floatFromInt(f32, src.y) / @floatFromInt(f32, t.height);
    const uv_bottom = 1 - @floatFromInt(f32, src.bottom()) / @floatFromInt(f32, t.height);

    const left = @floatFromInt(f32, dest.x);
    const right = @floatFromInt(f32, dest.right());
    const top = @floatFromInt(f32, dest.y);
    const bottom = @floatFromInt(f32, dest.bottom());
    const rgba = .{ 255, 255, 255, 255 };

    const vertices = [4]Vertex{
        Vertex{ .xyuv = zm.f32x4(left, top, uv_left, uv_top), .rgba = rgba },
        Vertex{ .xyuv = zm.f32x4(left, bottom, uv_left, uv_bottom), .rgba = rgba },
        Vertex{ .xyuv = zm.f32x4(right, bottom, uv_right, uv_bottom), .rgba = rgba },
        Vertex{ .xyuv = zm.f32x4(right, top, uv_right, uv_top), .rgba = rgba },
    };

    gl.bindBuffer(gl.ARRAY_BUFFER, self.buffer);
    gl.bufferData(gl.ARRAY_BUFFER, 4 * @sizeOf(Vertex), &vertices, gl.STREAM_DRAW);
    gl.drawArrays(gl.TRIANGLE_FAN, 0, 4);
}
