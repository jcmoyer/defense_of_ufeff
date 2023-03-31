//! Mostly identical to SpriteBatch, but accepts different parameters and does
//! not support coloring.
const WaterRenderer = @This();

const gl = @import("gl33");
const zm = @import("zmath");
const shader = @import("shader.zig");
const texmod = @import("texture.zig");
const Texture = texmod.Texture;
const Rect = @import("Rect.zig");
const std = @import("std");

const vssrc = @embedFile("WaterRenderer.vert");
const fssrc = @embedFile("WaterRenderer.frag");

const Vertex = extern struct {
    xyuv: zm.F32x4,
    world_xy: zm.F32x4,
};

const Uniforms = struct {
    uTransform: gl.GLint = -1,
    uGlobalTime: gl.GLint = -1,
    uWaterDirection: gl.GLint = -1,
    uWaterSpeed: gl.GLint = -1,
    uWaterDriftRange: gl.GLint = -1,
    uSamplerBase: gl.GLint = -1,
    uSamplerBlend: gl.GLint = -1,
    uBlendAmount: gl.GLint = -1,
    uWaterDriftScale: gl.GLint = -1,
};

pub const WaterRendererParams = struct {
    water_base: *const Texture,
    water_blend: *const Texture,
    water_direction: zm.Vec,
    water_drift_scale: zm.Vec,
    water_drift_range: zm.Vec,
    water_speed: f32,
    global_time: f32,
    blend_amount: f32 = 0,
};

const quad_count = 1024;
const vertex_count = quad_count * 4;
comptime {
    if (vertex_count > std.math.maxInt(u16)) {
        @compileError("WaterRenderer.quad_count requires indices larger than u16");
    }
}
const index_count = vertex_count * 6;

vao: gl.GLuint = 0,
index_buffer: gl.GLuint = 0,
vertex_buffer: gl.GLuint = 0,
vertex_head: usize = 0,
prog: shader.Program,
transform: zm.Mat = zm.identity(),
uniforms: Uniforms = .{},

vertices: []Vertex = &[_]Vertex{},
ref_width: f32 = 0,
ref_height: f32 = 0,

pub fn create() WaterRenderer {
    var self = WaterRenderer{
        .prog = shader.createProgramFromSource(vssrc, fssrc),
        // Initialized below
        .uniforms = undefined,
    };
    self.uniforms = shader.getUniformLocations(Uniforms, self.prog);

    gl.genVertexArrays(1, &self.vao);
    gl.genBuffers(1, &self.vertex_buffer);
    gl.genBuffers(1, &self.index_buffer);

    gl.bindVertexArray(self.vao);
    gl.bindBuffer(gl.ARRAY_BUFFER, self.vertex_buffer);
    gl.vertexAttribPointer(0, 4, gl.FLOAT, gl.FALSE, @sizeOf(Vertex), @intToPtr(?*anyopaque, 0));
    gl.vertexAttribPointer(1, 4, gl.FLOAT, gl.FALSE, @sizeOf(Vertex), @intToPtr(?*anyopaque, 16));
    gl.enableVertexAttribArray(0);
    gl.enableVertexAttribArray(1);

    self.createIndices();
    self.createVertexStorage();

    return self;
}

fn createIndices(self: *WaterRenderer) void {
    gl.bindBuffer(gl.ELEMENT_ARRAY_BUFFER, self.index_buffer);
    gl.bufferData(
        gl.ELEMENT_ARRAY_BUFFER,
        @intCast(gl.GLsizeiptr, @sizeOf(u16) * index_count),
        null,
        gl.STATIC_DRAW,
    );
    const index_mapping = gl.mapBuffer(gl.ELEMENT_ARRAY_BUFFER, gl.WRITE_ONLY);
    const indices = @ptrCast([*]u16, @alignCast(2, index_mapping))[0..index_count];

    var index_head: usize = 0;
    var vertex_base: u16 = 0;
    while (index_head < index_count) : (index_head += 6) {
        indices[index_head + 0] = vertex_base + 0;
        indices[index_head + 1] = vertex_base + 1;
        indices[index_head + 2] = vertex_base + 2;
        indices[index_head + 3] = vertex_base + 2;
        indices[index_head + 4] = vertex_base + 1;
        indices[index_head + 5] = vertex_base + 3;
        vertex_base += 4;
    }

    if (gl.unmapBuffer(gl.ELEMENT_ARRAY_BUFFER) == gl.FALSE) {
        std.log.err("Index buffer corrupted", .{});
        std.process.exit(1);
    }
}

fn createVertexStorage(self: *WaterRenderer) void {
    _ = self;
    gl.bufferData(
        gl.ARRAY_BUFFER,
        @intCast(gl.GLsizeiptr, @sizeOf(Vertex) * vertex_count),
        null,
        gl.STREAM_DRAW,
    );
}

