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

const WorkspaceProperties = struct {
    mission: StringSchema = .{
        .description = "Spec Kitty mission slug, for example 042-test-mission.",
    },
    wp: StringSchema = .{
        .description = "Work-package identifier, for example WP01.",
    },
};

const WorkspaceInputSchema = struct {
    @"$schema": []const u8 = schema_dialect,
    type: []const u8 = "object",
    properties: WorkspaceProperties = .{},
    required: []const []const u8 = &.{ "mission", "wp" },
    additionalProperties: bool = false,
};

const ContractProperties = struct {
    provider_version: StringSchema = .{
        .description = "Provider contract version; defaults to the adapter's version when omitted.",
    },
};

const ContractInputSchema = struct {
    @"$schema": []const u8 = schema_dialect,
    type: []const u8 = "object",
    properties: ContractProperties = .{},
    additionalProperties: bool = false,
};

const InputSchema = union(enum) {
    contract: ContractInputSchema,
    mission: MissionInputSchema,
    workspace: WorkspaceInputSchema,

    pub fn jsonStringify(schema: InputSchema, stringify: anytype) !void {
        switch (schema) {
            .contract => |value| try stringify.write(value),
            .mission => |value| try stringify.write(value),
            .workspace => |value| try stringify.write(value),
        }
    }
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
    inputSchema: InputSchema,
    outputSchema: EnvelopeSchema = .{},
    annotations: ToolAnnotations,
};

pub const catalog = [_]Definition{
    .{
        .name = "spec_kitty_contract_version",
        .title = "Spec Kitty Contract Version",
        .description = "Check provider compatibility with the active Spec Kitty orchestrator contract.",
        .inputSchema = .{ .contract = .{} },
        .annotations = .{ .title = "Check Spec Kitty contract compatibility" },
    },
    .{
        .name = "spec_kitty_mission_state",
        .title = "Spec Kitty Mission State",
        .description = "Return the authoritative mission summary and work-package states from Spec Kitty.",
        .inputSchema = .{ .mission = .{} },
        .annotations = .{ .title = "Inspect Spec Kitty mission state" },
    },
    .{
        .name = "spec_kitty_list_ready",
        .title = "Spec Kitty Ready Work Packages",
        .description = "List planned work packages whose dependencies satisfy Spec Kitty's readiness rules.",
        .inputSchema = .{ .mission = .{} },
        .annotations = .{ .title = "List ready Spec Kitty work packages" },
    },
    .{
        .name = "spec_kitty_resolve_workspace",
        .title = "Spec Kitty Resolve Workspace",
        .description = "Resolve an existing work-package workspace and prompt without allocating or transitioning it.",
        .inputSchema = .{ .workspace = .{} },
        .annotations = .{ .title = "Resolve a Spec Kitty work-package workspace" },
    },
};

const resolve_workspace_min_version = std.SemanticVersion{
    .major = 1,
    .minor = 2,
    .patch = 0,
};

pub fn catalogForVersion(api_version: ?[]const u8) []const Definition {
    if (api_version) |version| {
        if (supportsResolveWorkspace(version)) return &catalog;
    }
    return catalog[0 .. catalog.len - 1];
}

pub fn supportsResolveWorkspace(api_version: []const u8) bool {
    const version = std.SemanticVersion.parse(api_version) catch return false;
    return version.order(resolve_workspace_min_version) != .lt;
}

pub fn invoke(
    client: spec_kitty.Client,
    allocator: std.mem.Allocator,
    io: Io,
    name: []const u8,
    arguments: ?std.json.Value,
    default_provider_version: []const u8,
    api_version: []const u8,
) !spec_kitty.Invocation {
    if (std.mem.eql(u8, name, "spec_kitty_contract_version")) {
        const provider_version = try parseProviderVersion(
            arguments,
            default_provider_version,
        );
        return client.invoke(
            allocator,
            io,
            "contract-version",
            &.{ "--provider-version", provider_version },
        );
    }

    if (std.mem.eql(u8, name, "spec_kitty_resolve_workspace")) {
        if (!supportsResolveWorkspace(api_version)) return error.UnknownTool;
        const workspace = try parseWorkspace(arguments);
        return client.invoke(
            allocator,
            io,
            "resolve-workspace",
            &.{ "--mission", workspace.mission, "--wp", workspace.wp },
        );
    }

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

const WorkspaceArguments = struct {
    mission: []const u8,
    wp: []const u8,
};

fn parseWorkspace(arguments: ?std.json.Value) !WorkspaceArguments {
    const value = arguments orelse return error.InvalidArguments;
    const object = switch (value) {
        .object => |items| items,
        else => return error.InvalidArguments,
    };
    if (object.count() != 2) return error.InvalidArguments;

    return .{
        .mission = try requiredString(object, "mission"),
        .wp = try requiredString(object, "wp"),
    };
}

fn requiredString(object: std.json.ObjectMap, key: []const u8) ![]const u8 {
    const value = object.get(key) orelse return error.InvalidArguments;
    if (value != .string or value.string.len == 0) {
        return error.InvalidArguments;
    }
    if (std.mem.indexOfScalar(u8, value.string, 0) != null) {
        return error.InvalidArguments;
    }
    return value.string;
}

fn parseProviderVersion(
    arguments: ?std.json.Value,
    default_provider_version: []const u8,
) ![]const u8 {
    const value = arguments orelse return default_provider_version;
    const object = switch (value) {
        .object => |items| items,
        else => return error.InvalidArguments,
    };
    if (object.count() == 0) return default_provider_version;
    if (object.count() != 1) return error.InvalidArguments;

    const provider_version = object.get("provider_version") orelse
        return error.InvalidArguments;
    if (provider_version != .string or provider_version.string.len == 0) {
        return error.InvalidArguments;
    }
    if (std.mem.indexOfScalar(u8, provider_version.string, 0) != null) {
        return error.InvalidArguments;
    }
    return provider_version.string;
}

fn parseMission(arguments: ?std.json.Value) ![]const u8 {
    const value = arguments orelse return error.InvalidArguments;
    const object = switch (value) {
        .object => |items| items,
        else => return error.InvalidArguments,
    };

    if (object.count() != 1) return error.InvalidArguments;
    return requiredString(object, "mission");
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
        \\printf 'arg=%s\n' "$5" >&2
        \\printf 'arg=%s\n' "$6" >&2
        \\if [ "$2" = "contract-version" ]; then
        \\  if [ "$4" = "0.0.0" ]; then
        \\    printf '%s\n' '{"contract_version":"1.3.0","command":"orchestrator-api.contract-version","timestamp":"2026-08-06T00:00:00Z","correlation_id":"corr-mismatch","success":false,"error_code":"CONTRACT_VERSION_MISMATCH","data":{}}'
        \\    exit 1
        \\  fi
        \\  printf '%s\n' '{"contract_version":"1.3.0","command":"orchestrator-api.contract-version","timestamp":"2026-08-06T00:00:00Z","correlation_id":"corr-contract","success":true,"error_code":null,"data":{"api_version":"1.3.0","min_supported_provider_version":"0.1.0"}}'
        \\  exit 0
        \\fi
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

    try std.testing.expectEqual(@as(usize, 4), catalog.len);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"spec_kitty_contract_version\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"spec_kitty_mission_state\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"spec_kitty_list_ready\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"spec_kitty_resolve_workspace\"") != null);
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
        "0.1.0",
        "1.3.0",
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
        "0.1.0",
        "1.3.0",
    );
    defer ready.deinit(std.testing.allocator);
    try std.testing.expectEqualStrings("orchestrator-api.list-ready", ready.envelope().command);
    try std.testing.expect(std.mem.indexOf(u8, ready.stderr, "arg=list-ready\n") != null);
}

