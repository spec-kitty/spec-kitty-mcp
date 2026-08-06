const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const version = b.option(
        []const u8,
        "version",
        "Version reported by the spec-kitty-mcp binary",
    ) orelse "0.1.0-dev";
    const strip = b.option(bool, "strip", "Strip symbols from the executable") orelse false;
    const build_options = b.addOptions();
    build_options.addOption([]const u8, "version", version);

    const core = b.addModule("spec_kitty_mcp", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "build_options", .module = build_options.createModule() },
        },
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
    exe.root_module.strip = strip;
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

    const mutation_smoke_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/mutation_smoke.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "spec_kitty_mcp", .module = core },
            },
        }),
    });
    const run_mutation_smoke_tests = b.addRunArtifact(mutation_smoke_tests);
    const mutation_smoke_step = b.step(
        "smoke-mutations",
        "Run mutation MCP smoke tests against the installed Spec Kitty CLI",
    );
    mutation_smoke_step.dependOn(&run_mutation_smoke_tests.step);

    const fmt_check = b.addFmt(.{
        .paths = &.{ "build.zig", "src", "tests" },
        .check = true,
    });

    const check_step = b.step("check", "Check formatting, compile, and run tests");
    check_step.dependOn(&fmt_check.step);
    check_step.dependOn(&exe.step);
    check_step.dependOn(&run_core_tests.step);
}
