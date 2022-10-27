const QuadBatch = @This();

const gl = @import("gl33");
const zm = @import("zmath");
const shader = @import("shader.zig");
const texmod = @import("texture.zig");
const Texture = texmod.Texture;
const Rect = @import("Rect.zig");
const std = @import("std");
const Allocator = std.mem.Allocator;

const vssrc = @embedFile("QuadBatch.vert");
const fssrc = @embedFile("QuadBatch.frag");

const Vertex = extern struct {
    x: f32,
    y: f32,
    r: u8,
    g: u8,
    b: u8,
    a: u8,
};

const Uniforms = struct {
    uTransform: gl.GLint = -1,
};

pub const QuadBatchParams = struct {};

const quad_count = 1024;
const vertex_count = quad_count * 4;
comptime {
    if (vertex_count > std.math.maxInt(u16)) {
        @compileError("QuadBatch.quad_count requires indices larger than u16");
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

pub fn create() QuadBatch {
    var self = QuadBatch{
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
    gl.vertexAttribPointer(0, 2, gl.FLOAT, gl.FALSE, @sizeOf(Vertex), @intToPtr(?*anyopaque, @offsetOf(Vertex, "x")));
    gl.vertexAttribPointer(1, 4, gl.UNSIGNED_BYTE, gl.TRUE, @sizeOf(Vertex), @intToPtr(?*anyopaque, @offsetOf(Vertex, "r")));
    gl.enableVertexAttribArray(0);
    gl.enableVertexAttribArray(1);

    self.createIndices();
    self.createVertexStorage();

    return self;
}

fn createIndices(self: *QuadBatch) void {
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

fn createVertexStorage(self: *QuadBatch) void {
    _ = self;
    gl.bufferData(
        gl.ARRAY_BUFFER,
        @intCast(gl.GLsizeiptr, @sizeOf(Vertex) * vertex_count),
        null,
        gl.STREAM_DRAW,
    );
}

/// ARRAY_BUFFER should be bound before calling this function.
fn mapVertexStorage(self: *QuadBatch) void {
    const vertex_mapping = gl.mapBuffer(gl.ARRAY_BUFFER, gl.WRITE_ONLY);
    self.vertices = @ptrCast([*]Vertex, @alignCast(@alignOf(Vertex), vertex_mapping))[0..vertex_count];
}

/// ARRAY_BUFFER should be bound before calling this function.
fn unmapVertexStorage(self: *QuadBatch) !void {
    self.vertices = &[_]Vertex{};
    if (gl.unmapBuffer(gl.ARRAY_BUFFER) == gl.FALSE) {
        return error.BufferCorruption;
    }
}

pub fn destroy(self: *QuadBatch) void {
    gl.deleteVertexArrays(1, &self.vao);
}

pub fn setOutputDimensions(self: *QuadBatch, w: u32, h: u32) void {
    const wf = @intToFloat(f32, w);
    const hf = @intToFloat(f32, h);
    self.transform = zm.orthographicOffCenterRh(0, wf, 0, hf, 0, 1);
}

pub fn begin(self: *QuadBatch, params: QuadBatchParams) void {
    _ = params;
    gl.useProgram(self.prog.handle);
    gl.bindVertexArray(self.vao);
    gl.uniformMatrix4fv(self.uniforms.uTransform, 1, gl.TRUE, zm.arrNPtr(&self.transform));

    gl.bindBuffer(gl.ELEMENT_ARRAY_BUFFER, self.index_buffer);

    self.vertex_head = 0;
    gl.bindBuffer(gl.ARRAY_BUFFER, self.vertex_buffer);
    self.mapVertexStorage();
}

pub fn end(self: *QuadBatch) void {
    self.flush(false);
}

fn flush(self: *QuadBatch, remap: bool) void {
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

pub fn drawQuad(self: *QuadBatch, dest: Rect) void {
    self.drawQuadRGBA(dest, 255, 255, 255, 255);
}

pub fn drawQuadRGBA(self: *QuadBatch, dest: Rect, r: u8, g: u8, b: u8, a: u8) void {
    const left = @intToFloat(f32, dest.left());
    const right = @intToFloat(f32, dest.right());
    const top = @intToFloat(f32, dest.top());
    const bottom = @intToFloat(f32, dest.bottom());

    self.vertices[self.vertex_head + 0] = .{
        .x = left,
        .y = top,
        .r = r,
        .g = g,
        .b = b,
        .a = a,
    };
    self.vertices[self.vertex_head + 1] = .{
        .x = left,
        .y = bottom,
        .r = r,
        .g = g,
        .b = b,
        .a = a,
    };
    self.vertices[self.vertex_head + 2] = .{
        .x = right,
        .y = top,
        .r = r,
        .g = g,
        .b = b,
        .a = a,
    };
    self.vertices[self.vertex_head + 3] = .{
        .x = right,
        .y = bottom,
        .r = r,
        .g = g,
        .b = b,
        .a = a,
    };
    self.vertex_head += 4;

    if (self.vertex_head == vertex_count) {
        self.flush(true);
    }
}
