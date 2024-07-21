const std = @import("std");

const LSPCompletion = @import("lsp.zig").LSPCompletion;
const LSPError = @import("lsp.zig").LSPError;
const LSPPosition = @import("lsp.zig").LSPPosition;
const U8Slice = @import("u8slice.zig").U8Slice;
const Vec2u = @import("vec.zig").Vec2u;
const Vec4u = @import("vec.zig").Vec4u;

// JSON structures
// ------------------------------------------------------------

// shared
// ------

pub const position = struct {
    line: u64, // zero based
    character: u64, // zero based

    pub fn vec2u(self: position) Vec2u {
        return Vec2u{ .a = self.character, .b = self.line };
    }
};

pub const range = struct {
    start: position,
    end: position,

    pub fn vec4u(self: range) Vec4u {
        return Vec4u{
            .a = self.start.character,
            .b = self.start.line,
            .c = self.end.character,
            .d = self.end.line,
        };
    }
};

pub const dynReg = struct {
    dynamicRegistration: bool,
};

pub const dynRegTrue = dynReg{ .dynamicRegistration = true };
pub const dynRegFalse = dynReg{ .dynamicRegistration = false };
pub const emptyStruct = struct {};

pub const textDocumentIdentifier = struct {
    uri: []const u8,
};

pub const textDocumentIdentifierVersioned = struct {
    uri: []const u8,
    version: i64,
};

// Requests
// -------------------------------------------------------------

// message: initialize & initialized
// -------------------

pub const initialize = struct {
    jsonrpc: []const u8,
    id: i64,
    method: []const u8,
    params: initializeParams,
};

pub const initialized = struct {
    jsonrpc: []const u8,
    method: []const u8,
    params: emptyStruct,
};

pub const completionCapabilities = struct {
    dynamicRegistration: bool,
    completionItem: completionItemCapabilities,
};

pub const completionItemCapabilities = struct {
    insertReplaceSupport: bool,
    documentationFormat: [2][]const u8 = markupKind,
};

pub const hoverCapabilities = struct {
    dynamicRegistration: bool,
    contentFormat: [2][]const u8 = markupKind,
};

pub const publishDiagnosticsCapabilities = struct {
    relatedInformation: bool,
    // TODO(remy): tagSupport
    versionSupport: bool,
    codeDescriptionSupport: bool,
    dataSupport: bool,
};

pub const initializeTextDocumentCapabilities = struct {
    completion: completionCapabilities,
    definition: dynReg,
    implementation: dynReg,
    references: dynReg,
    hover: hoverCapabilities,
    publishDiagnostics: publishDiagnosticsCapabilities,
};

pub const initializeCapabilities = struct {
    // TODO(remy): workspace
    textDocument: initializeTextDocumentCapabilities,
};

pub const initializeParams = struct {
    processId: usize,
    capabilities: initializeCapabilities,
    workspaceFolders: [1]workspaceFolder,
};

pub const workspaceFolder = struct {
    uri: []const u8,
    name: []const u8,
};

// order in which we want to receive documentation and such
pub const markupKind = [_][]const u8{ "plaintext", "markdown" };

// message: textDocument/didOpen
// -----------------------------

pub const textDocumentDidOpen = struct {
    jsonrpc: []const u8,
    method: []const u8,
    params: textDocumentDidOpenParams,
};

pub const textDocumentDidOpenParams = struct {
    textDocument: textDocumentItem,
};

pub const textDocumentItem = struct {
    uri: []const u8,
    languageId: []const u8,
    version: i64,
    text: []const u8,
};

pub const textDocumentPositionParams = struct {
    textDocument: textDocumentIdentifier,
};

// message: textDocument/references
// --------------------------------

pub const textDocumentReferences = struct {
    jsonrpc: []const u8,
    method: []const u8,
    id: i64,
    params: referencesParams,
};

pub const referencesParams = struct {
    textDocument: textDocumentIdentifier,
    position: position,
    context: referencesContext,
};

pub const referencesContext = struct {
    includeDeclaration: bool,
};

// message: textDocument/definition
// --------------------------------

pub const textDocumentDefinition = struct {
    jsonrpc: []const u8,
    method: []const u8,
    id: i64,
    params: definitionParams,
};

pub const definitionParams = struct {
    textDocument: textDocumentIdentifier,
    position: position,
};

// message: textDocument/didChange
// -------------------------------

pub const textDocumentDidChange = struct {
    jsonrpc: []const u8,
    method: []const u8,
    params: didChangeParams,
};

pub const didChangeParams = struct {
    textDocument: textDocumentIdentifierVersioned,
    contentChanges: [1]contentChange,
};

pub const contentChange = struct {
    range: ?range,
    text: []const u8,
};

// message: textDocument/completion
// --------------------------------

pub const textDocumentCompletion = struct {
    jsonrpc: []const u8,
    id: i64,
    method: []const u8,
    params: completionParams,
};

pub const completionParams = struct {
    textDocument: textDocumentIdentifier,
    position: position,
};

// message: textDocument/hover
// ---------------------------

pub const textDocumentHover = struct {
    jsonrpc: []const u8,
    id: i64,
    method: []const u8,
    params: hoverParams,
};

pub const hoverParams = struct {
    textDocument: textDocumentIdentifier,
    position: position,
};

// Responses
// -------------------------------------------------------------

pub const headerResponse = struct {
    jsonrpc: []const u8,
    id: i64,
};

pub const headerNotificationResponse = struct {
    jsonrpc: []const u8,
    method: []const u8,
};

