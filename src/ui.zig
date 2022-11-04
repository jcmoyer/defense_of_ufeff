const Rect = @import("Rect.zig");
const std = @import("std");
const Allocator = std.mem.Allocator;
const IntrusiveSlotMap = @import("slotmap.zig").IntrusiveSlotMap;
const Texture = @import("texture.zig").Texture;

pub const ControlTexture = struct {
    texture: *const Texture,
    /// `null` means use the whole texture
    texture_rect: ?Rect = null,
};

pub const Panel = struct {
    root: *Root,
    children: std.ArrayListUnmanaged(Control),
    rect: Rect,
    texture: ?*const Texture = null,

    pub fn deinit(self: *Panel) void {
        self.children.deinit(self.root.allocator);
        self.root.allocator.destroy(self);
    }

    pub fn handleMouseClick(self: *const Panel, x: i32, y: i32) void {
        const local_x = x - self.rect.left();
        const local_y = y - self.rect.top();

        for (self.children.items) |child| {
            if (child.interactRect()) |rect| {
                if (rect.contains(local_x, local_y)) {
                    child.handleMouseClick(local_x, local_y);
                    return;
                }
            }
        }
    }

    pub fn addChild(self: *Panel, c: Control) !void {
        try self.children.append(self.root.allocator, c);
    }

    pub fn interactRect(self: *Panel) ?Rect {
        return self.rect;
    }

    pub fn control(self: *Panel) Control {
        return Control.init(self, .{
            .deinitFn = deinit,
            .handleMouseClickFn = handleMouseClick,
            .interactRectFn = interactRect,
            .getTextureFn = getTexture,
            .getChildrenFn = getChildren,
        });
    }

    pub fn getTexture(self: *Panel) ?ControlTexture {
        if (self.texture) |t| {
            return ControlTexture{ .texture = t };
        } else {
            return null;
        }
    }

    pub fn getChildren(self: *Panel) []Control {
        return self.children.items;
    }
};

pub const Button = struct {
    const ButtonState = enum {
        normal,
        hover,
        down,
        disabled,
    };

    root: *Root,
    text: []const u8,
    rect: Rect,
    texture: ?*const Texture = null,
    userdata: ?*anyopaque = null,
    callback: ?*const fn (*Button, ?*anyopaque) void = null,
    state: ButtonState = .normal,
    texture_rects: [4]Rect = .{
        // .normal
        Rect.init(0, 0, 32, 32),
        // .hover
        Rect.init(0, 32, 32, 32),
        // .down
        Rect.init(32, 0, 32, 32),
        // .disabled
        Rect.init(32, 32, 32, 32),
    },

    pub fn deinit(self: *Button) void {
        self.root.allocator.destroy(self);
    }

    pub fn setCallback(self: *Button, userdata_ptr: anytype, comptime cb: *const fn (*Button, @TypeOf(userdata_ptr)) void) void {
        const Ptr = @TypeOf(userdata_ptr);
        const alignment = @typeInfo(Ptr).Pointer.alignment;
        const Impl = struct {
            fn callbackImpl(button: *Button, userdata: ?*anyopaque) void {
                var userdata_ptr_ = @ptrCast(Ptr, @alignCast(alignment, userdata));
                cb(button, userdata_ptr_);
            }
        };
        self.userdata = userdata_ptr;
        self.callback = Impl.callbackImpl;
    }

    pub fn handleMouseEnter(self: *Button) void {
        if (self.state != .disabled) {
            self.root.interaction_hint = .clickable;
        }
        if (self.state == .normal) {
            self.state = .hover;
        }
    }

    pub fn handleMouseLeave(self: *Button) void {
        self.root.interaction_hint = .none;
        self.state = .normal;
    }

    pub fn handleMouseDown(self: *Button, x: i32, y: i32) void {
        _ = x;
        _ = y;
        self.state = .down;
    }

    pub fn handleMouseUp(self: *Button, x: i32, y: i32) void {
        _ = x;
        _ = y;
        self.state = .hover;
    }

    pub fn handleMouseClick(self: *Button, x: i32, y: i32) void {
        _ = x;
        _ = y;
        if (self.callback) |cb| {
            cb(self, self.userdata);
        }
    }

    pub fn interactRect(self: *Button) ?Rect {
        return self.rect;
    }

    pub fn control(self: *Button) Control {
        return Control.init(self, .{
            .deinitFn = deinit,
            .handleMouseClickFn = handleMouseClick,
            .interactRectFn = interactRect,
            .getTextureFn = getTexture,
            .handleMouseEnterFn = handleMouseEnter,
            .handleMouseLeaveFn = handleMouseLeave,
            .handleMouseDownFn = handleMouseDown,
            .handleMouseUpFn = handleMouseUp,
        });
    }

    pub fn getTexture(self: *Button) ?ControlTexture {
        if (self.texture) |t| {
            return ControlTexture{
                .texture = t,
                .texture_rect = self.texture_rects[@enumToInt(self.state)],
            };
        } else {
            return null;
        }
    }
};

