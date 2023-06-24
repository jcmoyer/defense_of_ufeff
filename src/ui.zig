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

pub const ControlColor = struct {
    color: [4]u8,

    pub const white = ControlColor{ .color = .{ 255, 255, 255, 255 } };
    pub const black = ControlColor{ .color = .{ 0, 0, 0, 255 } };
};

pub const MouseButtons = struct {
    left: bool = false,
    middle: bool = false,
    right: bool = false,
    x1: bool = false,
    x2: bool = false,
};

pub const MouseEventArgs = struct {
    x: i32,
    y: i32,
    buttons: MouseButtons,
};

pub const Background = union(enum) {
    none,
    texture: ControlTexture,
    color: ControlColor,
};

pub fn EventCallback(comptime ControlT: type) type {
    return struct {
        const Self = @This();

        userdata: ?*anyopaque = null,
        callback: ?*const fn (*ControlT, ?*anyopaque) void = null,

        pub fn setCallback(self: *Self, userdata_ptr: anytype, comptime cb: *const fn (*ControlT, @TypeOf(userdata_ptr)) void) void {
            const Ptr = @TypeOf(userdata_ptr);
            const alignment = @typeInfo(Ptr).Pointer.alignment;
            const Impl = struct {
                fn callbackImpl(button: *ControlT, userdata: ?*anyopaque) void {
                    var userdata_ptr_ = @ptrCast(Ptr, @alignCast(alignment, userdata));
                    cb(button, userdata_ptr_);
                }
            };
            self.userdata = userdata_ptr;
            self.callback = Impl.callbackImpl;
        }

        pub fn invoke(self: *Self, control: *ControlT) void {
            if (self.callback) |cb| {
                cb(control, self.userdata);
            }
        }
    };
}

pub const Panel = struct {
    root: *Root,
    children: std.ArrayListUnmanaged(Control),
    rect: Rect,
    background: Background = .none,
    visible: bool = true,

    pub fn deinit(self: *Panel) void {
        self.children.deinit(self.root.allocator);
        self.root.allocator.destroy(self);
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
            .interactRectFn = interactRect,
            .getBackgroundFn = getBackground,
            .getChildrenFn = getChildren,
            .isVisibleFn = isVisible,
        });
    }

    pub fn getBackground(self: *Panel) Background {
        return self.background;
    }

    pub fn getChildren(self: *Panel) []Control {
        return self.children.items;
    }

    pub fn isVisible(self: *Panel) bool {
        return self.visible;
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
    text: ?[]const u8,
    rect: Rect,
    background: Background = .none,
    ev_click: EventCallback(Button) = .{},
    ev_mouse_enter: EventCallback(Button) = .{},
    ev_mouse_leave: EventCallback(Button) = .{},
    state: ButtonState = .normal,
    texture_rects: [4]Rect = .{
        // .normal
        Rect.init(0, 0, 32, 32),
        // .hover
        Rect.init(0, 32, 32, 32),
        // .down
        Rect.init(0, 64, 32, 32),
        // .disabled
        Rect.init(0, 96, 32, 32),
    },
    tooltip_text: ?[]const u8 = null,

    pub fn deinit(self: *Button) void {
        self.root.allocator.destroy(self);
    }

    pub fn handleMouseEnter(self: *Button) void {
        if (self.state != .disabled) {
            self.root.interaction_hint = .clickable;
        }
        if (self.state == .normal) {
            self.state = .hover;
        }
        self.ev_mouse_enter.invoke(self);
    }

    pub fn handleMouseLeave(self: *Button) void {
        self.root.interaction_hint = .none;
        if (self.state != .disabled) {
            self.state = .normal;
        }
        self.ev_mouse_leave.invoke(self);
    }

    pub fn handleMouseDown(self: *Button, args: MouseEventArgs) void {
        if (self.state == .disabled) {
            return;
        }
        if (args.buttons.left) {
            self.state = .down;
        }
    }

    pub fn handleMouseUp(self: *Button, args: MouseEventArgs) void {
        if (self.state == .disabled) {
            return;
        }
        _ = args;
        self.state = .hover;
    }

    pub fn handleMouseClick(self: *Button, args: MouseEventArgs) void {
        if (self.state == .disabled) {
            return;
        }
        if (args.buttons.left) {
            self.ev_click.invoke(self);
        }
    }

    pub fn interactRect(self: *Button) ?Rect {
        return self.rect;
    }

    pub fn getText(self: *Button) ?[]const u8 {
        return self.text;
    }

    pub fn getTooltipText(self: *Button) ?[]const u8 {
        return self.tooltip_text;
    }

    pub fn control(self: *Button) Control {
        return Control.init(self, .{
            .deinitFn = deinit,
            .handleMouseClickFn = handleMouseClick,
            .interactRectFn = interactRect,
            .getBackgroundFn = getBackground,
            .getTextFn = getText,
            .getTooltipTextFn = getTooltipText,
            .handleMouseEnterFn = handleMouseEnter,
            .handleMouseLeaveFn = handleMouseLeave,
            .handleMouseDownFn = handleMouseDown,
            .handleMouseUpFn = handleMouseUp,
        });
    }

    pub fn setTexture(self: *Button, t: *const Texture) void {
        self.background = Background{ .texture = .{ .texture = t } };
    }

    pub fn getBackground(self: *Button) Background {
        if (self.background == .texture) {
            return Background{
                .texture = ControlTexture{
                    .texture = self.background.texture.texture,
                    .texture_rect = self.texture_rects[@intFromEnum(self.state)],
                },
            };
        }
        return self.background;
    }
};

