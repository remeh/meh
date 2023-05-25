const std = @import("std");
const Queue = std.atomic.Queue;

const LSPContext = @import("lsp.zig").LSPContext;
const LSPCompletion = @import("lsp.zig").LSPCompletion;
const LSPError = @import("lsp.zig").LSPError;
const LSPMessages = @import("lsp_messages.zig");
const LSPMessageType = @import("lsp.zig").LSPMessageType;
const LSPPosition = @import("lsp.zig").LSPPosition;
const LSPResponse = @import("lsp.zig").LSPResponse;
const U8Slice = @import("u8slice.zig").U8Slice;

/// stdoutThreadContext is used by the thread reading on stdout to communicate
/// with the LSP server thread.
const stdoutThreadContext = struct {
    allocator: std.mem.Allocator,
    child: *std.ChildProcess,
    is_running: std.atomic.Atomic(bool),
    queue: std.atomic.Queue(U8Slice),
};

pub const LSPThread = struct {
    pub fn run(ctx: *LSPContext) !void {
        std.log.debug("starting the LSP thread", .{});
        var requests = std.AutoHashMap(i64, LSPMessageType).init(ctx.allocator);

        // spawn the LSP server process

        var cmd = std.ArrayList([]const u8).init(ctx.allocator);
        defer cmd.deinit();
        var it = std.mem.tokenize(u8, ctx.server_exec, " ");
        while (it.next()) |arg| {
            try cmd.append(arg);
        }
        const slice = try cmd.toOwnedSlice();
        defer ctx.allocator.free(slice);

        var child = std.ChildProcess.init(slice, ctx.allocator);
        child.stdin_behavior = .Pipe;
        child.stdout_behavior = .Pipe;
        child.stderr_behavior = .Ignore;
        try child.spawn();

        // start a thread reading the subprocess stdout
        var stdout_ctx = stdoutThreadContext{
            .allocator = ctx.allocator,
            .child = &child,
            .queue = std.atomic.Queue(U8Slice).init(),
            .is_running = std.atomic.Atomic(bool).init(true),
        };

        const stdout_thread = try std.Thread.spawn(
            std.Thread.SpawnConfig{},
            LSPThread.readFromStdout,
            .{&stdout_ctx},
        );
        stdout_thread.detach();

        // lsp thread mainloop
        // -------------------

        var running: bool = true;
        while (running) {
            // check if the stdout thread is still running, because if it is not,
            // the lsp server thread is useless and should stop.
            // ---------------------------------------------

            var stdout_thread_is_running = stdout_ctx.is_running.load(.Acquire);
            if (!stdout_thread_is_running) {
                running = false;
            }

            // check if the LSP server has returned anything
            // meaningful.
            // ---------------------------------------------

            while (!stdout_ctx.queue.isEmpty()) {
                var node = stdout_ctx.queue.get().?;

                // interpret the JSON received from the LSP server

                if (LSPThread.interpret(ctx.allocator, &requests, node.data.bytes())) |response| {
                    // send it back to the main thread, converted to an LSPResponse
                    if (ctx.allocator.create(Queue(LSPResponse).Node)) |new_node| {
                        new_node.data = response;
                        ctx.response_queue.put(new_node);
                    } else |err| {
                        std.log.err("LSPThread.run: can't send a response to the main thread: {}", .{err});
                        response.deinit();
                    }
                } else |err| {
                    std.log.err("LSPThread.run: can't interpret: {}", .{err});
                }

                // free the resources of the data sent by the stdoud thread

                node.data.deinit(); // U8Slice.deinit()
                stdout_ctx.allocator.destroy(node);
            }

            // check if we have a command from the user input
            // to send to the lsp server.
            // ----------------------------------------------

            while (!ctx.send_queue.isEmpty()) {
                var node = ctx.send_queue.get().?;
                // message to stop the lsp server
                // -
                if (std.mem.eql(u8, node.data.json.bytes(), "exit")) {
                    running = false;
                } else {
                    // another kind of message, write it on the lsp server stdin
                    if (child.stdin != null) {
                        // format and write the data on stdin
                        var header = try std.fmt.allocPrint(ctx.allocator, "Content-Length: {d}\r\n\r\n", .{node.data.json.bytes().len});
                        // std.log.debug("request dump: {s}{s}", .{ header, node.data.json.bytes() });
                        _ = try child.stdin.?.write(header);
                        ctx.allocator.free(header);
                        _ = child.stdin.?.write(node.data.json.bytes()) catch |err| {
                            std.log.err("lspThread: can't send to the server: {}", .{err});
                        };

                        // store the request infos needed for later interpretation of the response
                        requests.put(node.data.request_id, node.data.message_type) catch |err| {
                            std.log.err("LSPThread.run: can't store request information: {}", .{err});
                        };
                    }
                }
                // release the request memory and the node memory
                node.data.deinit();
                ctx.allocator.destroy(node);
            }

            std.os.nanosleep(0, 100_000_000); // TODO(remy): replace with epoll/kqueue?
        }

        ctx.is_running.store(false, .Release);

        // kill the LSP server process
        _ = try child.kill();

        requests.deinit();
        drainQueues(ctx, &stdout_ctx);

        std.log.debug("leaving the LSP thread", .{});
    }

    fn drainQueues(ctx: *LSPContext, stdout_ctx: *stdoutThreadContext) void {
        while (!stdout_ctx.queue.isEmpty()) {
            var node = stdout_ctx.queue.get().?;
            node.data.deinit();
            stdout_ctx.allocator.destroy(node);
        }
        while (!ctx.send_queue.isEmpty()) {
            var node = ctx.send_queue.get().?;
            node.data.deinit();
            ctx.allocator.destroy(node);
        }
    }

    /// readFromStdout reads output from the LSP server and generates LSPResponse to send
    /// if there is anything to send to the main thread.
    /// Has to be executed in its own thread, this one will stop on its own since it will
    /// see the stdout handle being unavailable when we tear down the LSP server.
    fn readFromStdout(ctx: *stdoutThreadContext) !void {
        var rv = std.ArrayList(LSPResponse).init(ctx.allocator);
        errdefer rv.deinit();

        if (ctx.child.stdout == null) {
            return;
        }

        var slice = U8Slice.initEmpty(ctx.allocator);
        errdefer slice.deinit();

        const block_size = 64 * 1024;
        var array: [block_size]u8 = undefined;
        var buff = &array;
        var read: usize = block_size;

        std.log.debug("reading thread started", .{});

        var poll_fds = [_]std.os.pollfd{
            .{ .fd = ctx.child.stdout.?.handle, .events = std.os.POLL.IN, .revents = undefined },
        };

        const timeout = 1000; // ms
        const err_mask = std.os.POLL.ERR | std.os.POLL.NVAL | std.os.POLL.HUP;

        while (true) {
            const events = try std.os.poll(&poll_fds, timeout);
            if (events == 0) {
                continue; // timeout
            }

            if (ctx.child.stdout == null) {
                break;
            }

            if (poll_fds[0].revents & std.os.POLL.IN != 0) {
                // one of the error happened, most likely the lsp server which has been
                // teared down, just leave.
                if (poll_fds[0].revents & err_mask != 0) {
                    break;
                }

                // read available data
                read = std.os.read(ctx.child.stdout.?.handle, buff) catch |err| {
                    // it has been closed since, it means that the LSP server has been teared down.
                    if (err == error.NotOpenForReading) {
                        break;
                    } else {
                        return err;
                    }
                };

                // if anything has been read
                if (read > 0) {
                    // FIXME(remy): recompose lines using \n
                    try slice.appendConst(buff[0..read]);

                    // send the data to the lsp server thread
                    if (ctx.allocator.create(std.atomic.Queue(U8Slice).Node)) |new_node| {
                        if (slice.copy(ctx.allocator)) |copy| {
                            new_node.data = copy;
                            ctx.queue.put(new_node);
                        } else |err| {
                            std.log.err("LSPThread.readFromStdout: can't copy the json: {}", .{err});
                            ctx.allocator.destroy(new_node);
                        }
                    } else |err| {
                        std.log.err("LSPThread.readFromStdout: can't create node entry: {}", .{err});
                    }

                    slice.reset();
                }
            } else {
                // not in ready state, is it in error state?
                if (poll_fds[0].revents & err_mask != 0) {
                    break;
                }
            }
        }

        ctx.is_running.store(false, .Release);
        std.log.debug("reading thread stopped", .{});

        return;
    }

    fn interpret(allocator: std.mem.Allocator, requests: *std.AutoHashMap(i64, LSPMessageType), response: []const u8) !LSPResponse {
        // isolate the json
        var idx = std.mem.indexOf(u8, response, "{");
        if (idx == null) {
            return LSPError.MalformedResponse;
        }

        const json_params = std.json.ParseOptions{ .ignore_unknown_fields = true };
        if (std.json.parseFromSlice(LSPMessages.headerResponse, allocator, response, json_params)) |header| {
            defer std.json.parseFree(LSPMessages.headerResponse, allocator, header);

            // read the rest depending on the message type

            if (requests.get(header.id)) |message_type| {
                var rv = LSPResponse.init(allocator, header.id, message_type);
                errdefer rv.deinit();

                switch (message_type) {
                    .Completion => try LSPThread.interpretCompletion(allocator, &rv, response, idx.?),
                    .Definition => LSPThread.interpretDefinition(allocator, &rv, response, idx.?),
                    .References => try LSPThread.interpretReferences(allocator, &rv, response, idx.?),
                    else => {},
                }

                return rv;
            }
        } else |_| {
            // the header has no request ID, it must be a notification
            return LSPThread.readNotification(allocator, response, idx.?);
        }

        return LSPError.MissingRequestEntry;
    }

    fn interpretCompletion(allocator: std.mem.Allocator, rv: *LSPResponse, response: []const u8, json_start_idx: usize) !void {
        const json_params = std.json.ParseOptions{ .ignore_unknown_fields = true };

        rv.*.completions = std.ArrayList(LSPCompletion).init(allocator);

        const completions = try std.json.parseFromSlice(LSPMessages.completionsResponse, allocator, response[json_start_idx..], json_params);
        defer std.json.parseFree(LSPMessages.completionsResponse, allocator, completions);

        if (completions.result) |result| {
            if (result.items) |items| {
                for (items) |item| {
                    if (item.toLSPCompletion(allocator)) |completion| {
                        rv.completions.?.append(completion) catch |err| {
                            std.log.err("LSPThread.interpret: can't append completion: {}", .{err});
                        };
                    } else |err| {
                        std.log.err("LSPThread.interpret: can't convert to LSPCompletion: {}", .{err});
                    }
                }
            }
        }

        if (rv.*.completions) |comps| {
            if (comps.items.len == 0) {
                comps.deinit();
                rv.*.completions = null;
            }
        }
    }

    fn interpretDefinition(allocator: std.mem.Allocator, rv: *LSPResponse, response: []const u8, json_start_idx: usize) void {
        const json_params = std.json.ParseOptions{ .ignore_unknown_fields = true };

        // Some LSP servers return only one result (an object), some returns
        // an array, through trial and error we have to test both.

        rv.*.definitions = std.ArrayList(LSPPosition).init(allocator);

        // single value JSON
        if (std.json.parseFromSlice(LSPMessages.definitionResponse, allocator, response[json_start_idx..], json_params)) |definition| {
            defer std.json.parseFree(LSPMessages.definitionResponse, allocator, definition);
            if (definition.result) |result| {
                if (result.toLSPPosition(allocator)) |position| {
                    rv.*.definitions.?.append(position) catch |err| {
                        std.log.err("LSPThread.interpret: can't append position: {}", .{err});
                    };
                } else |err| {
                    std.log.err("LSPThread.interpret: can't convert to LSPPosition: {}", .{err});
                }
            }
        } else |_| {
            // multiple value JSON, reset the JSON token stream
            if (std.json.parseFromSlice(LSPMessages.definitionsResponse, allocator, response[json_start_idx..], json_params)) |definitions| {
                defer std.json.parseFree(LSPMessages.definitionsResponse, allocator, definitions);

                if (definitions.result) |results| {
                    for (results) |result| {
                        if (result.toLSPPosition(allocator)) |position| {
                            rv.*.definitions.?.append(position) catch |err| {
                                std.log.err("LSPThread.interpret: can't append position: {}", .{err});
                            };
                        } else |err| {
                            std.log.err("LSPThread.interpret: can't convert to LSPPosition: {}", .{err});
                        }
                    }
                }
            } else |_| {
                rv.*.definitions = null;
            }
        }

        if (rv.*.definitions) |defs| {
            if (defs.items.len == 0) {
                defs.deinit();
                rv.*.definitions = null;
            }
        }
    }

    fn interpretReferences(allocator: std.mem.Allocator, rv: *LSPResponse, response: []const u8, json_start_idx: usize) !void {
        const json_params = std.json.ParseOptions{ .ignore_unknown_fields = true };
        rv.references = std.ArrayList(LSPPosition).init(allocator);

        const references = try std.json.parseFromSlice(LSPMessages.referencesResponse, allocator, response[json_start_idx..], json_params);
        defer std.json.parseFree(LSPMessages.referencesResponse, allocator, references);

        if (references.result) |refs| {
            for (refs) |result| {
                if (result.toLSPPosition(allocator)) |position| {
                    rv.references.?.append(position) catch |err| {
                        std.log.err("LSPThread.interpret: can't append position: {}", .{err});
                    };
                } else |err| {
                    std.log.err("LSPThread.interpret: can't convert to LSPPosition: {}", .{err});
                }
            }
        }

        if (rv.references.?.items.len == 0) {
            rv.references.?.deinit();
            rv.references = null;
        }
    }

    fn readNotification(allocator: std.mem.Allocator, response: []const u8, json_start_idx: usize) !LSPResponse {
        const json_params = std.json.ParseOptions{ .ignore_unknown_fields = true };
        // read the header only
        const header = try std.json.parseFromSlice(LSPMessages.headerNotificationResponse, allocator, response[json_start_idx..], json_params);
        defer std.json.parseFree(LSPMessages.headerNotificationResponse, allocator, header);

        std.log.debug("received an LSP notification: {s}", .{header.method});
        return LSPError.MissingRequestEntry;
    }
};
