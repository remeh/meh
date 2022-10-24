const std = @import("std");
const expect = std.testing.expect;

const U8Slice = @import("u8slice.zig").U8Slice;
const Vec2i = @import("vec.zig").Vec2i;

pub const BufferError = error{
    OutOfBuffer,
};

// TODO(remy): comment
pub const Buffer = struct {
    /// allocator used for all things allocated by this buffer instance.
    allocator: std.mem.Allocator,
    /// in_ram_only indicates there is not file backing this buffer storage.
    in_ram_only: bool,
    /// filepath is the filepath to the file backing this buffer storage.
    filepath: U8Slice,
    /// lines is the content if this Buffer.
    lines: std.ArrayList(U8Slice),

    // Constructors
    // ------------

    /// init_empty initializes an empty buffer.
    // TODO(remy): better comment
    pub fn initEmpty(allocator: std.mem.Allocator) !Buffer {
        return Buffer{
            .allocator = allocator,
            .in_ram_only = true,
            .filepath = U8Slice.initEmpty(allocator),
            .lines = std.ArrayList(U8Slice).init(allocator),
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
            .lines = std.ArrayList(U8Slice).init(allocator),
        };

        rv.in_ram_only = false;

        var file = try std.fs.cwd().openFile(filepath, .{});
        defer file.close();

        // TODO(remy): move this file reading into a separate method.
        // NOTE(remy): should we consider using an ArenaAllocator to read the file?
        // (using stats first to know file size)

        // read the file

        const block_size = 4096;
        var slice: [4096]u8 = undefined;
        var buff = &slice;
        var read: usize = block_size;

        var buf_reader = std.io.bufferedReader(file.reader());
        var u8slice = U8Slice.initEmpty(allocator);
        var i: usize = 0;
        var last_append: usize = 0;

        // TODO(remy): refactor me
        // TODO(remy): what about performances? test with different block_size on large files
        while (read == block_size) {
            i = 0;
            last_append = 0;

            read = try buf_reader.reader().read(buff);

            while (i < read) : (i += 1) {
                if (buff[i] == '\n') {
                    // append the data left until the \n with the \n included
                    try u8slice.appendConst(buff[last_append .. i + 1]); // allocate the data in an u8slice
                    // append the line in the lines list of the buffer
                    try rv.lines.append(u8slice);
                    // move the cursor in this buffer
                    last_append = i + 1;
                    // recreate a new line to work with
                    u8slice = U8Slice.initEmpty(allocator);
                }
            }
            // append the rest of th read buffer
            try u8slice.appendConst(buff[last_append..read]);
        }

        // we completely read the file, if the buffer isn't empty, it means we have
        // dangling data, append it to the buffer.
        if (!u8slice.isEmpty()) {
            try rv.lines.append(u8slice);
        }

        std.log.debug("Buffer.initFromFile: read file {s}, lines count: {d}", .{ filepath, rv.lines.items.len });

        return rv;
    }

    fn dump(self: Buffer) void {
        var i: usize = 0;
        for (self.lines.items) |str| {
            std.log.debug("line {d}: {s}", .{ i, str.data.items });
            i += 1;
        }
    }

    pub fn deinit(self: *Buffer) void {
        for (self.lines.items) |line| {
            line.deinit();
        }
        self.lines.deinit();
        self.filepath.deinit();
    }

    // Methods
    // -------

    // TODO(remy): comment
    // TODO(remy): unit test
    /// Returns a pointer for the caller to be able to modify the line, however, the
    /// pointer should never be null.
    pub fn getLine(self: Buffer, line_number: u64) !*U8Slice {
        if (line_number + 1 > self.lines.items.len) {
            std.log.err("getLinePos: line_number out of bounds: line_number: {d}, self.lines.items.len: {d}", .{ line_number, self.lines.items.len });
            return BufferError.OutOfBuffer;
        }
        return &self.lines.items[line_number];
    }
};

test "init_empty" {
    const allocator = std.testing.allocator;
    var buffer = try Buffer.initEmpty(allocator);
    try expect(buffer.lines.items.len == 0);
    try expect(buffer.filepath.isEmpty() == true);
    try expect(buffer.in_ram_only == true);
    buffer.deinit();
}

test "init_from_file" {
    const allocator = std.testing.allocator;
    var buffer = try Buffer.initFromFile(allocator, "tests/sample_1");
    try expect(buffer.in_ram_only == false);
    try expect(buffer.lines.items.len == 1);
    try expect(std.mem.eql(u8, buffer.filepath.bytes(), "tests/sample_1"));
    try expect(std.mem.eql(u8, buffer.lines.items[0].bytes(), "hello world\n"));
    buffer.deinit();
}
