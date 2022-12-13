test "all_tests" {
    _ = @import("buffer.zig");
    _ = @import("editor.zig");
    _ = @import("ripgrep.zig");
    _ = @import("u8slice.zig");
    _ = @import("widget_command.zig");
    _ = @import("widget_lookup.zig");
    _ = @import("widget_text_edit.zig");
    _ = @import("widget_ripgrep.zig");
}
