const std = @import("std");
const Queue = std.atomic.Queue;

const AtomicQueue = @import("atomic_queue.zig").AtomicQueue;
const Buffer = @import("buffer.zig").Buffer;
const LSPMessages = @import("lsp_messages.zig");
const LSPThread = @import("lsp_thread.zig").LSPThread;
const U8Slice = @import("u8slice.zig").U8Slice;
const Vec2u = @import("vec.zig").Vec2u;
const Vec4u = @import("vec.zig").Vec4u;

pub const LSPError = error{
    IncompleteCompletionEntry,
    MalformedResponse,
    MalformedUri,
    MissingRequestEntry,
    UnknownExtension,
};

/// LSPMessageType is the type of the message sent by the LSP server.
pub const LSPMessageType = enum {
    ClearDiagnostics,
    Completion,
    Definition,
    Diagnostic,
    DidChange,
    Hover,
    Initialize,
    Initialized,
    LogMessage,
    TextDocumentDidOpen,
    References,
    // special, used internally to send the signal to stop the LSP server.
    MehExit,
};

/// LSPRequest is used to send a request to the LSP server.
pub const LSPRequest = struct {
    json: U8Slice,
    message_type: LSPMessageType,
    request_id: i64,
    pub fn deinit(self: *LSPRequest) void {
        self.json.deinit();
    }
};

/// LSPResponse is used to transport a message sent from the LSP server back to the main app.
pub const LSPResponse = struct {
    allocator: std.mem.Allocator,
    message_type: LSPMessageType,
    log_message: ?U8Slice, // TODO(remy): shouldn't this be a list of U8Slice instead?
    completions: ?std.ArrayList(LSPCompletion),
    diagnostics: ?std.ArrayList(LSPDiagnostic),
    definitions: ?std.ArrayList(LSPPosition),
    hover: ?std.ArrayList(U8Slice),
    references: ?std.ArrayList(LSPPosition),
    request_id: i64,
    pub fn init(allocator: std.mem.Allocator, request_id: i64, message_type: LSPMessageType) LSPResponse {
        return LSPResponse{
            .allocator = allocator,
            .message_type = message_type,
            .request_id = request_id,
            .completions = null,
            .diagnostics = null,
            .definitions = null,
            .hover = null,
            .references = null,
            .log_message = null,
        };
    }
    pub fn deinit(self: LSPResponse) void {
        if (self.completions) |comps| {
            for (comps.items) |completion| {
                completion.deinit();
            }
            comps.deinit();
        }
        if (self.diagnostics) |diags| {
            for (diags.items) |diag| {
                diag.deinit();
            }
            diags.deinit();
        }
        if (self.definitions) |defs| {
            for (defs.items) |def| {
                def.deinit();
            }
            defs.deinit();
        }
        if (self.hover) |hover| {
            for (hover.items) |item| {
                item.deinit();
            }
            hover.deinit();
        }
        if (self.log_message) |log_message| {
            log_message.deinit();
        }
        if (self.references) |refs| {
            for (refs.items) |ref| {
                ref.deinit();
            }
            refs.deinit();
        }
    }
};

pub const LSPPosition = struct {
    filepath: U8Slice,
    start: Vec2u,
    end: Vec2u,

    pub fn deinit(self: LSPPosition) void {
        self.filepath.deinit();
    }
};

pub const LSPCompletion = struct {
    detail: U8Slice,
    documentation: U8Slice,
    insert_text: U8Slice,
    label: U8Slice,
    sort_text: U8Slice,
    range: ?Vec4u,
    pub fn deinit(self: LSPCompletion) void {
        self.detail.deinit();
        self.insert_text.deinit();
        self.label.deinit();
        self.sort_text.deinit();
        self.documentation.deinit();
    }
};

pub const LSPDiagnostic = struct {
    filepath: U8Slice,
    message: U8Slice,
    range: Vec4u,
    pub fn deinit(self: LSPDiagnostic) void {
        self.filepath.deinit();
        self.message.deinit();
    }
};

