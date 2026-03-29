const Vec4u = @import("vec.zig").Vec4u;

// =============================================================================
// Base Colors
// =============================================================================

pub const white = Vec4u{ .a = 255, .b = 255, .c = 255, .d = 255 };

pub const light_gray = Vec4u{ .a = 190, .b = 190, .c = 190, .d = 255 };
pub const medium_gray = Vec4u{ .a = 150, .b = 150, .c = 155, .d = 255 };
pub const gray = Vec4u{ .a = 120, .b = 120, .c = 125, .d = 255 };
pub const dark_gray = Vec4u{ .a = 60, .b = 60, .c = 65, .d = 255 };
pub const darker_gray = Vec4u{ .a = 40, .b = 40, .c = 40, .d = 255 };
pub const darkest_gray = Vec4u{ .a = 20, .b = 20, .c = 20, .d = 255 };

// =============================================================================
// Accent Colors
// =============================================================================

pub const blue = Vec4u{ .a = 61, .b = 151, .c = 226, .d = 255 };
pub const blue_light = Vec4u{ .a = 91, .b = 181, .c = 255, .d = 255 };

pub const green = Vec4u{ .a = 151, .b = 194, .c = 73, .d = 255 };

pub const orange = Vec4u{ .a = 244, .b = 190, .c = 99, .d = 255 };

pub const red = Vec4u{ .a = 224, .b = 90, .c = 79, .d = 255 };

// =============================================================================
// Syntax Highlighting Colors
// =============================================================================

pub const syntax_keyword = Vec4u{ .a = 130, .b = 100, .c = 180, .d = 255 };      // Purple-ish for keywords
pub const syntax_string = Vec4u{ .a = 200, .b = 180, .c = 100, .d = 255 };      // Yellow-ish for strings
pub const syntax_number = Vec4u{ .a = 100, .b = 180, .c = 140, .d = 255 };      // Green-ish for numbers
pub const syntax_function = Vec4u{ .a = 100, .b = 160, .c = 220, .d = 255 };    // Blue-ish for functions
pub const syntax_type = Vec4u{ .a = 220, .b = 160, .c = 140, .d = 255 };        // Orange-ish for types
pub const syntax_comment = Vec4u{ .a = 90, .b = 95, .c = 105, .d = 255 };       // Muted gray for comments
pub const syntax_url = Vec4u{ .a = 100, .b = 180, .c = 220, .d = 255 };         // Cyan-blue for URLs
pub const syntax_todo = Vec4u{ .a = 240, .b = 140, .c = 80, .d = 255 };         // Orange for TODO
pub const syntax_done = Vec4u{ .a = 100, .b = 200, .c = 120, .d = 255 };        // Green for DONE

// =============================================================================
// UI Element Colors
// =============================================================================

pub const ui_background_alt = Vec4u{ .a = 40, .b = 40, .c = 45, .d = 255 };
pub const ui_surface = Vec4u{ .a = 45, .b = 45, .c = 50, .d = 255 };
pub const ui_surface_highlight = Vec4u{ .a = 55, .b = 55, .c = 60, .d = 255 };

pub const ui_text_primary = Vec4u{ .a = 230, .b = 230, .c = 235, .d = 255 };
pub const ui_text_secondary = Vec4u{ .a = 160, .b = 160, .c = 170, .d = 255 };

pub const ui_border = Vec4u{ .a = 70, .b = 70, .c = 80, .d = 255 };
pub const ui_border_light = Vec4u{ .a = 90, .b = 90, .c = 100, .d = 255 };

pub const ui_selection = Vec4u{ .a = 70, .b = 120, .c = 180, .d = 80 };
pub const ui_selection_focused = Vec4u{ .a = 90, .b = 150, .c = 220, .d = 100 };

pub const ui_cursor = Vec4u{ .a = 255, .b = 255, .c = 255, .d = 200 };
pub const ui_cursor_insert = Vec4u{ .a = 255, .b = 255, .c = 255, .d = 220 };
pub const ui_cursor_command = Vec4u{ .a = 255, .b = 255, .c = 255, .d = 180 };

pub const ui_line_number = Vec4u{ .a = 100, .b = 100, .c = 110, .d = 255 };
pub const ui_line_number_current = Vec4u{ .a = 200, .b = 200, .c = 210, .d = 255 };
pub const ui_line_number_bg = Vec4u{ .a = 35, .b = 35, .c = 40, .d = 255 };

pub const ui_gutter_git_added = Vec4u{ .a = 100, .b = 180, .c = 80, .d = 255 };
pub const ui_gutter_git_removed = Vec4u{ .a = 220, .b = 100, .c = 100, .d = 255 };
pub const ui_gutter_diagnostic_error = Vec4u{ .a = 240, .b = 100, .c = 100, .d = 255 };

// =============================================================================
// Shadow Colors
// =============================================================================

pub const shadow_medium = Vec4u{ .a = 0, .b = 0, .c = 0, .d = 60 };

// =============================================================================
// Helper Functions
// =============================================================================

/// withAlpha returns a copy of the color with modified alpha.
pub fn withAlpha(color: Vec4u, alpha: u8) Vec4u {
    return Vec4u{ .a = color.a, .b = color.b, .c = color.c, .d = alpha };
}
