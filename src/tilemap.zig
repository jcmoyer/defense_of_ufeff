const std = @import("std");
const Allocator = std.mem.Allocator;

/// Flags used to determine collision when entering a tile.
pub const CollisionFlags = packed struct {
    from_right: bool,
    from_left: bool,
    from_top: bool,
    from_bottom: bool,

    pub fn initAll() CollisionFlags {
        return .{
            .from_right = true,
            .from_left = true,
            .from_top = true,
            .from_bottom = true,
        };
    }

    pub fn initNone() CollisionFlags {
        return .{
            .from_right = false,
            .from_left = false,
            .from_top = false,
            .from_bottom = false,
        };
    }

    pub fn flagOr(a: CollisionFlags, b: CollisionFlags) CollisionFlags {
        return .{
            .from_right = a.from_right or b.from_right,
            .from_left = a.from_left or b.from_left,
            .from_top = a.from_top or b.from_top,
            .from_bottom = a.from_bottom or b.from_bottom,
        };
    }

    pub fn all(self: CollisionFlags) bool {
        return self.from_right and self.from_left and self.from_top and self.from_bottom;
    }

    pub fn none(self: CollisionFlags) bool {
        return !(self.from_right or self.from_left or self.from_top or self.from_bottom);
    }
};

pub const TileBank = enum(u8) {
    none,
    terrain,
    special,
};

pub const TileLayer = enum {
    base,
    detail,
};

pub const Tile = struct {
    id: u16,
    bank: TileBank,
    reserved: u8 = 0,

    pub fn isWater(self: Tile) bool {
        return self.bank == .terrain and self.id == 26;
    }

    // TODO: this should probably be data driven, maybe we can specify this in tiled?
    pub fn getCollisionFlags(self: Tile) CollisionFlags {
        return switch (self.bank) {
            .none => CollisionFlags.initNone(),
            .terrain => self.getTerrainCollisionFlags(),
            .special => self.getSpecialCollisionFlags(),
        };
    }

    fn getTerrainCollisionFlags(self: Tile) CollisionFlags {
        return switch (self.id) {
            24...25 => CollisionFlags.initNone(),
            else => CollisionFlags.initAll(),
        };
    }

    fn getSpecialCollisionFlags(self: Tile) CollisionFlags {
        return switch (self.id) {
            70...72, 74...76, 78...79 => CollisionFlags.initNone(),
            else => CollisionFlags.initAll(),
        };
    }
};

pub const Tilemap = struct {
    width: usize = 0,
    height: usize = 0,
    tiles: []Tile = &[_]Tile{},

    pub fn init(allocator: Allocator, width: usize, height: usize) !Tilemap {
        var tiles = try allocator.alloc(Tile, 2 * width * height);
        return Tilemap{
            .width = width,
            .height = height,
            .tiles = tiles,
        };
    }

    pub fn deinit(self: *Tilemap, allocator: Allocator) void {
        if (self.tiles.len != 0) {
            allocator.free(self.tiles);
        }
    }

    pub fn tileCount(self: Tilemap) usize {
        return self.width * self.height;
    }

    pub fn at2DPtr(self: Tilemap, layer: TileLayer, x: usize, y: usize) *Tile {
        return &self.tiles[self.layerStart(layer) + y * self.width + x];
    }

    pub fn atScalarPtr(self: Tilemap, layer: TileLayer, i: usize) *Tile {
        return &self.tiles[self.layerStart(layer) + i];
    }

    fn layerStart(self: Tilemap, layer: TileLayer) usize {
        return self.tileCount() * @enumToInt(layer);
    }

    pub fn isValidIndex(self: Tilemap, x: usize, y: usize) bool {
        return x < self.width and y < self.height;
    }

    pub fn getCollisionFlags2D(self: Tilemap, x: usize, y: usize) CollisionFlags {
        return self.at2DPtr(.base, x, y).getCollisionFlags().flagOr(self.at2DPtr(.detail, x, y).getCollisionFlags());
    }
};
