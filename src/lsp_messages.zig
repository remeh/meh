const std = @import("std");

const LSPError = @import("lsp.zig").LSPError;
const LSPPosition = @import("lsp.zig").LSPPosition;
const U8Slice = @import("u8slice.zig").U8Slice;
const Vec2u = @import("vec.zig").Vec2u;

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

pub const initializeTextDocumentCapabilities = struct {
    references: dynReg,
    implementation: dynReg,
    definition: dynReg,
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
    range: range,
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
    result: ?[]positionResponse,
};

// Definition

// Some LSP servers return only one result (an object), some returns
// an array, through trial and error we have to test both.

pub const definitionResponse = struct {
    jsonrpc: []const u8,
    id: i64,
    result: ?positionResponse,
};

pub const definitionsResponse = struct {
    jsonrpc: []const u8,
    id: i64,
    result: ?[]positionResponse,
};