// TODO(remy): comment
pub const LSPContext = struct {
    allocator: std.mem.Allocator,
    server_exec: []const u8,
    // queue used to communicate from the LSP thread to the main thread.
    response_queue: AtomicQueue(LSPResponse),
    // queue used to communicate from the main thread to the LSP thread.
    send_queue: AtomicQueue(LSPRequest),
    // LSP server thread is running
    is_running: std.atomic.Value(bool),
};

// TODO(remy): comment
pub const LSP = struct {
    allocator: std.mem.Allocator,
    context: *LSPContext,
    thread: std.Thread,
    current_request_id: i64,
    uri_working_dir: U8Slice,
    language_id: U8Slice,

    pub fn init(allocator: std.mem.Allocator, server_exec: []const u8, language_id: []const u8, working_dir: []const u8) !*LSP {
        // start a thread dealing with the LSP server in the background
        // create two queues for bidirectional communication
        var ctx = try allocator.create(LSPContext);
        ctx.allocator = allocator;
        ctx.response_queue = AtomicQueue(LSPResponse).init();
        ctx.send_queue = AtomicQueue(LSPRequest).init();
        ctx.server_exec = server_exec;

        // spawn the LSP thread
        const thread = try std.Thread.spawn(std.Thread.SpawnConfig{}, LSPThread.run, .{ctx});
        ctx.is_running = std.atomic.Value(bool).init(true);

        var uri_working_dir = try U8Slice.initFromSlice(allocator, "file://");
        try uri_working_dir.appendConst(working_dir);

        var lsp = try allocator.create(LSP);
        lsp.allocator = allocator;
        lsp.context = ctx;
        lsp.thread = thread;
        lsp.uri_working_dir = uri_working_dir;
        lsp.current_request_id = 0;
        lsp.language_id = try U8Slice.initFromSlice(allocator, language_id);
        return lsp;
    }

    pub fn deinit(self: *LSP) void {
        self.uri_working_dir.deinit();

        // send an exit message to the LSP thread
        // it'll process it and close the thread
        // --------------------------------------

        const is_running = self.context.is_running.load(.acquire);
        if (is_running) {
            // send an exit message if the lsp thread is still running

            var exit_msg = U8Slice.initEmpty(self.allocator);
            exit_msg.appendConst("exit") catch |err| {
                std.log.err("LSP.deinit: can't allocate the bytes to send the exit message: {}", .{err});
                return;
            };
            var node = self.allocator.create(AtomicQueue(LSPRequest).Node) catch |err| {
                std.log.err("LSP.deinit: can't allocate the node to send the exit message: {}", .{err});
                return;
            };
            node.data = LSPRequest{
                .json = exit_msg,
                .message_type = .MehExit,
                .request_id = 0,
            };
            self.context.send_queue.put(node);

            // wait for thread to finish
            self.thread.join();
            std.log.debug("self.thread.joined()", .{});
        }

        // release all messages sent from the lsp thread to the app thread
        // ---------------------------------------------------------------

        // drain and release nodes in the `response_queue`
        while (!self.context.response_queue.isEmpty()) {
            var msg_node = self.context.response_queue.get().?;
            msg_node.data.deinit();
            self.allocator.destroy(msg_node);
        }

        // release the thread context memory
        // ---------------------------------

        self.allocator.destroy(self.context);

        self.language_id.deinit();
        self.allocator.destroy(self);
    }

    pub fn serverFromExtension(extension: []const u8) ![]const u8 {
        if (std.mem.eql(u8, extension, ".go")) {
            return "gopls";
        } else if (std.mem.eql(u8, extension, ".zig")) {
            return "zls";
        } else if (std.mem.eql(u8, extension, ".rs")) {
            return "rust-analyzer";
        } else if (std.mem.eql(u8, extension, ".cpp")) {
            return "clangd";
        } else if (std.mem.eql(u8, extension, ".rb")) {
            return "solargraph stdio";
        } else if (std.mem.eql(u8, extension, ".py")) {
            // provided by: https://github.com/python-lsp/python-lsp-server
            return "pylsp";
        }
        return LSPError.UnknownExtension;
    }

    // LSP messages
    // ------------

    pub fn initialize(self: *LSP) !void {
        const msg_id = self.id();
        const json = try LSPWriter.initialize(self.allocator, msg_id, self.uri_working_dir.bytes());
        const request = LSPRequest{
            .json = json,
            .message_type = .Initialize,
            .request_id = msg_id,
        };
        try self.sendMessage(request);
    }

    pub fn initialized(self: *LSP) !void {
        const msg_id = self.id();
        const json = try LSPWriter.initialized(self.allocator);
        const request = LSPRequest{
            .json = json,
            .message_type = .Initialized,
            .request_id = msg_id,
        };

        // send the request
        try self.sendMessage(request);
    }

    pub fn openFile(self: *LSP, buffer: *Buffer) !void {
        if (self.context.is_running.load(.acquire) == false) {
            return;
        }

        const msg_id = self.id();
        var uri = try toUri(self.allocator, buffer.fullpath.bytes());
        defer uri.deinit();
        var fulltext = try buffer.fulltext();
        defer fulltext.deinit();

        const json = try LSPWriter.textDocumentDidOpen(self.allocator, uri.bytes(), self.language_id.bytes(), fulltext.bytes());
        const request = LSPRequest{
            .json = json,
            .message_type = .TextDocumentDidOpen,
            .request_id = msg_id,
        };
        try self.sendMessage(request);
    }

    pub fn internal(self: *LSP, buffer: *Buffer, cursor: Vec2u, msg_type: LSPMessageType) !void {
        if (self.context.is_running.load(.acquire) == false) {
            return;
        }

        // identify the message and prepare some values
        const msg_id = self.id();
        var uri = try toUri(self.allocator, buffer.fullpath.bytes());
        defer uri.deinit();

        // write the request
        const json = switch (msg_type) {
            .References => try LSPWriter.textDocumentReference(self.allocator, msg_id, uri.bytes(), cursor),
            .Definition => try LSPWriter.textDocumentDefinition(self.allocator, msg_id, uri.bytes(), cursor),
            .Completion => try LSPWriter.textDocumentCompletion(self.allocator, msg_id, uri.bytes(), cursor),
            .Hover      => try LSPWriter.textDocumentHover(self.allocator, msg_id, uri.bytes(), cursor),
            else        => unreachable, // unimplemented message type for a request
        };
        const request = LSPRequest{
            .json = json,
            .message_type = msg_type,
            .request_id = msg_id,
        };

        // send the request
        try self.sendMessage(request);
    }

    pub fn references(self: *LSP, buffer: *Buffer, cursor: Vec2u) !void {
        return self.internal(buffer, cursor, .References);
    }

    pub fn definition(self: *LSP, buffer: *Buffer, cursor: Vec2u) !void {
        return self.internal(buffer, cursor, .Definition);
    }

    pub fn completion(self: *LSP, buffer: *Buffer, cursor: Vec2u) !void {
        return self.internal(buffer, cursor, .Completion);
    }

    pub fn hover(self: *LSP, buffer: *Buffer, cursor: Vec2u) !void {
        return self.internal(buffer, cursor, .Hover);
    }

    pub fn didChangeComplete(self: *LSP, buffer: *Buffer) !void {
        if (self.context.is_running.load(.acquire) == false) {
            return;
        }

        // identify the request and prepare some values
        const msg_id = self.id();
        var uri = try toUri(self.allocator, buffer.fullpath.bytes());
        defer uri.deinit();

        var new_text = try buffer.fulltext();
        defer new_text.deinit();

        // write the request
        const json = try LSPWriter.textDocumentDidChange(self.allocator, msg_id, uri.bytes(), null, new_text.bytes());
        const request = LSPRequest{
            .json = json,
            .message_type = .DidChange,
            .request_id = msg_id,
        };

        // send the request
        try self.sendMessage(request);
    }

    pub fn didChange(self: *LSP, buffer: *Buffer, lines_range: Vec2u) !void {
        if (self.context.is_running.load(.acquire) == false) {
            return;
        }

        // identify the request and prepare some values
        const msg_id = self.id();
        var uri = try toUri(self.allocator, buffer.fullpath.bytes());
        defer uri.deinit();

        // new text
        var new_text = U8Slice.initEmpty(self.allocator);
        var i: usize = lines_range.a;
        var last_line_size: usize = 0;
        errdefer new_text.deinit();

        while (i <= lines_range.b) : (i += 1) {
            var line = buffer.getLine(i) catch {
                break;
            };
            last_line_size = line.size();
            try new_text.appendConst(line.bytes());
        }

        defer new_text.deinit();

        // range changed
        //        var range = if ((lines_range.b + 1) < buffer.linesCount()) Vec4u{
        //            .a = 0, .b = lines_range.a,
        //            .c = 0, .d = lines_range.b + 1,
        //        } else Vec4u{
        //            .a = 0, .b = lines_range.a,
        //            .c = last_line_size, .d = lines_range.b,
        //        };
        const range = Vec4u{
            .a = 0,
            .b = lines_range.a,
            .c = 0,
            .d = lines_range.b + 1,
        };

        // write the request
        const json = try LSPWriter.textDocumentDidChange(self.allocator, msg_id, uri.bytes(), range, new_text.bytes());
        const request = LSPRequest{
            .json = json,
            .message_type = .DidChange,
            .request_id = msg_id,
        };

        // send the request
        try self.sendMessage(request);
    }

    // -

    /// sendMessage sends the message to the other thread
    /// which will write the content on stdin.
    fn sendMessage(self: LSP, request: LSPRequest) !void {
        if (self.context.is_running.load(.acquire) == false) {
            return;
        }

        var node = try self.allocator.create(AtomicQueue(LSPRequest).Node);
        node.data = request;
        // send the JSON data to the other thread
        self.context.send_queue.put(node);
    }

    fn id(self: *LSP) i64 {
        defer self.current_request_id += 1;
        return self.current_request_id;
    }

    fn toUri(allocator: std.mem.Allocator, path: []const u8) !U8Slice {
        var uri = U8Slice.initEmpty(allocator);
        try uri.appendConst("file://");
        try uri.appendConst(path);
        return uri;
    }
};

