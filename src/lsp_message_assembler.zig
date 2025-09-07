const std = @import("std");

const U8Slice = @import("u8slice.zig").U8Slice;

/// MessageAssembler receives responses from an LSP server on its `next()`
/// function and returns assembled messages if a message is complete.
/// Otherwise, it buffers until completing the message.
pub const MessageAssembler = struct {
    allocator: std.mem.Allocator,
    /// when we need to buffer some chunks because the message is incomplete
    /// and need to be reassembled, buffer contains what we already had
    buffer: U8Slice,
    /// when we read the content length in a previous message and the
    /// message wasn't fully assembled, it's planned size is available here.
    buffer_planned_length: usize,

    pub fn init(allocator: std.mem.Allocator) MessageAssembler {
        return MessageAssembler{
            .allocator = allocator,
            .buffer = U8Slice.initEmpty(allocator),
            .buffer_planned_length = 0,
        };
    }

    pub fn deinit(self: *MessageAssembler) void {
        self.buffer.deinit();
        self.buffer_planned_length = 0;
    }

    fn reset(self: *MessageAssembler) void {
        self.buffer.deinit();
        self.buffer = U8Slice.initEmpty(self.allocator);
        self.buffer_planned_length = 0;
    }

    pub fn next(self: *MessageAssembler, response: []const u8) std.ArrayListUnmanaged(U8Slice) {
        var rv = std.ArrayListUnmanaged(U8Slice).empty;
        var done = false;
        var offset: u64 = 0;

        while (!done) {
            const chunk = response[offset..];
            if (chunk.len == 0) {
                done = true;
                break;
            }

            if (self.buffer_planned_length == 0) {
                // we are starting to read a new chunk
                if (!(std.mem.startsWith(u8, chunk, "Content-Length"))) {
                    std.log.err("MessageAssembler: new chunk not starting with a content-length", .{});
                    return rv;
                }

                if (std.mem.indexOf(u8, chunk, "\n")) |eol| {
                    const contentLengthStr = chunk["Content-Length: ".len .. eol - 1];

                    var contentLength: usize = 0;
                    if (std.fmt.parseInt(u32, contentLengthStr, 10)) |v| {
                        contentLength = v;
                        self.buffer_planned_length = contentLength;
                    } else |err| {
                        std.log.debug("MessageAssembler: can't convert content-length '{s}': {}", .{ contentLengthStr, err });
                    }

                    // The format is like this:
                    // Content-Length: 23\r\n\r\n{...
                    // I indexed the first \n, but we have 3 more bytes of line returns chars,
                    // hence the +3 below.
                    const lr = eol + 3;

                    if (chunk.len >= lr + contentLength) {
                        defer {
                            self.reset();
                        }
                        var message = U8Slice.initEmpty(self.allocator);
                        message.appendConst(chunk[lr .. lr + contentLength]) catch |err| {
                            std.log.err("MessageAssembler.append: can't append to buffer (fit): {}", .{err});
                            return rv;
                        };

                        rv.append(self.allocator, message) catch |err| {
                            std.log.err("MessageAssembler.append: can't append the message: {}", .{err});
                            return rv;
                        };

                        offset += contentLength + lr;
                        done = offset == chunk.len;
                    } else {
                        // append to the buffer assembly,
                        // the next message will contain the remaining data.
                        self.buffer.appendConst(chunk[lr..]) catch |err| {
                            std.log.err("MessageAssembler.append: can't append to buffer (unfit): {}", .{err});
                            self.reset();
                            return rv;
                        };
                        done = true;
                    }
                } else {
                    std.log.err("MessageAssembler.next: no line return while looking for the Content-Length line", .{});
                    self.reset();
                    return rv;
                }
            } else {
                if (self.buffer_planned_length == 0) {
                    std.log.err("MessageAssembler.append: buffer_planned_length is 0 when it shouldn't", .{});
                    self.reset();
                    return rv;
                }

                // let's look for how much we were missing
                const missing = self.buffer_planned_length - self.buffer.bytes().len;

                // is it part of this one this time?
                if (chunk.len >= missing) {
                    defer {
                        self.reset();
                    }

                    self.buffer.appendConst(chunk[0..missing]) catch |err| {
                        std.log.err("MessageAssembler.append: can't append missing part: {}", .{err});
                        return rv;
                    };

                    const copy = self.buffer.copy(self.allocator) catch |err| {
                        std.log.err("MessageAssembler.append: can't copy to return: {}", .{err});
                        return rv;
                    };

                    rv.append(self.allocator, copy) catch |err| {
                        std.log.err("MessageAssembler.append: can't append the message: {}", .{err});
                        return rv;
                    };

                    offset += missing;
                    done = offset == chunk.len;
                } else {
                    // still won't be enough, append everything
                    self.buffer.appendConst(chunk) catch |err| {
                        std.log.err("MessageAssembler.append: can't append another chunk: {}", .{err});
                        self.reset();
                        return rv;
                    };
                    done = true;
                }
            }

            if (done) {
                return rv;
            }
        }
        return rv;
    }
};

