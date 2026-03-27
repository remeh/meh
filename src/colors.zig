const std = @import("std");
const Vec4u = @import("vec.zig").Vec4u;

// =============================================================================
// Base Colors
// =============================================================================

pub const white = Vec4u{ .a = 255, .b = 255, .c = 255, .d = 255 };
pub const black = Vec4u{ .a = 0, .b = 0, .c = 0, .d = 255 };

pub const whitish = Vec4u{ .a = 230, .b = 230, .c = 230, .d = 255 };
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
pub const blue_dark = Vec4u{ .a = 31, .b = 121, .c = 196, .d = 255 };

pub const green = Vec4u{ .a = 151, .b = 194, .c = 73, .d = 255 };
pub const green_light = Vec4u{ .a = 181, .b = 224, .c = 103, .d = 255 };
pub const green_dark = Vec4u{ .a = 121, .b = 164, .c = 43, .d = 255 };

pub const orange = Vec4u{ .a = 244, .b = 190, .c = 99, .d = 255 };
pub const orange_light = Vec4u{ .a = 255, .b = 210, .c = 129, .d = 255 };
pub const orange_dark = Vec4u{ .a = 214, .b = 160, .c = 69, .d = 255 };

pub const red = Vec4u{ .a = 224, .b = 90, .c = 79, .d = 255 };
pub const red_light = Vec4u{ .a = 255, .b = 120, .c = 109, .d = 255 };
pub const red_dark = Vec4u{ .a = 194, .b = 60, .c = 49, .d = 255 };

pub const purple = Vec4u{ .a = 180, .b = 100, .c = 200, .d = 255 };
pub const purple_light = Vec4u{ .a = 210, .b = 130, .c = 230, .d = 255 };
pub const purple_dark = Vec4u{ .a = 150, .b = 70, .c = 170, .d = 255 };

pub const cyan = Vec4u{ .a = 73, .b = 200, .c = 194, .d = 255 };
pub const cyan_light = Vec4u{ .a = 103, .b = 230, .c = 224, .d = 255 };
pub const cyan_dark = Vec4u{ .a = 43, .b = 170, .c = 164, .d = 255 };

pub const yellow = Vec4u{ .a = 244, .b = 204, .c = 73, .d = 255 };
pub const yellow_light = Vec4u{ .a = 255, .b = 224, .c = 103, .d = 255 };
pub const yellow_dark = Vec4u{ .a = 214, .b = 174, .c = 43, .d = 255 };

// =============================================================================
// Syntax Highlighting Colors
// =============================================================================

pub const syntax_keyword = Vec4u{ .a = 130, .b = 100, .c = 180, .d = 255 };      // Purple-ish for keywords
pub const syntax_string = Vec4u{ .a = 200, .b = 180, .c = 100, .d = 255 };      // Yellow-ish for strings
pub const syntax_number = Vec4u{ .a = 100, .b = 180, .c = 140, .d = 255 };      // Green-ish for numbers
pub const syntax_function = Vec4u{ .a = 100, .b = 160, .c = 220, .d = 255 };    // Blue-ish for functions
pub const syntax_type = Vec4u{ .a = 220, .b = 160, .c = 140, .d = 255 };        // Orange-ish for types
pub const syntax_comment = Vec4u{ .a = 90, .b = 95, .c = 105, .d = 255 };       // Muted gray for comments
pub const syntax_operator = Vec4u{ .a = 180, .b = 150, .c = 200, .d = 255 };    // Purple-ish for operators
pub const syntax_builtin = Vec4u{ .a = 160, .b = 140, .c = 180, .d = 255 };     // Light purple for builtins
pub const syntax_constant = Vec4u{ .a = 180, .b = 120, .c = 100, .d = 255 };    // Orange-ish for constants
pub const syntax_decorator = Vec4u{ .a = 200, .b = 130, .c = 180, .d = 255 };   // Pink-ish for decorators
pub const syntax_url = Vec4u{ .a = 100, .b = 180, .c = 220, .d = 255 };         // Cyan-blue for URLs
pub const syntax_todo = Vec4u{ .a = 240, .b = 140, .c = 80, .d = 255 };         // Orange for TODO
pub const syntax_done = Vec4u{ .a = 100, .b = 200, .c = 120, .d = 255 };        // Green for DONE

// =============================================================================
// UI Element Colors
// =============================================================================

pub const ui_background = Vec4u{ .a = 30, .b = 30, .c = 35, .d = 255 };
pub const ui_background_alt = Vec4u{ .a = 40, .b = 40, .c = 45, .d = 255 };
pub const ui_surface = Vec4u{ .a = 45, .b = 45, .c = 50, .d = 255 };
pub const ui_surface_highlight = Vec4u{ .a = 55, .b = 55, .c = 60, .d = 255 };

pub const ui_text_primary = Vec4u{ .a = 230, .b = 230, .c = 235, .d = 255 };
pub const ui_text_secondary = Vec4u{ .a = 160, .b = 160, .c = 170, .d = 255 };
pub const ui_text_disabled = Vec4u{ .a = 100, .b = 100, .c = 110, .d = 255 };

