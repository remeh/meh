const std = @import("std");
const assert = std.debug.assert;
const expect = std.testing.expect;

pub const char_space = ' ';
pub const char_tab = '\t';
pub const char_linereturn = '\n';
pub const string_space = " ";
pub const string_tab = "\t";
pub const string_replacement_character = "�";

pub const U8SliceError = error{
    OutOfLine,
};

pub const UTF8IteratorError = error{
    GlyphOutOfBuffer,
    InvalidByte,
};

/// UTF8Iterator helps you iterate through an UTF8 text.
/// Usage is:
///     var it = UTF8Iterator("my utf8 text", 0); // 0 is the position in glyph you want to start in the text
///     while (true) {
///         // here you can use it.glyph() to get the current glyph
///         // or it.current_glyph_size to get its size in bytes
///         // also, it.current_byte is the position of the glyph in the text
///         if (!it.next()) {
///             break;
///         }
///     }
// TODO(remy): the iterator pattern isn't correct, anyone would expect `while (it.next()) {}`
pub const UTF8Iterator = struct {
    current_byte: usize,
    current_glyph: usize,
    current_glyph_size: usize,
    text: []const u8,

    pub fn init(text: []const u8, start_glyph: usize) !UTF8Iterator {
        if (text.len == 0) {
            return UTF8IteratorError.GlyphOutOfBuffer;
        }

        const glyph_size: usize = std.unicode.utf8ByteSequenceLength(text[0]) catch {
            return UTF8IteratorError.InvalidByte;
        };

        var rv = UTF8Iterator{
            .current_byte = 0,
            .current_glyph = 0,
            .current_glyph_size = glyph_size,
            .text = text,
        };

        var i: usize = start_glyph;
        while (i > 0) : (i -= 1) {
            if (!rv.next()) {
                return rv; // we've reached the last glyph
            }
        }

        return rv;
    }

    /// Compare it.current_byte or it.current_glyph before and after the call
    /// to make sure a move happened.
    pub fn prev(self: *UTF8Iterator) void {
        if (self.current_byte == 0) {
            if (std.unicode.utf8ByteSequenceLength(self.text[self.current_byte])) |size| {
                self.current_glyph_size = size;
            } else |_| {
                // best effort
                self.current_glyph_size = 1;
            }
            self.current_glyph = 0;
            return;
        }

        var byte: usize = self.current_byte;
        while (byte > 0) {
            byte -= 1;
            if (std.unicode.utf8ByteSequenceLength(self.text[byte])) |size| {
                self.current_byte = byte;
                self.current_glyph_size = size;
                self.current_glyph -= 1;
                return;
            } else |_| {
                continue;
            }
        }
    }

    /// next move the iterator forward in the buffer.
    /// Returns true if there is data left, return false if there is none (but still
    /// increase the value a last time).
    pub fn next(self: *UTF8Iterator) bool {
        if (self.text.len <= self.current_byte + self.current_glyph_size) {
            self.current_byte += 1;
            self.current_glyph += self.current_glyph_size;
            self.current_glyph_size = 1;
            return false;
        }

        self.current_byte += self.current_glyph_size;

        const glyph_size: usize = std.unicode.utf8ByteSequenceLength(self.text[self.current_byte]) catch |err| {
            std.log.err("UTF8Iterator.next: can't get glyph size: {}", .{err});
            // best effort
            self.current_byte += 1;
            self.current_glyph += 1;
            self.current_glyph_size = 1;
            return false;
        };

        self.current_glyph += 1;
        self.current_glyph_size = glyph_size;

        return true;
    }

    pub fn glyph(self: UTF8Iterator) []const u8 {
        if (self.current_byte >= self.text.len) {
            std.log.err("UTF8Iterator.glyph: called but iterator is done.", .{});
            return string_replacement_character;
        }
        return self.text[self.current_byte .. self.current_byte + self.current_glyph_size];
    }
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
    pub fn copy(self: U8Slice, allocator: std.mem.Allocator) !U8Slice {
        var rv = initEmpty(allocator);
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
        try self.data.ensureTotalCapacityPrecise(self.data.items.len + str.len);
        self.data.appendSliceAssumeCapacity(str);
    }

    /// appendSlice appends the given slice to the current u8slice.
    /// This method allocates memory to store the data.
    pub fn appendSlice(self: *U8Slice, slice: U8Slice) !void {
        try self.appendConst(slice.bytes());
    }

    /// bytes returns the data as a const u8 string.
    pub fn bytes(self: U8Slice) []const u8 {
        return self.data.items;
    }

    /// utf8pos receives a position in glyph, returns the offset in bytes in the line.
    pub fn utf8pos(self: U8Slice, glyph_pos: usize) !usize {
        var i: usize = 0;
        var bytes_pos: usize = 0;
        while (i < glyph_pos) : (i += 1) {
            if (bytes_pos >= self.data.items.len) {
                return U8SliceError.OutOfLine;
            }
            bytes_pos += try std.unicode.utf8ByteSequenceLength(self.data.items[bytes_pos]);
        }
        return bytes_pos;
    }

    pub fn isOnlyWhitespace(self: U8Slice) bool {
        var it = UTF8Iterator.init(self.bytes(), 0) catch {
            std.log.err("U8Slice.isOnlyWhitespace: can't create an iterator", .{});
            return false;
        };
        while (true) {
            if (!std.mem.eql(u8, it.glyph(), string_space) and !std.mem.eql(u8, it.glyph(), string_tab) and !std.mem.eql(u8, it.glyph(), "\n")) {
                return false;
            }
            if (!it.next()) {
                break;
            }
        }
        return true;
    }

    /// reset resets the content of the U8Slice to not contain anything.
    pub fn reset(self: *U8Slice) void {
        self.data.deinit();
        self.data = std.ArrayList(u8).init(self.allocator);
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

test "iterator basic test" {
    var it = try UTF8Iterator.init("normal string", 0);
    try expect(it.current_byte == 0);
    try expect(it.current_glyph == 0);
    try expect(it.current_glyph_size == 1);
    try expect(std.mem.eql(u8, it.glyph(), "n"));
    it.prev();
    try expect(it.current_byte == 0);
    try expect(it.current_glyph == 0);
    try expect(it.current_glyph_size == 1);
    try expect(std.mem.eql(u8, it.glyph(), "n"));
    try expect(it.next() == true);
    try expect(it.current_byte == 1);
    try expect(it.current_glyph == 1);
    try expect(it.current_glyph_size == 1);
    try expect(std.mem.eql(u8, it.glyph(), "o"));
    try expect(it.next() == true);
    try expect(it.current_byte == 2);
    try expect(it.current_glyph == 2);
    try expect(it.current_glyph_size == 1);
    try expect(std.mem.eql(u8, it.glyph(), "r"));
    it.prev();
    try expect(it.current_byte == 1);
    try expect(it.current_glyph == 1);
    try expect(it.current_glyph_size == 1);
    try expect(std.mem.eql(u8, it.glyph(), "o"));
    it.prev();
    try expect(it.current_byte == 0);
    try expect(it.current_glyph == 0);
    try expect(it.current_glyph_size == 1);
    try expect(std.mem.eql(u8, it.glyph(), "n"));
    it.prev();
    try expect(it.current_byte == 0);
    try expect(it.current_glyph == 0);
    try expect(it.current_glyph_size == 1);
    try expect(std.mem.eql(u8, it.glyph(), "n"));

    var i: usize = 0;
    while (it.next()) {
        i += 1;
    }

    try expect(i == "normal string".len - 1);
    try expect(it.current_byte == "normal string".len);
    try expect(it.current_glyph == "normal string".len);
    try expect(it.current_glyph_size == 1);

    it = try UTF8Iterator.init("normal string", 5);
    try expect(it.current_byte == 5);
    try expect(it.current_glyph == 5);
    try expect(it.current_glyph_size == 1);
    try expect(std.mem.eql(u8, it.glyph(), "l"));
}

test "iterator utf8" {
    var it = try UTF8Iterator.init("one éà 😃👻", 0);
    try expect(it.current_byte == 0);
    try expect(it.current_glyph == 0);
    try expect(it.current_glyph_size == 1);
    try expect(std.mem.eql(u8, it.glyph(), "o"));
    try expect(it.next());
    try expect(it.current_byte == 1);
    try expect(it.current_glyph == 1);
    try expect(it.current_glyph_size == 1);
    try expect(std.mem.eql(u8, it.glyph(), "n"));
    try expect(it.next());
    try expect(it.current_byte == 2);
    try expect(it.current_glyph == 2);
    try expect(it.current_glyph_size == 1);
    try expect(std.mem.eql(u8, it.glyph(), "e"));
    try expect(it.next());
    try expect(it.current_byte == 3);
    try expect(it.current_glyph == 3);
    try expect(it.current_glyph_size == 1);
    try expect(std.mem.eql(u8, it.glyph(), " "));
    try expect(it.next());
    try expect(it.current_byte == 4);
    try expect(it.current_glyph == 4);
    try expect(it.current_glyph_size == 2);
    try expect(std.mem.eql(u8, it.glyph(), "é"));
    try expect(it.next());
    try expect(it.current_byte == 6);
    try expect(it.current_glyph == 5);
    try expect(it.current_glyph_size == 2);
    try expect(std.mem.eql(u8, it.glyph(), "à"));
    try expect(it.next());
    try expect(it.current_byte == 8);
    try expect(it.current_glyph == 6);
    try expect(it.current_glyph_size == 1);
    try expect(std.mem.eql(u8, it.glyph(), " "));
    try expect(it.next());
    try expect(it.current_byte == 9);
    try expect(it.current_glyph == 7);
    try expect(it.current_glyph_size == 4);
    try expect(std.mem.eql(u8, it.glyph(), "😃"));
    try expect(it.next());
    try expect(it.current_byte == 13);
    try expect(it.current_glyph == 8);
    try expect(it.current_glyph_size == 4);
    try expect(std.mem.eql(u8, it.glyph(), "👻"));
    it.prev();
    try expect(it.current_byte == 9);
    try expect(it.current_glyph == 7);
    try expect(it.current_glyph_size == 4);
    try expect(std.mem.eql(u8, it.glyph(), "😃"));
    it.prev();
    try expect(it.current_byte == 8);
    try expect(it.current_glyph == 6);
    try expect(it.current_glyph_size == 1);
    try expect(std.mem.eql(u8, it.glyph(), " "));
    it.prev();
    try expect(it.current_byte == 6);
    try expect(it.current_glyph == 5);
    try expect(it.current_glyph_size == 2);
    try expect(std.mem.eql(u8, it.glyph(), "à"));
    it.prev();
    try expect(it.current_byte == 4);
    try expect(it.current_glyph == 4);
    try expect(it.current_glyph_size == 2);
    try expect(std.mem.eql(u8, it.glyph(), "é"));

    // with start glyph

    it = try UTF8Iterator.init("one éà 😃👻", 3);
    try expect(it.current_byte == 3);
    try expect(it.current_glyph == 3);
    try expect(it.current_glyph_size == 1);
    try expect(std.mem.eql(u8, it.glyph(), " "));

    it = try UTF8Iterator.init("one éà 😃👻", 4);
    try expect(it.current_byte == 4);
    try expect(it.current_glyph == 4);
    try expect(it.current_glyph_size == 2);
    try expect(std.mem.eql(u8, it.glyph(), "é"));

    it = try UTF8Iterator.init("one éà 😃👻", 7);
    try expect(it.current_byte == 9);
    try expect(it.current_glyph == 7);
    try expect(it.current_glyph_size == 4);
    try expect(std.mem.eql(u8, it.glyph(), "😃"));

    it = try UTF8Iterator.init("one éà 😃👻", 8);
    try expect(it.current_byte == 13);
    try expect(it.current_glyph == 8);
    try expect(it.current_glyph_size == 4);
    try expect(std.mem.eql(u8, it.glyph(), "👻"));
}

test "u8slice reset" {
    const allocator = std.testing.allocator;
    var str = try U8Slice.initFromSlice(allocator, "hello world");
    try std.testing.expectEqual(str.bytes().len, 11);
    str.reset();
    try std.testing.expectEqual(str.bytes().len, 0);
    try expect(std.mem.eql(u8, str.bytes(), ""));
    str.deinit();
}
