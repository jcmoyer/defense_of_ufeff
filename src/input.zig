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

pub const InputState = struct {
    keyboard: KeyboardState,

    pub fn init() InputState {
        return .{
            .keyboard = KeyboardState.init(),
        };
    }

    pub fn isKeyDown(self: InputState, scancode: u32) bool {
        std.debug.assert(scancode < sdl.SDL_NUM_SCANCODES);
        return self.keyboard.keys[scancode] != 0;
    }
};