pub const Minimap = struct {
    root: *Root,
    rect: Rect,
    texture: ?*const Texture = null,
    userdata: ?*anyopaque = null,
    callback: ?*const fn (?*anyopaque) void = null,

    pub fn deinit(self: *Minimap) void {
        self.root.allocator.destroy(self);
    }

    pub fn handleMouseClick(self: *const Minimap, x: i32, y: i32) void {
        _ = self;
        _ = x;
        _ = y;
    }

    pub fn interactRect(self: *Minimap) ?Rect {
        return self.rect;
    }

    pub fn control(self: *Minimap) Control {
        return Control.init(self, .{
            .deinitFn = deinit,
            .handleMouseClickFn = handleMouseClick,
            .interactRectFn = interactRect,
            .getTextureFn = getTexture,
        });
    }

    pub fn getTexture(self: *Minimap) ?ControlTexture {
        if (self.texture) |t| {
            return ControlTexture{ .texture = t };
        } else {
            return null;
        }
    }
};

fn ControlImpl(comptime PointerT: type) type {
    return struct {
        deinitFn: *const fn (PointerT) void,

        handleMouseClickFn: ?*const fn (PointerT, i32, i32) void = null,
        interactRectFn: ?*const fn (self: PointerT) ?Rect = null,
        getTextureFn: ?*const fn (self: PointerT) ?ControlTexture = null,
        getChildrenFn: ?*const fn (self: PointerT) []Control = null,
        handleMouseEnterFn: ?*const fn (self: PointerT) void = null,
        handleMouseLeaveFn: ?*const fn (self: PointerT) void = null,
        handleMouseDownFn: ?*const fn (PointerT, i32, i32) void = null,
        handleMouseUpFn: ?*const fn (PointerT, i32, i32) void = null,
    };
}

