pub const c = @cImport({
    @cDefine("CIMGUI_DEFINE_ENUMS_AND_STRUCTS", "1");
    @cDefine("CIMGUI_API", "extern \"C\" ");
    @cDefine("CIMGUI_USE_SDL", "1");
    @cDefine("CIMGUI_USE_OPENGL3", "1");

    @cInclude("SDL2/SDL.h");
    @cInclude("cimgui.h");
    @cInclude("cimgui_impl.h");
});

/// debugRect draws a pink debug rect.
pub fn debugRect(min: c.ImVec2, max: c.ImVec2) void {
    c.ImDrawList_AddRect(c.igGetForegroundDrawList_Nil(), min, max, 0xFFFF00FF, 1.0, 0, 0);
}
