const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const core = b.addModule("spec_kitty_mcp", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    const exe = b.addExecutable(.{
        .name = "spec-kitty-mcp",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "spec_kitty_mcp", .module = core },
            },
        }),
    });
    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| run_cmd.addArgs(args);

    const run_step = b.step("run", "Run spec-kitty-mcp");
    run_step.dependOn(&run_cmd.step);

    const core_tests = b.addTest(.{
        .root_module = core,
    });
    const run_core_tests = b.addRunArtifact(core_tests);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_core_tests.step);

    const smoke_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/read_only_smoke.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "spec_kitty_mcp", .module = core },
            },
        }),
    });
    const run_smoke_tests = b.addRunArtifact(smoke_tests);
    const smoke_step = b.step(
        "smoke-read-only",
        "Run read-only MCP smoke tests against the installed Spec Kitty CLI",
    );
    smoke_step.dependOn(&run_smoke_tests.step);

    const fmt_check = b.addFmt(.{
        .paths = &.{ "build.zig", "src", "tests" },
        .check = true,
    });

    const check_step = b.step("check", "Check formatting, compile, and run tests");
    check_step.dependOn(&fmt_check.step);
    check_step.dependOn(&exe.step);
    check_step.dependOn(&run_core_tests.step);
}
