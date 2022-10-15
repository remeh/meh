const std = @import("std");
const expect = std.testing.expect;

const U8Slice = @import("u8slice.zig").U8Slice;

// XXX(remy): A Buffer could track every \n it contains and would know where
// it has lines. Doing so, we would instantly know how many lines there is, we
// would be able to jump directly in the data because we have the position in bytes
// where lines start (i.e. position of a \n + 1), and probably much more.

// TODO(remy): comment me
pub const Buffer = struct {
    /// allocator used for all things allocated by this buffer instance.
    allocator: std.mem.Allocator,
    /// in_ram_only indicates there is not file backing this buffer storage.
    in_ram_only: bool,
    /// filepath is the filepath to the file backing this buffer storage.
    filepath: U8Slice,
    /// data is the content if this Buffer.
    data: std.ArrayList(u8),
    // TODO(remy): comment me
    lineReturns: std.ArrayList(u64),

    // Constructors
    // ------------

    /// init_empty initializes an empty buffer.
    // TODO(remy): better comment me
    pub fn initEmpty(allocator: std.mem.Allocator) !Buffer {
        return Buffer{
            .allocator = allocator,
            .in_ram_only = true,
            .filepath = U8Slice.initEmpty(allocator),
            .data = std.ArrayList(u8).init(allocator),
            .lineReturns = std.ArrayList(u64).init(allocator),
        };
    }

    /// initFromFile creates a buffer, reads data from the given filepath
    /// and copies it in the Buffer instance.
    /// initFromFile calls `trackLineReturnPositions` to start tracking the line returns.
    pub fn initFromFile(allocator: std.mem.Allocator, filepath: []const u8) !Buffer {
        var rv = Buffer{
            .allocator = allocator,
            .in_ram_only = false,
            .filepath = try U8Slice.initFromSlice(allocator, filepath),
            .data = std.ArrayList(u8).init(allocator),
            .lineReturns = std.ArrayList(u64).init(allocator),
        };

        rv.in_ram_only = false;

        var file = try std.fs.cwd().openFile(filepath, .{});
        defer file.close();

        // NOTE(remy): should we consider using an ArenaAllocator to read the file?
        // (using stats first to know its size)

        var buf_reader = std.io.bufferedReader(file.reader());
        try buf_reader.reader().readAllArrayList(&rv.data, 10E10);
        try rv.trackLineReturnPositions();

        std.log.debug("Buffer.initFromFile: read file {s}, size: {d}", .{ filepath, rv.data.items.len });
        std.log.debug("Buffer.initFromFile: counted {d} line returns.", .{rv.lineReturns.items.len});

        return rv;
    }

    pub fn deinit(self: *Buffer) void {
        self.data.deinit();
        self.filepath.deinit();
        self.lineReturns.deinit();
    }

    // Methods
    // -------

    // TODO(remy): comment me
    fn trackLineReturnPositions(self: *Buffer) !void {
        var i: u64 = 0;
        while (i < self.data.items.len) : (i += 1) {
            if (self.data.items[i] == '\n') {
                try self.lineReturns.append(@intCast(u64, i));
            }
        }
    }

    // TODO(remy): comment me
    // TODO(remy): unit test me
    pub fn getLinePos(self: Buffer, line_number: u64) void {
        if (self.lineReturns.items.len < line_number - 1) {
            std.log.err("getLinePos: line_number overflow", .{}); // TODO(remy): return an error
        }

        if (line_number == 1) {
            std.log.debug("[{d};{d}]", .{ 0, self.lineReturns.items[0] });
            return;
        }

        var start_line = self.lineReturns.items[line_number - 2] + 1;
        var end_line = self.lineReturns.items[line_number - 1];
        std.log.debug("[{d};{d}]", .{ start_line, end_line });
    }
};

test "init_empty" {
    const allocator = std.testing.allocator;
    var buffer = try Buffer.initEmpty(allocator);
    try expect(buffer.data.items.len == 0);
    try expect(buffer.filepath.isEmpty() == true);
    try expect(buffer.in_ram_only == true);
    buffer.deinit();
}

test "init_from_file" {
    const allocator = std.testing.allocator;
    var buffer = try Buffer.initFromFile(allocator, "tests/sample_1");
    try expect(buffer.in_ram_only == false);
    try expect(buffer.data.items.len == 12);
    try expect(std.mem.eql(u8, buffer.filepath.bytes(), "tests/sample_1"));
    try expect(std.mem.eql(u8, buffer.data.items, "hello world\n"));
    buffer.deinit();
}

test "track_line_return_positions" {
    const allocator = std.testing.allocator;
    var buffer = try Buffer.initFromFile(allocator, "tests/sample_1");
    try expect(buffer.lineReturns.items.len == 1);
    buffer.deinit();
    buffer = try Buffer.initFromFile(allocator, "tests/sample_2");
    try expect(buffer.lineReturns.items.len == 2);
    try expect(buffer.lineReturns.items[0] == 11);
    try expect(buffer.lineReturns.items[1] == 29);
    buffer.deinit();
}
