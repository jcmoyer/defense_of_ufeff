const std = @import("std");
const Allocator = std.mem.Allocator;

/// Very basic slot map. Guarantees dense storage, index stability, amortized
/// O(1) insert, lookup, erase. Does not implement generational indexing.
pub fn SlotMap(comptime T: type) type {
    return struct {
        const Self = @This();

        const TaggedT = struct {
            value: T,
            handle: u32,
        };

        const Index = struct {
            item_index: u32,
            next_free: ?u32,
        };

        items: std.MultiArrayList(TaggedT) = .{},
        indices: std.ArrayListUnmanaged(Index) = .{},
        free_first: ?u32 = null,
        free_last: ?u32 = null,

        pub fn deinit(self: *Self, allocator: Allocator) void {
            self.items.deinit(allocator);
            self.indices.deinit(allocator);
        }

        fn allocateHandle(self: *Self, allocator: Allocator, item_index: u32) !u32 {
            try self.indices.append(allocator, .{
                .item_index = item_index,
                // we set null here because it is intended for the item_index's storage to be written immediately
                // (i.e. this index is *not* a hole)
                .next_free = null,
            });
            return @intCast(u32, self.indices.items.len - 1);
        }

        /// Returns a handle that can be used to access item storage at `item_index`.
        /// Caller promises to write `self.items[item_index]` sometime in the future.
        fn reserveNextHandle(self: *Self, allocator: Allocator, item_index: u32) !u32 {
            var handle: u32 = undefined;
            if (self.free_first) |first| {
                handle = first;
                self.indices.items[first].item_index = item_index;
                self.free_first = self.indices.items[first].next_free;
                self.indices.items[first].next_free = null;
                if (self.free_first == null) {
                    self.free_last = null;
                }
            } else {
                handle = try self.allocateHandle(allocator, item_index);
            }
            return handle;
        }

        pub fn put(self: *Self, allocator: Allocator, value: T) !u32 {
            const handle = try self.reserveNextHandle(allocator, @intCast(u32, self.items.len));
            try self.items.append(allocator, TaggedT{
                .value = value,
                .handle = handle,
            });
            return handle;
        }

        pub fn get(self: Self, handle: u32) T {
            const index = self.indices.items[handle];
            return self.items.items(.value)[index.item_index];
        }

        pub fn getPtr(self: Self, handle: u32) *T {
            const index = self.indices.items[handle];
            return &self.items.items(.value)[index.item_index];
        }

        pub fn erase(self: *Self, handle: u32) void {
            // erase will *always* introduce a new hole in the indices table at `handle`
            if (self.free_last) |last| {
                self.indices.items[last].next_free = handle;
                self.free_last = handle;
                // the existence of free_last implies the existence of free_first, so we don't need to set it
            } else {
                // if free_last does not exist, then there is also no free_first; they both should point to the same hole
                self.free_last = handle;
                self.free_first = self.free_last;
            }

            var index = self.indices.items[handle];
            self.items.swapRemove(index.item_index);

            // if the element being removed is also the last element, there's nothing to update
            if (index.item_index == self.items.len) {
                return;
            }

            const swapped_handle = self.items.items(.handle)[index.item_index];
            self.indices.items[swapped_handle].item_index = index.item_index;
        }

        pub fn slice(self: Self) []T {
            return self.items.items(.value);
        }
    };
}

test "slotmap" {
    var allocator = std.testing.allocator;
    var map = SlotMap([]const u8){};
    defer map.deinit(allocator);

    const i = try map.put(allocator, "hello");
    const j = try map.put(allocator, "world");
    const k = try map.put(allocator, "zig");

    try std.testing.expectEqualStrings("hello", map.get(i));
    try std.testing.expectEqualStrings("world", map.get(j));
    try std.testing.expectEqualStrings("zig", map.get(k));

    map.erase(j);

    try std.testing.expectEqualStrings("hello", map.get(i));
    try std.testing.expectEqualStrings("zig", map.get(k));

    map.erase(k);

    try std.testing.expectEqualStrings("hello", map.get(i));

    const a = try map.put(allocator, "wow");

    try std.testing.expectEqualStrings("hello", map.get(i));
    try std.testing.expectEqualStrings("wow", map.get(a));

    const b = try map.put(allocator, "abc");
    const c = try map.put(allocator, "123");

    try std.testing.expectEqualStrings("abc", map.get(b));
    try std.testing.expectEqualStrings("123", map.get(c));

    // put 3 elements, erased 2, putting us to 1
    // then put 3 more elements
    // so indices should be (3-2)+3
    try std.testing.expect(map.indices.items.len == 4);

    try std.testing.expectEqualStrings("hello", map.slice()[0]);
    try std.testing.expectEqualStrings("wow", map.slice()[1]);
    try std.testing.expectEqualStrings("abc", map.slice()[2]);
    try std.testing.expectEqualStrings("123", map.slice()[3]);
}
