const std = @import("std");

pub fn build(b: *std.Build) void {
    const isV11 = @import("builtin").zig_version.minor == 11;

    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const lib_tests = b.addTest(.{
        .name = "term",
        .root_source_file = .{ .path = "term/term.zig" },
        .target = target,
        .optimize = optimize,
    });

    const lib_test_doc = lib_tests;
    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&lib_tests.step);

    const doc_step = b.step("docs", "Generate documentation");
    doc_step.dependOn(&lib_test_doc.step);

    const term_module = if (isV11)
        b.addModule("term", .{ .source_file = .{ .path = "term/term.zig" } })
    else
        b.addModule("term", .{ .root_source_file = .{ .path = "term/term.zig" } });

    const exe = b.addExecutable(.{
        .name = "basic",
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });
    if (isV11) {
        exe.addModule("term", term_module);
    } else {
        exe.root_module.addImport("term", term_module);
    }
    b.installArtifact(exe);

    const run_step = b.addRunArtifact(exe);
    run_step.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_step.addArgs(args);
    }

    const step = b.step("run", "Runs the executable");
    step.dependOn(&run_step.step);
}
