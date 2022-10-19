const Game = @This();

const std = @import("std");
const Allocator = std.mem.Allocator;

const sdl = @import("sdl.zig");
const gl = @import("gl33.zig");
const ImmRenderer = @import("ImmRenderer.zig");
const texture = @import("texture.zig");
const Texture = texture.Texture;
const TextureManager = texture.TextureManager;
const TextureHandle = texture.TextureHandle;
const AudioSystem = @import("audio.zig").AudioSystem;
const PlayState = @import("PlayState.zig");

/// Updates per second
const UPDATE_RATE = 30;
pub const INTERNAL_WIDTH = 512;
pub const INTERNAL_HEIGHT = 256;

const log = std.log.scoped(.Game);

allocator: Allocator,
window: *sdl.SDL_Window,
context: sdl.SDL_GLContext,
running: bool = false,

imm: ImmRenderer,
texman: TextureManager,
audio: *AudioSystem,

scene_framebuf: gl.GLuint = 0,
scene_renderbuf: gl.GLuint = 0,
// Texture containing color information
scene_color: TextureHandle,

current_state: ?StateId = null,
st_play: *PlayState,

pub const StateId = enum {
    play,
};

/// Allocate a Game and initialize core systems.
pub fn create(allocator: Allocator) !*Game {
    var ptr = try allocator.create(Game);
    ptr.* = .{
        .allocator = allocator,
        // Initialized below
        .texman = undefined,
        .window = undefined,
        .context = undefined,
        .imm = undefined,
        .audio = undefined,
        .scene_color = undefined,
        .st_play = undefined,
    };

    if (sdl.SDL_Init(sdl.SDL_INIT_EVERYTHING) != 0) {
        log.err("SDL_Init failed: {s}", .{sdl.SDL_GetError()});
        std.process.exit(1);
    }

    if (sdl.SDL_GL_SetAttribute(.SDL_GL_CONTEXT_PROFILE_MASK, sdl.SDL_GL_CONTEXT_PROFILE_CORE) != 0) {
        log.err("SDL_GL_SetAttribute failed: {s}", .{sdl.SDL_GetError()});
        std.process.exit(1);
    }

    if (sdl.SDL_GL_SetAttribute(.SDL_GL_CONTEXT_MAJOR_VERSION, 3) != 0) {
        log.err("SDL_GL_SetAttribute failed: {s}", .{sdl.SDL_GetError()});
        std.process.exit(1);
    }

    if (sdl.SDL_GL_SetAttribute(.SDL_GL_CONTEXT_MINOR_VERSION, 3) != 0) {
        log.err("SDL_GL_SetAttribute failed: {s}", .{sdl.SDL_GetError()});
        std.process.exit(1);
    }

    ptr.window = sdl.SDL_CreateWindow(
        "defense of ufeff",
        sdl.SDL_WINDOWPOS_CENTERED,
        sdl.SDL_WINDOWPOS_CENTERED,
        2 * INTERNAL_WIDTH,
        2 * INTERNAL_HEIGHT,
        sdl.SDL_WINDOW_OPENGL,
    ) orelse {
        log.err("SDL_CreateWindow failed: {s}", .{sdl.SDL_GetError()});
        std.process.exit(1);
    };

    ptr.context = sdl.SDL_GL_CreateContext(ptr.window) orelse {
        log.err("SDL_GL_CreateContext failed: {s}", .{sdl.SDL_GetError()});
        std.process.exit(1);
    };

    log.info("Loading OpenGL extensions", .{});
    gl.load({}, loadExtension) catch |err| {
        log.err("Failed to load extensions: {!}", .{err});
        std.process.exit(1);
    };

    ptr.texman = TextureManager.init(allocator);
    ptr.imm = ImmRenderer.create();
    ptr.audio = AudioSystem.create(allocator);

    ptr.init();

    ptr.st_play = PlayState.create(ptr) catch |err| {
        log.err("Could not create PlayState: {!}", .{err});
        std.process.exit(1);
    };

    // At this point, the game object should be fully constructed and in a valid state.

    return ptr;
}

pub fn destroy(self: *Game) void {
    self.st_play.destroy();
    self.texman.deinit();
    self.audio.destroy();
    sdl.SDL_GL_DeleteContext(self.context);
    sdl.SDL_DestroyWindow(self.window);
    sdl.SDL_Quit();
    self.allocator.destroy(self);
}

fn init(self: *Game) void {
    self.performLayout();

    // cull backfaces
    gl.enable(gl.CULL_FACE);
    gl.cullFace(gl.BACK);

    // enable alpha blending
    gl.enable(gl.BLEND);
    gl.blendFunc(gl.SRC_ALPHA, gl.ONE_MINUS_SRC_ALPHA);

    self.initFramebuffer();
}

/// Initialize game and run main loop.
pub fn run(self: *Game) void {
    self.running = true;
    self.changeState(.play);

    var last: f64 = @intToFloat(f64, sdl.SDL_GetTicks64());
    var acc: f64 = 0;
    const DELAY = 1000 / @intToFloat(f64, UPDATE_RATE);
    const MAX_SKIP_FRAMES = 4;

    while (self.running) {
        var ev: sdl.SDL_Event = undefined;
        while (sdl.SDL_PollEvent(&ev) != 0) {
            self.handleEvent(ev);
        }

        const now = @intToFloat(f64, sdl.SDL_GetTicks64());
        const elapsed = now - last;
        last = now;
        acc += elapsed;

        if (acc > MAX_SKIP_FRAMES * DELAY) {
            acc = MAX_SKIP_FRAMES * DELAY;
        }

        while (acc >= DELAY) {
            self.update();
            acc -= DELAY;
        }

        const alpha = acc / DELAY;
        self.render(alpha);
    }
}