pub const Control = struct {
    instance: *anyopaque,
    vtable: *const VTable,

    pub const VTable = struct {
        deinitFn: *const fn (*anyopaque) void,
        handleMouseClickFn: *const fn (*anyopaque, x: i32, y: i32) void,
        interactRectFn: *const fn (self: *anyopaque) ?Rect,
        getTextureFn: *const fn (self: *anyopaque) ?ControlTexture,
        getChildrenFn: *const fn (self: *anyopaque) []Control,
        handleMouseEnterFn: *const fn (*anyopaque) void,
        handleMouseLeaveFn: *const fn (*anyopaque) void,
        handleMouseDownFn: *const fn (*anyopaque, i32, i32) void,
        handleMouseUpFn: *const fn (*anyopaque, i32, i32) void,
    };

    pub fn init(
        pointer: anytype,
        comptime fns: ControlImpl(@TypeOf(pointer)),
    ) Control {
        const Ptr = @TypeOf(pointer);
        const alignment = @typeInfo(Ptr).Pointer.alignment;

        const Impl = struct {
            fn deinitImpl(ptr: *anyopaque) void {
                var inst = @ptrCast(Ptr, @alignCast(alignment, ptr));
                fns.deinitFn(inst);
            }

            fn handleMouseClickImpl(ptr: *anyopaque, x: i32, y: i32) void {
                var inst = @ptrCast(Ptr, @alignCast(alignment, ptr));
                if (fns.handleMouseClickFn) |f| {
                    f(inst, x, y);
                }
            }

            fn interactRectDefault(_: *anyopaque) ?Rect {
                return null;
            }

            fn interactRectImpl(ptr: *anyopaque) ?Rect {
                var inst = @ptrCast(Ptr, @alignCast(alignment, ptr));
                const f = fns.interactRectFn orelse interactRectDefault;
                return f(inst);
            }

            fn getTextureDefault(_: *anyopaque) ?ControlTexture {
                return null;
            }

            fn getTextureImpl(ptr: *anyopaque) ?ControlTexture {
                var inst = @ptrCast(Ptr, @alignCast(alignment, ptr));
                const f = fns.getTextureFn orelse getTextureDefault;
                return f(inst);
            }

            fn getChildrenDefault(_: *anyopaque) []Control {
                return &[_]Control{};
            }

            fn getChildrenImpl(ptr: *anyopaque) []Control {
                var inst = @ptrCast(Ptr, @alignCast(alignment, ptr));
                const f = fns.getChildrenFn orelse getChildrenDefault;
                return f(inst);
            }

            fn handleMouseEnterImpl(ptr: *anyopaque) void {
                var inst = @ptrCast(Ptr, @alignCast(alignment, ptr));
                const f = fns.handleMouseEnterFn orelse return;
                return f(inst);
            }

            fn handleMouseLeaveImpl(ptr: *anyopaque) void {
                var inst = @ptrCast(Ptr, @alignCast(alignment, ptr));
                const f = fns.handleMouseLeaveFn orelse return;
                return f(inst);
            }

            fn handleMouseDownImpl(ptr: *anyopaque, x: i32, y: i32) void {
                var inst = @ptrCast(Ptr, @alignCast(alignment, ptr));
                if (fns.handleMouseDownFn) |f| {
                    f(inst, x, y);
                }
            }

            fn handleMouseUpImpl(ptr: *anyopaque, x: i32, y: i32) void {
                var inst = @ptrCast(Ptr, @alignCast(alignment, ptr));
                if (fns.handleMouseUpFn) |f| {
                    f(inst, x, y);
                }
            }

            const vtable = VTable{
                .deinitFn = deinitImpl,
                .handleMouseClickFn = handleMouseClickImpl,
                .interactRectFn = interactRectImpl,
                .getTextureFn = getTextureImpl,
                .getChildrenFn = getChildrenImpl,
                .handleMouseEnterFn = handleMouseEnterImpl,
                .handleMouseLeaveFn = handleMouseLeaveImpl,
                .handleMouseDownFn = handleMouseDownImpl,
                .handleMouseUpFn = handleMouseUpImpl,
            };
        };

        return Control{
            .instance = pointer,
            .vtable = &Impl.vtable,
        };
    }

    pub fn deinit(self: Control) void {
        self.vtable.deinitFn(self.instance);
    }

    pub fn handleMouseClick(self: Control, x: i32, y: i32) void {
        self.vtable.handleMouseClickFn(self.instance, x, y);
    }

    pub fn interactRect(self: Control) ?Rect {
        return self.vtable.interactRectFn(self.instance);
    }

    pub fn getTexture(self: Control) ?ControlTexture {
        return self.vtable.getTextureFn(self.instance);
    }

    pub fn getChildren(self: Control) ?[]Control {
        return self.vtable.getChildrenFn(self.instance);
    }

    pub fn handleMouseEnter(self: Control) void {
        self.vtable.handleMouseEnterFn(self.instance);
    }

    pub fn handleMouseLeave(self: Control) void {
        self.vtable.handleMouseLeaveFn(self.instance);
    }

    pub fn handleMouseDown(self: Control, x: i32, y: i32) void {
        self.vtable.handleMouseDownFn(self.instance, x, y);
    }

    pub fn handleMouseUp(self: Control, x: i32, y: i32) void {
        self.vtable.handleMouseUpFn(self.instance, x, y);
    }
};

