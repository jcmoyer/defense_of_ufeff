const Game = @This();

const std = @import("std");
const Allocator = std.mem.Allocator;

const sdl = @import("sdl.zig");
const gl = @import("gl33");
const ImmRenderer = @import("ImmRenderer.zig");
const texture = @import("texture.zig");
const Texture = texture.Texture;
const TextureManager = texture.TextureManager;
const AudioSystem = @import("audio.zig").AudioSystem;
const MenuState = @import("MenuState.zig");
const PlayState = @import("PlayState.zig");
const OptionsState = @import("OptionsState.zig");
const LevelSelectState = @import("LevelSelectState.zig");
const PlayMenuState = @import("PlayMenuState.zig");
const LevelResultState = @import("LevelResultState.zig");
const EndState = @import("EndState.zig");
const ui = @import("ui.zig");
const InputState = @import("input.zig").InputState;
const Rect = @import("Rect.zig");
const RenderServices = @import("render.zig").RenderServices;

/// Updates per second
const UPDATE_RATE = 30;
pub const INTERNAL_WIDTH = 512;
pub const INTERNAL_HEIGHT = 256;

const log = std.log.scoped(.Game);

allocator: Allocator,
window: *sdl.SDL_Window,
context: sdl.SDL_GLContext,
running: bool = false,

texman: TextureManager,
audio: *AudioSystem,
renderers: RenderServices,

scene_framebuf: gl.GLuint = 0,
scene_renderbuf: gl.GLuint = 0,
// Texture containing color information
scene_color: *Texture,

current_state: ?StateId = null,
st_menu: *MenuState,
st_play: *PlayState,
st_options: *OptionsState,
st_levelselect: *LevelSelectState,
st_playmenu: *PlayMenuState,
st_levelresult: *LevelResultState,
st_end: *EndState,

frame_counter: u64 = 0,
output_scale_x: f32 = 2,
output_scale_y: f32 = 2,
output_rect: Rect = .{},

sdl_backend: ui.SDLBackend,

input: InputState,

pub const StateId = enum {
    menu,
    play,
    options,
    levelselect,
    playmenu,
    levelresult,
    end,
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
        .audio = undefined,
        .scene_color = undefined,
        .input = undefined,
        .st_menu = undefined,
        .st_play = undefined,
        .st_options = undefined,
        .st_levelselect = undefined,
        .st_playmenu = undefined,
        .st_levelresult = undefined,
        .st_end = undefined,
        .sdl_backend = undefined,
        .renderers = undefined,
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
        @intFromFloat(c_int, ptr.output_scale_x * INTERNAL_WIDTH),
        @intFromFloat(c_int, ptr.output_scale_y * INTERNAL_HEIGHT),
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

    ptr.sdl_backend = ui.SDLBackend.init(ptr.window);
    ptr.input = InputState.init();
    ptr.texman = TextureManager.init(allocator);
    ptr.renderers.init(&ptr.texman);
    ptr.audio = AudioSystem.create(allocator);

    ptr.init();

    ptr.st_menu = MenuState.create(ptr) catch |err| {
        log.err("Could not create MenuState: {!}", .{err});
        std.process.exit(1);
    };

    ptr.st_play = PlayState.create(ptr) catch |err| {
        log.err("Could not create PlayState: {!}", .{err});
        std.process.exit(1);
    };

    ptr.st_options = OptionsState.create(ptr) catch |err| {
        log.err("Could not create OptionsState: {!}", .{err});
        std.process.exit(1);
    };

    ptr.st_levelselect = LevelSelectState.create(ptr) catch |err| {
        log.err("Could not create LevelSelectState: {!}", .{err});
        std.process.exit(1);
    };

    ptr.st_playmenu = PlayMenuState.create(ptr) catch |err| {
        log.err("Could not create PlayMenuState: {!}", .{err});
        std.process.exit(1);
    };

    ptr.st_levelresult = LevelResultState.create(ptr) catch |err| {
        log.err("Could not create LevelResultState: {!}", .{err});
        std.process.exit(1);
    };

    ptr.st_end = EndState.create(ptr) catch |err| {
        log.err("Could not create EndState: {!}", .{err});
        std.process.exit(1);
    };

    // At this point, the game object should be fully constructed and in a valid state.

    return ptr;
}

