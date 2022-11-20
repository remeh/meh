const std = @import("std");
const c = @import("clib.zig").c;
const expect = std.testing.expect;

const Rect2u = @import("vec.zig").Rect2u;
const Vec2u = @import("vec.zig").Vec2u;
const U8Slice = @import("u8slice.zig").U8Slice;

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
    glyph_pos: std.AutoHashMap(u21, Rect2u),
    /// while writing the atlas, current position to write a glyph.
    current_pos: Vec2u,
    /// while writing the atlas, we have to keep track of next Y to use since some
    /// glyph needs slightly more than font_size.
    next_y: usize,
};

pub const Font = struct {
    filepath: U8Slice,
    font_size: usize,
    ttf_font: *c.TTF_Font,
    atlas: FontAtlas,
    sdl_renderer: *c.SDL_Renderer,

    /// init loads the font at filepath and immediately
    /// creates a font atlas in a texture.
    /// filepath must be null-terminated.
    pub fn init(allocator: std.mem.Allocator, sdl_renderer: *c.SDL_Renderer, filepath: []const u8, font_size: usize) !Font {
        var fp = U8Slice.initEmpty(allocator);
        try fp.appendConst(filepath);

        var font: *c.TTF_Font = undefined;
        if (c.TTF_OpenFont(@ptrCast([*c]const u8, filepath), @intCast(c_int, font_size))) |f| {
            font = f;
        } else {
            std.log.err("{s}", .{c.TTF_GetError()});
            return FontError.CantLoadFont;
        }

        var rv = Font{
            .filepath = fp,
            .font_size = font_size,
            .ttf_font = font,
            .atlas = FontAtlas{
                .texture = undefined,
                .glyph_pos = std.AutoHashMap(u21, Rect2u).init(allocator),
                .current_pos = Vec2u{ .a = 0, .b = 0 },
                .next_y = font_size,
            },
            .sdl_renderer = sdl_renderer, // not owned
        };

        // create the font atlas

        var surface: *c.SDL_Surface = c.SDL_CreateRGBSurface(0, atlas_size, atlas_size, 32, 0x00, 0x00, 0x00, 0xFF);
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
        self.filepath.deinit();
        self.atlas.glyph_pos.deinit();
        c.SDL_DestroyTexture(self.atlas.texture);
        c.TTF_CloseFont(self.ttf_font);
    }

    // Methods
    // -------

    /// bindTexture generates a texture from the given SDL surface and stores it
    /// in the font atlas.
    fn bindTexture(self: *Font, surface: *c.SDL_Surface) !void {
        var texture = c.SDL_CreateTextureFromSurface(self.sdl_renderer, surface);
        if (texture == null) {
            std.log.err("Font.buildAtlas: can't create texture for font {s} size {d}", .{ self.filepath.bytes(), self.font_size });
            return FontError.CantBuildAtlas;
        }
        self.atlas.texture = texture.?;
    }

    /// buildAtlasRange generates the glyphs in the given range and write them in the
    /// given surface, making sure no glyphs overlaps using the atlas information.
    fn buildAtlasRange(self: *Font, surface: *c.SDL_Surface, start: u21, end: u21) !void {
        var text: *c.SDL_Surface = undefined;

        var white = c.SDL_Color{ .r = 255, .g = 255, .b = 255, .a = 255 };
        var bg = c.SDL_Color{ .r = 0, .g = 0, .b = 0, .a = 0 };

        var i: u21 = start;
        var b: [5]u8 = std.mem.zeroes([5]u8);

        while (i < end) : (i += 1) {
            if (i == 0xAD or i == 0x34F) {
                // FIXME(remy): for some reasons, these two glyphs crash the call to TTF_RenderUTF8_LCD
                continue;
            }

            var seq_size = try std.unicode.utf8Encode(@intCast(u21, i), b[0..]);
            b[seq_size] = 0;

            text = c.TTF_RenderUTF8_LCD(self.ttf_font, b[0..], white, bg);
            _ = c.SDL_BlitSurface(text, 0, surface, &c.SDL_Rect{ .x = @intCast(c_int, self.atlas.current_pos.a), .y = @intCast(c_int, self.atlas.current_pos.b), .w = text.w, .h = text.h });
            c.SDL_FreeSurface(text);

            try self.atlas.glyph_pos.put(
                i,
                Rect2u{
                    .a = self.atlas.current_pos.a,
                    .b = self.atlas.current_pos.b,
                    .c = @intCast(usize, text.w),
                    .d = @intCast(usize, text.h),
                },
            );

            // if we can't write two more chars, means there is no more room left on this line
            // move to the next one using the store "next line" position.
            if (self.atlas.current_pos.a + self.font_size > atlas_size) {
                self.atlas.current_pos.a = 0;
                self.atlas.current_pos.b = self.atlas.next_y;
                self.atlas.next_y = self.atlas.current_pos.b + self.font_size;
            } else {
                self.atlas.current_pos.a += @intCast(usize, text.w);
                if (self.atlas.next_y - self.atlas.current_pos.b < text.h) {
                    self.atlas.next_y = self.atlas.current_pos.b + @intCast(usize, text.h);
                }
            }
        }
    }

    /// glyphPos returns the glyph position in the current font atlas texture.
    /// Never errors and returns a placeholder for unknown glyphs (or if an internal error happened).
    fn glyphPos(self: Font, glyph: []const u8) Rect2u {
        if (std.mem.eql(u8, glyph, "")) {
            return Rect2u{ .a = 0, .b = 0, .c = self.font_size / 2, .d = self.font_size };
        }

        var g: u21 = std.unicode.utf8Decode(glyph) catch |err| {
            std.log.err("Font.glyphPos: can't decode utf8 glyph: {s}: {}", .{ glyph, err });
            return Rect2u{ .a = 0, .b = 0, .c = self.font_size / 2, .d = self.font_size };
        };

        var glyph_pos = self.atlas.glyph_pos.get(g);
        if (glyph_pos != null) {
            return glyph_pos.?;
        }

        // unknown glyph, return the placeholder.
        return Rect2u{ .a = 0, .b = 0, .c = self.font_size / 2, .d = self.font_size };
    }

    /// drawText draws the given text at the given position, position being in window coordinates.
    pub fn drawText(self: Font, position: Vec2u, text: []const u8) void {
        var i: usize = 0;
        var x_offset: usize = 0;

        while (i < text.len) {
            if (text[i] == 0 or text[i] == '\n') {
                break;
            }
            var seq_size: u3 = std.unicode.utf8ByteSequenceLength(text[i]) catch |err| {
                std.log.err("Font.drawText: error while checking utf8 byte sequence length in text {s}: {}", .{ text, err });
                i += 1;
                continue;
            };

            var glyph_rect_in_atlas = self.glyphPos(text[i .. i + seq_size]);

            var src_rect = c.SDL_Rect{
                .x = @intCast(c_int, glyph_rect_in_atlas.a),
                .y = @intCast(c_int, glyph_rect_in_atlas.b),
                .w = @intCast(c_int, glyph_rect_in_atlas.c),
                .h = @intCast(c_int, glyph_rect_in_atlas.d),
            };

            var dst_rect = c.SDL_Rect{
                .x = @intCast(c_int, position.a + x_offset),
                .y = @intCast(c_int, position.b),
                .w = @divTrunc(@intCast(c_int, self.font_size), 2),
                .h = @intCast(c_int, self.font_size),
            };

            _ = c.SDL_RenderCopy(self.sdl_renderer, self.atlas.texture, &src_rect, &dst_rect);

            i += seq_size;
            x_offset += self.font_size / 2;
        }
    }
};
