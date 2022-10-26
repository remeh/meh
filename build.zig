const std = @import("std");
const builtin = @import("builtin");

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
    prepare(meh, target, mode);
    meh.install();

    const run_cmd = meh.run();
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    const meh_tests = b.addTest("src/tests.zig");
    prepare(meh_tests, target, mode);
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&meh_tests.step);
}

fn prepare(step: *std.build.LibExeObjStep, target: std.zig.CrossTarget, mode: std.builtin.Mode) void {
    step.setTarget(target);
    step.setBuildMode(mode);
    // meh.use_stage1 = true;

    // find "cimgui.h"
    step.addIncludePath("include/");
    if (builtin.os.tag == .macos) {
        // find "SDL2/SDL2.h"
        step.addIncludePath("/opt/homebrew/include");
        // find libSDL2.dylib
        step.addLibraryPath("/opt/homebrew/lib");
    }
    // find local libcimgui.dylib
    step.addLibraryPath("lib/");
    // linked libraries
    step.linkSystemLibrary("SDL2");
    // step.linkSystemLibrary("GL");
    step.linkSystemLibrary("cimgui");
    switch (builtin.os.tag) {
        .linux => step.linkLibC(),
        .macos => {
            step.linkFramework("OpenGl");
            step.linkFramework("CoreFoundation");
        },
        else => {},
    }
}
