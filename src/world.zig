const tmod = @import("tilemap.zig");
const std = @import("std");
const Allocator = std.mem.Allocator;
const anim = @import("animation.zig");
const Direction = @import("direction.zig").Direction;

const Tile = tmod.Tile;
const TileBank = tmod.TileBank;
const Tilemap = tmod.Tilemap;
const TileLayer = tmod.TileLayer;

pub const TileCoord = struct {
    x: usize,
    y: usize,

    fn offset(self: TileCoord, dir: Direction) TileCoord {
        return switch (dir) {
            .left => TileCoord{ .x = self.x -% 1, .y = self.y },
            .right => TileCoord{ .x = self.x +% 1, .y = self.y },
            .up => TileCoord{ .x = self.x, .y = self.y -% 1 },
            .down => TileCoord{ .x = self.x, .y = self.y +% 1 },
        };
    }
};

pub const MoveState = enum {
    idle,
    left,
    right,
    up,
    down,
};

pub const Monster = struct {
    world_x: u32 = 0,
    world_y: u32 = 0,
    mspeed: u32 = 4,
    mstate: MoveState = .idle,
    face: Direction = .down,
    animator: ?anim.Animator = null,

    pub fn setWorldPosition(self: *Monster, new_x: u32, new_y: u32) void {
        self.world_x = new_x;
        self.world_y = new_y;
    }

    pub fn getTilePosition(self: Monster) TileCoord {
        return .{ .x = self.world_x / 16, .y = self.world_y / 16 };
    }

    pub fn update(self: *Monster) void {
        switch (self.mstate) {
            .idle => {},
            .left => self.world_x -= self.mspeed,
            .right => self.world_x += self.mspeed,
            .up => self.world_y -= self.mspeed,
            .down => self.world_y += self.mspeed,
        }

        switch (self.mstate) {
            .idle => {},
            .left, .right => {
                if (self.world_x % 16 == 0) {
                    self.mstate = .idle;
                }
            },
            .up, .down => {
                if (self.world_y % 16 == 0) {
                    self.mstate = .idle;
                }
            },
        }
    }

    pub fn beginMove(self: *Monster, f: Direction) void {
        self.mstate = switch (f) {
            .left => .left,
            .up => .up,
            .right => .right,
            .down => .down,
        };
        self.setFacing(f);
    }

    pub fn setFacing(self: *Monster, f: Direction) void {
        self.face = f;
        self.setAnimationFromFacing();
    }

    pub fn setAnimationFromFacing(self: *Monster) void {
        if (self.animator) |*a| {
            const anim_name = @tagName(self.face);
            a.setAnimation(anim_name);
        }
    }
};

