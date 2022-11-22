const std = @import("std");
const assert = std.debug.assert;
const expect = std.testing.expect;

pub const char_space = ' ';
pub const char_tab = '\t';
pub const char_linereturn = '\n';
pub const string_space = " ";

pub const U8SliceError = error{
    OutOfLine,
};

/// U8Slice is a type helper to move []const u8 around in
/// an `std.ArrayList(u8)` instance.
pub const U8Slice = struct {
    allocator: std.mem.Allocator,
    data: std.ArrayList(u8),

    // Constructors
    // ------------

    /// initEmpty creates an U8Slice without any data.
    pub fn initEmpty(allocator: std.mem.Allocator) U8Slice {
        return U8Slice{
            .allocator = allocator,
            .data = std.ArrayList(u8).init(allocator),
        };
    }

    // initFromChar creates an U8Slice with only the given cahr as content.
    pub fn initFromChar(allocator: std.mem.Allocator, ch: u8) !U8Slice {
        var rv = initEmpty(allocator);
        try rv.data.append(ch);
        return rv;
    }

    /// initFromSlice creates an U8Slice with the given bytes in a slice of const u8.
    pub fn initFromSlice(allocator: std.mem.Allocator, str: []const u8) !U8Slice {
        var rv = initEmpty(allocator);
        try rv.data.appendSlice(str);
        return rv;
    }

    /// initFromCSlice creates an U8Slice with the given bytes.
    pub fn initFromCSlice(allocator: std.mem.Allocator, str: [*c]u8) !U8Slice {
        var rv = initEmpty(allocator);
        var i: usize = 0;
        while (true) : (i += 1) {
            if (str[i] == 0) {
                break;
            }
            try rv.data.append(str[i]);
        }
        return rv;
    }

    // Methods
    // -------

    /// copy creates a new U8Slice copying the data of the current one.
    /// The returned U8Slice is owned by the caller.
    pub fn copy(self: U8Slice) !U8Slice {
        var rv = initEmpty(self.allocator);
        try rv.appendConst(self.bytes());
        return rv;
    }

    /// size returns the size in bytes of the U8Slice.
    pub fn size(self: U8Slice) usize {
        return self.data.items.len;
    }

    /// utf8Size returns the amount of utf8 characters in the U8Slice.
    pub fn utf8size(self: U8Slice) !usize {
        var rv: usize = 0;
        var bytes_pos: usize = 0;
        while (bytes_pos < self.data.items.len) {
            bytes_pos += try std.unicode.utf8ByteSequenceLength(self.data.items[bytes_pos]);
            rv += 1;
        }
        return rv;
    }

    // isEmpty returns true if this U8Slice is an empty slice of bytes.
    pub fn isEmpty(self: U8Slice) bool {
        return self.data.items.len == 0;
    }

    /// appendConst appends the given string to the u8slice.
    /// This method allocates memory to store the data.
    pub fn appendConst(self: *U8Slice, str: []const u8) !void {
        try self.data.appendSlice(str);
    }

    /// appendSlice appends the given slice to the current u8slice.
    /// This method allocates memory to store the data.
    pub fn appendSlice(self: *U8Slice, slice: U8Slice) !void {
        try self.data.appendSlice(slice.bytes());
    }

    /// bytes returns the data as a const u8 string.
    pub fn bytes(self: U8Slice) []const u8 {
        return self.data.items;
    }

    /// utf8pos receives a position in character, returns the offset in bytes in the line.
    pub fn utf8pos(self: U8Slice, character_pos: usize) !usize {
        var i: usize = 0;
        var bytes_pos: usize = 0;
        while (i < character_pos) : (i += 1) {
            if (bytes_pos >= self.data.items.len) {
                return U8SliceError.OutOfLine;
            }
            bytes_pos += try std.unicode.utf8ByteSequenceLength(self.data.items[bytes_pos]);
        }
        return bytes_pos;
    }

    /// deinit releases memory used by the U8Slice.
    pub fn deinit(self: U8Slice) void {
        self.data.deinit();
    }
};

test "init_empty" {
    const allocator = std.testing.allocator;
    var str = U8Slice.initEmpty(allocator);
    try expect(str.size() == 0);
    try expect(str.isEmpty() == true);
    str.deinit();
}

test "init_from_slice_and_size_without_utf8" {
    const allocator = std.testing.allocator;
    var str = try U8Slice.initFromSlice(allocator, "hello world!");
    try expect(str.size() == 12);
    try expect(str.isEmpty() == false);
    str.deinit();
}

test "init_from_slice_and_size_with_utf8" {
    const allocator = std.testing.allocator;
    var str = try U8Slice.initFromSlice(allocator, "👻hello world 😃! éà");
    try expect(str.size() == 26);
    try expect(try str.utf8size() == 18);
    try expect(str.isEmpty() == false);
    str.deinit();
}

test "init_from_slice_and_utf8_pos" {
    const allocator = std.testing.allocator;
    var str = try U8Slice.initFromSlice(allocator, "👻hello world 😃! éà");
    try expect(str.isEmpty() == false);
    try expect(try str.utf8pos(0) == 0);
    try expect(try str.utf8pos(1) == 4);
    try expect(try str.utf8pos(2) == 5);
    try expect(try str.utf8pos(12) == 15);
    try expect(try str.utf8pos(13) == 16);
    try expect(try str.utf8pos(14) == 20);
    try expect(try str.utf8pos(15) == 21);
    try expect(try str.utf8pos(16) == 22);
    try expect(try str.utf8pos(17) == 24);
    try expect(try str.utf8pos(18) == 26);
    if (str.utf8pos(19)) |_| {
        try expect(0 == 1); // should never happen since the 19th char is out of bounds
    } else |err| {
        try expect(err == U8SliceError.OutOfLine);
    }
    str.deinit();
}

test "init_from_slice_and_append_data" {
    const allocator = std.testing.allocator;
    var str = try U8Slice.initFromSlice(allocator, "hello world");
    try expect(str.size() == 11);
    try expect(str.isEmpty() == false);
    try str.appendConst("addition");
    try expect(str.size() == 19);
    try expect(str.isEmpty() == false);
    str.deinit();
}