pub const InteractionHint = enum {
    none,
    clickable,
};

pub const Root = struct {
    allocator: Allocator,
    /// Top level controls
    children: std.ArrayListUnmanaged(Control),
    /// All controls owned by this Root
    controls: std.ArrayListUnmanaged(Control),
    hover: ?Control = null,
    mouse_down_control: ?Control = null,
    interaction_hint: InteractionHint = .none,
    backend: SDLBackend,

    pub fn init(allocator: Allocator) Root {
        return .{
            .allocator = allocator,
            .children = .{},
            .controls = .{},
            .backend = SDLBackend.init(),
        };
    }

    pub fn deinit(self: *Root) void {
        for (self.controls.items) |*c| {
            c.deinit();
        }
        self.controls.deinit(self.allocator);
        self.children.deinit(self.allocator);
        self.backend.deinit();
    }

    pub fn isMouseOnElement(self: *Root, x: i32, y: i32) bool {
        for (self.children.items) |child| {
            if (child.interactRect()) |rect| {
                if (rect.contains(x, y)) {
                    return true;
                }
            }
        }
        return false;
    }

    const FindElementResult = struct {
        control: Control,
        local_x: i32,
        local_y: i32,
    };

    fn findElementChild(self: *Root, at: Control, x: i32, y: i32) FindElementResult {
        if (at.getChildren()) |children| {
            for (children) |child| {
                if (child.interactRect()) |rect| {
                    if (rect.contains(x, y)) {
                        return self.findElementChild(child, x, y);
                    }
                }
            }
        }
        return FindElementResult{
            .control = at,
            .local_x = x,
            .local_y = y,
        };
    }

    fn findElementAt(self: *Root, x: i32, y: i32) ?FindElementResult {
        for (self.children.items) |child| {
            if (child.interactRect()) |rect| {
                if (rect.contains(x, y)) {
                    const lowest = self.findElementChild(child, x - rect.x, y - rect.y);
                    return lowest;
                }
            }
        }
        return null;
    }

    pub fn handleMouseMove(self: *Root, x: i32, y: i32) void {
        if (self.findElementAt(x, y)) |result| {
            if (self.hover) |h| {
                if (result.control.instance == h.instance) {
                    return;
                }
                h.handleMouseLeave();
            }
            self.hover = result.control;
            result.control.handleMouseEnter();
        } else {
            if (self.hover) |h| {
                h.handleMouseLeave();
                self.hover = null;
            }
        }
        self.backend.setCursorForHint(self.interaction_hint);
    }

    /// Returns true if a UI element handled the event.
    pub fn handleMouseUp(self: *Root, x: i32, y: i32) bool {
        var handled: bool = false;
        if (self.findElementAt(x, y)) |result| {
            if (self.mouse_down_control) |down_control| {
                if (result.control.instance == down_control.instance) {
                    result.control.handleMouseUp(result.local_x, result.local_y);
                    result.control.handleMouseClick(result.local_x, result.local_y);
                    handled = true;
                }
            }
        }
        self.mouse_down_control = null;
        return handled;
    }

    /// Returns true if a UI element handled the event.
    pub fn handleMouseDown(self: *Root, x: i32, y: i32) bool {
        if (self.findElementAt(x, y)) |result| {
            self.mouse_down_control = result.control;
            result.control.handleMouseDown(result.local_x, result.local_y);
            return true;
        }
        return false;
    }

    pub fn addChild(self: *Root, c: Control) !void {
        try self.children.append(self.allocator, c);
    }

    pub fn createPanel(self: *Root) !*Panel {
        var ptr = try self.allocator.create(Panel);
        ptr.* = Panel{
            .root = self,
            .children = .{},
            .rect = Rect.init(0, 0, 0, 0),
        };
        try self.controls.append(self.allocator, ptr.control());
        return ptr;
    }

    pub fn createButton(self: *Root) !*Button {
        var ptr = try self.allocator.create(Button);
        ptr.* = Button{
            .root = self,
            .text = "button",
            .rect = Rect.init(0, 0, 0, 0),
        };
        try self.controls.append(self.allocator, ptr.control());
        return ptr;
    }

    pub fn createMinimap(self: *Root) !*Minimap {
        var ptr = try self.allocator.create(Minimap);
        ptr.* = Minimap{
            .root = self,
            .rect = Rect.init(0, 0, 0, 0),
        };
        try self.controls.append(self.allocator, ptr.control());
        return ptr;
    }
};

