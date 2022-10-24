const ImmRenderer = @This();

const gl = @import("gl33");
const zm = @import("zmath");
const shader = @import("shader.zig");
const texture = @import("texture.zig");
const Rect = @import("Rect.zig");

const textured_vs = @embedFile("ImmRenderer.vert");
const textured_fs = @embedFile("ImmRenderer.frag");

const untextured_vs = @embedFile("ImmRendererUntextured.vert");
const untextured_fs = @embedFile("ImmRendererUntextured.frag");

// Shared between textured/untextured; wastes 2 floats per vertex but it should be fine
const Vertex = extern struct {
    xyuv: zm.F32x4,
    rgba: zm.F32x4,
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
    gl.vertexAttribPointer(0, 4, gl.FLOAT, gl.FALSE, @sizeOf(Vertex), @intToPtr(?*anyopaque, @offsetOf(Vertex, "xyuv")));
    gl.vertexAttribPointer(1, 4, gl.FLOAT, gl.FALSE, @sizeOf(Vertex), @intToPtr(?*anyopaque, @offsetOf(Vertex, "rgba")));
    gl.enableVertexAttribArray(0);
    gl.enableVertexAttribArray(1);

    return self;
}

pub fn destroy(self: *ImmRenderer) void {
    gl.deleteBuffers(1, &self.buffer);
    gl.deleteVertexArrays(1, &self.vao);
}

pub fn setOutputDimensions(self: *ImmRenderer, w: u32, h: u32) void {
    const wf = @intToFloat(f32, w);
    const hf = @intToFloat(f32, h);
    self.transform = zm.orthographicOffCenterRh(0, wf, 0, hf, 0, 1);
}

pub fn beginTextured(self: ImmRenderer) void {
    gl.useProgram(self.tex_prog.handle);
    gl.bindVertexArray(self.vao);
    gl.uniformMatrix4fv(self.tex_uniforms.uTransform, 1, gl.TRUE, zm.arrNPtr(&self.transform));
}

pub fn beginUntextured(self: ImmRenderer) void {
    gl.useProgram(self.untex_prog.handle);
    gl.bindVertexArray(self.vao);
    gl.uniformMatrix4fv(self.untex_uniforms.uTransform, 1, gl.TRUE, zm.arrNPtr(&self.transform));
}

pub fn drawQuad(self: ImmRenderer, x: i32, y: i32, w: u32, h: u32, r: f32, g: f32, b: f32) void {
    const left = @intToFloat(f32, x);
    const right = @intToFloat(f32, x + @intCast(i32, w));
    const top = @intToFloat(f32, y);
    const bottom = @intToFloat(f32, y + @intCast(i32, h));
    const rgba = zm.f32x4(r, g, b, 1);

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

pub fn drawQuadRGBA(self: ImmRenderer, dest: Rect, rgba: zm.Vec) void {
    const left = @intToFloat(f32, dest.left());
    const right = @intToFloat(f32, dest.right());
    const top = @intToFloat(f32, dest.top());
    const bottom = @intToFloat(f32, dest.bottom());

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

pub fn drawQuadTextured(self: ImmRenderer, t: texture.TextureState, src: Rect, dest: Rect) void {
    const uv_left = @intToFloat(f32, src.x) / @intToFloat(f32, t.width);
    const uv_right = @intToFloat(f32, src.right()) / @intToFloat(f32, t.width);
    const uv_top = 1 - @intToFloat(f32, src.y) / @intToFloat(f32, t.height);
    const uv_bottom = 1 - @intToFloat(f32, src.bottom()) / @intToFloat(f32, t.height);

    const left = @intToFloat(f32, dest.x);
    const right = @intToFloat(f32, dest.right());
    const top = @intToFloat(f32, dest.y);
    const bottom = @intToFloat(f32, dest.bottom());
    const rgba = zm.f32x4(1, 1, 1, 1);

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
