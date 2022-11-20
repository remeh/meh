const std = @import("std");
const c = @import("clib.zig").c;

const Font = @import("font.zig").Font;
const Scaler = @import("scaler.zig").Scaler;
const U8Slice = @import("u8slice.zig").U8Slice;
const Vec2u = @import("vec.zig").Vec2u;

pub const Draw = struct {
    pub fn fill_rect(sdl_renderer: *c.SDL_Renderer, scaler: Scaler, position: Vec2u, size: Vec2u, color: c.SDL_Color) void {
        var scaled_pos = scaler.Scale2u(position);
        var scaled_size = scaler.Scale2u(size);

        _ = c.SDL_SetRenderDrawColor(sdl_renderer, color.r, color.g, color.b, color.a);
        var rect = c.SDL_Rect{
            .x = @intCast(c_int, scaled_pos.a),
            .y = @intCast(c_int, scaled_pos.b),
            .w = @intCast(c_int, scaled_size.a),
            .h = @intCast(c_int, scaled_size.b),
        };
        _ = c.SDL_RenderFillRect(sdl_renderer, &rect);
    }

    pub fn draw_text(font: Font, scaler: Scaler, position: Vec2u, text: []const u8) void {
        _ = c.SDL_SetRenderDrawColor(font.sdl_renderer, 255, 255, 255, 255);
        var scaled_pos = scaler.Scale2u(position);
        font.drawText(scaled_pos, text);
    }
};
