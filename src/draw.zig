const std = @import("std");
const c = @import("clib.zig").c;

const Font = @import("font.zig").Font;
const Scaler = @import("scaler.zig").Scaler;
const U8Slice = @import("u8slice.zig").U8Slice;
const Vec4u = @import("vec.zig").Vec4u;
const Vec2u = @import("vec.zig").Vec2u;

pub const Draw = struct {
    /// fillRect fills a rectangle with the given color.
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

    /// shadow draws a subtle drop shadow beneath a rectangle.
    pub fn shadow(sdl_renderer: *c.SDL_Renderer, scaler: Scaler, position: Vec2u, size: Vec2u, offset_x: usize, offset_y: usize, blur: usize, color: Vec4u) void {
        const scaled_pos = scaler.Scale2u(position);
        const scaled_size = scaler.Scale2u(size);
        const scaled_offset_x = scaler.Scaleu(offset_x);
        const scaled_offset_y = scaler.Scaleu(offset_y);
        const scaled_blur = scaler.Scaleu(blur);

        // Draw multiple offset rectangles with decreasing opacity for blur effect
        var i: usize = 0;
        while (i <= scaled_blur) : (i += 1) {
            const alpha = @as(u8, @intCast(255 - (i * 255 / @max(1, scaled_blur + 1))));
            _ = c.SDL_SetRenderDrawColor(
                sdl_renderer,
                @as(u8, @intCast(color.a)),
                @as(u8, @intCast(color.b)),
                @as(u8, @intCast(color.c)),
                alpha,
            );

            var r = c.SDL_Rect{
                .x = @as(c_int, @intCast(scaled_pos.a + scaled_offset_x + i)),
                .y = @as(c_int, @intCast(scaled_pos.b + scaled_offset_y + i)),
                .w = @as(c_int, @intCast(scaled_size.a)),
                .h = @as(c_int, @intCast(scaled_size.b)),
            };
            _ = c.SDL_RenderFillRect(sdl_renderer, &r);
        }
    }

    /// gradientRect fills a rectangle with a vertical gradient.
    pub fn gradientRect(sdl_renderer: *c.SDL_Renderer, scaler: Scaler, position: Vec2u, size: Vec2u, top_color: Vec4u, bottom_color: Vec4u) void {
        const scaled_pos = scaler.Scale2u(position);
        const scaled_size = scaler.Scale2u(size);

        const height = @max(1, scaled_size.b);
        var y: usize = 0;
        while (y < height) : (y += 1) {
            const t = @as(f32, @floatFromInt(y)) / @as(f32, @floatFromInt(height - 1));
            const r = @as(u8, @intCast(@as(f32, @floatFromInt(top_color.a)) + t * (@as(f32, @floatFromInt(bottom_color.a)) - @as(f32, @floatFromInt(top_color.a)))));
            const g = @as(u8, @intCast(@as(f32, @floatFromInt(top_color.b)) + t * (@as(f32, @floatFromInt(bottom_color.b)) - @as(f32, @floatFromInt(top_color.b)))));
            const b = @as(u8, @intCast(@as(f32, @floatFromInt(top_color.c)) + t * (@as(f32, @floatFromInt(bottom_color.c)) - @as(f32, @floatFromInt(top_color.c)))));
            const a = @as(u8, @intCast(@as(f32, @floatFromInt(top_color.d)) + t * (@as(f32, @floatFromInt(bottom_color.d)) - @as(f32, @floatFromInt(top_color.d)))));

            _ = c.SDL_SetRenderDrawColor(sdl_renderer, r, g, b, a);

            var line_rect = c.SDL_Rect{
                .x = @as(c_int, @intCast(scaled_pos.a)),
                .y = @as(c_int, @intCast(scaled_pos.b + y)),
                .w = @as(c_int, @intCast(scaled_size.a)),
                .h = 1,
            };
            _ = c.SDL_RenderFillRect(sdl_renderer, &line_rect);
        }
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
