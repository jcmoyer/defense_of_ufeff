const SpriteBatch = @import("SpriteBatch.zig");
const texmod = @import("texture.zig");
const Texture = texmod.Texture;
const Rect = @import("Rect.zig");
const std = @import("std");
const Allocator = std.mem.Allocator;

pub const BitmapFontSpec = struct {
    allocator: Allocator,
    space: i32,
    map: std.AutoArrayHashMapUnmanaged(u8, Rect),
    kerning_map: std.AutoArrayHashMapUnmanaged(u16, i8),

    pub fn initJson(allocator: Allocator, json: []const u8) !BitmapFontSpec {
        const GlyphDef = struct {
            glyph: []const u8,
            rect: Rect,
        };
        const Document = struct {
            space: i32 = 0,
            glyphs: []GlyphDef,
            kerning: ?[][]const u8 = null,
        };
        var ts = std.json.TokenStream.init(json);
        var parse_opts = std.json.ParseOptions{
            .allocator = allocator,
        };

        var doc = try std.json.parse(Document, &ts, parse_opts);
        defer std.json.parseFree(Document, doc, parse_opts);

        var map = std.AutoArrayHashMapUnmanaged(u8, Rect){};
        errdefer map.deinit(allocator);
        for (doc.glyphs) |g| {
            var gop = try map.getOrPut(allocator, g.glyph[0]);
            if (gop.found_existing) {
                std.log.warn("Duplicate glyph: `{c}`; ignoring", .{g.glyph[0]});
            } else {
                gop.value_ptr.* = g.rect;
            }
        }

        var kerning_map = std.AutoArrayHashMapUnmanaged(u16, i8){};
        errdefer kerning_map.deinit(allocator);
        if (doc.kerning) |kern| {
            for (kern) |row| {
                var tok = std.mem.tokenize(u8, row, &[_]u8{' '});
                const head = tok.next() orelse {
                    std.log.warn("Kerning missing first element: `{s}`", .{row});
                    continue;
                };
                const pair_with = tok.next() orelse {
                    std.log.warn("Kerning missing second element: `{s}`", .{row});
                    continue;
                };
                const offset = tok.next() orelse {
                    std.log.warn("Kerning missing third element: `{s}`", .{row});
                    continue;
                };
                const offset_int = try std.fmt.parseInt(i8, offset, 10);

                const base: u16 = @as(u16, head[0]) << 8;
                for (pair_with) |pair| {
                    const id = base | pair;
                    try kerning_map.put(allocator, id, offset_int);
                }
            }
        }

        return BitmapFontSpec{
            .allocator = allocator,
            .space = doc.space,
            .map = map,
            .kerning_map = kerning_map,
        };
    }

    pub fn deinit(self: *BitmapFontSpec) void {
        self.map.deinit(self.allocator);
        self.kerning_map.deinit(self.allocator);
    }

    pub fn mapGlyph(self: BitmapFontSpec, glyph: u8) Rect {
        return self.map.get(glyph).?;
    }

    pub fn kerning(self: BitmapFontSpec, first: u8, second: u8) i8 {
        const key = (@as(u16, first) << 8) | second;
        return self.kerning_map.get(key) orelse 0;
    }
};

pub const BitmapFontParams = struct {
    texture: *const Texture,
    spec: *const BitmapFontSpec,
};

pub const BitmapFont = struct {
    r_batch: *SpriteBatch,
    ref_width: u32 = 0,
    ref_height: u32 = 0,
    fontspec: *const BitmapFontSpec = undefined,

    pub fn init(batch: *SpriteBatch) BitmapFont {
        return .{
            .r_batch = batch,
        };
    }

    pub fn begin(self: *BitmapFont, params: BitmapFontParams) void {
        self.r_batch.begin(.{
            .texture = params.texture,
        });
        self.ref_width = params.texture.width;
        self.ref_height = params.texture.height;
        self.fontspec = params.spec;
    }

    pub fn end(self: BitmapFont) void {
        self.r_batch.end();
    }

    pub const DrawTextOptions = struct {
        x: i32,
        y: i32,
        color: @Vector(4, u8) = @splat(4, @as(u8, 255)),
    };

    pub fn drawText(self: BitmapFont, text: []const u8, opts: DrawTextOptions) void {
        var dx = opts.x;
        var dy = opts.y;
        var last_ch: u8 = 0;
        for (text) |ch| {
            const src = self.mapGlyph(ch);
            dx += self.fontspec.kerning(last_ch, ch);
            const dest = Rect.init(
                dx,
                dy,
                src.w,
                src.h,
            );
            self.r_batch.drawQuadOptions(.{
                .src = src.toRectf(),
                .dest = dest.toRectf(),
                .color = opts.color,
            });
            dx += src.w + self.fontspec.space;
            last_ch = ch;
        }
    }

    pub fn measureText(self: BitmapFont, text: []const u8) Rect {
        var width: i32 = 0;
        var height: i32 = 0;
        var height_this_line: i32 = 0;
        var last_ch: u8 = 0;
        for (text) |ch| {
            const glyph_rect = self.mapGlyph(ch);
            width += glyph_rect.w + self.fontspec.space + self.fontspec.kerning(last_ch, ch);
            height_this_line = std.math.max(height_this_line, glyph_rect.h);
            last_ch = ch;
            // TODO: handle \n
        }
        width -= self.fontspec.space;
        height += height_this_line;
        return Rect.init(0, 0, width, height);
    }

    pub fn mapGlyph(self: BitmapFont, glyph: u8) Rect {
        return self.fontspec.mapGlyph(glyph);

        // TODO: can reuse this in a more generic interface
        // const lo = (glyph & 0x0F);
        // const hi = (glyph & 0xF0) >> 4;
        // const glyph_w = @intCast(i32, self.ref_width / 16);
        // const glyph_h = @intCast(i32, self.ref_height / 16);
        // return Rect.init(
        //     lo * glyph_w,
        //     hi * glyph_h,
        //     glyph_w,
        //     glyph_h,
        // );
    }
};
