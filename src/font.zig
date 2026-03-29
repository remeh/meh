const std = @import("std");
const c = @import("clib.zig").c;
const expect = std.testing.expect;

const Scaler = @import("scaler.zig").Scaler;
const Vec4u = @import("vec.zig").Vec4u;
const Vec2u = @import("vec.zig").Vec2u;
const U8Slice = @import("u8slice.zig").U8Slice;
const UTF8Iterator = @import("u8slice.zig").UTF8Iterator;

const char_tab = @import("u8slice.zig").char_tab;
const char_linereturn = @import("u8slice.zig").char_linereturn;

const font_data = @embedFile("res/UbuntuMono-Regular.ttf");

pub const FontError = error{
    CantLoadFont,
    CantBuildAtlas,
};

/// atlas_size is the size of the generated atlas (i.e. etxture) containing all
/// the glyphs. Must be power of 2.
pub const atlas_size = 512;

/// FontAtlas is used to build a texture containing all glyphs needed to render
/// all texts of the application.
pub const FontAtlas = struct {
    texture: *c.SDL_Texture,
    glyph_pos: std.AutoHashMap(u21, Vec4u),
    /// while writing the atlas, current position to write a glyph.
    current_pos: Vec2u,
    /// while writing the atlas, we have to keep track of next Y to use since some
    /// glyph needs slightly more than font_size.
    next_y: usize,
};

