const std = @import("std");

const U8Slice = @import("string.zig").U8Slice;

// TODO(remy): comment me
pub const Buffer = struct {
    /// allocator used for all things allocated by this buffer instance.
    allocator: std.mem.Allocator,
    /// in_ram_only indicates there is not file backing this buffer storage.
    in_ram_only: bool,
    /// filepath is the filepath to the file backing this buffer storage.
    filepath: U8Slice,
    // TODO(remy): comment me
    data: std.ArrayList(u8),

    /// init_empty initializes an empty buffer.
    // TODO(remy): better comment me
    pub fn initEmpty(allocator: std.mem.Allocator) !Buffer {
        return Buffer{
            .allocator = allocator,
            .in_ram_only = true,
            .filepath = U8Slice.initEmpty(allocator),
            .data = std.ArrayList(u8).init(allocator),
        };
    }

    // initFromFile creates a buffer, reads data from the given filepath
    // copies it in the Buffer instance.
    pub fn initFromFile(allocator: std.mem.Allocator, filepath: []const u8) !Buffer {
        var rv = Buffer{
            .allocator = allocator,
            .in_ram_only = false,
            .filepath = try U8Slice.initFromSlice(allocator, filepath),
            .data = std.ArrayList(u8).init(allocator),
        };
        rv.in_ram_only = false;

        var file = try std.fs.cwd().openFile(filepath, .{});
        defer file.close();
        var buf_reader = std.io.bufferedReader(file.reader());
        try buf_reader.reader().readAllArrayList(&rv.data, 10E9);

        return rv;
    }

    pub fn deinit(self: Buffer) void {
        self.data.deinit();
        self.filepath.deinit();
        self.allocator.destroy(self);
    }
};

// TODO(remy): unit tests initEmpty
// TODO(remy): unit tests initFromFile
