const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const lib_mod = b.createModule(.{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    const exe_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    exe_mod.addImport("zlisp_lib", lib_mod);

    const lib = b.addLibrary(.{
        .linkage = .static,
        .name = "zlisp",
        .root_module = lib_mod,
    });

    b.installArtifact(lib);
    const exe = b.addExecutable(.{
        .name = "zlisp",
        .root_module = exe_mod,
    });

    const pcre2_dep = b.dependency("pcre2", .{
        .target = target,
        .optimize = optimize,
    });
    exe.linkLibrary(pcre2_dep.artifact("pcre2-8"));

    const linenoise_dep = b.dependency("linenoise", .{
        .target = target,
        .optimize = optimize,
    });

    const linenoise_library = b.addLibrary(.{
        .name = "linenoise",
        .root_module = b.createModule(.{
            .target = target,
            .optimize = optimize,
        }),
    });
    linenoise_library.root_module.addSystemIncludePath(linenoise_dep.path("/usr/include"));
    linenoise_library.root_module.addCSourceFiles(.{
        .root = linenoise_dep.path("."),
        .files = &.{"linenoise.c"},
    });

    const linenoise_translate = b.addTranslateC(.{
        .root_source_file = linenoise_dep.path("linenoise.h"),
        .target = target,
        .optimize = optimize,
    });
    exe_mod.addImport("linenoise", b.createModule(.{
        .root_source_file = linenoise_translate.getOutput(),
        .target = target,
        .optimize = optimize,
    }));
    lib_mod.linkLibrary(linenoise_library);

    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    const lib_unit_tests = b.addTest(.{
        .root_module = lib_mod,
    });

    const run_lib_unit_tests = b.addRunArtifact(lib_unit_tests);

    const exe_unit_tests = b.addTest(.{
        .root_module = exe_mod,
    });

    const run_exe_unit_tests = b.addRunArtifact(exe_unit_tests);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_lib_unit_tests.step);
    test_step.dependOn(&run_exe_unit_tests.step);
}