pub const Label = struct {
    root: *Root,
    text: ?[]const u8 = null,
    rect: Rect,
    background: Background = .none,

    pub fn deinit(self: *Label) void {
        self.root.allocator.destroy(self);
    }

    pub fn interactRect(self: *Label) ?Rect {
        return self.rect;
    }

    pub fn getText(self: *Label) ?[]const u8 {
        return self.text;
    }

    pub fn control(self: *Label) Control {
        return Control.init(self, .{
            .deinitFn = deinit,
            .interactRectFn = interactRect,
            .getBackgroundFn = getBackground,
            .getTextFn = getText,
        });
    }

    pub fn getBackground(self: *Label) Background {
        return self.background;
    }
};

pub const Trackbar = struct {
    root: *Root,
    rect: Rect,
    texture: ?*const Texture = null,
    min_value: u32,
    max_value: u32,
    value: u32,
    ev_changed: EventCallback(Trackbar) = .{},
    tooltip_text: ?[]const u8 = null,

    pub fn deinit(self: *Trackbar) void {
        self.root.allocator.destroy(self);
    }

    pub fn handleMouseDown(self: *Trackbar, args: MouseEventArgs) void {
        self.handleMouseEvent(args);
    }

    pub fn handleMouseMove(self: *Trackbar, args: MouseEventArgs) void {
        self.handleMouseEvent(args);
    }

    fn handleMouseEvent(self: *Trackbar, args: MouseEventArgs) void {
        var cr = self.computeClickableRect();
        const p = cr.clampPoint(args.x - cr.left(), args.y - cr.top());
        if (args.buttons.left) {
            const crf = cr.toRectf();
            const xf = @floatFromInt(f32, p[0]);
            // hack: we get to this point because rect.contains() is used for
            // hit testing, but x+w is not considered "inside" the rectangle
            // because it produces strange results with button edges. Need to
            // investigate. For now, subtract 1 so a trackbar can be dragged
            // all the way to the right.
            const percent_x = xf / (crf.w - 1.0);
            self.value = self.min_value + @intFromFloat(u32, @floatFromInt(f32, self.max_value - self.min_value) * percent_x);
            self.ev_changed.invoke(self);
        }
    }

    fn handleMouseEnter(self: *Trackbar) void {
        self.root.interaction_hint = .clickable;
    }

    fn handleMouseLeave(self: *Trackbar) void {
        self.root.interaction_hint = .none;
    }

    pub fn interactRect(self: *Trackbar) ?Rect {
        return self.rect;
    }

    pub fn setPanCallback(self: *Trackbar, userdata_ptr: anytype, comptime cb: *const fn (*Minimap, @TypeOf(userdata_ptr), f32, f32) void) void {
        const Ptr = @TypeOf(userdata_ptr);
        const alignment = @typeInfo(Ptr).Pointer.alignment;
        const Impl = struct {
            fn callbackImpl(button: *Minimap, userdata: ?*anyopaque, x: f32, y: f32) void {
                var userdata_ptr_ = @ptrCast(Ptr, @alignCast(alignment, userdata));
                cb(button, userdata_ptr_, x, y);
            }
        };
        self.pan_userdata = userdata_ptr;
        self.pan_callback = Impl.callbackImpl;
    }

    pub fn control(self: *Trackbar) Control {
        return Control.init(self, .{
            .deinitFn = deinit,
            .handleMouseMoveFn = handleMouseMove,
            .handleMouseDownFn = handleMouseDown,
            .handleMouseEnterFn = handleMouseEnter,
            .handleMouseLeaveFn = handleMouseLeave,
            .interactRectFn = interactRect,
            .getBackgroundFn = getBackground,
            .customRenderFn = customRender,
            .getTooltipTextFn = getTooltipText,
        });
    }

    pub fn getTooltipText(self: *Trackbar) ?[]const u8 {
        return self.tooltip_text;
    }

    pub fn getBackground(self: *Trackbar) Background {
        if (self.texture) |t| {
            return Background{ .texture = ControlTexture{ .texture = t } };
        } else {
            return .none;
        }
    }

    fn computeClickableRect(self: *Trackbar) Rect {
        var rect = self.rect;
        // remember rect is relative to parent, so we make it local space
        rect.x = 0;
        rect.y = 0;
        return rect;
    }

    pub fn valueAsPercent(self: *Trackbar) f32 {
        return @floatFromInt(f32, self.value - self.min_value) / @floatFromInt(f32, self.max_value);
    }

    pub fn customRender(self: *Trackbar, ctx: CustomRenderContext) void {
        const cr = self.computeClickableRect().toRectf();

        const y = cr.centerPoint()[1];
        ctx.drawLine(cr.left(), y, cr.right(), y);

        const x = self.valueAsPercent() * cr.w;
        ctx.drawLine(x, cr.top(), x, cr.bottom());
    }
};

pub const MinimapElement = struct {
    normalized_pos: [2]f32,
    color: [4]u8,
};

