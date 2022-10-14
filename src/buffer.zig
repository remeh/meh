const std = @import("std");
const expect = std.testing.expect;

const U8Slice = @import("u8slice.zig").U8Slice;

// XXX(remy): A Buffer could track every \n it contains and would know where
// it has lines. Doing so, we would instantly know how many lines there is, we
// would be able to jump directly in the data because we have the position in bytes
// where lines start (i.e. position of a \n + 1), and probably much more.

const LineReturnsQueue = std.TailQueue(u64);

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
    lineReturns: LineReturnsQueue,

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
            .lineReturns = LineReturnsQueue{},
        };
    }

    /// initFromFile creates a buffer, reads data from the given filepath
    /// and copies it in the Buffer instance.
    // TODO(remy): catch properly all errors in htis since it could happen in case of a gigantic file or such
    pub fn initFromFile(allocator: std.mem.Allocator, filepath: []const u8) !Buffer {
        var rv = Buffer{
            .allocator = allocator,
            .in_ram_only = false,
            .filepath = try U8Slice.initFromSlice(allocator, filepath),
            .data = std.ArrayList(u8).init(allocator),
            .lineReturns = LineReturnsQueue{},
        };

        rv.in_ram_only = false;

        var file = try std.fs.cwd().openFile(filepath, .{});
        defer file.close();

        var buf_reader = std.io.bufferedReader(file.reader());
        try buf_reader.reader().readAllArrayList(&rv.data, 10E9);

        try rv.trackLineReturnPositions();

        std.log.debug("Buffer.initFromFile: read file {s}, size: {d}", .{ filepath, rv.data.items.len });

        return rv;
    }

    pub fn deinit(self: *Buffer) void {
        self.data.deinit();
        self.filepath.deinit();

        while (self.lineReturns.pop()) |node| {
            self.allocator.destroy(node);
        }
    }

    // Methods
    // -------

    fn trackLineReturnPositions(self: *Buffer) !void {
        var i: u64 = 0;
        while (i < self.data.items.len) : (i += 1) {
            if (self.data.items[i] == '\n') {
                var node = try self.allocator.create(LineReturnsQueue.Node);
                node.* = LineReturnsQueue.Node{
                    .data = @intCast(u64, i),
                };
                self.lineReturns.append(node);
            }
        }
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
    var buffer = try Buffer.initFromFile(allocator, "tests/sample_2");
    var it = buffer.lineReturns.first;
    try expect(it.?.*.data == 11);
    it = it.?.*.next;
    try expect(it.?.*.data == 29);
    try expect(it.?.*.next == null);

    buffer.deinit();
}
