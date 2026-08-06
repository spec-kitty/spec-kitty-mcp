const std = @import("std");
const Io = std.Io;

const spec_kitty = @import("spec_kitty.zig");

pub const Error = error{
    InvalidArguments,
    UnknownTool,
};

const schema_dialect = "https://json-schema.org/draft/2020-12/schema";

const StringSchema = struct {
    type: []const u8 = "string",
    description: []const u8,
    minLength: u8 = 1,
};

const ObjectSchema = struct {
    type: []const u8 = "object",
};

const NullableStringSchema = struct {
    type: []const []const u8 = &.{ "string", "null" },
};

const BooleanSchema = struct {
    type: []const u8 = "boolean",
};

const EnvelopeProperties = struct {
    contract_version: StringSchema = .{
        .description = "Spec Kitty orchestrator contract version.",
    },
    command: StringSchema = .{
        .description = "Canonical orchestrator command name.",
    },
    timestamp: StringSchema = .{
        .description = "Timestamp emitted by Spec Kitty.",
    },
    correlation_id: StringSchema = .{
        .description = "Invocation correlation identifier.",
    },
    success: BooleanSchema = .{},
    error_code: NullableStringSchema = .{},
    data: ObjectSchema = .{},
};

const EnvelopeSchema = struct {
    @"$schema": []const u8 = schema_dialect,
    type: []const u8 = "object",
    properties: EnvelopeProperties = .{},
    required: []const []const u8 = &.{
        "contract_version",
        "command",
        "timestamp",
        "correlation_id",
        "success",
        "error_code",
        "data",
    },
};

const MissionProperties = struct {
    mission: StringSchema = .{
        .description = "Spec Kitty mission slug, for example 042-test-mission.",
    },
};

const MissionInputSchema = struct {
    @"$schema": []const u8 = schema_dialect,
    type: []const u8 = "object",
    properties: MissionProperties = .{},
    required: []const []const u8 = &.{"mission"},
    additionalProperties: bool = false,
};

const ToolAnnotations = struct {
    title: []const u8,
    readOnlyHint: bool = true,
    destructiveHint: bool = false,
    idempotentHint: bool = true,
    openWorldHint: bool = false,
};

pub const Definition = struct {
    name: []const u8,
    title: []const u8,
    description: []const u8,
    inputSchema: MissionInputSchema = .{},
    outputSchema: EnvelopeSchema = .{},
    annotations: ToolAnnotations,
};

pub const catalog = [_]Definition{
    .{
        .name = "spec_kitty_mission_state",
        .title = "Spec Kitty Mission State",
        .description = "Return the authoritative mission summary and work-package states from Spec Kitty.",
        .annotations = .{ .title = "Inspect Spec Kitty mission state" },
    },
    .{
        .name = "spec_kitty_list_ready",
        .title = "Spec Kitty Ready Work Packages",
        .description = "List planned work packages whose dependencies satisfy Spec Kitty's readiness rules.",
        .annotations = .{ .title = "List ready Spec Kitty work packages" },
    },
};

pub fn invoke(
    client: spec_kitty.Client,
    allocator: std.mem.Allocator,
    io: Io,
    name: []const u8,
    arguments: ?std.json.Value,
) !spec_kitty.Invocation {
    const subcommand = if (std.mem.eql(u8, name, "spec_kitty_mission_state"))
        "mission-state"
    else if (std.mem.eql(u8, name, "spec_kitty_list_ready"))
        "list-ready"
    else
        return error.UnknownTool;

    const mission = try parseMission(arguments);
    return client.invoke(
        allocator,
        io,
        subcommand,
        &.{ "--mission", mission },
    );
}

fn parseMission(arguments: ?std.json.Value) ![]const u8 {
    const value = arguments orelse return error.InvalidArguments;
    const object = switch (value) {
        .object => |items| items,
        else => return error.InvalidArguments,
    };

    if (object.count() != 1) return error.InvalidArguments;
    const mission = object.get("mission") orelse return error.InvalidArguments;
    if (mission != .string or mission.string.len == 0) {
        return error.InvalidArguments;
    }
    if (std.mem.indexOfScalar(u8, mission.string, 0) != null) {
        return error.InvalidArguments;
    }
    return mission.string;
}

