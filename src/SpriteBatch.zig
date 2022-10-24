const SpriteBatch = @This();

const gl = @import("gl33");
const zm = @import("zmath");
const shader = @import("shader.zig");
const texmod = @import("texture.zig");
const TextureHandle = texmod.TextureHandle;
const TextureManager = texmod.TextureManager;
const Rect = @import("Rect.zig");
const std = @import("std");
const Allocator = std.mem.Allocator;

const vssrc = @embedFile("SpriteBatch.vert");
const fssrc = @embedFile("SpriteBatch.frag");

const Vertex = extern struct {
    xyuv: zm.F32x4,
    rgba: zm.F32x4,
};

const Uniforms = struct {
    uTransform: gl.GLint = -1,
    uSampler: gl.GLint = -1,
};

pub const SpriteBatchParams = struct {
    texture_manager: *const TextureManager,
    texture: TextureHandle,
};

const quad_count = 1024;
const vertex_count = quad_count * 4;
comptime {
    if (vertex_count > std.math.maxInt(u16)) {
        @compileError("SpriteBatch.quad_count requires indices larger than u16");
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

pub fn create() SpriteBatch {
    var self = SpriteBatch{
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

fn createIndices(self: *SpriteBatch) void {
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

fn createVertexStorage(self: *SpriteBatch) void {
    _ = self;
    gl.bufferData(
        gl.ARRAY_BUFFER,
        @intCast(gl.GLsizeiptr, @sizeOf(Vertex) * vertex_count),
        null,
        gl.STREAM_DRAW,
    );
}

/// ARRAY_BUFFER should be bound before calling this function.
fn mapVertexStorage(self: *SpriteBatch) void {
    const vertex_mapping = gl.mapBuffer(gl.ARRAY_BUFFER, gl.WRITE_ONLY);
    self.vertices = @ptrCast([*]Vertex, @alignCast(@alignOf(Vertex), vertex_mapping))[0..vertex_count];
}

/// ARRAY_BUFFER should be bound before calling this function.
fn unmapVertexStorage(self: *SpriteBatch) !void {
    self.vertices = &[_]Vertex{};
    if (gl.unmapBuffer(gl.ARRAY_BUFFER) == gl.FALSE) {
        return error.BufferCorruption;
    }
}

pub fn destroy(self: *SpriteBatch) void {
    gl.deleteVertexArrays(1, &self.vao);
}

pub fn setOutputDimensions(self: *SpriteBatch, w: u32, h: u32) void {
    const wf = @intToFloat(f32, w);
    const hf = @intToFloat(f32, h);
    self.transform = zm.orthographicOffCenterRh(0, wf, 0, hf, 0, 1);
}

pub fn begin(self: *SpriteBatch, params: SpriteBatchParams) void {
    gl.useProgram(self.prog.handle);
    gl.bindVertexArray(self.vao);
    gl.uniformMatrix4fv(self.uniforms.uTransform, 1, gl.TRUE, zm.arrNPtr(&self.transform));
    gl.uniform1i(self.uniforms.uSampler, 0);
    gl.activeTexture(gl.TEXTURE0);
    gl.bindTexture(gl.TEXTURE_2D, params.texture.raw_handle);

    gl.bindBuffer(gl.ELEMENT_ARRAY_BUFFER, self.index_buffer);

    const tex_state = params.texture_manager.getTextureState(params.texture);
    self.ref_width = @intToFloat(f32, tex_state.width);
    self.ref_height = @intToFloat(f32, tex_state.height);

    self.vertex_head = 0;
    gl.bindBuffer(gl.ARRAY_BUFFER, self.vertex_buffer);
    self.mapVertexStorage();
}

pub fn end(self: *SpriteBatch) void {
    self.flush(false);
}

fn flush(self: *SpriteBatch, remap: bool) void {
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

pub fn drawQuad(self: *SpriteBatch, src: Rect, dest: Rect) void {
    const left = @intToFloat(f32, dest.left());
    const right = @intToFloat(f32, dest.right());
    const top = @intToFloat(f32, dest.top());
    const bottom = @intToFloat(f32, dest.bottom());

    const uv_left = @intToFloat(f32, src.left()) / self.ref_width;
    const uv_right = @intToFloat(f32, src.right()) / self.ref_width;
    const uv_top = 1.0 - @intToFloat(f32, src.top()) / self.ref_height;
    const uv_bottom = 1.0 - @intToFloat(f32, src.bottom()) / self.ref_height;

    self.vertices[self.vertex_head + 0] = .{
        .xyuv = zm.f32x4(left, top, uv_left, uv_top),
        .rgba = zm.f32x4s(1),
    };
    self.vertices[self.vertex_head + 1] = .{
        .xyuv = zm.f32x4(left, bottom, uv_left, uv_bottom),
        .rgba = zm.f32x4s(1),
    };
    self.vertices[self.vertex_head + 2] = .{
        .xyuv = zm.f32x4(right, top, uv_right, uv_top),
        .rgba = zm.f32x4s(1),
    };
    self.vertices[self.vertex_head + 3] = .{
        .xyuv = zm.f32x4(right, bottom, uv_right, uv_bottom),
        .rgba = zm.f32x4s(1),
    };
    self.vertex_head += 4;

    if (self.vertex_head == vertex_count) {
        self.flush(true);
    }
}
