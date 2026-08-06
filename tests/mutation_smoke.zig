const std = @import("std");
const Io = std.Io;

const app = @import("spec_kitty_mcp");

const policy_json =
    \\{"orchestrator_id":"zig-mcp-smoke","orchestrator_version":"0.1.0","agent_family":"codex","approval_mode":"manual","sandbox_mode":"workspace-write","network_mode":"restricted","dangerous_flags":[]}
;

fn runCommand(
    allocator: std.mem.Allocator,
    io: Io,
    root: []const u8,
    argv: []const []const u8,
) ![]u8 {
    const result = try std.process.run(allocator, io, .{
        .argv = argv,
        .cwd = .{ .path = root },
        .stdout_limit = .limited(1024 * 1024),
        .stderr_limit = .limited(1024 * 1024),
    });
    defer allocator.free(result.stderr);
    errdefer allocator.free(result.stdout);

    const exit_code = switch (result.term) {
        .exited => |code| code,
        else => return error.CommandFailed,
    };
    if (exit_code != 0) return error.CommandFailed;
    return result.stdout;
}

fn runCommands(
    allocator: std.mem.Allocator,
    io: Io,
    root: []const u8,
    commands: []const []const []const u8,
) !void {
    for (commands) |argv| {
        const output = try runCommand(allocator, io, root, argv);
        allocator.free(output);
    }
}

fn exchange(server: *app.mcp.Server, line: []const u8) ![]u8 {
    var output: Io.Writer.Allocating = .init(std.testing.allocator);
    errdefer output.deinit();

    try server.handleLine(std.testing.allocator, line, &output.writer);
    return output.toOwnedSlice();
}

fn callTool(
    allocator: std.mem.Allocator,
    server: *app.mcp.Server,
    id: u32,
    name: []const u8,
    arguments: []const u8,
) ![]u8 {
    const request = try std.fmt.allocPrint(
        allocator,
        "{{\"jsonrpc\":\"2.0\",\"id\":{d},\"method\":\"tools/call\",\"params\":{{\"name\":{f},\"arguments\":{s}}}}}",
        .{ id, std.json.fmt(name, .{}), arguments },
    );
    defer allocator.free(request);
    return exchange(server, request);
}

fn expectToolResult(
    allocator: std.mem.Allocator,
    response: []const u8,
    is_error: bool,
    error_code: ?[]const u8,
) !void {
    var parsed = try std.json.parseFromSlice(std.json.Value, allocator, response, .{});
    defer parsed.deinit();
    const result = parsed.value.object.get("result") orelse return error.InvalidToolResponse;
    if (result != .object) return error.InvalidToolResponse;
    const actual_error = result.object.get("isError") orelse return error.InvalidToolResponse;
    if (actual_error != .bool) return error.InvalidToolResponse;
    try std.testing.expectEqual(is_error, actual_error.bool);

    if (error_code) |expected| {
        const envelope = result.object.get("structuredContent") orelse
            return error.InvalidToolResponse;
        if (envelope != .object) return error.InvalidToolResponse;
        const actual = envelope.object.get("error_code") orelse
            return error.InvalidToolResponse;
        if (actual != .string) return error.InvalidToolResponse;
        try std.testing.expectEqualStrings(expected, actual.string);
    }
}

fn dataStringFromResponse(
    allocator: std.mem.Allocator,
    response: []const u8,
    key: []const u8,
) ![]u8 {
    var parsed = try std.json.parseFromSlice(std.json.Value, allocator, response, .{});
    defer parsed.deinit();
    const result = parsed.value.object.get("result") orelse return error.InvalidToolResponse;
    const envelope = result.object.get("structuredContent") orelse
        return error.InvalidToolResponse;
    const data = envelope.object.get("data") orelse return error.InvalidToolResponse;
    const value = data.object.get(key) orelse
        return error.InvalidToolResponse;
    if (value != .string) return error.InvalidToolResponse;
    return allocator.dupe(u8, value.string);
}

fn expectDataBoolean(
    allocator: std.mem.Allocator,
    response: []const u8,
    key: []const u8,
    expected: bool,
) !void {
    var parsed = try std.json.parseFromSlice(std.json.Value, allocator, response, .{});
    defer parsed.deinit();
    const result = parsed.value.object.get("result") orelse return error.InvalidToolResponse;
    const envelope = result.object.get("structuredContent") orelse
        return error.InvalidToolResponse;
    const data = envelope.object.get("data") orelse return error.InvalidToolResponse;
    const actual = data.object.get(key) orelse return error.InvalidToolResponse;
    if (actual != .bool) return error.InvalidToolResponse;
    try std.testing.expectEqual(expected, actual.bool);
}