pub const Minimap = struct {
    root: *Root,
    rect: Rect,
    texture: ?*const Texture = null,
    pan_userdata: ?*anyopaque = null,
    pan_callback: ?*const fn (*Minimap, ?*anyopaque, f32, f32) void = null,
    view: Rect,
    bounds: Rect,
    elements: []MinimapElement = &[_]MinimapElement{},

    pub fn deinit(self: *Minimap) void {
        self.root.allocator.destroy(self);
    }

    pub fn handleMouseDown(self: *Minimap, args: MouseEventArgs) void {
        self.handleMouseEvent(args);
    }

    pub fn handleMouseMove(self: *Minimap, args: MouseEventArgs) void {
        self.handleMouseEvent(args);
    }

    fn handleMouseEvent(self: *Minimap, args: MouseEventArgs) void {
        var cr = self.computeClickableRect();
        const p = cr.clampPoint(args.x - cr.left(), args.y - cr.top());
        if (args.buttons.left) {
            const crf = cr.toRectf();
            const xf = @floatFromInt(f32, p[0]);
            const yf = @floatFromInt(f32, p[1]);
            const percent_x = xf / crf.w;
            const percent_y = yf / crf.h;
            if (self.pan_callback) |cb| {
                cb(self, self.pan_userdata, percent_x, percent_y);
            }
        }
    }

    fn handleMouseEnter(self: *Minimap) void {
        self.root.interaction_hint = .clickable;
    }

    fn handleMouseLeave(self: *Minimap) void {
        self.root.interaction_hint = .none;
    }

    pub fn interactRect(self: *Minimap) ?Rect {
        return self.rect;
    }

    pub fn setPanCallback(self: *Minimap, userdata_ptr: anytype, comptime cb: *const fn (*Minimap, @TypeOf(userdata_ptr), f32, f32) void) void {
        const Ptr = @TypeOf(userdata_ptr);
        const alignment = @typeInfo(Ptr).Pointer.alignment;
        const Impl = struct {
            fn callbackImpl(button: *Minimap, userdata: ?*anyopaque, x: f32, y: f32) void {
                var userdata_ptr_ = @ptrCast(Ptr, @alignCast(alignment, userdata));
                cb(button, userdata_ptr_, x, y);
            }
        };
        self.pan_userdata = userdata_ptr;
        self.pan_callback = Impl.callbackImpl;
    }

    pub fn control(self: *Minimap) Control {
        return Control.init(self, .{
            .deinitFn = deinit,
            .handleMouseMoveFn = handleMouseMove,
            .handleMouseDownFn = handleMouseDown,
            .handleMouseEnterFn = handleMouseEnter,
            .handleMouseLeaveFn = handleMouseLeave,
            .interactRectFn = interactRect,
            .getBackgroundFn = getBackground,
            .customRenderFn = customRender,
        });
    }

    pub fn getBackground(self: *Minimap) Background {
        if (self.texture) |t| {
            return Background{ .texture = ControlTexture{ .texture = t } };
        } else {
            return .none;
        }
    }

    fn computeClickableRect(self: *Minimap) Rect {
        var rect = self.rect;
        // remember rect is relative to parent, so we make it local space
        rect.x = 0;
        rect.y = 0;

        const background = self.getBackground();
        if (background != .texture) {
            return .{};
        }

        const t = background.texture;

        var render_dest = rect;

        // touch inside of dest rect
        // this is for the minimap, mostly
        const aspect_ratio = @floatFromInt(f32, t.texture.width) / @floatFromInt(f32, t.texture.height);
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
            render_dest.h = @intFromFloat(i32, @floatFromInt(f32, render_dest.w) / aspect_ratio);
            render_dest.centerOn(p[0], p[1]);
        } else {
            render_dest.h = rect.h;
            render_dest.w = @intFromFloat(i32, @floatFromInt(f32, render_dest.h) * aspect_ratio);
            render_dest.centerOn(p[0], p[1]);
        }

        return render_dest;
    }

    pub fn customRender(self: *Minimap, ctx: CustomRenderContext) void {
        const background = self.getBackground();
        if (background != .texture) {
            return;
        }

        const t = background.texture;
        const cr = self.computeClickableRect();
        ctx.drawTexture(t.texture, cr);

        // we draw lines onto this
        const crf = cr.toRectf();

        for (self.elements) |element| {
            ctx.drawPointRect(.{
                .x = crf.x + element.normalized_pos[0] * crf.w,
                .y = crf.y + element.normalized_pos[1] * crf.h,
                .radius = 1,
                .color = element.color,
            });
        }

        const vf = self.view.toRectf();
        const bf = self.bounds.toRectf();

        const left_f = ((vf.left() - bf.left()) / bf.w) * crf.w + crf.x;
        const top_f = ((vf.top() - bf.top()) / bf.h) * crf.h + crf.y;
        const bottom_f = ((vf.bottom() - bf.top()) / bf.h) * crf.h + crf.y;
        const right_f = ((vf.right() - bf.left()) / bf.w) * crf.w + crf.x;

        ctx.drawRectangle(left_f, top_f, right_f, bottom_f);
    }
};