pub const World = struct {
    allocator: Allocator,
    map: Tilemap = .{},
    monsters: std.ArrayListUnmanaged(Monster) = .{},
    animan: ?*anim.AnimationManager = null,

    pub fn init(allocator: Allocator) World {
        return .{
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *World) void {
        self.monsters.deinit(self.allocator);
        self.map.deinit(self.allocator);
    }

    pub fn getWidth(self: World) usize {
        return self.map.width;
    }

    pub fn getHeight(self: World) usize {
        return self.map.height;
    }

    pub fn spawnMonsterWorld(self: *World, world_x: u32, world_y: u32) !void {
        try self.monsters.append(self.allocator, Monster{
            .world_x = world_x,
            .world_y = world_y,
        });
    }

    pub fn update(self: *World) void {
        for (self.monsters.items) |*m| {
            m.update();
        }
    }

    pub fn tryMove(self: *World, mobid: usize, dir: Direction) bool {
        var m = &self.monsters.items[mobid];

        // cannot interrupt an object that is already moving
        if (m.mstate != .idle) {
            return false;
        }

        const coord_now = m.getTilePosition();
        const coord_want = coord_now.offset(dir);

        if (!self.map.isValidIndex(coord_want.x, coord_want.y)) {
            return false;
        }

        const flags_x0 = self.map.getCollisionFlags2D(coord_now.x, coord_now.y);
        const flags_x1 = self.map.getCollisionFlags2D(coord_want.x, coord_want.y);

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

        m.beginMove(dir);

        return true;
    }
};

pub fn loadWorldFromJson(allocator: Allocator, filename: []const u8) !World {
    var arena = std.heap.ArenaAllocator.init(allocator);
    var arena_allocator = arena.allocator();
    defer arena.deinit();

    var file = try std.fs.cwd().openFile(filename, .{});
    defer file.close();

    const buffer = try file.readToEndAlloc(arena_allocator, 1024 * 1024);

    var tokens = std.json.TokenStream.init(buffer);
    var doc = try std.json.parse(TiledDoc, &tokens, .{ .allocator = arena_allocator, .ignore_unknown_fields = true });

    var world = World{
        .allocator = allocator,
        .map = try Tilemap.init(allocator, doc.width, doc.height),
    };
    errdefer world.map.deinit(allocator);

    var classifier = BankClassifier{};
    defer classifier.deinit(arena_allocator);

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

    for (doc.layers) |layer| {
        const ctx = LoadContext{
            .arena = arena_allocator,
            .world = &world,
            .classifier = &classifier,
        };
        switch (layer) {
            .tilelayer => |x| try loadTileLayer(x, ctx),
            .objectgroup => |x| try loadObjectGroup(x, ctx),
        }
    }

    return world;
}

const LoadContext = struct {
    arena: Allocator,
    /// Loading data into this world
    world: *World,
    classifier: *const BankClassifier,
};

fn loadTileLayer(layer: TiledTileLayer, ctx: LoadContext) !void {
    var tilemap = ctx.world.map;

    if (layer.encoding == null or !std.mem.eql(u8, layer.encoding.?, "base64")) {
        std.log.err("Map layer is not encoded using base64", .{});
        std.process.exit(1);
    }
    if (layer.compression == null or !std.mem.eql(u8, layer.compression.?, "zlib")) {
        std.log.err("Map layer is not compressed using zlib", .{});
        std.process.exit(1);
    }

    const layer_ints = try b64decompressLayer(ctx.arena, layer.data);
    defer ctx.arena.free(layer_ints);

    if (layer_ints.len != tilemap.tileCount()) {
        std.log.err("Map layer has wrong tile count; got {d} expected {d}", .{ layer_ints, tilemap.tileCount() });
        std.process.exit(1);
    }

    const layer_id = std.meta.stringToEnum(TileLayer, layer.name) orelse {
        std.log.err("Map layer has unknown name; got '{s}'", .{layer.name});
        std.process.exit(1);
    };

    for (layer_ints) |t_tid, i| {
        const result = ctx.classifier.classify(@intCast(u16, t_tid));
        tilemap.atScalarPtr(layer_id, i).* = .{
            .bank = result.bank,
            .id = result.adjusted_tile_id,
        };
    }
}

fn loadObjectGroup(layer: TiledObjectGroup, ctx: LoadContext) !void {
    for (layer.objects) |obj| {
        if (std.mem.eql(u8, obj.class, "spawn_indicator")) {
            // TODO: just for testing
            try ctx.world.spawnMonsterWorld(@intCast(u32, obj.x), @intCast(u32, obj.y));
        }
    }
}

fn b64decompressLayer(allocator: Allocator, data: []const u8) ![]u32 {
    const b64_decode_size = try std.base64.standard.Decoder.calcSizeForSlice(data);
    var b64_decode_buffer = try allocator.alloc(u8, b64_decode_size);
    defer allocator.free(b64_decode_buffer);

    try std.base64.standard.Decoder.decode(b64_decode_buffer, data);

    var fbs = std.io.fixedBufferStream(b64_decode_buffer);
    var b64_reader = fbs.reader();

    var zstream = try std.compress.zlib.zlibStream(allocator, b64_reader);
    var zreader = zstream.reader();

    // enough for a 512x512 map
    const layer_bytes = try zreader.readAllAlloc(allocator, 1024 * 1024);
    // TODO: looks weird, maybe we should explicitly allocate an aligned buffer instead of using readAllAlloc?
    return std.mem.bytesAsSlice(u32, @alignCast(4, layer_bytes));
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

    const ClassifyResult = struct {
        bank: TileBank,
        adjusted_tile_id: u16,
    };

    ranges: std.ArrayListUnmanaged(Range) = .{},

    fn addRange(self: *BankClassifier, allocator: Allocator, bank: TileBank, firstgid: u16) !void {
        if (self.getLastRange()) |ptr| {
            ptr.last = firstgid;
        }
        try self.ranges.append(allocator, Range{
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

    fn classify(self: BankClassifier, id: u16) ClassifyResult {
        if (id == 0) {
            return ClassifyResult{
                .bank = .none,
                .adjusted_tile_id = 0,
            };
        }
        for (self.ranges.items) |r| {
            if (r.contains(id)) {
                return ClassifyResult{
                    .bank = r.bank,
                    .adjusted_tile_id = id - r.first,
                };
            }
        }
        std.log.err("No tile bank for tile {d}", .{id});
        std.process.exit(1);
    }

    fn deinit(self: *BankClassifier, allocator: Allocator) void {
        self.ranges.deinit(allocator);
    }
};

const TiledTileset = struct {
    firstgid: u16,
    source: []const u8,
};

const TiledLayerType = enum {
    tilelayer,
    objectgroup,
};

const TiledTileLayer = struct {
    name: []const u8,
    // Fields for base64 + zlib compressed layers. std.json.parse will fail
    // for uncompressed documents because tile IDs will overflow u8.
    // Need to do manual parsing to support both formats I guess?
    data: []const u8,
    compression: ?[]const u8 = null,
    encoding: ?[]const u8 = null,
};

const TiledObjectGroup = struct {
    name: []const u8,
    objects: []TiledObject,
};

const TiledObject = struct {
    name: []const u8,
    class: []const u8,
    x: i32,
    y: i32,
    width: i32,
    height: i32,
};

const TiledLayer = union(TiledLayerType) {
    tilelayer: TiledTileLayer,
    objectgroup: TiledObjectGroup,
};

const TiledDoc = struct {
    width: usize,
    height: usize,
    tilesets: []TiledTileset,
    layers: []TiledLayer,
};
