//! Implements a specialized quad renderer based on:
//!
//! https://www.reedbeta.com/blog/quadrilateral-interpolation-part-2/#implementation
const FingerRenderer = @This();

const std = @import("std");
const log = std.log.scoped(.FingerRenderer);
const gl = @import("gl33");
const zm = @import("zmath");
const shader = @import("shader.zig");
const texture = @import("texture.zig");
const Rect = @import("Rect.zig");

const textured_vs = @embedFile("FingerRenderer.vert");
const textured_fs = @embedFile("FingerRenderer.frag");

pub const TexturedParams = struct {
    texture: *const texture.Texture,
};

const Vertex = extern struct {
    id: u32,
};

const TexturedUniforms = struct {
    uTransform: gl.GLint = -1,
    uSampler: gl.GLint = -1,
    uPos: gl.GLint = -1,
};

tex_prog: shader.Program,
tex_uniforms: TexturedUniforms = .{},

// Shared
vao: gl.GLuint = 0,
buffer: gl.GLuint = 0,
transform: zm.Mat = zm.identity(),
tex_params: ?TexturedParams = null,

pub fn create() FingerRenderer {
    var self: FingerRenderer = .{
        .tex_prog = shader.createProgramFromSource(textured_vs, textured_fs),
    };
    self.tex_uniforms = shader.getUniformLocations(TexturedUniforms, self.tex_prog);

    gl.genVertexArrays(1, &self.vao);
    gl.genBuffers(1, &self.buffer);
    gl.bindVertexArray(self.vao);
    gl.bindBuffer(gl.ARRAY_BUFFER, self.buffer);
    gl.vertexAttribIPointer(0, 1, gl.UNSIGNED_INT, @sizeOf(Vertex), @ptrFromInt(?*anyopaque, @offsetOf(Vertex, "id")));
    gl.enableVertexAttribArray(0);

    return self;
}

pub fn destroy(self: *FingerRenderer) void {
    gl.deleteBuffers(1, &self.buffer);
    gl.deleteVertexArrays(1, &self.vao);
}

pub fn setOutputDimensions(self: *FingerRenderer, w: u32, h: u32) void {
    const wf = @floatFromInt(f32, w);
    const hf = @floatFromInt(f32, h);
    self.transform = zm.orthographicOffCenterRh(0, wf, 0, hf, 0, 1);
}

pub fn beginTextured(self: *FingerRenderer, params: TexturedParams) void {
    gl.useProgram(self.tex_prog.handle);
    gl.bindVertexArray(self.vao);
    gl.uniformMatrix4fv(self.tex_uniforms.uTransform, 1, gl.FALSE, zm.arrNPtr(&self.transform));
    gl.activeTexture(gl.TEXTURE0);
    gl.bindTexture(gl.TEXTURE_2D, params.texture.handle);
    self.tex_params = params;
}

pub fn drawFinger(self: FingerRenderer, point_x: f32, point_y: f32, t: f32) void {
    const finger_w = 24;
    const finger_h = 24;
    const drift_y = 20;
    const y_squash = 0.8;

    const left = -finger_w / 2;
    const right = finger_w / 2;
    const top = -finger_h / 2;
    const bottom = finger_h / 2;

    // sin in 0..1
    const s01 = (1 + @sin(t)) * 0.5;
    // 1..2
    const s12 = 1 + s01;

    var top_row = zm.f32x4(left, top, right, top);
    var bot_row = zm.f32x4(left, bottom, right, bottom);
    top_row *= zm.f32x4(2.5 - s12, s01 * y_squash, 2.5 - s12, s01 * y_squash);
    bot_row *= zm.f32x4(3 - s12, 1, 3 - s12, 1);
    // translate into place
    const translation = zm.f32x4(point_x, point_y - finger_h / 2 - s01 * drift_y, point_x, point_y - finger_h / 2 - s01 * drift_y);
    top_row += translation;
    bot_row += translation;

    const pos = [8]gl.GLfloat{
        bot_row[0], bot_row[1],
        bot_row[2], bot_row[3],
        top_row[0], top_row[1],
        top_row[2], top_row[3],
    };

    gl.uniform2fv(self.tex_uniforms.uPos, 4, &pos);

    const vertices = [4]Vertex{
        Vertex{ .id = 0 },
        Vertex{ .id = 1 },
        Vertex{ .id = 3 },
        Vertex{ .id = 2 },
    };

    gl.bindBuffer(gl.ARRAY_BUFFER, self.buffer);
    gl.bufferData(gl.ARRAY_BUFFER, 4 * @sizeOf(Vertex), &vertices, gl.STREAM_DRAW);
    gl.drawArrays(gl.TRIANGLE_FAN, 0, 4);
}
