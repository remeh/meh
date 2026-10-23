const std = @import("std");

const Vec4u = @import("vec.zig").Vec4u;

// =============================================================================
// Theme
//
// A single, cohesive dark palette the whole UI is built from: black and dark
// grays, with a small set of muted accents (blue, cyan, green, amber) — no
// purple, and no color cast in the backgrounds.
//
// Backgrounds go from the deepest (`crust`, used for overlays and for text
// drawn on an accent) to the editor background (`base`), with `mantle` for the
// bars and panels that frame the text, and `surface0..2` for borders and
// hover states. The grays above that (`overlay*`, `subtext*`, `text`) are what
// text and muted elements are drawn with.
// =============================================================================

pub const crust = Vec4u{ .a = 10, .b = 10, .c = 11, .d = 255 };
pub const mantle = Vec4u{ .a = 16, .b = 16, .c = 18, .d = 255 };
pub const base = Vec4u{ .a = 22, .b = 22, .c = 24, .d = 255 };
pub const surface0 = Vec4u{ .a = 38, .b = 38, .c = 42, .d = 255 };
pub const surface1 = Vec4u{ .a = 52, .b = 52, .c = 57, .d = 255 };
pub const surface2 = Vec4u{ .a = 68, .b = 68, .c = 74, .d = 255 };
pub const overlay0 = Vec4u{ .a = 98, .b = 98, .c = 106, .d = 255 };
pub const overlay1 = Vec4u{ .a = 126, .b = 126, .c = 134, .d = 255 };
pub const overlay2 = Vec4u{ .a = 152, .b = 152, .c = 160, .d = 255 };
pub const subtext0 = Vec4u{ .a = 178, .b = 178, .c = 186, .d = 255 };
pub const subtext1 = Vec4u{ .a = 203, .b = 203, .c = 210, .d = 255 };
pub const text = Vec4u{ .a = 230, .b = 230, .c = 235, .d = 255 };

// =============================================================================
// Accent Colors
//
// Used sparingly: they carry meaning (a mode, a warning, a selection), they
// are not there to decorate. All of them stay readable on `base`.
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
pub const syntax_type = subtext1; // types, constants: bright, but plain
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
pub const ui_overlay = Vec4u{ .a = 10, .b = 10, .c = 11, .d = 178 };

pub const ui_text_primary = text;
pub const ui_text_secondary = subtext0;
pub const ui_text_muted = overlay0;
/// text drawn on top of an accent-colored badge.
pub const ui_text_on_accent = crust;

pub const ui_border = surface1;
pub const ui_border_light = surface2;
/// the 80 and 120 columns limits.
pub const ui_column_limit = Vec4u{ .a = 255, .b = 255, .c = 255, .d = 14 };

pub const ui_selection = Vec4u{ .a = 122, .b = 162, .c = 212, .d = 62 };
pub const ui_selection_focused = Vec4u{ .a = 122, .b = 162, .c = 212, .d = 95 };

/// background of the line the cursor is on.
pub const ui_current_line = Vec4u{ .a = 255, .b = 255, .c = 255, .d = 18 };
/// background/border of the occurrences of the word under the cursor.
pub const ui_match = Vec4u{ .a = 122, .b = 162, .c = 212, .d = 36 };
pub const ui_match_border = Vec4u{ .a = 122, .b = 162, .c = 212, .d = 120 };
/// very light vertical line marking an indentation level.
pub const ui_indent_guide = Vec4u{ .a = 255, .b = 255, .c = 255, .d = 12 };

pub const ui_cursor = Vec4u{ .a = 255, .b = 255, .c = 255, .d = 120 };
pub const ui_cursor_insert = sand;
pub const ui_cursor_command = Vec4u{ .a = 217, .b = 160, .c = 102, .d = 220 };
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
pub const ui_minimap_line_highlight = Vec4u{ .a = 122, .b = 162, .c = 212, .d = 210 };
pub const ui_minimap_viewport = Vec4u{ .a = 255, .b = 255, .c = 255, .d = 16 };
pub const ui_minimap_viewport_border = Vec4u{ .a = 126, .b = 126, .c = 134, .d = 130 };

// =============================================================================
// Helper Functions
// =============================================================================

/// withAlpha returns a copy of the color with modified alpha.
pub fn withAlpha(color: Vec4u, alpha: u8) Vec4u {
    return Vec4u{ .a = color.a, .b = color.b, .c = color.c, .d = alpha };
}

