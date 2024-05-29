const std = @import("std");
const expect = std.testing.expect;

const U8Slice = @import("u8slice.zig").U8Slice;
const Vec2u = @import("vec.zig").Vec2u;
const Vec2i = @import("vec.zig").Vec2i;

pub const BufferError = error{
    OutOfBuffer,
    NoFilepath,
};

/// BufferPosition is used to refer to a position in a given buffer.
pub const BufferPosition = struct {
    fullpath: U8Slice,
    cursor_position: Vec2u,

    pub fn deinit(self: BufferPosition) void {
        self.fullpath.deinit();
    }
};

// TODO(remy): comment
pub const Buffer = struct {
    /// allocator used for all things allocated by this buffer instance.
    allocator: std.mem.Allocator,
    /// in_ram_only indicates there is not file backing this buffer storage.
    in_ram_only: bool,
    /// fullpath is the fullpath to the file backing this buffer storage.
    fullpath: U8Slice,
    /// lines is the content of this Buffer.
    lines: std.ArrayList(U8Slice),

    // Constructors
    // ------------

    /// init_empty initializes an empty buffer.
    /// Creates an initial first line.
    pub fn initEmpty(allocator: std.mem.Allocator) !Buffer {
        const empty_line = U8Slice.initEmpty(allocator);
        var buff = Buffer{
            .allocator = allocator,
            .in_ram_only = true,
            .fullpath = U8Slice.initEmpty(allocator),
            .lines = std.ArrayList(U8Slice).init(allocator),
        };
        try buff.lines.append(empty_line);
        return buff;
    }

    /// initFromFile creates a buffer, reads data from the given fullpath
    /// and copies it in the Buffer instance.
    /// initFromFile calls `trackLineReturnPositions` to start tracking the line returns.
    // TODO(remy): some refactoring (see `App.peekLine`) would be nice here.
    pub fn initFromFile(allocator: std.mem.Allocator, filepath: []const u8) !Buffer {
        // make sure that the provided fullpath is absolute
        const path = try std.fs.realpathAlloc(allocator, filepath);
        defer allocator.free(path);
        var fullpath = U8Slice.initEmpty(allocator);
        try fullpath.appendConst(path);

        var rv = Buffer{
            .allocator = allocator,
            .in_ram_only = false,
            .fullpath = fullpath,
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

        // TODO(remy): refactor
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
                    // recreate a new u8slice to work with for next lines
                    u8slice = U8Slice.initEmpty(allocator);
                }
            }
            // append the rest of the read buffer
            try u8slice.appendConst(buff[last_append..read]);
        }

        // we completely read the file, if the buffer isn't empty, it means we have
        // dangling data, append it to the buffer.
        if (!u8slice.isEmpty()) {
            try rv.lines.append(u8slice);
        }

        var size: usize = 0;
        var length: usize = 0;
        for (rv.lines.items) |line| {
            size += line.data.capacity;
            length += line.data.items.len;
        }

        return rv;
    }

    /// writeOnDisk stores the buffer data in the file (in `fullpath`).
    pub fn writeOnDisk(self: *Buffer) !void {
        if (self.in_ram_only) {
            return;
        }
        if (self.fullpath.size() == 0) {
            return BufferError.NoFilepath;
        }

        // check if the file exists, if not, try creating it
        var file = try (std.fs.cwd().createFile(self.fullpath.bytes(), .{ .truncate = true }));

        // at this point, the file is opened, defer closing it.
        defer file.close();

        var buf_writer = std.io.bufferedWriter(file.writer());
        var bytes_written: usize = 0;

        for (self.lines.items) |line| {
            bytes_written += try buf_writer.writer().write(line.bytes());
        }

        try buf_writer.flush();
        self.in_ram_only = false;
    }

    pub fn deinit(self: *Buffer) void {
        for (self.lines.items) |line| {
            line.deinit();
        }
        self.lines.deinit();
        self.fullpath.deinit();
    }

    // Methods
    // -------

    /// getLine returns a pointer in the buffer to a given line.
    /// `line_number` starts with 0.
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
        return self.lines.orderedRemove(@as(usize, @intCast(line_number)));
    }

    /// longestLine returns the size of the longest line in the lines visible
    /// between the given interval.
    pub fn longestLine(self: *Buffer, line_start: usize, line_end: usize) !usize {
        if (line_start >= self.lines.items.len) {
            return 0;
        }

        var rv: usize = 0;
        var i: usize = line_start;

        while (i < line_end) : (i += 1) {
            if (i < self.lines.items.len) {
                if (self.getLine(i)) |line| {
                    const utf8size = try line.utf8size();
                    rv = @max(utf8size, rv);
                } else |_| {}
            }
        }

        return rv;
    }

    /// linesCount returns how many lines is this buffer containing.
    pub fn linesCount(self: Buffer) usize {
        return self.lines.items.len;
    }

    /// fulltext returns all the text of the buffer in one U8Slice.
    /// Callers has to manage the U8Slice memory.
    // TODO(remy): add line_start and line_end
    // TODO(remy): test
    pub fn fulltext(self: Buffer) !U8Slice {
        var rv = U8Slice.initEmpty(self.allocator);
        for (self.lines.items) |line| {
            try rv.appendConst(line.bytes());
        }
        return rv;
    }
};

