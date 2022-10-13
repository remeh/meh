const std = @import("std");

pub fn build(b: *std.build.Builder) void {
    // Standard target options allows the person running `zig build` to choose
    // what target to build for. Here we do not override the defaults, which
    // means any target is allowed, and the default is native. Other options
    // for restricting supported target set are available.
    const target = b.standardTargetOptions(.{});

    // Standard release options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall.
    const mode = b.standardReleaseOptions();

    // const imgui_sdl = b.addSharedLibrary("imgui_sdl", "lib/imgui_impl_sdl.cpp", .unversioned);
    // imgui_sdl.addIncludePath("include/");
    // imgui_sdl.install();

    const meh = b.addExecutable("meh", "src/main.zig");
    meh.setTarget(target);
    meh.setBuildMode(mode);
    meh.use_stage1 = true;

    // find "cimgui.h"
    meh.addIncludePath("include/");
    // find "SDL2/SDL2.h"
    meh.addIncludePath("/opt/homebrew/include");
    // find libSDL2.dylib
    meh.addLibraryPath("/opt/homebrew/lib");
    // find local libcimgui.dylib
    meh.addLibraryPath("lib/");
    // linked libraries
    meh.linkSystemLibrary("SDL2");
    meh.linkSystemLibrary("cimgui");

    meh.install();

    const run_cmd = meh.run();
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    const meh_tests = b.addTest("src/main.zig");
    meh_tests.setTarget(target);
    meh_tests.setBuildMode(mode);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&meh_tests.step);
}