// Try to contain all the SDL-specific calls here
const sdl = @import("sdl.zig");
const SDLBackend = struct {
    c_arrow: ?*sdl.SDL_Cursor = null,
    c_hand: ?*sdl.SDL_Cursor = null,

    fn init() SDLBackend {
        return SDLBackend{
            .c_arrow = sdl.SDL_CreateSystemCursor(.SDL_SYSTEM_CURSOR_ARROW),
            .c_hand = sdl.SDL_CreateSystemCursor(.SDL_SYSTEM_CURSOR_HAND),
        };
    }

    fn deinit(self: *SDLBackend) void {
        if (self.c_hand) |hand| {
            sdl.SDL_FreeCursor(hand);
        }
        if (self.c_arrow) |arrow| {
            sdl.SDL_FreeCursor(arrow);
        }
    }

    fn setCursorForHint(self: SDLBackend, hint: InteractionHint) void {
        switch (hint) {
            .none => sdl.SDL_SetCursor(self.c_arrow),
            .clickable => sdl.SDL_SetCursor(self.c_hand),
        }
    }
};

// Try to contain the UI rendering stuff here
const SpriteBatch = @import("SpriteBatch.zig");

const ControlRenderState = struct {
    translate_x: i32 = 0,
    translate_y: i32 = 0,
};

fn renderControl(r_batch: *SpriteBatch, control: Control, renderstate: ControlRenderState) void {
    if (control.interactRect()) |rect| {
        if (control.getTexture()) |t| {
            var render_src = t.texture_rect orelse Rect.init(0, 0, @intCast(i32, t.texture.width), @intCast(i32, t.texture.height));
            var render_dest = rect;
            render_dest.translate(renderstate.translate_x, renderstate.translate_y);
            r_batch.begin(.{
                .texture = t.texture,
            });

            // touch inside of dest rect
            // this is for the minimap, mostly
            const aspect_ratio = @intToFloat(f32, t.texture.width) / @intToFloat(f32, t.texture.height);
            const p = render_dest.centerPoint();

            // A = aspect ratio, W = width, H = height
            //
            // A = W/H
            // H = W/A
            // W = AH
            //
            // A > 1 means rect is wider than tall
            // A < 1 means rect is taller than wide
            //
            // we can maintain A at different sizes by setting W or H and then
            // doing one of the above transforms for the other axis
            if (aspect_ratio > 1) {
                render_dest.w = rect.w;
                render_dest.h = @floatToInt(i32, @intToFloat(f32, render_dest.w) / aspect_ratio);
                render_dest.centerOn(p[0], p[1]);
            } else {
                render_dest.h = rect.h;
                render_dest.w = @floatToInt(i32, @intToFloat(f32, render_dest.h) * aspect_ratio);
                render_dest.centerOn(p[0], p[1]);
            }

            r_batch.drawQuad(render_src, render_dest);
            r_batch.end();
        }
    }
    if (control.getChildren()) |children| {
        for (children) |child| {
            renderControl(r_batch, child, .{
                .translate_x = renderstate.translate_x + control.interactRect().?.x,
                .translate_y = renderstate.translate_y + control.interactRect().?.y,
            });
        }
    }
}

pub fn renderUI(r_batch: *SpriteBatch, ui_root: Root) void {
    for (ui_root.children.items) |child| {
        renderControl(r_batch, child, .{});
    }
}