test "buffer init_empty" {
    const allocator = std.testing.allocator;
    var buffer = try Buffer.initEmpty(allocator);
    try expect(buffer.lines.items.len == 1);
    try expect(buffer.fullpath.isEmpty() == true);
    try expect(buffer.in_ram_only == true);
    buffer.deinit();
}

test "buffer init_from_file" {
    const allocator = std.testing.allocator;

    var working_dir = U8Slice.initEmpty(allocator);
    defer working_dir.deinit();
    // read cwd
    const working_path = try std.fs.realpathAlloc(allocator, ".");
    defer allocator.free(working_path);
    try working_dir.appendConst(working_path);

    var fullpath = U8Slice.initEmpty(allocator);
    defer fullpath.deinit();

    try fullpath.appendConst(working_dir.bytes());
    try fullpath.appendConst("/");
    var copy = try fullpath.copy(allocator);
    defer copy.deinit();

    try fullpath.appendConst("tests/sample_1");
    var buffer = try Buffer.initFromFile(allocator, "tests/sample_1");
    try expect(buffer.in_ram_only == false);
    try expect(buffer.lines.items.len == 1);
    try expect(std.mem.eql(u8, buffer.fullpath.bytes(), fullpath.bytes()));
    try expect(std.mem.eql(u8, buffer.lines.items[0].bytes(), "hello world\n"));
    buffer.deinit();

    try copy.appendConst("tests/sample_2");
    buffer = try Buffer.initFromFile(allocator, "tests/sample_2");
    try expect(buffer.in_ram_only == false);
    try expect(buffer.lines.items.len == 3);
    try expect(std.mem.eql(u8, buffer.fullpath.bytes(), copy.bytes()));
    try expect(std.mem.eql(u8, buffer.lines.items[0].bytes(), "hello world\n"));
    try expect(std.mem.eql(u8, buffer.lines.items[1].bytes(), "and a second line\n"));
    try expect(std.mem.eql(u8, buffer.lines.items[2].bytes(), "and a third"));
    buffer.deinit();
}

test "buffer longest_line" {
    const allocator = std.testing.allocator;
    var buffer = try Buffer.initFromFile(allocator, "tests/sample_1");
    try std.testing.expectEqual(buffer.longestLine(0, buffer.lines.items.len), 12);
    buffer.deinit();
    buffer = try Buffer.initFromFile(allocator, "tests/sample_3");
    try std.testing.expectEqual(buffer.longestLine(0, buffer.lines.items.len), 9);
    buffer.deinit();
    buffer = try Buffer.initFromFile(allocator, "tests/sample_5");
    try std.testing.expectEqual(buffer.longestLine(3, 5), 71);
    buffer.deinit();
}

test "buffer write_file" {
    const allocator = std.testing.allocator;
    var buffer_first = try Buffer.initFromFile(allocator, "tests/sample_5");

    // read it and write it in a different file
    var buffer_second = try Buffer.initFromFile(allocator, "tests/sample_5");
    buffer_second.fullpath.deinit();
    buffer_second.fullpath = try U8Slice.initFromSlice(allocator, "tests/sample_5_test");
    try buffer_second.writeOnDisk();

    // close it, read the newly created file
    buffer_second.deinit();
    buffer_second = try Buffer.initFromFile(allocator, "tests/sample_5_test");

    // validate that it contains the correct data
    try std.testing.expectEqual(buffer_first.lines.items.len, buffer_second.lines.items.len);

    var i: usize = 0;
    while (i < buffer_first.lines.items.len) : (i += 1) {
        var left_line = buffer_first.getLine(i) catch {
            try expect(true == false);
            return;
        };
        var right_line = buffer_second.getLine(i) catch {
            try expect(true == false);
            return;
        };
        try std.testing.expectEqualSlices(u8, left_line.bytes(), right_line.bytes());
    }

    // remove the temporary file
    try std.fs.deleteFileAbsolute(buffer_second.fullpath.bytes());

    buffer_first.deinit();
    buffer_second.deinit();
}

test "buffer getLine" {
    const allocator = std.testing.allocator;
    var buffer = try Buffer.initFromFile(allocator, "tests/sample_2");
    defer buffer.deinit();

    // two get should always return the same pointer
    const first_time = try buffer.getLine(0);
    const second_time = try buffer.getLine(0);

    try std.testing.expectEqual(first_time, second_time);
    try std.testing.expectEqualStrings("hello world\n", first_time.bytes());
    try std.testing.expectEqualStrings("hello world\n", second_time.bytes());

    var line = try buffer.getLine(1);
    try std.testing.expectEqualStrings("and a second line\n", line.bytes());
    line = try buffer.getLine(2);
    try std.testing.expectEqualStrings("and a third", line.bytes());

    // can't get more than what's in the buffer
    try std.testing.expectError(BufferError.OutOfBuffer, buffer.getLine(3));
    try std.testing.expectError(BufferError.OutOfBuffer, buffer.getLine(100));
}
