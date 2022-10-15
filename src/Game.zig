const Game = @This();

const std = @import("std");
const Allocator = std.mem.Allocator;

const sdl = @import("sdl.zig");
const gl = @import("gl33.zig");
const ImmRenderer = @import("imm_renderer.zig").ImmRenderer;
const TextureManager = @import("texture.zig").TextureManager;
const AudioSystem = @import("audio.zig").AudioSystem;

/// Updates per second
const UPDATE_RATE = 30;
const INTERNAL_WIDTH = 512;
const INTERNAL_HEIGHT = 256;

const log = std.log.scoped(.Game);

allocator: Allocator,
window: *sdl.SDL_Window,
context: sdl.SDL_GLContext,
running: bool = false,

imm: ImmRenderer,
texman: TextureManager,
audio: *AudioSystem,

/// Allocate a Game and initialize core systems.
pub fn create(allocator: Allocator) !*Game {
    var ptr = try allocator.create(Game);
    ptr.* = .{
        .allocator = allocator,
        .texman = TextureManager.init(allocator),
        // Initialized below
        .window = undefined,
        .context = undefined,
        .imm = undefined,
        .audio = undefined,
    };

    if (sdl.SDL_Init(sdl.SDL_INIT_EVERYTHING) != 0) {
        log.err("SDL_Init failed: {s}", .{sdl.SDL_GetError()});
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

    ptr.imm = ImmRenderer.create();
    ptr.audio = AudioSystem.create(allocator);

    // At this point, the game object should be fully constructed and in a valid state.

    return ptr;
}

pub fn destroy(self: *Game) void {
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
}

/// Initialize game and run main loop.
pub fn run(self: *Game) void {
    self.init();
    self.running = true;
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
    _ = self;
}

pub fn render(self: *Game, alpha: f64) void {
    _ = alpha;

    gl.clearColor(0x64.0 / 255.0, 0x95.0 / 255.0, 0xED.0 / 255.0, 1);
    gl.clear(gl.COLOR_BUFFER_BIT);

    const t = self.texman.get("assets/textures/0-ufeff tiles.png");
    gl.bindTexture(gl.TEXTURE_2D, t.handle);

    self.imm.begin();
    self.imm.drawQuad(0, 0, t.width, t.height, 1, 0, 0);

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