pub const ui_border = Vec4u{ .a = 70, .b = 70, .c = 80, .d = 255 };
pub const ui_border_light = Vec4u{ .a = 90, .b = 90, .c = 100, .d = 255 };
pub const ui_border_focus = Vec4u{ .a = 100, .b = 160, .c = 220, .d = 255 };

pub const ui_selection = Vec4u{ .a = 70, .b = 120, .c = 180, .d = 80 };
pub const ui_selection_focused = Vec4u{ .a = 90, .b = 150, .c = 220, .d = 100 };

pub const ui_cursor = Vec4u{ .a = 255, .b = 255, .c = 255, .d = 200 };
pub const ui_cursor_insert = Vec4u{ .a = 255, .b = 255, .c = 255, .d = 220 };
pub const ui_cursor_command = Vec4u{ .a = 255, .b = 255, .c = 255, .d = 180 };

pub const ui_line_number = Vec4u{ .a = 100, .b = 100, .c = 110, .d = 255 };
pub const ui_line_number_current = Vec4u{ .a = 200, .b = 200, .c = 210, .d = 255 };
pub const ui_line_number_bg = Vec4u{ .a = 35, .b = 35, .c = 40, .d = 255 };

pub const ui_gutter_git_added = Vec4u{ .a = 100, .b = 180, .c = 80, .d = 255 };
pub const ui_gutter_git_modified = Vec4u{ .a = 220, .b = 180, .c = 60, .d = 255 };
pub const ui_gutter_git_removed = Vec4u{ .a = 220, .b = 100, .c = 100, .d = 255 };
pub const ui_gutter_diagnostic_error = Vec4u{ .a = 240, .b = 100, .c = 100, .d = 255 };
pub const ui_gutter_diagnostic_warn = Vec4u{ .a = 240, .b = 180, .c = 80, .d = 255 };
pub const ui_gutter_diagnostic_info = Vec4u{ .a = 100, .b = 180, .c = 220, .d = 255 };

// =============================================================================
// Shadow Colors
// =============================================================================

pub const shadow_dark = Vec4u{ .a = 0, .b = 0, .c = 0, .d = 80 };
pub const shadow_medium = Vec4u{ .a = 0, .b = 0, .c = 0, .d = 60 };
pub const shadow_light = Vec4u{ .a = 0, .b = 0, .c = 0, .d = 40 };

// =============================================================================
// Theme Support
// =============================================================================

pub const Theme = struct {
    background: Vec4u,
    background_alt: Vec4u,
    surface: Vec4u,
    surface_highlight: Vec4u,

    text_primary: Vec4u,
    text_secondary: Vec4u,
    text_disabled: Vec4u,

    border: Vec4u,
    border_light: Vec4u,
    border_focus: Vec4u,

    selection: Vec4u,
    selection_focused: Vec4u,

    cursor: Vec4u,
    line_number: Vec4u,
    line_number_current: Vec4u,
    line_number_bg: Vec4u,

    syntax: SyntaxColors,
    ui: UIColors,

    pub fn dark() Theme {
        return Theme{
            .background = ui_background,
            .background_alt = ui_background_alt,
            .surface = ui_surface,
            .surface_highlight = ui_surface_highlight,
            .text_primary = ui_text_primary,
            .text_secondary = ui_text_secondary,
            .text_disabled = ui_text_disabled,
            .border = ui_border,
            .border_light = ui_border_light,
            .border_focus = ui_border_focus,
            .selection = ui_selection,
            .selection_focused = ui_selection_focused,
            .cursor = ui_cursor,
            .line_number = ui_line_number,
            .line_number_current = ui_line_number_current,
            .line_number_bg = ui_line_number_bg,
            .syntax = SyntaxColors.dark(),
            .ui = UIColors.dark(),
        };
    }

    pub fn light() Theme {
        return Theme{
            .background = Vec4u{ .a = 250, .b = 250, .c = 252, .d = 255 },
            .background_alt = Vec4u{ .a = 240, .b = 240, .c = 242, .d = 255 },
            .surface = Vec4u{ .a = 255, .b = 255, .c = 255, .d = 255 },
            .surface_highlight = Vec4u{ .a = 245, .b = 245, .c = 247, .d = 255 },
            .text_primary = Vec4u{ .a = 40, .b = 40, .c = 45, .d = 255 },
            .text_secondary = Vec4u{ .a = 100, .b = 100, .c = 110, .d = 255 },
            .text_disabled = Vec4u{ .a = 160, .b = 160, .c = 170, .d = 255 },
            .border = Vec4u{ .a = 200, .b = 200, .c = 210, .d = 255 },
            .border_light = Vec4u{ .a = 220, .b = 220, .c = 230, .d = 255 },
            .border_focus = Vec4u{ .a = 70, .b = 140, .c = 210, .d = 255 },
            .selection = Vec4u{ .a = 200, .b = 220, .c = 255, .d = 100 },
            .selection_focused = Vec4u{ .a = 180, .b = 210, .c = 255, .d = 120 },
            .cursor = Vec4u{ .a = 50, .b = 50, .c = 60, .d = 200 },
            .line_number = Vec4u{ .a = 180, .b = 180, .c = 190, .d = 255 },
            .line_number_current = Vec4u{ .a = 80, .b = 80, .c = 90, .d = 255 },
            .line_number_bg = Vec4u{ .a = 245, .b = 245, .c = 247, .d = 255 },
            .syntax = SyntaxColors.light(),
            .ui = UIColors.light(),
        };
    }
};

