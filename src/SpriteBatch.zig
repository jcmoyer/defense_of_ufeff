const SpriteBatch = @This();

const gl = @import("gl33");
const zm = @import("zmath");
const shader = @import("shader.zig");
const texmod = @import("texture.zig");
const Texture = texmod.Texture;
const Rect = @import("Rect.zig");
const Rectf = @import("Rectf.zig");
const std = @import("std");
const Allocator = std.mem.Allocator;

const vssrc = @embedFile("SpriteBatch.vert");
const fssrc = @embedFile("SpriteBatch.frag");

const Vertex = extern struct {
    xyuv: zm.F32x4,
    rgba: [4]u8,
    flash: u8,
    pad: [3]u8 = undefined,
};

const Uniforms = struct {
    uTransform: gl.GLint = -1,
    uSampler: gl.GLint = -1,
    uFlashRGB: gl.GLint = -1,
};

pub const SpriteBatchParams = struct {
    texture: *const Texture,
    flash_r: u8 = 255,
    flash_g: u8 = 255,
    flash_b: u8 = 255,
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
    gl.vertexAttribPointer(0, 4, gl.FLOAT, gl.FALSE, @sizeOf(Vertex), @ptrFromInt(?*anyopaque, @offsetOf(Vertex, "xyuv")));
    gl.vertexAttribPointer(1, 4, gl.UNSIGNED_BYTE, gl.TRUE, @sizeOf(Vertex), @ptrFromInt(?*anyopaque, @offsetOf(Vertex, "rgba")));
    gl.vertexAttribPointer(2, 1, gl.UNSIGNED_BYTE, gl.TRUE, @sizeOf(Vertex), @ptrFromInt(?*anyopaque, @offsetOf(Vertex, "flash")));

    gl.enableVertexAttribArray(0);
    gl.enableVertexAttribArray(1);
    gl.enableVertexAttribArray(2);

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
    const wf = @floatFromInt(f32, w);
    const hf = @floatFromInt(f32, h);
    self.transform = zm.orthographicOffCenterRh(0, wf, 0, hf, 0, 1);
}

