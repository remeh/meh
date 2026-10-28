const Vec4u = @import("vec.zig").Vec4u;

// =============================================================================
// Theme
//
// Dark, neutral grays plus a few muted accents. The ramps below go from the
// deepest background (`crust`) through the editor background (`base`) and the
// borders (`surface*`) up to the inks (`overlay*`, `subtext*`, `text`).
// =============================================================================

pub const crust = Vec4u{ .a = 10, .b = 10, .c = 11, .d = 255 };
pub const mantle = Vec4u{ .a = 16, .b = 16, .c = 18, .d = 255 };
pub const base = Vec4u{ .a = 22, .b = 22, .c = 24, .d = 255 };
pub const surface0 = Vec4u{ .a = 38, .b = 38, .c = 42, .d = 255 };
pub const surface1 = Vec4u{ .a = 52, .b = 52, .c = 57, .d = 255 };
pub const surface2 = Vec4u{ .a = 68, .b = 68, .c = 74, .d = 255 };
pub const overlay0 = Vec4u{ .a = 98, .b = 98, .c = 106, .d = 255 };
pub const overlay1 = Vec4u{ .a = 126, .b = 126, .c = 134, .d = 255 };
pub const subtext0 = Vec4u{ .a = 178, .b = 178, .c = 186, .d = 255 };
pub const subtext1 = Vec4u{ .a = 203, .b = 203, .c = 210, .d = 255 };
pub const text = Vec4u{ .a = 230, .b = 230, .c = 235, .d = 255 };

// =============================================================================
// Accent Colors
//
// They carry meaning (a mode, a warning, a selection), they don't decorate.
// =============================================================================

pub const blue = Vec4u{ .a = 122, .b = 162, .c = 212, .d = 255 };
pub const cyan = Vec4u{ .a = 95, .b = 184, .c = 196, .d = 255 };
pub const green = Vec4u{ .a = 157, .b = 202, .c = 135, .d = 255 };
pub const orange = Vec4u{ .a = 217, .b = 160, .c = 102, .d = 255 };
pub const yellow = Vec4u{ .a = 216, .b = 191, .c = 122, .d = 255 };
pub const red = Vec4u{ .a = 219, .b = 122, .c = 122, .d = 255 };
pub const sand = Vec4u{ .a = 232, .b = 199, .c = 154, .d = 255 };

// =============================================================================
// Syntax Highlighting Colors
// =============================================================================

pub const syntax_keyword = blue; // keywords: const, fn, pub, try, …
pub const syntax_string = green; // "strings"
pub const syntax_function = cyan; // called()
pub const syntax_comment = overlay0; // muted, never competing with code
pub const syntax_number = orange; // 42, 3.14
pub const syntax_url = Vec4u{ .a = 110, .b = 199, .c = 210, .d = 255 };
pub const syntax_todo = yellow; // TODO, XXX, FIXME
pub const syntax_done = green; // DONE

// =============================================================================
// UI Element Colors
// =============================================================================

pub const ui_background = base;
pub const ui_background_alt = mantle;
/// background of a floating panel.
pub const ui_surface = surface0;
/// background of a field inside a panel (the command line, …).
pub const ui_surface_highlight = surface1;
/// the shadow a floating panel casts over the dimmed editor behind it.
pub const ui_panel_shadow = Vec4u{ .a = 0, .b = 0, .c = 0, .d = 130 };
/// dims the editor behind a floating panel.
pub const ui_overlay = withAlpha(crust, 178);

pub const ui_text_primary = text;
pub const ui_text_secondary = subtext0;
pub const ui_text_muted = overlay0;

pub const ui_border = surface1;
pub const ui_border_light = surface2;
/// the hairline between the line numbers and the code.
pub const ui_gutter_separator = surface0;
/// the 80 and 120 columns limits.
pub const ui_column_limit = Vec4u{ .a = 255, .b = 255, .c = 255, .d = 14 };

pub const ui_selection = withAlpha(blue, 62);
pub const ui_selection_focused = withAlpha(blue, 95);

/// background of the line the cursor is on.
pub const ui_current_line = Vec4u{ .a = 255, .b = 255, .c = 255, .d = 18 };
/// background/border of the occurrences of the word under the cursor.
pub const ui_match = withAlpha(blue, 36);
pub const ui_match_border = withAlpha(blue, 120);
/// vertical line marking an indentation level.
pub const ui_indent_guide = Vec4u{ .a = 255, .b = 255, .c = 255, .d = 12 };

pub const ui_cursor = Vec4u{ .a = 255, .b = 255, .c = 255, .d = 120 };
pub const ui_cursor_insert = sand;
pub const ui_cursor_command = withAlpha(orange, 220);
pub const ui_cursor_unfocused = overlay1;

pub const ui_line_number = overlay0;
pub const ui_line_number_current = subtext1;

pub const ui_gutter_git_added = green;
pub const ui_gutter_git_removed = red;
pub const ui_gutter_diagnostic_error = Vec4u{ .a = 232, .b = 140, .c = 140, .d = 255 };

// =============================================================================
// Minimap Colors
// =============================================================================

pub const ui_minimap_background = mantle;
pub const ui_minimap_line = surface1;
pub const ui_minimap_line_visible = overlay1;
pub const ui_minimap_line_highlight = withAlpha(blue, 210);
pub const ui_minimap_viewport = Vec4u{ .a = 255, .b = 255, .c = 255, .d = 16 };
pub const ui_minimap_viewport_border = withAlpha(overlay1, 130);

// =============================================================================
// Helper Functions
// =============================================================================

/// withAlpha returns a copy of the color with modified alpha.
pub fn withAlpha(color: Vec4u, alpha: u8) Vec4u {
    return Vec4u{ .a = color.a, .b = color.b, .c = color.c, .d = alpha };
}
