const std = @import("std");
const Allocator = std.mem.Allocator;
const Direction = @import("direction.zig").Direction;

pub const TileCoord = struct {
    x: usize,
    y: usize,

    pub fn worldX(self: TileCoord) u32 {
        return @intCast(u32, self.x * 16);
    }

    pub fn worldY(self: TileCoord) u32 {
        return @intCast(u32, self.y * 16);
    }

    pub fn toScalarCoord(self: TileCoord, ref_width: usize) usize {
        return self.y * ref_width + self.x;
    }

    pub fn manhattan(a: TileCoord, b: TileCoord) usize {
        const dx = @intCast(isize, a.x) - @intCast(isize, b.x);
        const dy = @intCast(isize, a.y) - @intCast(isize, b.y);
        return @intCast(usize, std.math.absInt(dx + dy) catch @panic("manhattan distance of TileCoords too big"));
    }

    /// This seems to be a better A* heuristic than manhattan distance, as the
    /// resulting path doesn't change by placing obstacles next to it.
    pub fn euclideanDistance(a: TileCoord, b: TileCoord) f32 {
        const dx = @intToFloat(f32, a.x) - @intToFloat(f32, b.x);
        const dy = @intToFloat(f32, a.y) - @intToFloat(f32, b.y);
        return std.math.sqrt(dx * dx + dy * dy);
    }

    pub fn offset(self: TileCoord, dir: Direction) TileCoord {
        return switch (dir) {
            .left => TileCoord{ .x = self.x -% 1, .y = self.y },
            .right => TileCoord{ .x = self.x +% 1, .y = self.y },
            .up => TileCoord{ .x = self.x, .y = self.y -% 1 },
            .down => TileCoord{ .x = self.x, .y = self.y +% 1 },
        };
    }

    pub fn directionToAdjacent(self: TileCoord, to: TileCoord) Direction {
        const dx = @intCast(isize, self.x) - @intCast(isize, to.x);
        if (dx == 1) {
            return .left;
        }
        if (dx == -1) {
            return .right;
        }
        const dy = @intCast(isize, self.y) - @intCast(isize, to.y);
        if (dy == 1) {
            return .up;
        }
        if (dy == -1) {
            return .down;
        }
        unreachable;
    }
};

/// Flags used to determine collision when entering a tile.
pub const CollisionFlags = packed struct {
    from_right: bool = false,
    from_left: bool = false,
    from_top: bool = false,
    from_bottom: bool = false,

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

    pub fn from(self: CollisionFlags, dir: Direction) bool {
        return switch (dir) {
            .right => self.from_right,
            .up => self.from_top,
            .down => self.from_bottom,
            .left => self.from_left,
        };
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

pub const TileInstanceFlags = packed struct {
    construction_blocked: bool = false,
    contains_tower: bool = false,
    reserved: u6 = 0,
};

pub const Tile = struct {
    id: u16,
    bank: TileBank,
    flags: TileInstanceFlags = .{},

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
            // Grass (no cliff)
            0...11,
            32...43,
            64...75,
            96...107,
            // Sand (no cliff)
            12...23,
            44...55,
            76...87,
            108...119,
            // Plain tiles
            24...25,
            => CollisionFlags.initNone(),
            136 => .{
                .from_left = true,
                .from_top = true,
            },
            138 => .{
                .from_top = true,
            },
            168 => .{
                .from_left = true,
            },
            else => CollisionFlags.initAll(),
        };
    }

    fn getSpecialCollisionFlags(self: Tile) CollisionFlags {
        return switch (self.id) {
            70...72,
            74...76,
            78...79,
            89,
            => CollisionFlags.initNone(),
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

    /// Simply returns null if the index is invalid. Use with wrapping ops (e.g. -%)
    /// so that 0 - 1 => USIZE_MAX => invalid index
    pub fn at2DPtrOpt(self: Tilemap, layer: TileLayer, x: usize, y: usize) ?*Tile {
        if (!self.isValidIndex(x, y)) {
            return null;
        }
        return self.at2DPtr(layer, x, y);
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

    pub fn isValidMove(self: Tilemap, start: TileCoord, dir: Direction) bool {
        const coord_now = start;
        const coord_want = coord_now.offset(dir);

        if (!self.isValidIndex(coord_want.x, coord_want.y)) {
            return false;
        }

        const dest_tile = self.at2DPtr(.base, coord_want.x, coord_want.y);
        if (dest_tile.flags.contains_tower) {
            return false;
        }

        const flags_x0 = self.getCollisionFlags2D(coord_now.x, coord_now.y);
        const flags_x1 = self.getCollisionFlags2D(coord_want.x, coord_want.y);

        // remember 'dir' is the direction we want to move IN, but it's not the
        // direction we're entering the tile from!
        const entering_from = dir.invert();

        // collides from where we're currently standing
        if (flags_x1.from(entering_from)) {
            return false;
        }

        // We also need to handle the case where e.g. we're on a cliffside,
        // if the cliff is a top-left corner tile like so:
        //             ___
        //            |
        //          A | B
        //            |
        //
        // Tile B will have the flag: collides .from_left, so A->B will be blocked.
        // However, it is also invalid to move from B to A, even though A may be a
        // tile that accepts movement from all directions. To solve this, we need
        // to check both A->B and B->A
        if (flags_x0.from(dir)) {
            return false;
        }

        return true;
    }

    pub fn copyInto(self: Tilemap, dest: *Tilemap) void {
        std.debug.assert(self.width == dest.width and self.height == dest.height);
        std.mem.copy(Tile, dest.tiles, self.tiles);
    }
};