pub const Font = struct {
    font_size: usize,
    ttf_font: *c.TTF_Font,
    atlas: FontAtlas,
    sdl_renderer: *c.SDL_Renderer,

    /// init loads the font at filepath and immediately
    /// creates a font atlas in a texture.
    /// filepath must be null-terminated.
    pub fn init(allocator: std.mem.Allocator, sdl_renderer: *c.SDL_Renderer, font_size: usize) !Font {
        // will be cleaned up by the TTF_OpenFontRW call (the second parameter set to 1).
        const rwops: *c.SDL_RWops = c.SDL_RWFromConstMem(font_data, font_data.len);

        var font: *c.TTF_Font = undefined;
        if (c.TTF_OpenFontRW(rwops, 1, @as(c_int, @intCast(font_size)))) |f| {
            font = f;
        } else {
            std.log.err("{s}", .{c.TTF_GetError()});
            return FontError.CantLoadFont;
        }

        var rv = Font{
            .font_size = font_size,
            .ttf_font = font,
            .atlas = FontAtlas{
                .texture = undefined,
                .glyph_pos = std.AutoHashMap(u21, Vec4u).init(allocator),
                .current_pos = Vec2u{ .a = 0, .b = 0 },
                .next_y = font_size,
            },
            .sdl_renderer = sdl_renderer, // not owned
        };

        // create the font atlas

        const surface: *c.SDL_Surface = c.SDL_CreateRGBSurface(0, atlas_size, atlas_size, 32, 0x00, 0x00, 0x00, 0x00);
        _ = c.SDL_SetSurfaceBlendMode(surface, c.SDL_BLENDMODE_BLEND);
        _ = c.SDL_SetColorKey(surface, c.SDL_TRUE, c.SDL_MapRGBA(surface.format, 0, 0, 0, 255));

        // replacement character goes first in the atlas
        try rv.buildAtlasRange(surface, @as(u21, std.unicode.replacement_character), @as(u21, std.unicode.replacement_character + 1));
        try rv.buildAtlasRange(surface, @as(u21, 0x001A), @as(u21, 0x007F));
        try rv.buildAtlasRange(surface, @as(u21, 0x00A0), @as(u21, 0x017F));

        try rv.bindTexture(surface);
        c.SDL_FreeSurface(surface);

        return rv;
    }

    pub fn deinit(self: *Font) void {
        self.atlas.glyph_pos.deinit();
        c.SDL_DestroyTexture(self.atlas.texture);
        c.TTF_CloseFont(self.ttf_font);
    }

    // Methods
    // -------

    /// bindTexture generates a texture from the given SDL surface and stores it
    /// in the font atlas.
    fn bindTexture(self: *Font, surface: *c.SDL_Surface) !void {
        const texture = c.SDL_CreateTextureFromSurface(self.sdl_renderer, surface);
        if (texture == null) {
            std.log.err("Font.buildAtlas: can't create texture for font size {d}", .{self.font_size});
            return FontError.CantBuildAtlas;
        }

        self.atlas.texture = texture.?;
    }

    /// buildAtlasRange generates the glyphs in the given range and write them in the
    /// given surface, making sure no glyphs overlaps using the atlas information.
    fn buildAtlasRange(self: *Font, surface: *c.SDL_Surface, start: u21, end: u21) !void {
        var text: *c.SDL_Surface = undefined;

        const white = c.SDL_Color{ .r = 255, .g = 255, .b = 255, .a = 255 };
        const bg = c.SDL_Color{ .r = 0, .g = 0, .b = 0, .a = 0 };

        var i: u21 = start;
        var b: [5]u8 = std.mem.zeroes([5]u8);

        while (i < end) : (i += 1) {
            if (i == 0xAD or i == 0x34F) {
                // FIXME(remy): for some reasons, these two glyphs crash the call to TTF_RenderUTF8_LCD
                continue;
            }

            const glyph_bytes_size = try std.unicode.utf8Encode(@as(u21, @intCast(i)), b[0..]);
            b[glyph_bytes_size] = 0;

            text = c.TTF_RenderUTF8_LCD(self.ttf_font, b[0..], white, bg);

            // we store the glyph size because we'll need it after having freed the text surface.
            const glyph_size = Vec2u{ .a = @as(usize, @intCast(text.w)), .b = @as(usize, @intCast(text.h)) };

            var rect: c.SDL_Rect = c.SDL_Rect{
                .x = @as(c_int, @intCast(self.atlas.current_pos.a)),
                .y = @as(c_int, @intCast(self.atlas.current_pos.b)),
                .w = @as(c_int, @intCast(glyph_size.a)),
                .h = @as(c_int, @intCast(glyph_size.b)),
            };
            _ = c.SDL_BlitSurface(text, 0, surface, &rect);
            c.SDL_FreeSurface(text);

            try self.atlas.glyph_pos.put(
                i,
                Vec4u{
                    .a = self.atlas.current_pos.a,
                    .b = self.atlas.current_pos.b,
                    .c = @as(usize, @intCast(glyph_size.a)),
                    .d = @as(usize, @intCast(glyph_size.b)),
                },
            );

            // if we can't write two more chars, means there is no more room left on this line
            // move to the next one using the store "next line" position.
            if (self.atlas.current_pos.a + self.font_size > atlas_size) {
                self.atlas.current_pos.a = 0;
                self.atlas.current_pos.b = self.atlas.next_y;
                self.atlas.next_y = self.atlas.current_pos.b + self.font_size;
            } else {
                self.atlas.current_pos.a += @as(usize, @intCast(glyph_size.a));
                if (self.atlas.next_y - self.atlas.current_pos.b < glyph_size.b) {
                    self.atlas.next_y = self.atlas.current_pos.b + @as(usize, @intCast(glyph_size.b));
                }
            }
        }
    }

    /// glyphPos returns the glyph position in the current font atlas texture.
    /// Never errors and returns a placeholder for unknown glyphs (or if an internal error happened).
    fn glyphPos(self: Font, glyph: []const u8) Vec4u {
        if (std.mem.eql(u8, glyph, "")) {
            return Vec4u{ .a = 0, .b = 0, .c = self.font_size / 2, .d = self.font_size };
        }

        const g: u21 = std.unicode.utf8Decode(glyph) catch |err| {
            std.log.err("Font.glyphPos: can't decode utf8 glyph: {s}: {}", .{ glyph, err });
            return Vec4u{ .a = 0, .b = 0, .c = self.font_size / 2, .d = self.font_size };
        };

        const glyph_pos = self.atlas.glyph_pos.get(g);
        if (glyph_pos != null) {
            return glyph_pos.?;
        }

        // unknown glyph, return the placeholder.
        return Vec4u{ .a = 0, .b = 0, .c = self.font_size / 2, .d = self.font_size };
    }

    /// drawGlyph draws the glyph starting at the first byte of the given `str`.
    pub fn drawGlyph(self: Font, position: Vec2u, color: Vec4u, str: []const u8) void {
        if (str.len == 0) {
            return;
        }

        const glyph_rect_in_atlas = self.glyphPos(str);
        var src_rect = c.SDL_Rect{
            .x = @as(c_int, @intCast(glyph_rect_in_atlas.a)),
            .y = @as(c_int, @intCast(glyph_rect_in_atlas.b)),
            .w = @as(c_int, @intCast(glyph_rect_in_atlas.c)),
            .h = @as(c_int, @intCast(glyph_rect_in_atlas.d)),
        };

        var dst_rect = c.SDL_Rect{
            .x = @as(c_int, @intCast(position.a)),
            .y = @as(c_int, @intCast(position.b)),
            .w = @divTrunc(@as(c_int, @intCast(self.font_size)), 2),
            .h = @as(c_int, @intCast(self.font_size)),
        };
        const pdst_rect: *c.SDL_Rect = &dst_rect; // XXX(remy): don't use me

        _ = c.SDL_SetTextureColorMod(self.atlas.texture, @as(u8, @intCast(color.a)), @as(u8, @intCast(color.b)), @as(u8, @intCast(color.c)));
        _ = c.SDL_RenderCopy(self.sdl_renderer, self.atlas.texture, &src_rect, pdst_rect);
    }

    /// drawText draws the given text at the given position, position being in window coordinates.
    /// If `max_width` > 0, stops drawing when it has been reached.
    pub fn drawText(self: Font, position: Vec2u, max_width: usize, color: Vec4u, text: []const u8) void {
        var x_offset: usize = 0;
        var it = UTF8Iterator.init(text, 0) catch |err| {
            std.log.err("Font.drawText: {}", .{err});
            return;
        };

        while (true) {
            if (it.glyph()[0] == 0 or it.glyph()[0] == char_linereturn) {
                break;
            }

            if (it.glyph()[0] == char_tab) {
                x_offset += self.font_size * 2;
            } else {
                self.drawGlyph(Vec2u{ .a = position.a + x_offset, .b = position.b }, color, it.glyph());
                x_offset += self.font_size / 2;
            }

            if (max_width > 0 and x_offset >= max_width) {
                break;
            }

            if (!it.next()) {
                break;
            }
        }
    }

    /// textPixelSize returns how many pixel are needed to draw the given text on one line.
    pub fn textPixelSize(self: Font, scaler: Scaler, text: []const u8) usize {
        if (text.len == 0) {
            return 0;
        }
        const unscaled = @divTrunc(self.font_size, 2) * text.len;
        const scaled = @as(usize, @intFromFloat(@divTrunc(@as(f32, @floatFromInt(unscaled)), scaler.scale)));
        return scaled;
    }
};