test "LSP message assembler" {
    const allocator = std.testing.allocator;

    var message_assembler = MessageAssembler.init(allocator);
    defer message_assembler.deinit();

    // simple
    // ------

    var messages = message_assembler.next("Content-Length: 9\r\n\r\n{\"a\":\"b\"}");
    for (messages.items) |message| {
        try std.testing.expectEqualStrings("{\"a\":\"b\"}", message.bytes());
        message.deinit();
    }
    messages.deinit(allocator);

    // several in one message
    // ----------------------

    messages = message_assembler.next("Content-Length: 9\r\n\r\n{\"a\":\"b\"}Content-Length: 5\r\n\r\nhello");
    var i: usize = 0;
    for (messages.items) |message| {
        switch (i) {
            0 => try std.testing.expectEqualStrings("{\"a\":\"b\"}", message.bytes()),
            1 => try std.testing.expectEqualStrings("hello", message.bytes()),
            else => try std.testing.expect(false),
        }
        message.deinit();
        i += 1;
    }
    messages.deinit(allocator);

    // one among two messages
    // --------------------------

    messages = message_assembler.next("Content-Length: 9\r\n\r\n{\"a\":");
    for (messages.items) |_| {
        // no message should be returned
        try std.testing.expect(false);
    }
    messages.deinit(allocator);
    messages = message_assembler.next("\"b\"}");
    for (messages.items) |message| {
        try std.testing.expectEqualStrings("{\"a\":\"b\"}", message.bytes());
        message.deinit();
    }
    messages.deinit(allocator);

    // one among two messages with a trailing one
    // -----------------------------------------------

    messages = message_assembler.next("Content-Length: 9\r\n\r\n{\"a\":");
    for (messages.items) |_| {
        // no message should be returned
        try std.testing.expect(false);
    }
    messages.deinit(allocator);
    messages = message_assembler.next("\"b\"}Content-Length: 5\r\n\r\nhello");
    i = 0;
    for (messages.items) |message| {
        switch (i) {
            0 => try std.testing.expectEqualStrings("{\"a\":\"b\"}", message.bytes()),
            1 => try std.testing.expectEqualStrings("hello", message.bytes()),
            else => try std.testing.expect(false),
        }
        message.deinit();
        i += 1;
    }
    messages.deinit(allocator);

    // one among several messages with a trailing one
    // followed by a trailing one
    // -----------------------------------------------

    messages = message_assembler.next("Content-Length: 9\r\n\r\n{\"a\":");
    for (messages.items) |_| {
        // no message should be returned
        try std.testing.expect(false);
    }
    messages.deinit(allocator);

    messages = message_assembler.next("\"b\"");
    for (messages.items) |_| {
        // no message should be returned
        try std.testing.expect(false);
    }
    messages.deinit(allocator);
    messages = message_assembler.next("}Content-Length: 5\r\n\r\nhello");
    i = 0;
    for (messages.items) |message| {
        switch (i) {
            0 => try std.testing.expectEqualStrings("{\"a\":\"b\"}", message.bytes()),
            1 => try std.testing.expectEqualStrings("hello", message.bytes()),
            else => try std.testing.expect(false),
        }
        message.deinit();
        i += 1;
    }
    messages.deinit(allocator);
}
