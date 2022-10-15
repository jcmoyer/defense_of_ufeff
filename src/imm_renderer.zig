const gl = @import("gl33.zig");
const zm = @import("zmath");

const vssrc = @embedFile("imm_renderer_vs.glsl");
const fssrc = @embedFile("imm_renderer_fs.glsl");
const Vertex = extern struct {
    x: f32,
    y: f32,
    u: f32,
    v: f32,
    r: f32,
    g: f32,
    b: f32,
};

const shader = @import("shader.zig");

pub const ImmRenderer = struct {
    prog: shader.Program,
    vao: gl.GLuint,
    buffer: gl.GLuint,
    transform: zm.Mat,

    pub fn create() ImmRenderer {
        var self: ImmRenderer = undefined;
        self.prog = shader.createProgramFromSource(vssrc, fssrc);
        gl.genVertexArrays(1, &self.vao);
        gl.genBuffers(1, &self.buffer);
        gl.bindVertexArray(self.vao);
        gl.bindBuffer(gl.ARRAY_BUFFER, self.buffer);
        gl.vertexAttribPointer(0, 4, gl.FLOAT, gl.FALSE, @sizeOf(Vertex), @intToPtr(?*anyopaque, @offsetOf(Vertex, "x")));
        gl.vertexAttribPointer(1, 3, gl.FLOAT, gl.FALSE, @sizeOf(Vertex), @intToPtr(?*anyopaque, @offsetOf(Vertex, "r")));
        gl.enableVertexAttribArray(0);
        gl.enableVertexAttribArray(1);
        return self;
    }

    pub fn destroy(self: *ImmRenderer) void {
        // TODO lol lmao I never wrote this in C++
        _ = self;
    }

    pub fn setOutputDimensions(self: *ImmRenderer, w: u32, h: u32) void {
        const wf = @intToFloat(f32, w);
        const hf = @intToFloat(f32, h);
        self.transform = zm.orthographicOffCenterRh(0, wf, 0, hf, 0, 1);
    }

    pub fn begin(self: ImmRenderer) void {
        gl.useProgram(self.prog.handle);
        gl.bindVertexArray(self.vao);
        const uTransform = gl.getUniformLocation(self.prog.handle, "uTransform");
        gl.uniformMatrix4fv(uTransform, 1, gl.TRUE, zm.arrNPtr(&self.transform));
    }

    pub fn drawQuad(self: ImmRenderer, x: i32, y: i32, w: u32, h: u32, r: f32, g: f32, b: f32) void {
        const left = @intToFloat(f32, x);
        const right = @intToFloat(f32, x + @intCast(i32, w));
        const top = @intToFloat(f32, y);
        const bottom = @intToFloat(f32, y + @intCast(i32, h));

        const vertices = [4]Vertex{
            Vertex{ .x = left, .y = top, .u = 0, .v = 0, .r = r, .g = g, .b = b },
            Vertex{ .x = left, .y = bottom, .u = 0, .v = 1, .r = r, .g = g, .b = b },
            Vertex{ .x = right, .y = bottom, .u = 1, .v = 1, .r = r, .g = g, .b = b },
            Vertex{ .x = right, .y = top, .u = 1, .v = 0, .r = r, .g = g, .b = b },
        };

        gl.bindBuffer(gl.ARRAY_BUFFER, self.buffer);
        gl.bufferData(gl.ARRAY_BUFFER, 4 * @sizeOf(Vertex), &vertices, gl.STREAM_DRAW);
        gl.drawArrays(gl.TRIANGLE_FAN, 0, 4);
    }
};
