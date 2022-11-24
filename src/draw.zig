const std = @import("std");
const c = @import("clib.zig").c;

const Font = @import("font.zig").Font;
const Scaler = @import("scaler.zig").Scaler;
const U8Slice = @import("u8slice.zig").U8Slice;
const Vec4u = @import("vec.zig").Vec4u;
const Vec2u = @import("vec.zig").Vec2u;

pub const Draw = struct {
    pub fn fillRect(sdl_renderer: *c.SDL_Renderer, scaler: Scaler, position: Vec2u, size: Vec2u, color: Vec4u) void {
        var scaled_pos = scaler.Scale2u(position);
        var scaled_size = scaler.Scale2u(size);

        _ = c.SDL_SetRenderDrawColor(
            sdl_renderer,
            @intCast(u8, color.a),
            @intCast(u8, color.b),
            @intCast(u8, color.c),
            @intCast(u8, color.d),
        );

        var rect = c.SDL_Rect{
            .x = @intCast(c_int, scaled_pos.a),
            .y = @intCast(c_int, scaled_pos.b),
            .w = @intCast(c_int, scaled_size.a),
            .h = @intCast(c_int, scaled_size.b),
        };

        _ = c.SDL_RenderFillRect(sdl_renderer, &rect);
    }

    pub fn line(sdl_renderer: *c.SDL_Renderer, scaler: Scaler, start: Vec2u, end: Vec2u, color: Vec4u) void {
        var scaled_start = scaler.Scale2u(start);
        var scaled_end = scaler.Scale2u(end);

        _ = c.SDL_SetRenderDrawColor(
            sdl_renderer,
            @intCast(u8, color.a),
            @intCast(u8, color.b),
            @intCast(u8, color.c),
            @intCast(u8, color.d),
        );

        _ = c.SDL_RenderDrawLine(
            sdl_renderer,
            @intCast(c_int, scaled_start.a),
            @intCast(c_int, scaled_start.b),
            @intCast(c_int, scaled_end.a),
            @intCast(c_int, scaled_end.b),
        );
    }

    pub fn text(font: Font, scaler: Scaler, position: Vec2u, color: Vec4u, str: []const u8) void {
        var scaled_pos = scaler.Scale2u(position);
        font.drawText(scaled_pos, color, str);
    }

    pub fn glyph(font: Font, scaler: Scaler, position: Vec2u, color: Vec4u, str: []const u8) void {
        if (str.len == 0) {
            return;
        }

        // do not draw line returns
        if (str[0] == '\n') {
            return;
        }

        var scaled_pos = scaler.Scale2u(position);
        _ = font.drawGlyph(scaled_pos, color, str);
    }
};