test "contract tool defaults and validates provider version overrides" {
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

    var defaulted = try invoke(
        client,
        std.testing.allocator,
        std.testing.io,
        "spec_kitty_contract_version",
        null,
        "0.1.0",
        "1.3.0",
    );
    defer defaulted.deinit(std.testing.allocator);
    try std.testing.expect(defaulted.envelope().success);
    try std.testing.expect(std.mem.indexOf(u8, defaulted.stderr, "arg=contract-version\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, defaulted.stderr, "arg=0.1.0\n") != null);

    var parsed = try std.json.parseFromSlice(
        std.json.Value,
        std.testing.allocator,
        "{\"provider_version\":\"0.0.0\"}",
        .{},
    );
    defer parsed.deinit();
    var mismatch = try invoke(
        client,
        std.testing.allocator,
        std.testing.io,
        "spec_kitty_contract_version",
        parsed.value,
        "0.1.0",
        "1.3.0",
    );
    defer mismatch.deinit(std.testing.allocator);
    try std.testing.expect(!mismatch.envelope().success);
    try std.testing.expectEqualStrings(
        "CONTRACT_VERSION_MISMATCH",
        mismatch.envelope().error_code.?,
    );

    var invalid = try std.json.parseFromSlice(
        std.json.Value,
        std.testing.allocator,
        "{\"provider_version\":\"\",\"extra\":true}",
        .{},
    );
    defer invalid.deinit();
    try std.testing.expectError(error.InvalidArguments, invoke(
        client,
        std.testing.allocator,
        std.testing.io,
        "spec_kitty_contract_version",
        invalid.value,
        "0.1.0",
        "1.3.0",
    ));
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
        "0.1.0",
        "1.3.0",
    ));
    try std.testing.expectError(error.InvalidArguments, invoke(
        client,
        std.testing.allocator,
        std.testing.io,
        "spec_kitty_mission_state",
        null,
        "0.1.0",
        "1.3.0",
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
        "0.1.0",
        "1.3.0",
    ));
}

test "resolve-workspace is capability gated and uses exact arguments" {
    if (@import("builtin").os.tag == .windows) return error.SkipZigTest;

    try std.testing.expectEqual(@as(usize, 3), catalogForVersion(null).len);
    try std.testing.expectEqual(@as(usize, 3), catalogForVersion("1.1.9").len);
    try std.testing.expectEqual(@as(usize, 3), catalogForVersion("1.2.0-rc.1").len);
    try std.testing.expectEqual(@as(usize, 4), catalogForVersion("1.2.0").len);
    try std.testing.expectEqual(@as(usize, 4), catalogForVersion("2.0.0").len);

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
        "{\"mission\":\"042 mission;$(no-shell)\",\"wp\":\"WP01\"}",
        .{},
    );
    defer parsed.deinit();

    try std.testing.expectError(error.UnknownTool, invoke(
        client,
        std.testing.allocator,
        std.testing.io,
        "spec_kitty_resolve_workspace",
        parsed.value,
        "0.1.0",
        "1.1.9",
    ));

    var invocation = try invoke(
        client,
        std.testing.allocator,
        std.testing.io,
        "spec_kitty_resolve_workspace",
        parsed.value,
        "0.1.0",
        "1.3.0",
    );
    defer invocation.deinit(std.testing.allocator);
    try std.testing.expectEqualStrings(
        "orchestrator-api.resolve-workspace",
        invocation.envelope().command,
    );
    try std.testing.expect(std.mem.indexOf(u8, invocation.stderr, "arg=resolve-workspace\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, invocation.stderr, "arg=042 mission;$(no-shell)\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, invocation.stderr, "arg=--wp\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, invocation.stderr, "arg=WP01\n") != null);
}
