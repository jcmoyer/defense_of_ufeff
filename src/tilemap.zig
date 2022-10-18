const std = @import("std");
const Allocator = std.mem.Allocator;

pub const TileBank = enum(u8) {
    none,
    terrain,
    special,
};

pub const Tile = struct {
    id: u16,
    bank: TileBank,
    reserved: u8 = 0,
};

pub const Tilemap = struct {
    width: usize = 0,
    height: usize = 0,
    tiles: []Tile = &[_]Tile{},

    pub fn deinit(self: *Tilemap, allocator: Allocator) void {
        if (self.tiles.len != 0) {
            allocator.free(self.tiles);
        }
    }

    pub fn tileCount(self: Tilemap) usize {
        return self.width * self.height;
    }

    pub fn at2DPtr(self: Tilemap, x: usize, y: usize) *Tile {
        return &self.tiles[y * self.width + x];
    }

    pub fn atScalarPtr(self: Tilemap, i: usize) *Tile {
        return &self.tiles[i];
    }
};

pub fn loadTilemapFromJson(allocator: Allocator, filename: []const u8) !Tilemap {
    const TiledTileset = struct {
        firstgid: u16,
        source: []const u8,
    };
    const TiledLayer = struct {
        name: []const u8,
        data: []u16,
    };
    const TiledDoc = struct {
        width: usize,
        height: usize,
        tilesets: []TiledTileset,
        layers: []TiledLayer,
    };

    var arena = std.heap.ArenaAllocator.init(allocator);
    var arena_allocator = arena.allocator();
    defer arena.deinit();

    var file = try std.fs.cwd().openFile(filename, .{});
    defer file.close();

    const buffer = try file.readToEndAlloc(arena_allocator, 1024 * 1024);

    var tokens = std.json.TokenStream.init(buffer);
    var doc = try std.json.parse(TiledDoc, &tokens, .{ .allocator = arena_allocator, .ignore_unknown_fields = true });

    var tm = Tilemap{
        .width = doc.width,
        .height = doc.height,
        .tiles = try allocator.alloc(Tile, doc.width * doc.height),
    };
    errdefer tm.deinit(allocator);

    // goes in arena, no need to free
    var classifier = BankClassifier{};

    for (doc.tilesets) |t_tileset| {
        if (std.mem.eql(u8, t_tileset.source, "terrain.tsx")) {
            try classifier.addRange(arena_allocator, .terrain, t_tileset.firstgid);
        } else if (std.mem.eql(u8, t_tileset.source, "special.tsx")) {
            try classifier.addRange(arena_allocator, .special, t_tileset.firstgid);
        } else {
            std.log.err("Unrecognized tileset source: '{s}' from '{s}'", .{ t_tileset.source, filename });
            std.process.exit(1);
        }
    }

    for (doc.layers) |t_layer| {
        if (t_layer.data.len != tm.tileCount()) {
            std.log.err("Map layer has wrong tile count; got {d} expected {d}", .{ t_layer.data.len, tm.tileCount() });
            std.process.exit(1);
        }
        for (t_layer.data) |t_tid, i| {
            const bank = classifier.classify(t_tid);
            tm.atScalarPtr(i).* = .{
                .bank = bank,
                .id = if (bank != .none) t_tid - 1 else 0,
            };
        }
        // only load one layer for now
        break;
    }

    return tm;
}

// for tiled tilesets
const BankClassifier = struct {
    const Range = struct {
        bank: TileBank,
        first: u16,
        last: u16,

        /// [first,last)
        fn contains(self: Range, val: u16) bool {
            return val >= self.first and val < self.last;
        }
    };

    ranges: std.ArrayListUnmanaged(Range) = .{},

    fn addRange(self: *BankClassifier, a: Allocator, bank: TileBank, firstgid: u16) !void {
        if (self.getLastRange()) |ptr| {
            ptr.last = firstgid;
        }
        try self.ranges.append(a, Range{
            .bank = bank,
            .first = firstgid,
            .last = std.math.maxInt(u16),
        });
    }

    fn getLastRange(self: BankClassifier) ?*Range {
        if (self.ranges.items.len == 0) {
            return null;
        }
        return &self.ranges.items[self.ranges.items.len - 1];
    }

    fn classify(self: BankClassifier, id: u16) TileBank {
        if (id == 0) {
            return .none;
        }
        for (self.ranges.items) |r| {
            if (r.contains(id)) {
                return r.bank;
            }
        }
        std.log.err("No tile bank for tile {d}", .{id});
        std.process.exit(1);
    }
};