pub const SyntaxColors = struct {
    keyword: Vec4u,
    string: Vec4u,
    number: Vec4u,
    function: Vec4u,
    type: Vec4u,
    comment: Vec4u,
    operator: Vec4u,
    builtin: Vec4u,
    constant: Vec4u,
    decorator: Vec4u,

    pub fn dark() SyntaxColors {
        return SyntaxColors{
            .keyword = syntax_keyword,
            .string = syntax_string,
            .number = syntax_number,
            .function = syntax_function,
            .type = syntax_type,
            .comment = syntax_comment,
            .operator = syntax_operator,
            .builtin = syntax_builtin,
            .constant = syntax_constant,
            .decorator = syntax_decorator,
        };
    }

    pub fn light() SyntaxColors {
        return SyntaxColors{
            .keyword = Vec4u{ .a = 150, .b = 80, .c = 180, .d = 255 },
            .string = Vec4u{ .a = 180, .b = 120, .c = 40, .d = 255 },
            .number = Vec4u{ .a = 80, .b = 140, .c = 100, .d = 255 },
            .function = Vec4u{ .a = 80, .b = 120, .c = 200, .d = 255 },
            .type = Vec4u{ .a = 180, .b = 120, .c = 80, .d = 255 },
            .comment = Vec4u{ .a = 140, .b = 145, .c = 155, .d = 255 },
            .operator = Vec4u{ .a = 140, .b = 110, .c = 170, .d = 255 },
            .builtin = Vec4u{ .a = 120, .b = 100, .c = 150, .d = 255 },
            .constant = Vec4u{ .a = 160, .b = 100, .c = 80, .d = 255 },
            .decorator = Vec4u{ .a = 180, .b = 100, .c = 150, .d = 255 },
        };
    }
};

pub const UIColors = struct {
    git_added: Vec4u,
    git_modified: Vec4u,
    git_removed: Vec4u,
    diagnostic_error: Vec4u,
    diagnostic_warn: Vec4u,
    diagnostic_info: Vec4u,

    pub fn dark() UIColors {
        return UIColors{
            .git_added = ui_gutter_git_added,
            .git_modified = ui_gutter_git_modified,
            .git_removed = ui_gutter_git_removed,
            .diagnostic_error = ui_gutter_diagnostic_error,
            .diagnostic_warn = ui_gutter_diagnostic_warn,
            .diagnostic_info = ui_gutter_diagnostic_info,
        };
    }

    pub fn light() UIColors {
        return UIColors{
            .git_added = Vec4u{ .a = 80, .b = 160, .c = 60, .d = 255 },
            .git_modified = Vec4u{ .a = 200, .b = 160, .c = 40, .d = 255 },
            .git_removed = Vec4u{ .a = 200, .b = 80, .c = 80, .d = 255 },
            .diagnostic_error = Vec4u{ .a = 220, .b = 80, .c = 80, .d = 255 },
            .diagnostic_warn = Vec4u{ .a = 220, .b = 160, .c = 60, .d = 255 },
            .diagnostic_info = Vec4u{ .a = 80, .b = 160, .c = 200, .d = 255 },
        };
    }
};

// =============================================================================
// Helper Functions
// =============================================================================

/// withAlpha returns a copy of the color with modified alpha.
pub fn withAlpha(color: Vec4u, alpha: u8) Vec4u {
    return Vec4u{ .a = color.a, .b = color.b, .c = color.c, .d = alpha };
}

/// blend blends two colors together with the given ratio (0-255).
pub fn blend(color1: Vec4u, color2: Vec4u, ratio: u8) Vec4u {
    const t = @as(f32, @floatFromInt(ratio)) / 255.0;
    return Vec4u{
        .a = @as(u8, @intCast(@as(f32, @floatFromInt(color1.a)) + t * (@as(f32, @floatFromInt(color2.a)) - @as(f32, @floatFromInt(color1.a))))),
        .b = @as(u8, @intCast(@as(f32, @floatFromInt(color1.b)) + t * (@as(f32, @floatFromInt(color2.b)) - @as(f32, @floatFromInt(color1.b))))),
        .c = @as(u8, @intCast(@as(f32, @floatFromInt(color1.c)) + t * (@as(f32, @floatFromInt(color2.c)) - @as(f32, @floatFromInt(color1.c))))),
        .d = @as(u8, @intCast(@as(f32, @floatFromInt(color1.d)) + t * (@as(f32, @floatFromInt(color2.d)) - @as(f32, @floatFromInt(color1.d))))),
    };
}
