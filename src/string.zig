const std = @import("std");
const assert = std.debug.assert;
const expect = std.testing.expect;

/// U8Slice is a type helper to move []const u8 around in
/// an `std.ArrayList(u8)` instance.
pub const U8Slice = struct {
    allocator: std.mem.Allocator,
    data: std.ArrayList(u8),

    /// initEmpty creates an U8Slice without any data.
    pub fn initEmpty(allocator: std.mem.Allocator) U8Slice {
        return U8Slice{
            .allocator = allocator,
            .data = std.ArrayList(u8).init(allocator),
        };
    }

    /// initFromSlice creates an U8Slice with the given string in a slice of const u8.
    pub fn initFromSlice(allocator: std.mem.Allocator, str: []const u8) !U8Slice {
        var rv = initEmpty(allocator);
        try rv.data.appendSlice(str);
        return rv;
    }

    /// size returns the size in bytes of the U8Slice.
    pub fn size(self: U8Slice) usize {
        return self.data.items.len;
    }

    /// deinit releases memory used by the U8Slice.
    pub fn deinit(self: U8Slice) void {
        self.data.deinit();
    }
};

test "init_empty" {
    const allocator = std.testing.allocator;
    var str = U8Slice.initEmpty(allocator);
    try expect(0 == str.size());
    str.deinit();
}

test "init_from_slice_and_size_without_utf8" {
    const allocator = std.testing.allocator;
    var str = try U8Slice.initFromSlice(allocator, "hello world!");
    try expect(str.size() == 12);
    str.deinit();
}

test "init_from_slice_and_size_with_utf8" {
    const allocator = std.testing.allocator;
    var str = try U8Slice.initFromSlice(allocator, "hello world 😃");
    try expect(str.size() == 16);
    str.deinit();
}