pub const positionResponse = struct {
    uri: []const u8,
    range: range,

    pub fn toLSPPosition(self: positionResponse, allocator: std.mem.Allocator) !LSPPosition {
        if (self.uri.len <= 7) {
            return LSPError.MalformedUri;
        }
        return LSPPosition{
            .filepath = try U8Slice.initFromSlice(allocator, self.uri[7..]),
            .start = self.range.start.vec2u(),
            .end = self.range.end.vec2u(),
        };
    }
};

// References

pub const referencesResponse = struct {
    jsonrpc: []const u8,
    id: i64,
    result: ?[]positionResponse = null,
};

// Definition

// Some LSP servers return only one result (an object), some returns
// an array, through trial and error we have to test both.

pub const definitionResponse = struct {
    jsonrpc: []const u8,
    id: i64,
    result: ?positionResponse = null,
};

pub const definitionsResponse = struct {
    jsonrpc: []const u8,
    id: i64,
    result: ?[]positionResponse = null,
};

// PublishDiagnostics

pub const publishDiagnosticsNotification = struct {
    jsonrpc: []const u8,
    method: []const u8,
    params: ?publishDiagnosticsParams = null,
};

pub const publishDiagnosticsParams = struct {
    uri: []const u8,
    diagnostics: []diagnostic,
};

pub const diagnostic = struct {
    message: []const u8,
    range: range,
};

pub const showMessageNotification = struct {
    jsonrpc: []const u8,
    method: []const u8,
    params: ?showMessageParams,
};

pub const showMessageParams = struct {
    message: []const u8,
};

// Completion

pub const completionsResponse = struct {
    jsonrpc: []const u8,
    id: i64,
    result: ?completionResult = null,
};

pub const completionResult = struct {
    isIncomplete: bool,
    items: ?[]completionItem = null,
};

// FIXME(remy): these fields could be here or could be missing, I did not succeed
// to get them "optional" for now while parsing the JSON using the stdlib json parser.
pub const completionItem = struct {
    label: ?[]const u8 = null,
    kind: ?i64 = null,
    detail: ?[]const u8 = null,
    documentation: ?completionResultDoc = null,
    sortText: ?[]const u8 = null,
    insertText: ?[]const u8 = null,
    textEdit: ?completionTextEdit = null,

    pub fn toLSPCompletion(self: completionItem, allocator: std.mem.Allocator) !LSPCompletion {
        // detail

        var detail = U8Slice.initEmpty(allocator);
        errdefer detail.deinit();
        if (self.detail) |d| {
            try detail.appendConst(d);
        }

        // label

        var label = U8Slice.initEmpty(allocator);
        errdefer label.deinit();

        if (self.label) |l| {
            try label.appendConst(l);
        } else {
            return LSPError.IncompleteCompletionEntry;
        }

        if (self.kind == 2 or self.kind == 3 or self.kind == 4) {
            try label.appendConst("()");
        }

        // sort text

        var sort_text = U8Slice.initEmpty(allocator);
        errdefer sort_text.deinit();
        if (self.sortText) |i| {
            try sort_text.appendConst(i);
        } else {
            // from the lsp documentation:
            //   When omitted the label is used as the sort text for this item.
            try sort_text.appendConst(label.bytes());
        }

        // documentation

        var documentation = U8Slice.initEmpty(allocator);
        errdefer documentation.deinit();        if (self.documentation) |doc| {
            if (doc.value) |v| {
                try documentation.appendConst(v);
            }
        }

        // insert text

        var insert_text = U8Slice.initEmpty(allocator);
        var text_range: Vec4u = undefined;
        errdefer insert_text.deinit();

        if (self.textEdit) |text_edit| {
            // TODO(remy): implement support for replace
            if (text_edit.range) |r| {
                text_range = r.vec4u();
            } else if (text_edit.insert) |i| {
                text_range = i.vec4u();
            } else {
                return LSPError.IncompleteCompletionEntry;
            }
            try insert_text.appendConst(text_edit.newText);
        } else {
            if (self.insertText) |i| {
                try insert_text.appendConst(i);
            } else {
                return LSPError.IncompleteCompletionEntry;
            }
        }

        // create the object

        return LSPCompletion{
            .detail = detail,
            .label = label,
            .documentation = documentation,
            .insert_text = insert_text,
            .sort_text = sort_text,
            .range = text_range,
        };
    }
};

pub const completionTextEdit = struct {
    range: ?range = null,
    insert: ?range = null,
    // TODO(remy): add support for replace
    newText: []const u8,
};

pub const completionResultDoc = struct {
    kind: ?[]const u8 = null,
    value: ?[]const u8 = null,

    /// jsonParse implements the logic that depending on the LSP server
    /// (despite sending them the proper initial "markupKind" values),
    /// this field is sometimes a simple []const u8 while it is sometimes
    /// an object.
    pub fn jsonParse(allocator: std.mem.Allocator, source: anytype, options: std.json.ParseOptions) !@This() {
        if (std.json.innerParse([]const u8, allocator, source, options)) |value| {
            return completionResultDoc{
                .kind = "plaintext",
                .value = value,
            };
        } else |_| {
            const obj = try std.json.innerParse(completionResultDocObj, allocator, source, options);
            return completionResultDoc{
                .kind = obj.kind,
                .value = obj.value,
            };
        }
    }
};

pub const completionResultDocObj = struct {
    kind: ?[]const u8 = null,
    value: ?[]const u8 = null,
};

// Hover

pub const hoverResponse = struct {
    jsonrpc: []const u8,
    id: i64,
    result: ?hoverResult = null,
};

pub const hoverResult = struct {
    contents: ?hoverContent = null,
};

pub const hoverContent = struct {
    kind: ?[]const u8 = null,
    value: ?[]const u8 = null,
};
