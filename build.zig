const std = @import("std");
const builtin = @import("builtin");

pub fn build(b: *std.Build) void {
    b.verbose = true;

    // Standard target options allows the person running `zig build` to choose
    // what target to build for. Here we do not override the defaults, which
    // means any target is allowed, and the default is native. Other options
    // for restricting supported target set are available.
    const target = b.standardTargetOptions(.{});

    // Standard optimization options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall. Here we do not
    // set a preferred release mode, allowing the user to decide how to optimize.
    const optimize = b.standardOptimizeOption(.{});

    const meh = b.addExecutable(.{
        .name = "meh",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    prepare(meh);
    b.installArtifact(meh);

    const run_cmd = b.addRunArtifact(meh);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    const test_step = b.step("test", "Run unit tests");
    const meh_tests = b.addTest(.{
        .name = "meh unit tests",
        .root_source_file = b.path("src/tests.zig"),
        .target = target,
        .optimize = optimize,
    });
    const run_tests = b.addRunArtifact(meh_tests);
    prepare(meh_tests);
    test_step.dependOn(&run_tests.step);
}

fn prepare(step: *std.Build.Step.Compile) void {
    // step.use_stage1 = true;

    // linked libraries
    step.linkSystemLibrary("git2");
    step.linkSystemLibrary("SDL2");
    step.linkSystemLibrary("SDL2_ttf");
    switch (builtin.os.tag) {
        .linux => step.linkLibC(),
        else => {},
    }
}
