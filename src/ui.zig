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
        down,
        hover,
        disabled,
    };

    root: *Root,
    text: []const u8,
    rect: Rect,
    texture: ?*const Texture = null,
    userdata: ?*anyopaque = null,
    callback: ?*const fn (*Button, ?*anyopaque) void = null,
    state: ButtonState = .normal,

    pub fn deinit(self: *Button) void {
        self.root.allocator.destroy(self);
    }

    pub fn handleMouseEnter(self: *Button) void {
        self.state = .hover;
    }

    pub fn handleMouseLeave(self: *Button) void {
        self.state = .normal;
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
        });
    }

    pub fn getTexture(self: *Button) ?ControlTexture {
        if (self.texture) |t| {
            switch (self.state) {
                .normal => return ControlTexture{
                    .texture = t,
                    .texture_rect = Rect.init(0, 0, 32, 32),
                },
                .hover => return ControlTexture{
                    .texture = t,
                    .texture_rect = Rect.init(0, 32, 32, 32),
                },
                .down => return ControlTexture{
                    .texture = t,
                    .texture_rect = Rect.init(32, 0, 32, 32),
                },
                .disabled => return ControlTexture{
                    .texture = t,
                    .texture_rect = Rect.init(32, 32, 32, 32),
                },
            }
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

            const vtable = VTable{
                .deinitFn = deinitImpl,
                .handleMouseClickFn = handleMouseClickImpl,
                .interactRectFn = interactRectImpl,
                .getTextureFn = getTextureImpl,
                .getChildrenFn = getChildrenImpl,
                .handleMouseEnterFn = handleMouseEnterImpl,
                .handleMouseLeaveFn = handleMouseLeaveImpl,
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
};

pub const Root = struct {
    allocator: Allocator,
    /// Top level controls
    children: std.ArrayListUnmanaged(Control),
    /// All controls owned by this Root
    controls: std.ArrayListUnmanaged(Control),
    hover: ?Control = null,

    pub fn init(allocator: Allocator) Root {
        return .{
            .allocator = allocator,
            .children = .{},
            .controls = .{},
        };
    }

    pub fn deinit(self: *Root) void {
        for (self.controls.items) |*c| {
            c.deinit();
        }
        self.controls.deinit(self.allocator);
        self.children.deinit(self.allocator);
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

    fn findElementChild(self: *Root, at: Control, x: i32, y: i32) Control {
        if (at.getChildren()) |children| {
            for (children) |child| {
                if (child.interactRect()) |rect| {
                    if (rect.contains(x, y)) {
                        return self.findElementChild(child, x, y);
                    }
                }
            }
        }
        return at;
    }

    fn findElementAt(self: *Root, x: i32, y: i32) ?Control {
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
        if (self.findElementAt(x, y)) |e| {
            if (self.hover) |h| {
                if (e.instance == h.instance) {
                    return;
                }
                h.handleMouseLeave();
            }
            self.hover = e;
            e.handleMouseEnter();
        }
    }

    pub fn handleMouseClick(self: *Root, x: i32, y: i32) void {
        for (self.children.items) |child| {
            if (child.interactRect()) |rect| {
                if (rect.contains(x, y)) {
                    child.handleMouseClick(x, y);
                    return;
                }
            }
        }
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
