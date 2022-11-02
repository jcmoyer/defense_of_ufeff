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

    pub fn addChild(self: *Panel, c: Control) void {
        self.children.append(self.root.allocator, c);
    }

    pub fn interactRect(self: *Panel) ?Rect {
        return self.rect;
    }

    pub fn control(self: *Panel) Control {
        return Control{
            .instance = self,
            .vtable = &vtable,
        };
    }

    pub fn getTexture(self: *Panel) ?*const Texture {
        return self.texture;
    }

    const vtable = ControlVtbl{
        .deinitFn = @ptrCast(*const fn (*anyopaque) void, &deinit),
        .handleMouseClickFn = @ptrCast(*const fn (*anyopaque, x: i32, y: i32) void, &handleMouseClick),
        .interactRectFn = @ptrCast(*const fn (self: *anyopaque) ?Rect, &interactRect),
        .getTextureFn = @ptrCast(*const fn (self: *anyopaque) ?*const Texture, &getTexture),
    };
};

pub const Button = struct {
    root: *Root,
    text: []const u8,
    rect: Rect,
    texture: ?*const Texture = null,
};

pub const ControlVtbl = struct {
    deinitFn: *const fn (*anyopaque) void,
    handleMouseClickFn: ?*const fn (*anyopaque, x: i32, y: i32) void = null,
    interactRectFn: ?*const fn (self: *anyopaque) ?Rect = null,
    getTextureFn: ?*const fn (self: *anyopaque) ?*const Texture = null,
};

pub const Control = struct {
    instance: *anyopaque,
    vtable: *const ControlVtbl,

    pub fn deinit(self: Control) void {
        self.vtable.deinitFn(self.instance);
    }

    pub fn handleMouseClick(self: Control, x: i32, y: i32) void {
        if (self.vtable.handleMouseClickFn) |f| {
            f(self.instance, x, y);
        }
    }

    pub fn interactRect(self: Control) ?Rect {
        if (self.vtable.interactRectFn) |f| {
            return f(self.instance);
        }
        return null;
    }

    pub fn getTexture(self: Control) ?*const Texture {
        if (self.vtable.getTextureFn) |f| {
            return f(self.instance);
        }
        return null;
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
        };
        try self.controls.append(self.allocator, ptr);
        return ptr;
    }
};