pub fn handleEvent(self: *Game, ev: sdl.SDL_Event) void {
    if (ev.type == .SDL_QUIT) {
        self.running = false;
    }
}

pub fn update(self: *Game) void {
    self.stateDispatchUpdate(self.current_state.?);
}

pub fn render(self: *Game, alpha: f64) void {
    self.beginRenderToScene();

    self.stateDispatchRender(self.current_state.?, alpha);

    self.endRenderToScene();

    self.scene_color.bind(gl.TEXTURE_2D);
    self.imm.setOutputDimensions(1, 1);
    self.imm.begin();
    self.imm.drawQuad(0, 0, 1, 1, 1, 1, 1);
    gl.bindTexture(gl.TEXTURE_2D, 0);

    sdl.SDL_GL_SwapWindow(self.window);
}

fn loadExtension(_: void, name: [:0]const u8) ?*const anyopaque {
    log.info("    {s}", .{name});
    return sdl.SDL_GL_GetProcAddress(name);
}

fn performLayout(self: *Game) void {
    var window_width: c_int = 0;
    var window_height: c_int = 0;
    sdl.SDL_GetWindowSize(self.window, &window_width, &window_height);
    self.imm.setOutputDimensions(@intCast(u32, window_width), @intCast(u32, window_height));
}

fn initFramebuffer(self: *Game) void {
    gl.genFramebuffers(1, &self.scene_framebuf);
    gl.bindFramebuffer(gl.FRAMEBUFFER, self.scene_framebuf);

    // allocate storage for framebuffer color
    self.scene_color = self.texman.createInMemory();
    const scene_color = self.scene_color.raw_handle;

    gl.bindTexture(gl.TEXTURE_2D, scene_color);
    gl.texImage2D(gl.TEXTURE_2D, 0, gl.RGB, INTERNAL_WIDTH, INTERNAL_HEIGHT, 0, gl.RGB, gl.UNSIGNED_BYTE, null);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.NEAREST);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.NEAREST);
    gl.bindTexture(gl.TEXTURE_2D, 0);

    // attach to framebuffer
    gl.framebufferTexture2D(gl.FRAMEBUFFER, gl.COLOR_ATTACHMENT0, gl.TEXTURE_2D, scene_color, 0);

    // allocate renderbuffer
    gl.genRenderbuffers(1, &self.scene_renderbuf);
    gl.bindRenderbuffer(gl.RENDERBUFFER, self.scene_renderbuf);
    gl.renderbufferStorage(gl.RENDERBUFFER, gl.DEPTH24_STENCIL8, INTERNAL_WIDTH, INTERNAL_HEIGHT);
    gl.bindRenderbuffer(gl.RENDERBUFFER, 0);

    // attach to framebuffer
    gl.framebufferRenderbuffer(gl.FRAMEBUFFER, gl.DEPTH_STENCIL_ATTACHMENT, gl.RENDERBUFFER, self.scene_renderbuf);

    if (gl.checkFramebufferStatus(gl.FRAMEBUFFER) != gl.FRAMEBUFFER_COMPLETE) {
        log.err("could not construct framebuffer", .{});
        std.process.exit(1);
    }

    gl.bindFramebuffer(gl.FRAMEBUFFER, 0);
}

fn beginRenderToScene(self: *Game) void {
    gl.viewport(0, 0, INTERNAL_WIDTH, INTERNAL_HEIGHT);
    gl.bindFramebuffer(gl.FRAMEBUFFER, self.scene_framebuf);
    self.imm.setOutputDimensions(INTERNAL_WIDTH, INTERNAL_HEIGHT);
}

/// After this call, `self.scene_color` is the texture containing color information.
fn endRenderToScene(self: *Game) void {
    gl.bindFramebuffer(gl.FRAMEBUFFER, 0);

    var window_width: c_int = 0;
    var window_height: c_int = 0;
    sdl.SDL_GetWindowSize(self.window, &window_width, &window_height);
    self.imm.setOutputDimensions(@intCast(u32, window_width), @intCast(u32, window_height));
    gl.viewport(0, 0, window_width, window_height);
}

fn stateDispatchUpdate(self: *Game, id: StateId) void {
    switch (id) {
        .play => self.st_play.update(),
    }
}

fn stateDispatchRender(self: *Game, id: StateId, alpha: f64) void {
    switch (id) {
        .play => self.st_play.render(alpha),
    }
}

fn stateDispatchEnter(self: *Game, id: StateId, from: ?StateId) void {
    switch (id) {
        .play => self.st_play.enter(from),
    }
}

fn stateDispatchLeave(self: *Game, id: StateId, to: ?StateId) void {
    switch (id) {
        .play => self.st_play.leave(to),
    }
}

pub fn changeState(self: *Game, to: StateId) void {
    const old = self.current_state;
    if (self.current_state) |old_val| {
        self.stateDispatchLeave(old_val, to);
    }
    self.current_state = to;
    self.stateDispatchEnter(to, old);
    log.debug("State change: {any} -> {any}", .{ old, to });
}
