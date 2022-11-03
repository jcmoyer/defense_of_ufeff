const Rect = @import("Rect.zig");
const std = @import("std");
const Allocator = std.mem.Allocator;
const IntrusiveSlotMap = @import("slotmap.zig").IntrusiveSlotMap;
const Texture = @import("texture.zig").Texture;

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

    pub fn getTexture(self: *Panel) ?*const Texture {
        return self.texture;
    }

    pub fn getChildren(self: *Panel) []Control {
        return self.children.items;
    }
};

pub const Button = struct {
    root: *Root,
    text: []const u8,
    rect: Rect,
    texture: ?*const Texture = null,
    userdata: ?*anyopaque = null,
    callback: ?*const fn (?*anyopaque) void = null,

    pub fn deinit(self: *Button) void {
        self.root.allocator.destroy(self);
    }

    pub fn handleMouseClick(self: *const Button, x: i32, y: i32) void {
        _ = x;
        _ = y;
        std.log.debug("Button clicked", .{});
        if (self.callback) |cb| {
            cb(self.userdata);
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
        });
    }

    pub fn getTexture(self: *Button) ?*const Texture {
        return self.texture;
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

    pub fn getTexture(self: *Minimap) ?*const Texture {
        return self.texture;
    }
};

fn ControlImpl(comptime PointerT: type) type {
    return struct {
        deinitFn: *const fn (PointerT) void,
        handleMouseClickFn: ?*const fn (PointerT, i32, i32) void = null,
        interactRectFn: ?*const fn (self: PointerT) ?Rect = null,
        getTextureFn: ?*const fn (self: PointerT) ?*const Texture = null,
        getChildrenFn: ?*const fn (self: PointerT) []Control = null,
    };
}

pub const Control = struct {
    instance: *anyopaque,
    vtable: *const VTable,

    pub const VTable = struct {
        deinitFn: *const fn (*anyopaque) void,
        handleMouseClickFn: *const fn (*anyopaque, x: i32, y: i32) void,
        interactRectFn: *const fn (self: *anyopaque) ?Rect,
        getTextureFn: *const fn (self: *anyopaque) ?*const Texture,
        getChildrenFn: *const fn (self: *anyopaque) []Control,
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

            fn getTextureDefault(_: *anyopaque) ?*const Texture {
                return null;
            }

            fn getTextureImpl(ptr: *anyopaque) ?*const Texture {
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

            const vtable = VTable{
                .deinitFn = deinitImpl,
                .handleMouseClickFn = handleMouseClickImpl,
                .interactRectFn = interactRectImpl,
                .getTextureFn = getTextureImpl,
                .getChildrenFn = getChildrenImpl,
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

    pub fn getTexture(self: Control) ?*const Texture {
        return self.vtable.getTextureFn(self.instance);
    }

    pub fn getChildren(self: Control) ?[]Control {
        return self.vtable.getChildrenFn(self.instance);
    }
};

pub const Root = struct {
    allocator: Allocator,
    /// Top level controls
    children: std.ArrayListUnmanaged(Control),
    /// All controls owned by this Root
    controls: std.ArrayListUnmanaged(Control),

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