/// relative luminance of a color, as WCAG defines it.
fn luminance(color: Vec4u) f32 {
    const channel = struct {
        fn value(v: usize) f32 {
            const c = @as(f32, @floatFromInt(v)) / 255.0;
            return if (c <= 0.03928) c / 12.92 else std.math.pow(f32, (c + 0.055) / 1.055, 2.4);
        }
    }.value;

    return 0.2126 * channel(color.a) + 0.7152 * channel(color.b) + 0.0722 * channel(color.c);
}

/// contrastRatio returns the contrast between `color` drawn over `under` — the
/// translucent colors are blended first — and `under` itself.
fn contrastRatio(color: Vec4u, under: Vec4u) f32 {
    const alpha: f32 = @as(f32, @floatFromInt(color.d)) / 255.0;
    const mixed = struct {
        fn channel(over: usize, below: usize, at: f32) usize {
            const value = @as(f32, @floatFromInt(over)) * at + @as(f32, @floatFromInt(below)) * (1.0 - at);
            return @intFromFloat(@min(@max(value, 0), 255));
        }
    }.channel;

    const blended = Vec4u{
        .a = mixed(color.a, under.a, alpha),
        .b = mixed(color.b, under.b, alpha),
        .c = mixed(color.c, under.c, alpha),
        .d = 255,
    };

    const here = luminance(blended);
    const there = luminance(under);
    const lighter, const darker = if (here > there) .{ here, there } else .{ there, here };
    return (lighter + 0.05) / (darker + 0.05);
}

// the palette is only cohesive if everything the user is meant to read stays
// readable on top of the editor background: it keeps the theme honest whenever
// one of its colors changes.
test "colors: what is drawn on the editor stays readable" {
    const Ink = struct { name: []const u8, color: Vec4u };
    const inks = [_]Ink{
        .{ .name = "ui_text_primary", .color = ui_text_primary },
        .{ .name = "ui_text_secondary", .color = ui_text_secondary },
        .{ .name = "ui_text_muted", .color = ui_text_muted },
        .{ .name = "ui_line_number", .color = ui_line_number },
        .{ .name = "ui_line_number_current", .color = ui_line_number_current },
        .{ .name = "syntax_keyword", .color = syntax_keyword },
        .{ .name = "syntax_string", .color = syntax_string },
        .{ .name = "syntax_function", .color = syntax_function },
        .{ .name = "syntax_comment", .color = syntax_comment },
        .{ .name = "syntax_number", .color = syntax_number },
        .{ .name = "syntax_type", .color = syntax_type },
        .{ .name = "syntax_url", .color = syntax_url },
        .{ .name = "syntax_todo", .color = syntax_todo },
        .{ .name = "syntax_done", .color = syntax_done },
        .{ .name = "blue", .color = blue },
        .{ .name = "cyan", .color = cyan },
        .{ .name = "green", .color = green },
        .{ .name = "orange", .color = orange },
        .{ .name = "yellow", .color = yellow },
        .{ .name = "red", .color = red },
        .{ .name = "sand", .color = sand },
    };

    // the mode badge is the one thing drawn on a colored background
    try std.testing.expect(contrastRatio(ui_text_on_accent, blue) > 4.5);
    try std.testing.expect(contrastRatio(ui_text_on_accent, green) > 4.5);
    try std.testing.expect(contrastRatio(ui_text_on_accent, orange) > 4.5);
    try std.testing.expect(contrastRatio(ui_text_on_accent, yellow) > 4.5);

    var worst: f32 = 100;
    var worst_ink: []const u8 = "";
    for (inks) |ink| {
        const ratio = contrastRatio(ink.color, base);
        if (ratio < worst) {
            worst, worst_ink = .{ ratio, ink.name };
        }
    }

    if (worst < 2.5) std.debug.print("worst ink: {s} ({d:.2})\n", .{ worst_ink, worst });
    try std.testing.expect(worst > 2.5);
}

// the backgrounds are dark grays, not tinted blues or purples, and they stay
// ordered from the deepest to the editor background.
test "colors: the backgrounds are neutral and ordered" {
    const ramp = [_]Vec4u{ crust, mantle, base, surface0, surface1, surface2 };

    for (ramp, 0..) |color, i| {
        // black & gray: the three channels stay within a hair of each other
        const spread = @max(color.a, @max(color.b, color.c)) - @min(color.a, @min(color.b, color.c));
        if (spread > 6) std.debug.print("background #{d} is tinted: ({d},{d},{d})\n", .{ i, color.a, color.b, color.c });
        try std.testing.expect(spread <= 6);

        if (i > 0) {
            try std.testing.expect(luminance(color) > luminance(ramp[i - 1]));
        }
    }
}