pub fn begin(self: *SpriteBatch, params: SpriteBatchParams) void {
    gl.useProgram(self.prog.handle);
    gl.bindVertexArray(self.vao);
    gl.uniformMatrix4fv(self.uniforms.uTransform, 1, gl.FALSE, zm.arrNPtr(&self.transform));
    gl.uniform1i(self.uniforms.uSampler, 0);
    gl.uniform3f(
        self.uniforms.uFlashRGB,
        @floatFromInt(f32, params.flash_r) / 255.0,
        @floatFromInt(f32, params.flash_g) / 255.0,
        @floatFromInt(f32, params.flash_r) / 255.0,
    );
    gl.activeTexture(gl.TEXTURE0);
    gl.bindTexture(gl.TEXTURE_2D, params.texture.handle);

    gl.bindBuffer(gl.ELEMENT_ARRAY_BUFFER, self.index_buffer);

    self.ref_width = @floatFromInt(f32, params.texture.width);
    self.ref_height = @floatFromInt(f32, params.texture.height);

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

pub const DrawQuadOptions = struct {
    src: Rectf,
    dest: Rectf,
    color: [4]u8 = @splat(4, @as(u8, 255)),
    flash: bool = false,
    flash_mag: f32 = 1,
};

/// Simple quad routine, no transforms
pub fn drawQuad(self: *SpriteBatch, opts: DrawQuadOptions) void {
    const uv_left = opts.src.left() / self.ref_width;
    const uv_right = opts.src.right() / self.ref_width;
    const uv_top = 1.0 - opts.src.top() / self.ref_height;
    const uv_bottom = 1.0 - opts.src.bottom() / self.ref_height;

    var p0: zm.Vec = undefined;
    var p1: zm.Vec = undefined;
    var p2: zm.Vec = undefined;
    var p3: zm.Vec = undefined;

    const left = opts.dest.left();
    const right = opts.dest.right();
    const top = opts.dest.top();
    const bottom = opts.dest.bottom();

    p0 = zm.f32x4(left, top, uv_left, uv_top);
    p1 = zm.f32x4(left, bottom, uv_left, uv_bottom);
    p2 = zm.f32x4(right, top, uv_right, uv_top);
    p3 = zm.f32x4(right, bottom, uv_right, uv_bottom);

    const f_val: u8 = if (opts.flash) @intFromFloat(u8, opts.flash_mag * 255) else 0;

    self.vertices[self.vertex_head + 0] = .{
        .xyuv = p0,
        .rgba = opts.color,
        .flash = f_val,
    };
    self.vertices[self.vertex_head + 1] = .{
        .xyuv = p1,
        .rgba = opts.color,
        .flash = f_val,
    };
    self.vertices[self.vertex_head + 2] = .{
        .xyuv = p2,
        .rgba = opts.color,
        .flash = f_val,
    };
    self.vertices[self.vertex_head + 3] = .{
        .xyuv = p3,
        .rgba = opts.color,
        .flash = f_val,
    };
    self.vertex_head += 4;

    if (self.vertex_head == vertex_count) {
        self.flush(true);
    }
}

pub const DrawQuadTransformedOptions = struct {
    src: Rectf,
    color: [4]u8 = .{ 255, 255, 255, 255 },
    flash: bool = false,
    transform: zm.Mat,
};

pub fn drawQuadTransformed(self: *SpriteBatch, opts: DrawQuadTransformedOptions) void {
    const uv_left = opts.src.left() / self.ref_width;
    const uv_right = opts.src.right() / self.ref_width;
    const uv_top = 1.0 - opts.src.top() / self.ref_height;
    const uv_bottom = 1.0 - opts.src.bottom() / self.ref_height;

    const f_val: u8 = if (opts.flash) 255 else 0;

    const w = opts.src.w;
    const h = opts.src.h;

    const hw = w / 2;
    const hh = h / 2;

    var p0 = zm.mul(zm.f32x4(-hw, -hh, 0, 1), opts.transform);
    var p1 = zm.mul(zm.f32x4(-hw, hh, 0, 1), opts.transform);
    var p2 = zm.mul(zm.f32x4(hw, -hh, 0, 1), opts.transform);
    var p3 = zm.mul(zm.f32x4(hw, hh, 0, 1), opts.transform);

    // that was just the transform, now we need to write in UV coords
    p0[2] = uv_left;
    p0[3] = uv_top;
    p1[2] = uv_left;
    p1[3] = uv_bottom;
    p2[2] = uv_right;
    p2[3] = uv_top;
    p3[2] = uv_right;
    p3[3] = uv_bottom;

    self.vertices[self.vertex_head + 0] = .{
        .xyuv = p0,
        .rgba = opts.color,
        .flash = f_val,
    };
    self.vertices[self.vertex_head + 1] = .{
        .xyuv = p1,
        .rgba = opts.color,
        .flash = f_val,
    };
    self.vertices[self.vertex_head + 2] = .{
        .xyuv = p2,
        .rgba = opts.color,
        .flash = f_val,
    };
    self.vertices[self.vertex_head + 3] = .{
        .xyuv = p3,
        .rgba = opts.color,
        .flash = f_val,
    };
    self.vertex_head += 4;

    if (self.vertex_head == vertex_count) {
        self.flush(true);
    }
}

pub fn drawQuadFlash(self: *SpriteBatch, src: Rect, dest: Rect, flash: bool) void {
    self.drawQuad(.{
        .src = src.toRectf(),
        .dest = dest.toRectf(),
        .flash = flash,
    });
}

pub fn drawQuadRotated(self: *SpriteBatch, src: Rect, dest_x: f32, dest_y: f32, angle: f32) void {
    self.drawQuadTransformed(.{
        .src = src.toRectf(),
        .transform = zm.mul(zm.rotationZ(angle), zm.translation(dest_x, dest_y, 0)),
    });
}