pub const LSPWriter = struct {
    fn initialize(allocator: std.mem.Allocator, request_id: i64, uri_working_dir: []const u8) !U8Slice {
        const m = LSPMessages.initialize{
            .jsonrpc = "2.0",
            .id = request_id,
            .method = "initialize",
            .params = LSPMessages.initializeParams{
                .processId = 0,
                .capabilities = LSPMessages.initializeCapabilities{
                    .textDocument = LSPMessages.initializeTextDocumentCapabilities{
                        .completion = LSPMessages.completionCapabilities{
                            .dynamicRegistration = true,
                            .completionItem = LSPMessages.completionItemCapabilities{
                                .insertReplaceSupport = true,
                                .documentationFormat = LSPMessages.markupKind,
                            },
                        },
                        .definition = LSPMessages.dynRegTrue,
                        .implementation = LSPMessages.dynRegTrue,
                        .references = LSPMessages.dynRegTrue,
                        .hover = LSPMessages.hoverCapabilities{
                            .dynamicRegistration = true,
                            .contentFormat = LSPMessages.markupKind,
                        },
                        .publishDiagnostics = LSPMessages.publishDiagnosticsCapabilities{
                            .relatedInformation = false,
                            .codeDescriptionSupport = false,
                            .versionSupport = false,
                            .dataSupport = false,
                        },
                    },
                },
                .workspaceFolders = [1]LSPMessages.workspaceFolder{
                    LSPMessages.workspaceFolder{
                        .uri = uri_working_dir,
                        .name = "workspace",
                    },
                },
            },
        };
        return try LSPWriter.toJson(allocator, m);
    }

    fn initialized(allocator: std.mem.Allocator) !U8Slice {
        const m = LSPMessages.initialized{
            .jsonrpc = "2.0",
            .params = LSPMessages.emptyStruct{},
            .method = "initialized",
        };
        return try LSPWriter.toJson(allocator, m);
    }

    fn textDocumentDidOpen(allocator: std.mem.Allocator, uri: []const u8, language_id: []const u8, text: []const u8) !U8Slice {
        const m = LSPMessages.textDocumentDidOpen{
            .jsonrpc = "2.0",
            .method = "textDocument/didOpen",
            .params = LSPMessages.textDocumentDidOpenParams{
                .textDocument = LSPMessages.textDocumentItem{
                    .uri = uri,
                    .languageId = language_id,
                    .version = 1,
                    .text = text,
                },
            },
        };
        return try LSPWriter.toJson(allocator, m);
    }

    fn textDocumentReference(allocator: std.mem.Allocator, msg_id: i64, filepath: []const u8, cursor_pos: Vec2u) !U8Slice {
        const m = LSPMessages.textDocumentReferences{
            .jsonrpc = "2.0",
            .method = "textDocument/references",
            .id = msg_id,
            .params = LSPMessages.referencesParams{
                .textDocument = LSPMessages.textDocumentIdentifier{
                    .uri = filepath,
                },
                .position = LSPMessages.position{
                    .character = cursor_pos.a,
                    .line = cursor_pos.b,
                },
                .context = LSPMessages.referencesContext{
                    .includeDeclaration = true,
                },
            },
        };
        return try LSPWriter.toJson(allocator, m);
    }

    fn textDocumentDefinition(allocator: std.mem.Allocator, msg_id: i64, filepath: []const u8, cursor_pos: Vec2u) !U8Slice {
        const m = LSPMessages.textDocumentDefinition{
            .jsonrpc = "2.0",
            .method = "textDocument/definition",
            .id = msg_id,
            .params = LSPMessages.definitionParams{
                .textDocument = LSPMessages.textDocumentIdentifier{
                    .uri = filepath,
                },
                .position = LSPMessages.position{
                    .character = cursor_pos.a,
                    .line = cursor_pos.b,
                },
            },
        };
        return try LSPWriter.toJson(allocator, m);
    }

    fn textDocumentDidChange(allocator: std.mem.Allocator, msg_id: i64, filepath: []const u8, range: ?Vec4u, new_text: []const u8) !U8Slice {
        const content_change = if (range) |r| LSPMessages.contentChange{
            .range = LSPMessages.range{
                .start = LSPMessages.position{ .character = r.a, .line = r.b },
                .end = LSPMessages.position{ .character = r.c, .line = r.d },
            },
            .text = new_text,
        } else LSPMessages.contentChange{
            .range = null,
            .text = new_text,
        };
        const m = LSPMessages.textDocumentDidChange{
            .jsonrpc = "2.0",
            .method = "textDocument/didChange",
            .params = LSPMessages.didChangeParams{
                .textDocument = LSPMessages.textDocumentIdentifierVersioned{
                    .uri = filepath,
                    .version = msg_id, // we can re-use the msg id which is a monotonic counter
                },
                .contentChanges = [1]LSPMessages.contentChange{content_change},
            },
        };
        return try LSPWriter.toJson(allocator, m);
    }

    fn textDocumentCompletion(allocator: std.mem.Allocator, msg_id: i64, filepath: []const u8, cursor_pos: Vec2u) !U8Slice {
        const m = LSPMessages.textDocumentCompletion{
            .jsonrpc = "2.0",
            .method = "textDocument/completion",
            .id = msg_id,
            .params = LSPMessages.completionParams{
                .textDocument = LSPMessages.textDocumentIdentifier{
                    .uri = filepath,
                },
                .position = LSPMessages.position{
                    .character = cursor_pos.a,
                    .line = cursor_pos.b,
                },
            },
        };
        return try LSPWriter.toJson(allocator, m);
    }

    fn textDocumentHover(allocator: std.mem.Allocator, msg_id: i64, filepath: []const u8, cursor_pos: Vec2u) !U8Slice {
        const m = LSPMessages.textDocumentHover{
            .jsonrpc = "2.0",
            .method = "textDocument/hover",
            .id = msg_id,
            .params = LSPMessages.hoverParams{
                .textDocument = LSPMessages.textDocumentIdentifier{
                    .uri = filepath,
                },
                .position = LSPMessages.position{
                    .character = cursor_pos.a,
                    .line = cursor_pos.b,
                },
            },
        };
        return try LSPWriter.toJson(allocator, m);
    }

    fn toJson(allocator: std.mem.Allocator, message: anytype) !U8Slice {
        var rv = U8Slice.initEmpty(allocator);
        errdefer rv.deinit();
        try std.json.stringify(message, std.json.StringifyOptions{}, rv.data.writer());
        return rv;
    }
};

test "lspwriter initialize" {
    const allocator = std.testing.allocator;
    var init_msg = try LSPWriter.initialize(allocator, 0, "hello world");
    init_msg.deinit();
}