fn expectRpcError(
    allocator: std.mem.Allocator,
    response: []const u8,
    expected_code: i64,
) !void {
    var parsed = try std.json.parseFromSlice(std.json.Value, allocator, response, .{});
    defer parsed.deinit();
    const rpc_error = parsed.value.object.get("error") orelse return error.InvalidToolResponse;
    if (rpc_error != .object) return error.InvalidToolResponse;
    const code = rpc_error.object.get("code") orelse return error.InvalidToolResponse;
    if (code != .integer) return error.InvalidToolResponse;
    try std.testing.expectEqual(expected_code, code.integer);
}

test "MCP mutations drive a disposable mission through the merge failure matrix" {
    if (@import("builtin").os.tag == .windows) return error.SkipZigTest;

    const allocator = std.testing.allocator;
    const io = std.testing.io;

    const version_output = std.process.run(allocator, io, .{
        .argv = &.{ "spec-kitty", "--version" },
        .stdout_limit = .limited(4096),
        .stderr_limit = .limited(4096),
    }) catch |err| switch (err) {
        error.FileNotFound => return error.SkipZigTest,
        else => return err,
    };
    defer allocator.free(version_output.stdout);
    defer allocator.free(version_output.stderr);
    const version_exit = switch (version_output.term) {
        .exited => |code| code,
        else => return error.CommandFailed,
    };
    if (version_exit != 0) return error.CommandFailed;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.createDirPath(io, ".kittify/templates");
    try tmp.dir.writeFile(io, .{
        .sub_path = ".kittify/config.yaml",
        .data =
        \\project:
        \\  uuid: 00000000-0000-4000-8000-000000000002
        \\  slug: spec-kitty-mcp-mutation-smoke
        \\vcs:
        \\  type: git
        \\agents:
        \\  available:
        \\  - codex
        \\  auto_commit: false
        \\  lint_on_edit: false
        \\protection:
        \\  protected_branches: []
        ,
    });
    try tmp.dir.writeFile(io, .{
        .sub_path = ".kittify/templates/plan-template.md",
        .data =
        \\# Implementation Plan
        \\
        \\## Technical Context
        \\
        \\**Language/Version**: Zig 0.16
        \\**Primary Dependencies**: spec-kitty CLI
        \\**Storage**: Disposable git repository
        ,
    });

    var root_buffer: [Io.Dir.max_path_bytes]u8 = undefined;
    const root_len = try tmp.dir.realPath(io, &root_buffer);
    const root = root_buffer[0..root_len];

    try runCommands(allocator, io, root, &.{
        &.{ "git", "init", "-b", "main" },
        &.{ "git", "config", "user.name", "Spec Kitty MCP Smoke" },
        &.{ "git", "config", "user.email", "smoke@example.invalid" },
        &.{ "git", "config", "commit.gpgsign", "false" },
        &.{ "git", "add", "." },
        &.{ "git", "commit", "-m", "Initialize mutation smoke fixture" },
    });

    const specify_output = try runCommand(allocator, io, root, &.{
        "spec-kitty",
        "specify",
        "mutation-smoke",
        "--mission-type",
        "software-dev",
        "--topology",
        "lanes",
        "--json",
    });
    defer allocator.free(specify_output);
    var specify = try std.json.parseFromSlice(std.json.Value, allocator, specify_output, .{});
    defer specify.deinit();
    const mission_value = specify.value.object.get("mission_slug") orelse
        return error.InvalidSpecifyOutput;
    const mission_id_value = specify.value.object.get("mission_id") orelse
        return error.InvalidSpecifyOutput;
    if (mission_value != .string or mission_id_value != .string) {
        return error.InvalidSpecifyOutput;
    }
    const mission = mission_value.string;
    const mission_id = mission_id_value.string;

    const feature_dir = try std.fmt.allocPrint(allocator, "kitty-specs/{s}", .{mission});
    defer allocator.free(feature_dir);
    const spec_path = try std.fmt.allocPrint(allocator, "{s}/spec.md", .{feature_dir});
    defer allocator.free(spec_path);
    try tmp.dir.writeFile(io, .{
        .sub_path = spec_path,
        .data =
        \\# Mutation Smoke Spec
        \\
        \\## Functional Requirements
        \\
        \\| ID | Requirement | Acceptance Criteria | Status |
        \\| --- | --- | --- | --- |
        \\| FR-001 | Exercise a guarded work-package lifecycle. | WP01 advances through implementation and review using MCP mutation tools. | proposed |
        \\
        \\## Non-Functional Requirements
        \\
        \\| ID | Requirement | Measurable Threshold | Status |
        \\| --- | --- | --- | --- |
        \\| NFR-001 | Keep the smoke fixture disposable. | The test creates and removes its own temporary repository. | proposed |
        \\
        \\## Constraints
        \\
        \\| ID | Constraint | Rationale | Status |
        \\| --- | --- | --- | --- |
        \\| C-001 | Use public Spec Kitty interfaces. | Validate the external integration contract. | fixed |
        ,
    });
    try runCommands(allocator, io, root, &.{
        &.{ "git", "add", "." },
        &.{ "git", "commit", "-m", "Seed mutation smoke specification" },
    });

    const setup_output = try runCommand(allocator, io, root, &.{
        "spec-kitty",
        "agent",
        "mission",
        "setup-plan",
        "--mission",
        mission,
        "--json",
    });
    allocator.free(setup_output);

    const tasks_path = try std.fmt.allocPrint(allocator, "{s}/tasks.md", .{feature_dir});
    defer allocator.free(tasks_path);
    try tmp.dir.writeFile(io, .{
        .sub_path = tasks_path,
        .data =
        \\# Work Packages
        \\
        \\## Work Package WP01: Mutation lifecycle
        \\**Dependencies**: None
        \\**Requirement Refs**: FR-001, NFR-001, C-001
        \\
        \\### Included Subtasks
        \\- T001 Add a disposable implementation artifact
        \\
        \\---
        ,
    });
    const wp_path = try std.fmt.allocPrint(
        allocator,
        "{s}/tasks/WP01-mutation-lifecycle.md",
        .{feature_dir},
    );
    defer allocator.free(wp_path);
    try tmp.dir.writeFile(io, .{
        .sub_path = wp_path,
        .data =
        \\---
        \\work_package_id: "WP01"
        \\title: "Mutation lifecycle"
        \\subtasks:
        \\  - "T001"
        \\phase: "Phase 1"
        \\assignee: ""
        \\agent: ""
        \\shell_pid: ""
        \\review_status: ""
        \\reviewed_by: ""
        \\history:
        \\  - at: "2026-08-06T00:00:00Z"
        \\    actor: "system"
        \\    action: "Generated for mutation smoke"
        \\---
        \\
        \\# Work Package Prompt: WP01 -- Mutation lifecycle
        \\
        \\Add a disposable implementation artifact.
        ,
    });
    const meta_path = try std.fmt.allocPrint(allocator, "{s}/meta.json", .{feature_dir});
    defer allocator.free(meta_path);
    const meta = try std.fmt.allocPrint(
        allocator,
        "{{\"created_at\":\"2026-08-06T00:00:00Z\",\"friendly_name\":\"mutation smoke\",\"mission_id\":{f},\"mission_number\":null,\"mission_slug\":{f},\"mission_type\":\"software-dev\",\"slug\":{f},\"target_branch\":\"main\",\"topology\":\"lanes\",\"vcs\":\"git\"}}\n",
        .{
            std.json.fmt(mission_id, .{}),
            std.json.fmt(mission, .{}),
            std.json.fmt(mission, .{}),
        },
    );
    defer allocator.free(meta);
    try tmp.dir.writeFile(io, .{ .sub_path = meta_path, .data = meta });
    try runCommands(allocator, io, root, &.{
        &.{ "git", "add", "." },
        &.{ "git", "commit", "-m", "Add mutation smoke plan and tasks" },
    });

    const finalize_output = try runCommand(allocator, io, root, &.{
        "spec-kitty",
        "agent",
        "mission",
        "finalize-tasks",
        "--mission",
        mission,
        "--json",
    });
    allocator.free(finalize_output);

    const client: app.spec_kitty.Client = .{
        .executable = "spec-kitty",
        .project_root = root,
    };
    var contract = try client.negotiate(allocator, io, app.provider_version);
    defer contract.deinit(allocator);
    var server = app.mcp.Server.initWithTools(
        "mutation-smoke",
        client,
        io,
        app.provider_version,
        contract.api_version,
    );
    server.state = .ready;

    const start_arguments = try std.fmt.allocPrint(
        allocator,
        "{{\"mission\":{f},\"wp\":\"WP01\",\"actor\":\"codex\",\"policy\":{s}}}",
        .{ std.json.fmt(mission, .{}), policy_json },
    );
    defer allocator.free(start_arguments);
    const started = try callTool(
        allocator,
        &server,
        1,
        "spec_kitty_start_implementation",
        start_arguments,
    );
    defer allocator.free(started);
    try expectToolResult(allocator, started, false, null);
    const workspace = try dataStringFromResponse(allocator, started, "workspace_path");
    defer allocator.free(workspace);
    const lane_branch = try dataStringFromResponse(allocator, started, "lane_branch");
    defer allocator.free(lane_branch);

    const repeated = try callTool(
        allocator,
        &server,
        2,
        "spec_kitty_start_implementation",
        start_arguments,
    );
    defer allocator.free(repeated);
    try expectToolResult(allocator, repeated, false, null);
    try expectDataBoolean(allocator, repeated, "no_op", true);

    const competing_arguments = try std.fmt.allocPrint(
        allocator,
        "{{\"mission\":{f},\"wp\":\"WP01\",\"actor\":\"other-agent\",\"policy\":{s}}}",
        .{ std.json.fmt(mission, .{}), policy_json },
    );
    defer allocator.free(competing_arguments);
    const competing = try callTool(
        allocator,
        &server,
        3,
        "spec_kitty_start_implementation",
        competing_arguments,
    );
    defer allocator.free(competing);
    try expectToolResult(allocator, competing, true, "WP_ALREADY_CLAIMED");

    const history_arguments = try std.fmt.allocPrint(
        allocator,
        "{{\"mission\":{f},\"wp\":\"WP01\",\"actor\":\"codex\",\"note\":\"mutation smoke reached implementation\"}}",
        .{std.json.fmt(mission, .{})},
    );
    defer allocator.free(history_arguments);
    const history = try callTool(
        allocator,
        &server,
        4,
        "spec_kitty_append_history",
        history_arguments,
    );
    defer allocator.free(history);
    try expectToolResult(allocator, history, false, null);

    const for_review_arguments = try std.fmt.allocPrint(
        allocator,
        "{{\"mission\":{f},\"wp\":\"WP01\",\"to\":\"for_review\",\"actor\":\"codex\",\"policy\":{s},\"subtasks_complete\":true,\"implementation_evidence_present\":true}}",
        .{ std.json.fmt(mission, .{}), policy_json },
    );
    defer allocator.free(for_review_arguments);
    const premature_review = try callTool(
        allocator,
        &server,
        5,
        "spec_kitty_transition",
        for_review_arguments,
    );
    defer allocator.free(premature_review);
    try expectToolResult(allocator, premature_review, true, "TRANSITION_REJECTED");

    {
        var workspace_dir = try Io.Dir.cwd().openDir(io, workspace, .{});
        defer workspace_dir.close(io);
        try workspace_dir.createDirPath(io, "src");
        try workspace_dir.writeFile(io, .{
            .sub_path = "src/mutation-smoke.txt",
            .data = "implemented through disposable MCP smoke\n",
        });
    }
    try runCommands(allocator, io, workspace, &.{
        &.{ "git", "add", "." },
        &.{ "git", "commit", "-m", "Implement mutation smoke work package" },
    });

    const for_review = try callTool(
        allocator,
        &server,
        6,
        "spec_kitty_transition",
        for_review_arguments,
    );
    defer allocator.free(for_review);
    try expectToolResult(allocator, for_review, false, null);

    const start_review_arguments = try std.fmt.allocPrint(
        allocator,
        "{{\"mission\":{f},\"wp\":\"WP01\",\"actor\":\"reviewer\",\"policy\":{s}}}",
        .{ std.json.fmt(mission, .{}), policy_json },
    );
    defer allocator.free(start_review_arguments);
    const review = try callTool(
        allocator,
        &server,
        7,
        "spec_kitty_start_review",
        start_review_arguments,
    );
    defer allocator.free(review);
    try expectToolResult(allocator, review, false, null);

    const approve_arguments = try std.fmt.allocPrint(
        allocator,
        "{{\"mission\":{f},\"wp\":\"WP01\",\"to\":\"approved\",\"actor\":\"reviewer\",\"policy\":{s},\"review_ref\":\"review://mutation-smoke/WP01\",\"review_result\":{{\"reviewer\":\"reviewer\",\"verdict\":\"approved\",\"reference\":\"review://mutation-smoke/WP01\"}},\"evidence\":{{\"review\":{{\"reviewer\":\"reviewer\",\"verdict\":\"approved\",\"reference\":\"review://mutation-smoke/WP01\"}}}}}}",
        .{ std.json.fmt(mission, .{}), policy_json },
    );
    defer allocator.free(approve_arguments);
    const approved = try callTool(
        allocator,
        &server,
        8,
        "spec_kitty_transition",
        approve_arguments,
    );
    defer allocator.free(approved);
    try expectToolResult(allocator, approved, false, null);

    const accept_arguments = try std.fmt.allocPrint(
        allocator,
        "{{\"mission\":{f},\"actor\":\"maintainer\"}}",
        .{std.json.fmt(mission, .{})},
    );
    defer allocator.free(accept_arguments);
    const accepted = try callTool(
        allocator,
        &server,
        9,
        "spec_kitty_accept_mission",
        accept_arguments,
    );
    defer allocator.free(accepted);
    try expectToolResult(allocator, accepted, false, null);

    {
        var workspace_dir = try Io.Dir.cwd().openDir(io, workspace, .{});
        defer workspace_dir.close(io);
        try workspace_dir.writeFile(io, .{
            .sub_path = "dirty-after-acceptance.txt",
            .data = "merge must reject this dirty lane worktree\n",
        });
    }
    const merge_arguments = try std.fmt.allocPrint(
        allocator,
        "{{\"mission\":{f},\"strategy\":\"merge\"}}",
        .{std.json.fmt(mission, .{})},
    );
    defer allocator.free(merge_arguments);
    const merge = try callTool(
        allocator,
        &server,
        10,
        "spec_kitty_merge_mission",
        merge_arguments,
    );
    defer allocator.free(merge);
    try expectToolResult(allocator, merge, true, "PREFLIGHT_FAILED");

    {
        var workspace_dir = try Io.Dir.cwd().openDir(io, workspace, .{});
        defer workspace_dir.close(io);
        try workspace_dir.deleteFile(io, "dirty-after-acceptance.txt");
    }
    const invalid_strategy_arguments = try std.fmt.allocPrint(
        allocator,
        "{{\"mission\":{f},\"strategy\":\"octopus\"}}",
        .{std.json.fmt(mission, .{})},
    );
    defer allocator.free(invalid_strategy_arguments);
    const invalid_strategy = try callTool(
        allocator,
        &server,
        11,
        "spec_kitty_merge_mission",
        invalid_strategy_arguments,
    );
    defer allocator.free(invalid_strategy);
    try expectRpcError(allocator, invalid_strategy, -32602);

    try tmp.dir.createDirPath(io, "src");
    try tmp.dir.writeFile(io, .{
        .sub_path = "src/mutation-smoke.txt",
        .data = "divergent target implementation\n",
    });
    try runCommands(allocator, io, root, &.{
        &.{ "git", "add", "src/mutation-smoke.txt" },
        &.{ "git", "commit", "-m", "Create divergent target implementation" },
    });
    const divergent = try callTool(
        allocator,
        &server,
        12,
        "spec_kitty_merge_mission",
        merge_arguments,
    );
    defer allocator.free(divergent);
    try expectToolResult(allocator, divergent, true, "PREFLIGHT_FAILED");
    try std.testing.expect(std.mem.indexOf(u8, divergent, "Merge conflict") != null);

    try runCommands(allocator, io, root, &.{
        &.{ "git", "worktree", "remove", "--force", workspace },
        &.{ "git", "branch", "-D", lane_branch },
    });
    const missing_lane = try callTool(
        allocator,
        &server,
        13,
        "spec_kitty_merge_mission",
        merge_arguments,
    );
    defer allocator.free(missing_lane);
    try expectToolResult(allocator, missing_lane, true, "PREFLIGHT_FAILED");
    try std.testing.expect(std.mem.indexOf(u8, missing_lane, "does not exist") != null);
}
