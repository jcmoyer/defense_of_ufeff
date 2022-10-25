const std = @import("std");
const sdl = @import("sdl.zig");

/// State of the keyboard at any instant in time.
const KeyboardState = struct {
    keys: []const u8,

    pub fn init() KeyboardState {
        // normally I use SDL key events and update the array manually but let's try this
        var ptr = sdl.SDL_GetKeyboardState(null);
        return KeyboardState{
            .keys = ptr[0..sdl.SDL_NUM_SCANCODES],
        };
    }
};

const MouseState = struct {
    client_x: i32 = 0,
    client_y: i32 = 0,
};

pub const InputState = struct {
    keyboard: KeyboardState,
    mouse: MouseState = .{},

    pub fn init() InputState {
        return .{
            .keyboard = KeyboardState.init(),
        };
    }

    pub fn isKeyDown(self: InputState, scancode: u32) bool {
        std.debug.assert(scancode < sdl.SDL_NUM_SCANCODES);
        return self.keyboard.keys[scancode] != 0;
    }

    pub fn getMouseClientX(self: InputState) i32 {
        return self.mouse.client_x;
    }

    pub fn getMouseClientY(self: InputState) i32 {
        return self.mouse.client_y;
    }
};