/// ARRAY_BUFFER should be bound before calling this function.
fn mapVertexStorage(self: *WaterRenderer) void {
    const vertex_mapping = gl.mapBuffer(gl.ARRAY_BUFFER, gl.WRITE_ONLY);
    self.vertices = @ptrCast([*]Vertex, @alignCast(@alignOf(Vertex), vertex_mapping))[0..vertex_count];
}

/// ARRAY_BUFFER should be bound before calling this function.
fn unmapVertexStorage(self: *WaterRenderer) !void {
    self.vertices = &[_]Vertex{};
    if (gl.unmapBuffer(gl.ARRAY_BUFFER) == gl.FALSE) {
        return error.BufferCorruption;
    }
}

pub fn destroy(self: *WaterRenderer) void {
    gl.deleteVertexArrays(1, &self.vao);
}

pub fn setOutputDimensions(self: *WaterRenderer, w: u32, h: u32) void {
    const wf = @intToFloat(f32, w);
    const hf = @intToFloat(f32, h);
    self.transform = zm.orthographicOffCenterRh(0, wf, 0, hf, 0, 1);
}

pub fn begin(self: *WaterRenderer, params: WaterRendererParams) void {
    gl.useProgram(self.prog.handle);
    gl.bindVertexArray(self.vao);

    gl.uniformMatrix4fv(self.uniforms.uTransform, 1, gl.FALSE, zm.arrNPtr(&self.transform));
    gl.uniform1f(self.uniforms.uGlobalTime, params.global_time);
    gl.uniform2fv(self.uniforms.uWaterDirection, 1, zm.arrNPtr(&params.water_direction));
    gl.uniform1f(self.uniforms.uWaterSpeed, params.water_speed);
    gl.uniform2fv(self.uniforms.uWaterDriftRange, 1, zm.arrNPtr(&params.water_drift_range));
    gl.uniform1i(self.uniforms.uSamplerBase, 0);
    gl.uniform1i(self.uniforms.uSamplerBlend, 1);
    gl.uniform1f(self.uniforms.uBlendAmount, params.blend_amount);
    gl.uniform2fv(self.uniforms.uWaterDriftScale, 1, zm.arrNPtr(&params.water_drift_scale));

    gl.activeTexture(gl.TEXTURE0);
    gl.bindTexture(gl.TEXTURE_2D, params.water_base.handle);
    gl.activeTexture(gl.TEXTURE1);
    gl.bindTexture(gl.TEXTURE_2D, params.water_blend.handle);

    gl.bindBuffer(gl.ELEMENT_ARRAY_BUFFER, self.index_buffer);

    self.vertex_head = 0;
    gl.bindBuffer(gl.ARRAY_BUFFER, self.vertex_buffer);
    self.mapVertexStorage();
}

pub fn end(self: *WaterRenderer) void {
    self.flush(false);
}

fn flush(self: *WaterRenderer, remap: bool) void {
    defer if (remap) {
        self.mapVertexStorage();
    };
    const prim_count = @intCast(gl.GLsizei, self.vertex_head / 4 * 6);
    self.vertex_head = 0;
    self.unmapVertexStorage() catch {
        std.log.warn("ARRAY_BUFFER corrupted; no primitives drawn", .{});
        return;
    };
    gl.drawElements(
        gl.TRIANGLES,
        prim_count,
        gl.UNSIGNED_SHORT,
        null,
    );
}

pub fn drawQuad(self: *WaterRenderer, dest: Rect, world_xy: zm.Vec) void {
    const left = @intToFloat(f32, dest.left());
    const right = @intToFloat(f32, dest.right());
    const top = @intToFloat(f32, dest.top());
    const bottom = @intToFloat(f32, dest.bottom());

    const uv_left = 0.0;
    const uv_right = 1.0;
    const uv_top = 1.0;
    const uv_bottom = 0.0;

    const uv_scale = zm.f32x4(@intToFloat(f32, dest.w), @intToFloat(f32, dest.h), 0, 0);

    self.vertices[self.vertex_head + 0] = .{
        .xyuv = zm.f32x4(left, top, uv_left, uv_top),
        .world_xy = world_xy,
    };
    self.vertices[self.vertex_head + 1] = .{
        .xyuv = zm.f32x4(left, bottom, uv_left, uv_bottom),
        .world_xy = world_xy + zm.swizzle(uv_scale, .w, .y, .w, .w),
    };
    self.vertices[self.vertex_head + 2] = .{
        .xyuv = zm.f32x4(right, top, uv_right, uv_top),
        .world_xy = world_xy + zm.swizzle(uv_scale, .x, .w, .w, .w),
    };
    self.vertices[self.vertex_head + 3] = .{
        .xyuv = zm.f32x4(right, bottom, uv_right, uv_bottom),
        .world_xy = world_xy + zm.swizzle(uv_scale, .x, .y, .w, .w),
    };
    self.vertex_head += 4;

    if (self.vertex_head == vertex_count) {
        self.flush(true);
    }
}