pub fn destroy(self: *Game) void {
    self.st_playmenu.destroy();
    self.st_play.destroy();
    self.st_menu.destroy();
    self.st_options.destroy();
    self.st_levelselect.destroy();
    self.st_levelresult.destroy();
    self.st_end.destroy();
    self.renderers.deinit();
    self.texman.deinit();
    self.audio.destroy();
    self.sdl_backend.deinit();
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

pub fn quit(self: *Game) void {
    self.running = false;
}

/// Initialize game and run main loop.
pub fn run(self: *Game) void {
    self.running = true;
    self.changeState(.menu);

    var last: f64 = @floatFromInt(f64, sdl.SDL_GetTicks64());
    var acc: f64 = 0;
    const DELAY = 1000 / @floatFromInt(f64, UPDATE_RATE);
    const MAX_SKIP_FRAMES = 4;

    while (self.running) {
        var ev: sdl.SDL_Event = undefined;
        while (sdl.SDL_PollEvent(&ev) != 0) {
            self.handleEvent(ev);
        }

        const now = @floatFromInt(f64, sdl.SDL_GetTicks64());
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
    } else if (ev.type == .SDL_MOUSEMOTION) {
        self.input.mouse.client_x = ev.motion.x;
        self.input.mouse.client_y = ev.motion.y;
    } else if (ev.type == .SDL_KEYDOWN) {
        if (ev.key.keysym.scancode == sdl.SDL_SCANCODE_RETURN and (sdl.SDL_GetModState() & sdl.KMOD_LALT) > 0) {
            self.toggleFullscreen();
        }
    }

    self.stateDispatchEvent(self.current_state.?, ev);
}

pub fn update(self: *Game) void {
    self.frame_counter += 1;
    self.stateDispatchUpdate(self.current_state.?);
}

pub fn render(self: *Game, alpha: f64) void {
    self.beginRenderToScene();

    self.stateDispatchRender(self.current_state.?, alpha);

    self.endRenderToScene();

    gl.clearColor(0, 0, 0, 1);
    gl.clear(gl.COLOR_BUFFER_BIT);

    self.renderers.r_imm.beginTextured(.{
        .texture = self.scene_color,
    });
    self.renderers.r_imm.drawQuad(
        self.output_rect.x,
        self.output_rect.y,
        @intCast(u32, self.output_rect.w),
        @intCast(u32, self.output_rect.h),
        255,
        255,
        255,
    );

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

    const aspect_ratio = @floatFromInt(f32, INTERNAL_WIDTH) / @floatFromInt(f32, INTERNAL_HEIGHT);
    if (self.isFullscreen()) {
        var output_width: i32 = undefined;
        var output_height: i32 = undefined;
        if (aspect_ratio > 1) {
            output_width = @intCast(i32, window_width);
            output_height = @intFromFloat(i32, @floatFromInt(f32, output_width) / aspect_ratio);
        } else {
            output_height = @intCast(i32, window_height);
            output_width = @intFromFloat(f32, @floatFromInt(f32, output_height) * aspect_ratio);
        }
        self.output_rect = .{
            .x = @divFloor(window_width - output_width, 2),
            .y = @divFloor(window_height - output_height, 2),
            .w = output_width,
            .h = output_height,
        };
    } else {
        self.output_rect = .{
            .x = 0,
            .y = 0,
            .w = window_width,
            .h = window_height,
        };
    }
    log.debug("Output rect: {any}", .{self.output_rect});

    self.output_scale_x = @floatFromInt(f32, self.output_rect.w) / INTERNAL_WIDTH;
    self.output_scale_y = @floatFromInt(f32, self.output_rect.h) / INTERNAL_HEIGHT;

    log.debug("New scale {d}, {d}", .{ self.output_scale_x, self.output_scale_y });

    self.sdl_backend.client_rect = self.output_rect;
    self.sdl_backend.coord_scale_x = self.output_scale_x;
    self.sdl_backend.coord_scale_y = self.output_scale_y;
    self.renderers.output_width = @intCast(u32, self.output_rect.w);
    self.renderers.output_height = @intCast(u32, self.output_rect.h);
}

fn initFramebuffer(self: *Game) void {
    gl.genFramebuffers(1, &self.scene_framebuf);
    gl.bindFramebuffer(gl.FRAMEBUFFER, self.scene_framebuf);

    // allocate storage for framebuffer color
    self.scene_color = self.texman.createInMemory();
    const scene_color = self.scene_color.handle;

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
    self.renderers.r_imm.setOutputDimensions(INTERNAL_WIDTH, INTERNAL_HEIGHT);
}

/// After this call, `self.scene_color` is the texture containing color information.
fn endRenderToScene(self: *Game) void {
    gl.bindFramebuffer(gl.FRAMEBUFFER, 0);

    var window_width: c_int = 0;
    var window_height: c_int = 0;
    sdl.SDL_GetWindowSize(self.window, &window_width, &window_height);
    self.renderers.r_imm.setOutputDimensions(@intCast(u32, window_width), @intCast(u32, window_height));
    gl.viewport(0, 0, window_width, window_height);
}

fn stateDispatchEvent(self: *Game, id: StateId, ev: sdl.SDL_Event) void {
    switch (id) {
        .menu => self.st_menu.handleEvent(ev),
        .play => self.st_play.handleEvent(ev),
        .options => self.st_options.handleEvent(ev),
        .levelselect => self.st_levelselect.handleEvent(ev),
        .playmenu => self.st_playmenu.handleEvent(ev),
        .levelresult => self.st_levelresult.handleEvent(ev),
        .end => self.st_end.handleEvent(ev),
    }
}

fn stateDispatchUpdate(self: *Game, id: StateId) void {
    switch (id) {
        .menu => self.st_menu.update(),
        .play => self.st_play.update(),
        .options => self.st_options.update(),
        .levelselect => self.st_levelselect.update(),
        .playmenu => self.st_playmenu.update(),
        .levelresult => self.st_levelresult.update(),
        .end => self.st_end.update(),
    }
}

fn stateDispatchRender(self: *Game, id: StateId, alpha: f64) void {
    switch (id) {
        .menu => self.st_menu.render(alpha),
        .play => self.st_play.render(alpha),
        .options => self.st_options.render(alpha),
        .levelselect => self.st_levelselect.render(alpha),
        .playmenu => self.st_playmenu.render(alpha),
        .levelresult => self.st_levelresult.render(alpha),
        .end => self.st_end.render(alpha),
    }
}

fn stateDispatchEnter(self: *Game, id: StateId, from: ?StateId) void {
    switch (id) {
        .menu => self.st_menu.enter(from),
        .play => self.st_play.enter(from),
        .options => self.st_options.enter(from),
        .levelselect => self.st_levelselect.enter(from),
        .playmenu => self.st_playmenu.enter(from),
        .levelresult => self.st_levelresult.enter(from),
        .end => self.st_end.enter(from),
    }
}

fn stateDispatchLeave(self: *Game, id: StateId, to: ?StateId) void {
    switch (id) {
        .menu => self.st_menu.leave(to),
        .play => self.st_play.leave(to),
        .options => self.st_options.leave(to),
        .levelselect => self.st_levelselect.leave(to),
        .playmenu => self.st_playmenu.leave(to),
        .levelresult => self.st_levelresult.leave(to),
        .end => self.st_end.leave(to),
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

pub fn unproject(self: *Game, x: i32, y: i32) [2]i32 {
    const scale_x = self.output_scale_x;
    const scale_y = self.output_scale_y;

    return [2]i32{
        @intFromFloat(i32, @floatFromInt(f64, x - self.output_rect.x) / scale_x),
        @intFromFloat(i32, @floatFromInt(f64, y - self.output_rect.y) / scale_y),
    };
}

pub fn setOutputScale(self: *Game, s: f32) void {
    const window_width = @intFromFloat(c_int, s * INTERNAL_WIDTH);
    const window_height = @intFromFloat(c_int, s * INTERNAL_HEIGHT);
    sdl.SDL_SetWindowSize(self.window, window_width, window_height);
    sdl.SDL_SetWindowPosition(self.window, sdl.SDL_WINDOWPOS_CENTERED, sdl.SDL_WINDOWPOS_CENTERED);
    self.performLayout();
}

pub fn toggleFullscreen(self: *Game) void {
    const fullscreen_arg: u32 = if (self.isFullscreen()) 0 else sdl.SDL_WINDOW_FULLSCREEN_DESKTOP;
    if (sdl.SDL_SetWindowFullscreen(self.window, fullscreen_arg) != 0) {
        log.err("SDL_SetWindowFullscreen failed: {s}", .{sdl.SDL_GetError()});
    }
    self.performLayout();
}

pub fn isFullscreen(self: *Game) bool {
    const flags = sdl.SDL_GetWindowFlags(self.window);
    return (flags & sdl.SDL_WINDOW_FULLSCREEN_DESKTOP) != 0;
}