fn makeFakeExecutable(
    allocator: std.mem.Allocator,
    dir: Io.Dir,
) ![]u8 {
    const script =
        \\#!/bin/sh
        \\printf 'arg=%s\n' "$1" >&2
        \\printf 'arg=%s\n' "$2" >&2
        \\printf 'arg=%s\n' "$3" >&2
        \\printf 'arg=%s\n' "$4" >&2
        \\printf '{"contract_version":"1.3.0","command":"orchestrator-api.%s","timestamp":"2026-08-06T00:00:00Z","correlation_id":"corr-query","success":true,"error_code":null,"data":{"mission_slug":"%s"}}\n' "$2" "$4"
    ;
    try dir.writeFile(std.testing.io, .{
        .sub_path = "fake-spec-kitty",
        .data = script,
        .flags = .{ .permissions = .executable_file },
    });

    var root_buffer: [Io.Dir.max_path_bytes]u8 = undefined;
    const root_len = try dir.realPath(std.testing.io, &root_buffer);
    return std.fs.path.join(allocator, &.{
        root_buffer[0..root_len],
        "fake-spec-kitty",
    });
}

test "catalog publishes typed read-only tools" {
    var output: Io.Writer.Allocating = .init(std.testing.allocator);
    defer output.deinit();

    try std.json.Stringify.value(catalog, .{}, &output.writer);
    const json = output.written();

    try std.testing.expectEqual(@as(usize, 2), catalog.len);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"spec_kitty_mission_state\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"spec_kitty_list_ready\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"additionalProperties\":false") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"readOnlyHint\":true") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"destructiveHint\":false") != null);
}

test "query tools map to fixed commands and exact mission arguments" {
    if (@import("builtin").os.tag == .windows) return error.SkipZigTest;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const executable = try makeFakeExecutable(std.testing.allocator, tmp.dir);
    defer std.testing.allocator.free(executable);

    var root_buffer: [Io.Dir.max_path_bytes]u8 = undefined;
    const root_len = try tmp.dir.realPath(std.testing.io, &root_buffer);
    const client: spec_kitty.Client = .{
        .executable = executable,
        .project_root = root_buffer[0..root_len],
    };

    var parsed = try std.json.parseFromSlice(
        std.json.Value,
        std.testing.allocator,
        "{\"mission\":\"042 mission;$(no-shell)\"}",
        .{},
    );
    defer parsed.deinit();

    var state = try invoke(
        client,
        std.testing.allocator,
        std.testing.io,
        "spec_kitty_mission_state",
        parsed.value,
    );
    defer state.deinit(std.testing.allocator);
    try std.testing.expectEqualStrings("orchestrator-api.mission-state", state.envelope().command);
    try std.testing.expect(std.mem.indexOf(u8, state.stderr, "arg=mission-state\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, state.stderr, "arg=042 mission;$(no-shell)\n") != null);

    var ready = try invoke(
        client,
        std.testing.allocator,
        std.testing.io,
        "spec_kitty_list_ready",
        parsed.value,
    );
    defer ready.deinit(std.testing.allocator);
    try std.testing.expectEqualStrings("orchestrator-api.list-ready", ready.envelope().command);
    try std.testing.expect(std.mem.indexOf(u8, ready.stderr, "arg=list-ready\n") != null);
}

test "query tools reject unknown names and malformed arguments" {
    const client: spec_kitty.Client = .{
        .executable = "unused",
        .project_root = ".",
    };

    try std.testing.expectError(error.UnknownTool, invoke(
        client,
        std.testing.allocator,
        std.testing.io,
        "not_a_tool",
        null,
    ));
    try std.testing.expectError(error.InvalidArguments, invoke(
        client,
        std.testing.allocator,
        std.testing.io,
        "spec_kitty_mission_state",
        null,
    ));

    var parsed = try std.json.parseFromSlice(
        std.json.Value,
        std.testing.allocator,
        "{\"mission\":\"x\",\"extra\":true}",
        .{},
    );
    defer parsed.deinit();
    try std.testing.expectError(error.InvalidArguments, invoke(
        client,
        std.testing.allocator,
        std.testing.io,
        "spec_kitty_list_ready",
        parsed.value,
    ));
}
