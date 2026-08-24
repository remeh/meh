const std = @import("std");
const builtin = @import("builtin");

pub fn build(b: *std.Build) void {
    // Standard target options allows the person running `zig build` to choose
    // what target to build for. Here we do not override the defaults, which
    // means any target is allowed, and the default is native. Other options
    // for restricting supported target set are available.
    const target = b.standardTargetOptions(.{});

    // Standard optimization options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall. Here we do not
    // set a preferred release mode, allowing the user to decide how to optimize.
    const optimize = b.standardOptimizeOption(.{});

    // Generate Zig bindings for SDL2 / SDL2_ttf from the C headers. `@cImport`
    // was removed from recent Zig versions, so we translate the C headers up
    // front with the `translate-c` build step instead.
    const sdl_bindings = b.addTranslateC(.{
        .root_source_file = b.path("src/sdl_bindings.h"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    if (builtin.os.tag == .macos) {
        sdl_bindings.addIncludePath(.{ .cwd_relative = "/opt/homebrew/include" });
        sdl_bindings.addAfterIncludePath(.{ .cwd_relative = "/opt/homebrew/include/SDL2" });
    } else {
        sdl_bindings.addIncludePath(b.path("src"));
    }
    const sdl_module = sdl_bindings.createModule();
    // The translated SDL API is exposed to clib.zig via `@import("c")`.
    // (`@import("std")` used by the generated bindings is resolved by the
    // compiler automatically.)

    const meh = b.addExecutable(.{
        .name = "meh",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    meh.root_module.addImport("c", sdl_module);

    prepare(meh);

    // default build output
    b.installArtifact(meh);

    // macOS application artifact
    if (builtin.os.tag == .macos) {
        //        // copy the macOS app def
        //        const install_dir = b.addInstallDirectory(.{
        //            .source_dir = b.path("src/macos"), // source of the files to copy
        //            .install_dir = .prefix, // install to zig-out/
        //            .install_subdir = "macos", // subdirectory in the install path
        //        });
        //        b.getInstallStep().dependOn(&install_dir.step);
        const install_macos_release = b.addInstallArtifact(meh, .{
            .dest_dir = .{ .override = .{ .custom = "macos/meh.app/contents/MacOS/" } },
        });
        b.getInstallStep().dependOn(&install_macos_release.step);
    }

    const run_cmd = b.addRunArtifact(meh);
    run_cmd.step.dependOn(b.getInstallStep());
    run_cmd.addPassthruArgs();

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    const test_step = b.step("test", "Run unit tests");
    const meh_tests = b.addTest(.{
        .name = "meh unit tests",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/tests.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    meh_tests.root_module.addImport("c", sdl_module);
    const run_tests = b.addRunArtifact(meh_tests);
    prepare(meh_tests);
    test_step.dependOn(&run_tests.step);
}

fn prepare(step: *std.Build.Step.Compile) void {
    // step.use_stage1 = true;

    // linked libraries
    step.root_module.linkSystemLibrary("SDL2", .{});
    // SDL2_ttf depends on SDL2, and its pkg-config flags include `-lSDL2`.
    // Since we link SDL2 explicitly above, disable pkg-config for SDL2_ttf
    // to avoid linking SDL2 twice (macOS dyld rejects duplicate dylibs).
    step.root_module.linkSystemLibrary("SDL2_ttf", .{ .use_pkg_config = .no });
    switch (builtin.os.tag) {
        .macos => {
            step.root_module.addLibraryPath(.{ .cwd_relative = "/opt/homebrew/lib" });
            step.root_module.addIncludePath(.{ .cwd_relative = "/opt/homebrew/include" });
            step.root_module.link_libc = true;
        },

        .linux => step.root_module.link_libc = true,
        else => {},
    }
}
