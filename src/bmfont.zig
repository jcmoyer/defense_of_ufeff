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

    pub fn loadFromFile(allocator: std.mem.Allocator, filename: []const u8) !BitmapFontSpec {
        var font_file = try std.fs.cwd().openFile(filename, .{});
        defer font_file.close();
        var spec_json = try font_file.readToEndAlloc(allocator, 1024 * 1024);
        defer allocator.free(spec_json);
        return try BitmapFontSpec.initJson(allocator, spec_json);
    }

    pub fn mapGlyph(self: BitmapFontSpec, glyph: u8) Rect {
        return self.map.get(glyph) orelse {
            std.log.warn("Could not map glyph: `{c}`", .{glyph});
            return Rect.init(0, 0, 0, 0);
        };
    }

    pub fn kerning(self: BitmapFontSpec, first: u8, second: u8) i8 {
        const key = (@as(u16, first) << 8) | second;
        return self.kerning_map.get(key) orelse 0;
    }

    pub fn measureText(self: BitmapFontSpec, text: []const u8) Rect {
        var width_this_line: i32 = 0;
        var width: i32 = 0;
        var height: i32 = 0;
        var height_this_line: i32 = 0;
        var last_ch: u8 = 0;
        for (text) |ch| {
            if (ch == '\n') {
                width = std.math.max(width, width_this_line);
                height += height_this_line;
                width_this_line = 0;
                height_this_line = self.mapGlyph(' ').h;
                continue;
            }
            const glyph_rect = self.mapGlyph(ch);
            width_this_line += glyph_rect.w + self.space + self.kerning(last_ch, ch);
            height_this_line = std.math.max(height_this_line, glyph_rect.h);
            last_ch = ch;
        }
        width_this_line -= self.space;
        width = std.math.max(width, width_this_line);
        height += height_this_line;
        return Rect.init(0, 0, width, height);
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

    pub const HTextAlignment = enum {
        left,
        /// For multiline strings, all lines will be centered based on the longest line.
        center,
        right,
    };

    pub const VTextAlignment = enum {
        top,
        middle,
        bottom,
    };

    pub const DrawTextOptions = struct {
        dest: Rect,
        color: [4]u8 = .{ 255, 255, 255, 255 },
        h_alignment: HTextAlignment = .left,
        v_alignment: VTextAlignment = .middle,
    };

    fn getXStart(alignment: HTextAlignment, dest: Rect, text_measure: Rect, line_measure: Rect) i32 {
        // TODO: work this out on paper and make sure it's correct
        _ = text_measure;
        switch (alignment) {
            .left => return dest.left(),
            .center => return dest.left() + @divFloor(dest.w, 2) - @divFloor(line_measure.w, 2),
            .right => return dest.right() - line_measure.w,
        }
    }

    fn getYStart(alignment: VTextAlignment, dest: Rect, measure: Rect) i32 {
        switch (alignment) {
            .top => return dest.top(),
            .middle => return dest.top() + @divFloor(dest.h, 2) - @divFloor(measure.h, 2),
            .bottom => return dest.bottom() - measure.h,
        }
    }

    pub fn drawText(self: BitmapFont, text: []const u8, opts: DrawTextOptions) void {
        var dims = self.fontspec.measureText(text);
        var dx: i32 = 0;
        var dy = getYStart(opts.v_alignment, opts.dest, dims);
        if (std.mem.indexOfScalar(u8, text, '\n')) |linebreak| {
            const line_dims = self.fontspec.measureText(text[0..linebreak]);
            dx = getXStart(opts.h_alignment, opts.dest, dims, line_dims);
        } else {
            const line_dims = self.fontspec.measureText(text);
            dx = getXStart(opts.h_alignment, opts.dest, dims, line_dims);
        }
        var last_ch: u8 = 0;
        for (text) |ch, i| {
            if (ch == '\n') {
                dy += self.mapGlyph(' ').h;
                dx = opts.dest.x;
                if (std.mem.indexOfScalarPos(u8, text, i + 1, '\n')) |linebreak| {
                    const line_dims = self.fontspec.measureText(text[i + 1 .. linebreak]);
                    dx = getXStart(opts.h_alignment, opts.dest, dims, line_dims);
                } else {
                    const line_dims = self.fontspec.measureText(text[i + 1 ..]);
                    dx = getXStart(opts.h_alignment, opts.dest, dims, line_dims);
                }
                continue;
            }
            const src = self.mapGlyph(ch);
            dx += self.fontspec.kerning(last_ch, ch);
            const dest = Rect.init(
                dx,
                dy,
                src.w,
                src.h,
            );
            self.r_batch.drawQuad(.{
                .src = src.toRectf(),
                .dest = dest.toRectf(),
                .color = opts.color,
            });
            dx += src.w + self.fontspec.space;
            last_ch = ch;
        }
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
