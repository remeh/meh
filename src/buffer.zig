const std = @import("std");
const expect = std.testing.expect;

const U8Slice = @import("u8slice.zig").U8Slice;
const Vec2u = @import("vec.zig").Vec2u;
const Vec2i = @import("vec.zig").Vec2i;

pub const BufferError = error{
    OutOfBuffer,
    NoFilepath,
};

// TODO(remy): comment
pub const Buffer = struct {
    /// allocator used for all things allocated by this buffer instance.
    allocator: std.mem.Allocator,
    /// in_ram_only indicates there is not file backing this buffer storage.
    in_ram_only: bool,
    /// filepath is the filepath to the file backing this buffer storage.
    filepath: U8Slice,
    /// lines is the content of this Buffer.
    lines: std.ArrayList(U8Slice),

    // Constructors
    // ------------

    /// init_empty initializes an empty buffer.
    /// Creates an initial first line.
    pub fn initEmpty(allocator: std.mem.Allocator) !Buffer {
        var empty_line = U8Slice.initEmpty(allocator);
        var buff = Buffer{
            .allocator = allocator,
            .in_ram_only = true,
            .filepath = U8Slice.initEmpty(allocator),
            .lines = std.ArrayList(U8Slice).init(allocator),
        };
        try buff.lines.append(empty_line);
        return buff;
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

    // TODO(remy): comment
    // TODO(remy): unit test
    // FIXME(remy): implement should probably be in another file fs.zig
    pub fn writeOnDisk(self: *Buffer) !void {
        if (self.in_ram_only) {
            return;
        }
        if (self.filepath.size() == 0) {
            return BufferError.NoFilepath;
        }

        // check if the file exists, if not, try creating it
        var file = try (std.fs.cwd().createFile(self.filepath.bytes(), .{ .truncate = true }));

        // at this point, the file is opened, defer closing it.
        defer file.close();

        var buf_writer = std.io.bufferedWriter(file.writer());
        var bytes_written: usize = 0;

        for (self.lines.items) |line| {
            bytes_written += try buf_writer.writer().write(line.bytes());
        }

        try buf_writer.flush();
        self.in_ram_only = false;
        std.log.debug("Buffer.writeOnDisk: write file {s}, bytes written: {d}", .{ self.filepath.bytes(), bytes_written });
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
    pub fn getLine(self: Buffer, line_number: usize) !*U8Slice {
        if (line_number + 1 > self.lines.items.len) {
            return BufferError.OutOfBuffer;
        }
        return &self.lines.items[line_number];
    }

    pub fn deleteLine(self: *Buffer, line_number: usize) !U8Slice {
        if (line_number + 1 > self.lines.items.len) {
            return BufferError.OutOfBuffer;
        }
        return self.lines.orderedRemove(@intCast(usize, line_number));
    }

    /// longestLine returns the size of the longest line in the lines visible
    /// between the given interval.
    // TODO(remy): unit test
    pub fn longestLine(self: *Buffer, line_start: usize, line_end: usize) usize {
        if (line_start >= self.lines.items.len) {
            return 0;
        }

        var rv: usize = 0;
        var i: usize = line_start;

        while (i < line_end) : (i += 1) {
            if (i < self.lines.items.len) {
                if (self.getLine(i)) |line| {
                    rv = @max(line.size(), rv);
                } else |_| {}
            }
        }

        return rv;
    }

    /// linesCount returns how many lines is this buffer containing.
    pub fn linesCount(self: Buffer) usize {
        return self.lines.items.len;
    }
};

test "init_empty" {
    const allocator = std.testing.allocator;
    var buffer = try Buffer.initEmpty(allocator);
    try expect(buffer.lines.items.len == 1);
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
    buffer = try Buffer.initFromFile(allocator, "tests/sample_2");
    try expect(buffer.in_ram_only == false);
    try expect(buffer.lines.items.len == 3);
    try expect(std.mem.eql(u8, buffer.filepath.bytes(), "tests/sample_2"));
    try expect(std.mem.eql(u8, buffer.lines.items[0].bytes(), "hello world\n"));
    try expect(std.mem.eql(u8, buffer.lines.items[1].bytes(), "and a second line\n"));
    try expect(std.mem.eql(u8, buffer.lines.items[2].bytes(), "and a third"));
    buffer.deinit();
}
