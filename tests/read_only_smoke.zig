const std = @import("std");
const Io = std.Io;

const app = @import("spec_kitty_mcp");

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

fn exchange(server: *app.mcp.Server, line: []const u8) ![]u8 {
    var output: Io.Writer.Allocating = .init(std.testing.allocator);
    errdefer output.deinit();

    try server.handleLine(std.testing.allocator, line, &output.writer);
    return output.toOwnedSlice();
}

test "installed Spec Kitty exposes a disposable mission through MCP" {
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
    try tmp.dir.createDirPath(io, ".kittify");
    try tmp.dir.writeFile(io, .{
        .sub_path = ".kittify/config.yaml",
        .data =
        \\project:
        \\  uuid: 00000000-0000-4000-8000-000000000001
        \\  slug: spec-kitty-mcp-smoke
        \\vcs:
        \\  type: git
        \\agents:
        \\  available:
        \\  - codex
        \\  auto_commit: false
        \\  lint_on_edit: false
        ,
    });

    var root_buffer: [Io.Dir.max_path_bytes]u8 = undefined;
    const root_len = try tmp.dir.realPath(io, &root_buffer);
    const root = root_buffer[0..root_len];

    const commands = [_][]const []const u8{
        &.{ "git", "init", "-b", "main" },
        &.{ "git", "config", "user.name", "Spec Kitty MCP Smoke" },
        &.{ "git", "config", "user.email", "smoke@example.invalid" },
        &.{ "git", "config", "commit.gpgsign", "false" },
        &.{ "git", "add", ".kittify/config.yaml" },
        &.{ "git", "commit", "-m", "Initialize smoke fixture" },
    };
    for (commands) |argv| {
        const output = runCommand(allocator, io, root, argv) catch |err| switch (err) {
            error.FileNotFound => return error.SkipZigTest,
            else => return err,
        };
        allocator.free(output);
    }

    const specify_output = try runCommand(allocator, io, root, &.{
        "spec-kitty",
        "specify",
        "read-only-smoke",
        "--mission-type",
        "software-dev",
        "--topology",
        "single_branch",
        "--json",
    });
    defer allocator.free(specify_output);
    var specify = try std.json.parseFromSlice(
        std.json.Value,
        allocator,
        specify_output,
        .{},
    );
    defer specify.deinit();
    const mission = specify.value.object.get("mission_slug") orelse
        return error.InvalidSpecifyOutput;
    if (mission != .string) return error.InvalidSpecifyOutput;

    const client: app.spec_kitty.Client = .{
        .executable = "spec-kitty",
        .project_root = root,
    };
    var contract = try client.negotiate(allocator, io, app.provider_version);
    defer contract.deinit(allocator);
    try std.testing.expect(app.tools.supportsResolveWorkspace(contract.api_version));

    var server = app.mcp.Server.initWithTools(
        "smoke",
        client,
        io,
        app.provider_version,
        contract.api_version,
    );
    server.state = .ready;

    const listed = try exchange(
        &server,
        "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"tools/list\"}",
    );
    defer allocator.free(listed);
    try std.testing.expect(std.mem.indexOf(u8, listed, "spec_kitty_resolve_workspace") != null);

    const state_request = try std.fmt.allocPrint(
        allocator,
        "{{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"tools/call\",\"params\":{{\"name\":\"spec_kitty_mission_state\",\"arguments\":{{\"mission\":{f}}}}}}}",
        .{std.json.fmt(mission.string, .{})},
    );
    defer allocator.free(state_request);
    const state = try exchange(&server, state_request);
    defer allocator.free(state);
    try std.testing.expect(std.mem.indexOf(u8, state, "\"isError\":false") != null);
    try std.testing.expect(std.mem.indexOf(u8, state, mission.string) != null);

    const ready_request = try std.fmt.allocPrint(
        allocator,
        "{{\"jsonrpc\":\"2.0\",\"id\":3,\"method\":\"tools/call\",\"params\":{{\"name\":\"spec_kitty_list_ready\",\"arguments\":{{\"mission\":{f}}}}}}}",
        .{std.json.fmt(mission.string, .{})},
    );
    defer allocator.free(ready_request);
    const ready = try exchange(&server, ready_request);
    defer allocator.free(ready);
    try std.testing.expect(std.mem.indexOf(u8, ready, "\"isError\":false") != null);
    try std.testing.expect(std.mem.indexOf(u8, ready, "ready_work_packages") != null);

    const workspace_request = try std.fmt.allocPrint(
        allocator,
        "{{\"jsonrpc\":\"2.0\",\"id\":4,\"method\":\"tools/call\",\"params\":{{\"name\":\"spec_kitty_resolve_workspace\",\"arguments\":{{\"mission\":{f},\"wp\":\"WP99\"}}}}}}",
        .{std.json.fmt(mission.string, .{})},
    );
    defer allocator.free(workspace_request);
    const workspace = try exchange(&server, workspace_request);
    defer allocator.free(workspace);
    try std.testing.expect(std.mem.indexOf(u8, workspace, "\"isError\":true") != null);
    try std.testing.expect(std.mem.indexOf(u8, workspace, "WP_NOT_FOUND") != null);
}