fn ControlImpl(comptime PointerT: type) type {
    return struct {
        deinitFn: *const fn (PointerT) void,

        handleMouseClickFn: ?*const fn (PointerT, MouseEventArgs) void = null,
        interactRectFn: ?*const fn (self: PointerT) ?Rect = null,
        getBackgroundFn: ?*const fn (self: PointerT) Background = null,
        getChildrenFn: ?*const fn (self: PointerT) []Control = null,
        handleMouseEnterFn: ?*const fn (self: PointerT) void = null,
        handleMouseLeaveFn: ?*const fn (self: PointerT) void = null,
        handleMouseDownFn: ?*const fn (PointerT, MouseEventArgs) void = null,
        handleMouseUpFn: ?*const fn (PointerT, MouseEventArgs) void = null,
        handleMouseMoveFn: ?*const fn (PointerT, MouseEventArgs) void = null,
        getTextFn: ?*const fn (PointerT) ?[]const u8 = null,
        getTooltipTextFn: ?*const fn (PointerT) ?[]const u8 = null,
        isVisibleFn: ?*const fn (PointerT) bool = null,
        customRenderFn: ?*const fn (PointerT, CustomRenderContext) void = null,
    };
}

pub const Control = struct {
    instance: *anyopaque,
    vtable: *const VTable,

    pub const VTable = struct {
        deinitFn: *const fn (*anyopaque) void,
        handleMouseClickFn: *const fn (*anyopaque, MouseEventArgs) void,
        interactRectFn: *const fn (self: *anyopaque) ?Rect,
        getBackgroundFn: *const fn (self: *anyopaque) Background,
        getTextFn: *const fn (self: *anyopaque) ?[]const u8,
        getTooltipTextFn: *const fn (*anyopaque) ?[]const u8,
        getChildrenFn: *const fn (self: *anyopaque) []Control,
        handleMouseEnterFn: *const fn (*anyopaque) void,
        handleMouseLeaveFn: *const fn (*anyopaque) void,
        handleMouseDownFn: *const fn (*anyopaque, MouseEventArgs) void,
        handleMouseUpFn: *const fn (*anyopaque, MouseEventArgs) void,
        handleMouseMoveFn: *const fn (*anyopaque, MouseEventArgs) void,
        isVisibleFn: *const fn (*anyopaque) bool,
        customRenderFn: ?*const fn (*anyopaque, CustomRenderContext) void = null,
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

            fn handleMouseClickImpl(ptr: *anyopaque, args: MouseEventArgs) void {
                var inst = @ptrCast(Ptr, @alignCast(alignment, ptr));
                if (fns.handleMouseClickFn) |f| {
                    f(inst, args);
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

            fn getBackgroundDefault(_: *anyopaque) Background {
                return .none;
            }

            fn getBackgroundImpl(ptr: *anyopaque) Background {
                var inst = @ptrCast(Ptr, @alignCast(alignment, ptr));
                const f = fns.getBackgroundFn orelse getBackgroundDefault;
                return f(inst);
            }

            fn getTextImpl(ptr: *anyopaque) ?[]const u8 {
                var inst = @ptrCast(Ptr, @alignCast(alignment, ptr));
                const f = fns.getTextFn orelse return null;
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

            fn handleMouseDownImpl(ptr: *anyopaque, args: MouseEventArgs) void {
                var inst = @ptrCast(Ptr, @alignCast(alignment, ptr));
                if (fns.handleMouseDownFn) |f| {
                    f(inst, args);
                }
            }

            fn handleMouseUpImpl(ptr: *anyopaque, args: MouseEventArgs) void {
                var inst = @ptrCast(Ptr, @alignCast(alignment, ptr));
                if (fns.handleMouseUpFn) |f| {
                    f(inst, args);
                }
            }

            fn handleMouseMoveImpl(ptr: *anyopaque, args: MouseEventArgs) void {
                var inst = @ptrCast(Ptr, @alignCast(alignment, ptr));
                if (fns.handleMouseMoveFn) |f| {
                    f(inst, args);
                }
            }

            fn customRenderImpl(ptr: *anyopaque, ctx: CustomRenderContext) void {
                var inst = @ptrCast(Ptr, @alignCast(alignment, ptr));
                if (fns.customRenderFn) |f| {
                    f(inst, ctx);
                }
            }

            fn getTooltipTextImpl(ptr: *anyopaque) ?[]const u8 {
                var inst = @ptrCast(Ptr, @alignCast(alignment, ptr));
                const f = fns.getTooltipTextFn orelse return null;
                return f(inst);
            }

            fn isVisibleImpl(ptr: *anyopaque) bool {
                var inst = @ptrCast(Ptr, @alignCast(alignment, ptr));
                if (fns.isVisibleFn) |f| {
                    return f(inst);
                } else {
                    return true;
                }
            }

            const vtable = VTable{
                .deinitFn = deinitImpl,
                .handleMouseClickFn = handleMouseClickImpl,
                .interactRectFn = interactRectImpl,
                .getBackgroundFn = getBackgroundImpl,
                .getTextFn = getTextImpl,
                .getTooltipTextFn = getTooltipTextImpl,
                .getChildrenFn = getChildrenImpl,
                .handleMouseEnterFn = handleMouseEnterImpl,
                .handleMouseLeaveFn = handleMouseLeaveImpl,
                .handleMouseDownFn = handleMouseDownImpl,
                .handleMouseUpFn = handleMouseUpImpl,
                .handleMouseMoveFn = handleMouseMoveImpl,
                .isVisibleFn = isVisibleImpl,
                .customRenderFn = if (fns.customRenderFn != null) customRenderImpl else null,
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

    pub fn handleMouseClick(self: Control, args: MouseEventArgs) void {
        self.vtable.handleMouseClickFn(self.instance, args);
    }

    pub fn handleMouseMove(self: Control, args: MouseEventArgs) void {
        self.vtable.handleMouseMoveFn(self.instance, args);
    }

    pub fn interactRect(self: Control) ?Rect {
        return self.vtable.interactRectFn(self.instance);
    }

    pub fn getBackground(self: Control) Background {
        return self.vtable.getBackgroundFn(self.instance);
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

    pub fn handleMouseDown(self: Control, args: MouseEventArgs) void {
        self.vtable.handleMouseDownFn(self.instance, args);
    }

    pub fn handleMouseUp(self: Control, args: MouseEventArgs) void {
        self.vtable.handleMouseUpFn(self.instance, args);
    }

    pub fn getText(self: Control) ?[]const u8 {
        return self.vtable.getTextFn(self.instance);
    }

    pub fn supportsCustomRender(self: Control) bool {
        return self.vtable.customRenderFn != null;
    }

    pub fn customRender(self: Control, ctx: CustomRenderContext) void {
        self.vtable.customRenderFn.?(self.instance, ctx);
    }

    pub fn getTooltipText(self: Control) ?[]const u8 {
        return self.vtable.getTooltipTextFn(self.instance);
    }

    pub fn isVisible(self: Control) bool {
        return self.vtable.isVisibleFn(self.instance);
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
    tooltip_text: ?[]const u8 = null,
    interaction_hint: InteractionHint = .none,
    backend: *SDLBackend,

    pub fn init(allocator: Allocator, backend: *SDLBackend) Root {
        return .{
            .allocator = allocator,
            .children = .{},
            .controls = .{},
            .backend = backend,
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

    pub fn clearTransientState(self: *Root) void {
        self.hover = null;
        self.mouse_down_control = null;
        self.tooltip_text = null;
        self.interaction_hint = .none;
        self.backend.setCursorForHint(self.interaction_hint);
    }

    pub fn isMouseOnElement(self: *Root, x: i32, y: i32) bool {
        for (self.children.items) |child| {
            if (!child.isVisible()) {
                continue;
            }
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
                if (!child.isVisible()) {
                    continue;
                }
                if (child.interactRect()) |rect| {
                    if (rect.contains(x, y)) {
                        return self.findElementChild(child, x - rect.x, y - rect.y);
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
            if (!child.isVisible()) {
                continue;
            }
            if (child.interactRect()) |rect| {
                if (rect.contains(x, y)) {
                    const lowest = self.findElementChild(child, x - rect.x, y - rect.y);
                    return lowest;
                }
            }
        }
        return null;
    }

    pub fn handleMouseMove(self: *Root, args: MouseEventArgs) bool {
        var handled: bool = false;
        if (self.findElementAt(args.x, args.y)) |result| {
            // Mouse enter triggers on one of two conditions,
            // 1) mousing from nothing onto a control
            // 2) mousing from one control to a new one
            var entering_new_control = false;
            if (self.hover) |h| {
                if (result.control.instance != h.instance) {
                    h.handleMouseLeave();
                    entering_new_control = true;
                }
            } else {
                entering_new_control = true;
            }
            self.hover = result.control;
            if (entering_new_control) {
                result.control.handleMouseEnter();
            }
            const local_args = MouseEventArgs{
                .x = result.local_x,
                .y = result.local_y,
                .buttons = args.buttons,
            };
            result.control.handleMouseMove(local_args);
            self.tooltip_text = result.control.getTooltipText();
            handled = true;
        } else {
            if (self.hover) |h| {
                h.handleMouseLeave();
                self.hover = null;
            }
            self.tooltip_text = null;
        }
        self.backend.setCursorForHint(self.interaction_hint);
        return handled;
    }

    /// Returns true if a UI element handled the event.
    pub fn handleMouseUp(self: *Root, args: MouseEventArgs) bool {
        var handled: bool = false;
        if (self.findElementAt(args.x, args.y)) |result| {
            if (self.mouse_down_control) |down_control| {
                if (result.control.instance == down_control.instance) {
                    const local_args = MouseEventArgs{
                        .x = result.local_x,
                        .y = result.local_y,
                        .buttons = args.buttons,
                    };
                    result.control.handleMouseUp(local_args);
                    result.control.handleMouseClick(local_args);
                    // it's possible clicking the control updated its tooltip; maybe
                    // we should add setTooltipText and flag the tooltip as dirty in
                    // the interface?
                    if (self.hover) |h| {
                        self.tooltip_text = h.getTooltipText();
                    }
                    handled = true;
                }
            }
        }
        self.mouse_down_control = null;
        return handled;
    }

    /// Returns true if a UI element handled the event.
    pub fn handleMouseDown(self: *Root, args: MouseEventArgs) bool {
        if (self.findElementAt(args.x, args.y)) |result| {
            self.mouse_down_control = result.control;
            const local_args = MouseEventArgs{
                .x = result.local_x,
                .y = result.local_y,
                .buttons = args.buttons,
            };

            result.control.handleMouseDown(local_args);
            // see related comment in handleMouseUp
            if (self.hover) |h| {
                self.tooltip_text = h.getTooltipText();
            }
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
            .text = null,
            .rect = Rect.init(0, 0, 0, 0),
        };
        try self.controls.append(self.allocator, ptr.control());
        return ptr;
    }

    pub fn createLabel(self: *Root) !*Label {
        var ptr = try self.allocator.create(Label);
        ptr.* = Label{
            .root = self,
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
            .view = .{},
            .bounds = .{},
        };
        try self.controls.append(self.allocator, ptr.control());
        return ptr;
    }

    pub fn createTrackbar(self: *Root) !*Trackbar {
        var ptr = try self.allocator.create(Trackbar);
        ptr.* = Trackbar{
            .root = self,
            .rect = Rect.init(0, 0, 0, 0),
            .min_value = 0,
            .max_value = 0,
            .value = 0,
        };
        try self.controls.append(self.allocator, ptr.control());
        return ptr;
    }
};

// Try to contain all the SDL-specific calls here
const sdl = @import("sdl.zig");
pub const SDLBackend = struct {
    c_arrow: ?*sdl.SDL_Cursor = null,
    c_hand: ?*sdl.SDL_Cursor = null,

    window: *sdl.SDL_Window,

    client_rect: Rect,
    coord_scale_x: f32 = 1,
    coord_scale_y: f32 = 1,

    pub fn init(window: *sdl.SDL_Window) SDLBackend {
        var width: c_int = 0;
        var height: c_int = 0;
        sdl.SDL_GetWindowSize(window, &width, &height);

        return SDLBackend{
            .c_arrow = sdl.SDL_CreateSystemCursor(.SDL_SYSTEM_CURSOR_ARROW),
            .c_hand = sdl.SDL_CreateSystemCursor(.SDL_SYSTEM_CURSOR_HAND),
            .window = window,
            .client_rect = Rect.init(0, 0, width, height),
        };
    }

    pub fn deinit(self: *SDLBackend) void {
        if (self.c_hand) |hand| {
            sdl.SDL_FreeCursor(hand);
        }
        if (self.c_arrow) |arrow| {
            sdl.SDL_FreeCursor(arrow);
        }
    }

    pub fn setCursorForHint(self: SDLBackend, hint: InteractionHint) void {
        switch (hint) {
            .none => sdl.SDL_SetCursor(self.c_arrow),
            .clickable => sdl.SDL_SetCursor(self.c_hand),
        }
    }

    pub fn dispatchEvent(self: SDLBackend, ev: sdl.SDL_Event, root: *Root) bool {
        switch (ev.type) {
            .SDL_MOUSEMOTION => {
                const mouse_p = self.mouseVirtual();
                const mouse_args = MouseEventArgs{
                    .x = mouse_p[0],
                    .y = mouse_p[1],
                    .buttons = mouseEventToButtons(ev),
                };
                return root.handleMouseMove(mouse_args);
            },
            .SDL_MOUSEBUTTONDOWN => {
                const mouse_p = self.mouseVirtual();
                const mouse_args = MouseEventArgs{
                    .x = mouse_p[0],
                    .y = mouse_p[1],
                    .buttons = mouseEventToButtons(ev),
                };
                return root.handleMouseDown(mouse_args);
            },
            .SDL_MOUSEBUTTONUP => {
                const mouse_p = self.mouseVirtual();
                const mouse_args = MouseEventArgs{
                    .x = mouse_p[0],
                    .y = mouse_p[1],
                    .buttons = mouseEventToButtons(ev),
                };
                return root.handleMouseUp(mouse_args);
            },
            else => return false,
        }
    }

    pub fn mouseEventToButtons(ev: sdl.SDL_Event) MouseButtons {
        switch (ev.type) {
            .SDL_MOUSEMOTION => {
                return MouseButtons{
                    .left = ev.motion.state & sdl.SDL_BUTTON_LMASK > 0,
                    .middle = ev.motion.state & sdl.SDL_BUTTON_MMASK > 0,
                    .right = ev.motion.state & sdl.SDL_BUTTON_RMASK > 0,
                    .x1 = ev.motion.state & sdl.SDL_BUTTON_X1MASK > 0,
                    .x2 = ev.motion.state & sdl.SDL_BUTTON_X2MASK > 0,
                };
            },
            .SDL_MOUSEBUTTONDOWN,
            .SDL_MOUSEBUTTONUP,
            => {
                switch (ev.button.button) {
                    sdl.SDL_BUTTON_LEFT => return MouseButtons{ .left = true },
                    sdl.SDL_BUTTON_MIDDLE => return MouseButtons{ .middle = true },
                    sdl.SDL_BUTTON_RIGHT => return MouseButtons{ .right = true },
                    sdl.SDL_BUTTON_X1 => return MouseButtons{ .x1 = true },
                    sdl.SDL_BUTTON_X2 => return MouseButtons{ .x2 = true },
                    else => unreachable,
                }
            },
            else => {
                std.log.err("mouseEventToButtons got unrecognized event: {}", .{ev.type});
                @panic("mouseEventToButtons got unrecognized event");
            },
        }
    }

    /// Maps OS-space window client coordinates to virtual coordinates using scaling constants
    /// `coord_scale_x` and `coord_scale_y`.
    pub fn clientToVirtual(self: SDLBackend, x: i32, y: i32) [2]i32 {
        return [2]i32{
            @intFromFloat(i32, (@floatFromInt(f64, x - self.client_rect.x)) / self.coord_scale_x),
            @intFromFloat(i32, (@floatFromInt(f64, y - self.client_rect.y)) / self.coord_scale_y),
        };
    }

    pub fn mouseVirtual(self: SDLBackend) [2]i32 {
        var x: c_int = 0;
        var y: c_int = 0;
        _ = sdl.SDL_GetMouseState(&x, &y);
        return self.clientToVirtual(x, y);
    }

    fn clientRect(self: SDLBackend) Rect {
        return self.client_rect;
    }

    fn virtualRect(self: SDLBackend) Rect {
        var r = self.clientRect();
        r.x = 0;
        r.y = 0;
        r.w = @intFromFloat(i32, @floatFromInt(f32, r.w) / self.coord_scale_x);
        r.h = @intFromFloat(i32, @floatFromInt(f32, r.h) / self.coord_scale_y);
        return r;
    }
};

// Try to contain the UI rendering stuff here
const SpriteBatch = @import("SpriteBatch.zig");
const font = @import("bmfont.zig");
const ImmRenderer = @import("ImmRenderer.zig");
const zm = @import("zmath");
const QuadBatch = @import("QuadBatch.zig");
const Rectf = @import("Rectf.zig");

const PointRectOptions = struct {
    x: f32,
    y: f32,
    radius: f32,
    color: [4]u8 = .{ 255, 255, 255, 255 },
};

const CustomRenderContext = struct {
    instance: *anyopaque,
    vtable: *const VTable,

    const VTable = struct {
        drawPointRectFn: *const fn (*anyopaque, opts: PointRectOptions) void,
        drawLineFn: *const fn (*anyopaque, x0: f32, y0: f32, x1: f32, y1: f32) void,
        drawRectangleFn: *const fn (*anyopaque, x0: f32, y0: f32, x1: f32, y1: f32) void,
        drawTextureFn: *const fn (ptr: *anyopaque, texture: *const Texture, dest: Rect) void,
    };

    fn drawPointRect(self: CustomRenderContext, opts: PointRectOptions) void {
        self.vtable.drawPointRectFn(self.instance, opts);
    }

    fn drawLine(self: CustomRenderContext, x0: f32, y0: f32, x1: f32, y1: f32) void {
        self.vtable.drawLineFn(self.instance, x0, y0, x1, y1);
    }

    fn drawRectangle(self: CustomRenderContext, x0: f32, y0: f32, x1: f32, y1: f32) void {
        self.vtable.drawRectangleFn(self.instance, x0, y0, x1, y1);
    }

    fn drawTexture(self: CustomRenderContext, texture: *const Texture, dest: Rect) void {
        self.vtable.drawTextureFn(self.instance, texture, dest);
    }
};

const LastDrawType = union(enum) {
    none,
    quadbatch,
    spritebatch: *const Texture,
    immediate,
};

const ControlRenderState = struct {
    translate_x: i32 = 0,
    translate_y: i32 = 0,
    opts: *const UIRenderOptions,
    last_draw: LastDrawType = .none,

    fn createRenderContext(self: *ControlRenderState) CustomRenderContext {
        return CustomRenderContext{
            .instance = self,
            .vtable = &CRVTable,
        };
    }

    fn finishLastDrawType(self: *ControlRenderState) void {
        switch (self.last_draw) {
            .none => {},
            .quadbatch => self.opts.r_quad.end(),
            .spritebatch => self.opts.r_batch.end(),
            .immediate => {},
        }
    }
};

const UIRenderOptions = struct {
    r_batch: *SpriteBatch,
    r_font: *font.BitmapFont,
    r_imm: *ImmRenderer,
    r_quad: *QuadBatch,
    font_texture: *const Texture,
    font_spec: *const font.BitmapFontSpec,
};

fn renderControl(opts: UIRenderOptions, control: Control, renderstate: ControlRenderState) void {
    if (!control.isVisible()) {
        return;
    }

    if (control.supportsCustomRender()) {
        // nasty temporary but we die of const poisoning otherwise
        var rs = renderstate;

        if (control.interactRect()) |rect| {
            rs.translate_x += rect.x;
            rs.translate_y += rect.y;
        }

        control.customRender(rs.createRenderContext());
        rs.finishLastDrawType();
    } else {
        if (control.interactRect()) |rect| {
            var render_dest = rect;
            render_dest.translate(renderstate.translate_x, renderstate.translate_y);

            switch (control.getBackground()) {
                .texture => |t| {
                    var render_src = t.texture_rect orelse Rect.init(0, 0, @intCast(i32, t.texture.width), @intCast(i32, t.texture.height));
                    opts.r_batch.begin(.{
                        .texture = t.texture,
                    });

                    // touch inside of dest rect
                    // this is for the minimap, mostly
                    const aspect_ratio = @floatFromInt(f32, render_src.w) / @floatFromInt(f32, render_src.h);
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
                        render_dest.h = @intFromFloat(i32, @floatFromInt(f32, render_dest.w) / aspect_ratio);
                        render_dest.centerOn(p[0], p[1]);
                    } else {
                        render_dest.h = rect.h;
                        render_dest.w = @intFromFloat(i32, @floatFromInt(f32, render_dest.h) * aspect_ratio);
                        render_dest.centerOn(p[0], p[1]);
                    }

                    opts.r_batch.drawQuad(.{ .src = render_src.toRectf(), .dest = render_dest.toRectf() });
                    opts.r_batch.end();
                },
                .color => |c| {
                    opts.r_imm.beginUntextured();
                    opts.r_imm.drawQuadRGBA(render_dest, c.color);
                },
                .none => {},
            }

            if (control.getText()) |text| {
                opts.r_font.begin(.{
                    .texture = opts.font_texture,
                    .spec = opts.font_spec,
                });
                opts.r_font.drawText(text, .{
                    .dest = render_dest,
                    .h_alignment = .center,
                    .v_alignment = .middle,
                });
                opts.r_font.end();
            }
        }
    }

    if (control.getChildren()) |children| {
        for (children) |child| {
            renderControl(opts, child, .{
                .opts = renderstate.opts,
                .translate_x = renderstate.translate_x + control.interactRect().?.x,
                .translate_y = renderstate.translate_y + control.interactRect().?.y,
            });
        }
    }
}

fn drawPointRectImpl(ptr: *anyopaque, opts: PointRectOptions) void {
    var state = @ptrCast(*ControlRenderState, @alignCast(@alignOf(ControlRenderState), ptr));
    var dest = Rectf.init(@floatFromInt(f32, state.translate_x) + opts.x, @floatFromInt(f32, state.translate_y) + opts.y, 0, 0);
    dest.inflate(opts.radius, opts.radius);
    if (state.last_draw != .quadbatch) {
        state.finishLastDrawType();
        state.opts.r_quad.begin(.{});
        state.last_draw = .quadbatch;
    }
    state.opts.r_quad.drawQuad(.{
        .dest = dest,
        .color = opts.color,
    });
}

fn drawLineImpl(ptr: *anyopaque, x0: f32, y0: f32, x1: f32, y1: f32) void {
    var state = @ptrCast(*ControlRenderState, @alignCast(@alignOf(ControlRenderState), ptr));
    if (state.last_draw != .immediate) {
        state.finishLastDrawType();
        state.opts.r_imm.beginUntextured();
        state.last_draw = .immediate;
    }
    state.opts.r_imm.drawLine(
        .{ @floatFromInt(f32, state.translate_x) + x0, @floatFromInt(f32, state.translate_y) + y0, 0, 1 },
        .{ @floatFromInt(f32, state.translate_x) + x1, @floatFromInt(f32, state.translate_y) + y1, 0, 1 },
        .{ 255, 255, 255, 255 },
    );
}

fn drawRectangleImpl(ptr: *anyopaque, x0: f32, y0: f32, x1: f32, y1: f32) void {
    var state = @ptrCast(*ControlRenderState, @alignCast(@alignOf(ControlRenderState), ptr));
    if (state.last_draw != .immediate) {
        state.finishLastDrawType();
        state.opts.r_imm.beginUntextured();
        state.last_draw = .immediate;
    }
    const tx = @floatFromInt(f32, state.translate_x);
    const ty = @floatFromInt(f32, state.translate_y);
    state.opts.r_imm.drawRectangle(.{ tx + x0, ty + y0, 0, 1 }, .{ tx + x1, ty + y1, 0, 1 }, .{ 255, 255, 255, 255 });
}

fn drawTextureImpl(ptr: *anyopaque, texture: *const Texture, dest: Rect) void {
    var state = @ptrCast(*ControlRenderState, @alignCast(@alignOf(ControlRenderState), ptr));
    if (state.last_draw != .spritebatch or (state.last_draw == .spritebatch and state.last_draw.spritebatch != texture)) {
        state.finishLastDrawType();
        state.opts.r_batch.begin(.{ .texture = texture });
        state.last_draw = .{ .spritebatch = texture };
    }
    const src = Rect.init(0, 0, @intCast(i32, texture.width), @intCast(i32, texture.height));
    var t_dest = dest;
    t_dest.translate(state.translate_x, state.translate_y);
    state.opts.r_batch.drawQuad(.{
        .src = src.toRectf(),
        .dest = t_dest.toRectf(),
    });
}

const CRVTable = CustomRenderContext.VTable{
    .drawPointRectFn = drawPointRectImpl,
    .drawLineFn = drawLineImpl,
    .drawRectangleFn = drawRectangleImpl,
    .drawTextureFn = drawTextureImpl,
};

pub fn renderUI(opts: UIRenderOptions, ui_root: Root) void {
    var state = ControlRenderState{
        .opts = &opts,
    };

    for (ui_root.children.items) |child| {
        renderControl(opts, child, state);
    }

    if (ui_root.tooltip_text) |text| {
        const tooltip_padding = 4;

        var text_rect = opts.font_spec.measureText(text);
        var m = ui_root.backend.mouseVirtual();

        var frame_rect = text_rect;
        frame_rect.inflate(tooltip_padding, tooltip_padding);
        // tooltips always shift downward
        frame_rect.translate(m[0], m[1] + 16);

        const render_rect = ui_root.backend.virtualRect();

        if (!render_rect.containsRect(frame_rect)) {
            // if there's not enough space on the right, draw to the left of the cursor
            if (frame_rect.right() > render_rect.right()) {
                frame_rect.alignRight(frame_rect.left());
            }
            // clamp to bottom of screen
            if (frame_rect.bottom() > render_rect.bottom()) {
                frame_rect.alignBottom(render_rect.bottom());
            }
        }

        text_rect.alignLeft(frame_rect.left() + tooltip_padding);
        text_rect.alignTop(frame_rect.top() + tooltip_padding);

        opts.r_imm.beginUntextured();
        opts.r_imm.drawQuadRGBA(frame_rect, .{ 0, 0, 0, 150 });

        opts.r_font.begin(.{
            .texture = opts.font_texture,
            .spec = opts.font_spec,
        });
        opts.r_font.drawText(text, .{
            .dest = text_rect,
        });
        opts.r_font.end();
    }
}
