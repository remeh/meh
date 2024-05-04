const std = @import("std");
const c = @import("clib.zig").c;

const Font = @import("font.zig").Font;
const Scaler = @import("scaler.zig").Scaler;
const U8Slice = @import("u8slice.zig").U8Slice;
const Vec4u = @import("vec.zig").Vec4u;
const Vec2u = @import("vec.zig").Vec2u;

pub const Draw = struct {
    pub fn fillRect(sdl_renderer: *c.SDL_Renderer, scaler: Scaler, position: Vec2u, size: Vec2u, color: Vec4u) void {
        const scaled_pos = scaler.Scale2u(position);
        const scaled_size = scaler.Scale2u(size);

        _ = c.SDL_SetRenderDrawColor(
            sdl_renderer,
            @as(u8, @intCast(color.a)),
            @as(u8, @intCast(color.b)),
            @as(u8, @intCast(color.c)),
            @as(u8, @intCast(color.d)),
        );

        var r = c.SDL_Rect{
            .x = @as(c_int, @intCast(scaled_pos.a)),
            .y = @as(c_int, @intCast(scaled_pos.b)),
            .w = @as(c_int, @intCast(scaled_size.a)),
            .h = @as(c_int, @intCast(scaled_size.b)),
        };

        _ = c.SDL_RenderFillRect(sdl_renderer, &r);
    }

    pub fn rect(sdl_renderer: *c.SDL_Renderer, scaler: Scaler, position: Vec2u, size: Vec2u, color: Vec4u) void {
        const scaled_pos = scaler.Scale2u(position);
        const scaled_size = scaler.Scale2u(size);

        _ = c.SDL_SetRenderDrawColor(
            sdl_renderer,
            @as(u8, @intCast(color.a)),
            @as(u8, @intCast(color.b)),
            @as(u8, @intCast(color.c)),
            @as(u8, @intCast(color.d)),
        );

        var r = c.SDL_Rect{
            .x = @as(c_int, @intCast(scaled_pos.a)),
            .y = @as(c_int, @intCast(scaled_pos.b)),
            .w = @as(c_int, @intCast(scaled_size.a)),
            .h = @as(c_int, @intCast(scaled_size.b)),
        };

        _ = c.SDL_RenderDrawRect(sdl_renderer, &r);
    }

    pub fn line(sdl_renderer: *c.SDL_Renderer, scaler: Scaler, start: Vec2u, end: Vec2u, color: Vec4u) void {
        const scaled_start = scaler.Scale2u(start);
        const scaled_end = scaler.Scale2u(end);

        _ = c.SDL_SetRenderDrawColor(
            sdl_renderer,
            @as(u8, @intCast(color.a)),
            @as(u8, @intCast(color.b)),
            @as(u8, @intCast(color.c)),
            @as(u8, @intCast(color.d)),
        );

        _ = c.SDL_RenderDrawLine(
            sdl_renderer,
            @as(c_int, @intCast(scaled_start.a)),
            @as(c_int, @intCast(scaled_start.b)),
            @as(c_int, @intCast(scaled_end.a)),
            @as(c_int, @intCast(scaled_end.b)),
        );
    }

    pub fn text(font: Font, scaler: Scaler, position: Vec2u, max_width: usize, color: Vec4u, str: []const u8) void {
        if (str.len == 0) {
            return;
        }

        const scaled_pos = scaler.Scale2u(position);
        const scaled_max_width = scaler.Scaleu(max_width);
        font.drawText(scaled_pos, scaled_max_width, color, str);
    }

    /// glyph draws the given glyph.
    pub fn glyph(font: Font, scaler: Scaler, position: Vec2u, color: Vec4u, str: []const u8) void {
        if (str.len == 0) {
            return;
        }

        // do not draw line returns
        if (str[0] == '\n') {
            return;
        }

        const scaled_pos = scaler.Scale2u(position);
        font.drawGlyph(scaled_pos, color, str);
    }
};
