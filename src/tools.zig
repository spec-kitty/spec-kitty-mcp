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

const StringItemsSchema = struct {
    type: []const u8 = "string",
    minLength: u8 = 1,
};

const StringArraySchema = struct {
    type: []const u8 = "array",
    description: []const u8,
    items: StringItemsSchema = .{},
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

const DescribedBooleanSchema = struct {
    type: []const u8 = "boolean",
    description: []const u8,
};

const StructuredObjectSchema = struct {
    type: []const u8 = "object",
    description: []const u8,
    additionalProperties: bool = true,
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

const PolicyNullableStringSchema = struct {
    type: []const []const u8 = &.{ "string", "null" },
    description: []const u8,
};

const PolicyProperties = struct {
    orchestrator_id: StringSchema = .{
        .description = "Stable identity of the external orchestrator.",
    },
    orchestrator_version: StringSchema = .{
        .description = "Version of the external orchestrator.",
    },
    agent_family: StringSchema = .{
        .description = "Agent family that will perform the run, for example codex.",
    },
    approval_mode: StringSchema = .{
        .description = "Approval mode governing the run.",
    },
    sandbox_mode: StringSchema = .{
        .description = "Sandbox mode governing the run.",
    },
    network_mode: StringSchema = .{
        .description = "Network access mode governing the run.",
    },
    dangerous_flags: StringArraySchema = .{
        .description = "Dangerous execution flags enabled for the run; may be empty.",
    },
    tool_restrictions: PolicyNullableStringSchema = .{
        .description = "Optional description of tool restrictions for the run.",
    },
};

const PolicySchema = struct {
    type: []const u8 = "object",
    properties: PolicyProperties = .{},
    required: []const []const u8 = &.{
        "orchestrator_id",
        "orchestrator_version",
        "agent_family",
        "approval_mode",
        "sandbox_mode",
        "network_mode",
        "dangerous_flags",
    },
    additionalProperties: bool = false,
};

const StartImplementationProperties = struct {
    mission: StringSchema = .{
        .description = "Spec Kitty mission slug, for example 042-test-mission.",
    },
    wp: StringSchema = .{
        .description = "Work-package identifier, for example WP01.",
    },
    actor: StringSchema = .{
        .description = "Auditable identity claiming the work package.",
    },
    policy: PolicySchema = .{},
};

const StartImplementationInputSchema = struct {
    @"$schema": []const u8 = schema_dialect,
    type: []const u8 = "object",
    properties: StartImplementationProperties = .{},
    required: []const []const u8 = &.{ "mission", "wp", "actor", "policy" },
    additionalProperties: bool = false,
};

const StartReviewProperties = struct {
    mission: StringSchema = .{
        .description = "Spec Kitty mission slug, for example 042-test-mission.",
    },
    wp: StringSchema = .{
        .description = "Work-package identifier, for example WP01.",
    },
    actor: StringSchema = .{
        .description = "Auditable identity claiming the review.",
    },
    policy: PolicySchema = .{},
    review_ref: StringSchema = .{
        .description = "Optional reference to an external review artifact.",
    },
};

const StartReviewInputSchema = struct {
    @"$schema": []const u8 = schema_dialect,
    type: []const u8 = "object",
    properties: StartReviewProperties = .{},
    required: []const []const u8 = &.{ "mission", "wp", "actor", "policy" },
    additionalProperties: bool = false,
};

const TransitionProperties = struct {
    mission: StringSchema = .{
        .description = "Spec Kitty mission slug, for example 042-test-mission.",
    },
    wp: StringSchema = .{
        .description = "Work-package identifier, for example WP01.",
    },
    to: StringSchema = .{
        .description = "Target Spec Kitty lane.",
    },
    actor: StringSchema = .{
        .description = "Auditable identity requesting the transition.",
    },
    note: StringSchema = .{
        .description = "Optional audit note explaining the transition.",
    },
    policy: PolicySchema = .{},
    review_ref: StringSchema = .{
        .description = "Optional reference to an external review artifact.",
    },
    review_result: StructuredObjectSchema = .{
        .description = "Structured review outcome passed to Spec Kitty.",
    },
    evidence: StructuredObjectSchema = .{
        .description = "Structured terminal evidence passed to Spec Kitty.",
    },
    subtasks_complete: DescribedBooleanSchema = .{
        .description = "Assert that required subtasks are complete.",
    },
    implementation_evidence_present: DescribedBooleanSchema = .{
        .description = "Assert that implementation evidence exists.",
    },
};

const TransitionInputSchema = struct {
    @"$schema": []const u8 = schema_dialect,
    type: []const u8 = "object",
    properties: TransitionProperties = .{},
    required: []const []const u8 = &.{ "mission", "wp", "to", "actor" },
    additionalProperties: bool = false,
};

const HistoryProperties = struct {
    mission: StringSchema = .{
        .description = "Spec Kitty mission slug, for example 042-test-mission.",
    },
    wp: StringSchema = .{
        .description = "Work-package identifier, for example WP01.",
    },
    actor: StringSchema = .{
        .description = "Auditable identity authoring the history entry.",
    },
    note: StringSchema = .{
        .description = "History note to append.",
    },
};

const HistoryInputSchema = struct {
    @"$schema": []const u8 = schema_dialect,
    type: []const u8 = "object",
    properties: HistoryProperties = .{},
    required: []const []const u8 = &.{ "mission", "wp", "actor", "note" },
    additionalProperties: bool = false,
};

const AcceptProperties = struct {
    mission: StringSchema = .{
        .description = "Spec Kitty mission slug, for example 042-test-mission.",
    },
    actor: StringSchema = .{
        .description = "Auditable identity requesting mission acceptance.",
    },
};

const AcceptInputSchema = struct {
    @"$schema": []const u8 = schema_dialect,
    type: []const u8 = "object",
    properties: AcceptProperties = .{},
    required: []const []const u8 = &.{ "mission", "actor" },
    additionalProperties: bool = false,
};

const InputSchema = union(enum) {
    contract: ContractInputSchema,
    mission: MissionInputSchema,
    workspace: WorkspaceInputSchema,
    start_implementation: StartImplementationInputSchema,
    start_review: StartReviewInputSchema,
    transition: TransitionInputSchema,
    history: HistoryInputSchema,
    accept: AcceptInputSchema,

    pub fn jsonStringify(schema: InputSchema, stringify: anytype) !void {
        switch (schema) {
            .contract => |value| try stringify.write(value),
            .mission => |value| try stringify.write(value),
            .workspace => |value| try stringify.write(value),
            .start_implementation => |value| try stringify.write(value),
            .start_review => |value| try stringify.write(value),
            .transition => |value| try stringify.write(value),
            .history => |value| try stringify.write(value),
            .accept => |value| try stringify.write(value),
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
        .name = "spec_kitty_start_implementation",
        .title = "Spec Kitty Start Implementation",
        .description = "Atomically claim and start a ready work package through Spec Kitty, recording the supplied policy metadata.",
        .inputSchema = .{ .start_implementation = .{} },
        .annotations = .{
            .title = "Start Spec Kitty work-package implementation",
            .readOnlyHint = false,
        },
    },
    .{
        .name = "spec_kitty_start_review",
        .title = "Spec Kitty Start Review",
        .description = "Claim a work package review through Spec Kitty, recording the supplied policy metadata.",
        .inputSchema = .{ .start_review = .{} },
        .annotations = .{
            .title = "Start a Spec Kitty work-package review",
            .readOnlyHint = false,
            .idempotentHint = false,
        },
    },
    .{
        .name = "spec_kitty_transition",
        .title = "Spec Kitty Transition Work Package",
        .description = "Request one guarded work-package lane transition through Spec Kitty without exposing force.",
        .inputSchema = .{ .transition = .{} },
        .annotations = .{
            .title = "Transition a Spec Kitty work package",
            .readOnlyHint = false,
            .idempotentHint = false,
        },
    },
    .{
        .name = "spec_kitty_append_history",
        .title = "Spec Kitty Append History",
        .description = "Append an auditable work-package history note through Spec Kitty.",
        .inputSchema = .{ .history = .{} },
        .annotations = .{
            .title = "Append Spec Kitty work-package history",
            .readOnlyHint = false,
            .idempotentHint = false,
        },
    },
    .{
        .name = "spec_kitty_accept_mission",
        .title = "Spec Kitty Accept Mission",
        .description = "Request guarded mission acceptance after Spec Kitty verifies all work packages.",
        .inputSchema = .{ .accept = .{} },
        .annotations = .{
            .title = "Accept a Spec Kitty mission",
            .readOnlyHint = false,
            .idempotentHint = false,
        },
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

    if (std.mem.eql(u8, name, "spec_kitty_start_implementation")) {
        const run = try parseStartImplementation(arguments);
        const policy = try serializePolicy(allocator, run.policy);
        defer allocator.free(policy);
        return client.invoke(
            allocator,
            io,
            "start-implementation",
            &.{
                "--mission",
                run.mission,
                "--wp",
                run.wp,
                "--actor",
                run.actor,
                "--policy",
                policy,
            },
        );
    }

    if (std.mem.eql(u8, name, "spec_kitty_start_review")) {
        const run = try parseStartReview(arguments);
        const policy = try serializePolicy(allocator, run.policy);
        defer allocator.free(policy);
        if (run.review_ref) |review_ref| {
            return client.invoke(
                allocator,
                io,
                "start-review",
                &.{
                    "--mission",
                    run.mission,
                    "--wp",
                    run.wp,
                    "--actor",
                    run.actor,
                    "--review-ref",
                    review_ref,
                    "--policy",
                    policy,
                },
            );
        }
        return client.invoke(
            allocator,
            io,
            "start-review",
            &.{
                "--mission",
                run.mission,
                "--wp",
                run.wp,
                "--actor",
                run.actor,
                "--policy",
                policy,
            },
        );
    }

    if (std.mem.eql(u8, name, "spec_kitty_transition")) {
        const transition = try parseTransition(arguments);
        const policy = if (transition.policy) |value|
            try serializeJson(allocator, value)
        else
            null;
        defer if (policy) |owned| allocator.free(owned);
        const review_result = if (transition.review_result) |value|
            try serializeJson(allocator, value)
        else
            null;
        defer if (review_result) |owned| allocator.free(owned);
        const evidence = if (transition.evidence) |value|
            try serializeJson(allocator, value)
        else
            null;
        defer if (evidence) |owned| allocator.free(owned);

        var argv: std.ArrayList([]const u8) = .empty;
        defer argv.deinit(allocator);
        try argv.appendSlice(allocator, &.{
            "--mission",
            transition.mission,
            "--wp",
            transition.wp,
            "--to",
            transition.to,
            "--actor",
            transition.actor,
        });
        if (transition.note) |note| {
            try argv.appendSlice(allocator, &.{ "--note", note });
        }
        if (policy) |value| {
            try argv.appendSlice(allocator, &.{ "--policy", value });
        }
        if (transition.review_ref) |review_ref| {
            try argv.appendSlice(allocator, &.{ "--review-ref", review_ref });
        }
        if (review_result) |value| {
            try argv.appendSlice(allocator, &.{ "--review-result-json", value });
        }
        if (evidence) |value| {
            try argv.appendSlice(allocator, &.{ "--evidence-json", value });
        }
        if (transition.subtasks_complete) {
            try argv.append(allocator, "--subtasks-complete");
        }
        if (transition.implementation_evidence_present) {
            try argv.append(allocator, "--implementation-evidence-present");
        }
        return client.invoke(allocator, io, "transition", argv.items);
    }

    if (std.mem.eql(u8, name, "spec_kitty_append_history")) {
        const history = try parseHistory(arguments);
        return client.invoke(
            allocator,
            io,
            "append-history",
            &.{
                "--mission",
                history.mission,
                "--wp",
                history.wp,
                "--actor",
                history.actor,
                "--note",
                history.note,
            },
        );
    }

    if (std.mem.eql(u8, name, "spec_kitty_accept_mission")) {
        const acceptance = try parseAcceptance(arguments);
        return client.invoke(
            allocator,
            io,
            "accept-mission",
            &.{
                "--mission",
                acceptance.mission,
                "--actor",
                acceptance.actor,
            },
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

const StartImplementationArguments = struct {
    mission: []const u8,
    wp: []const u8,
    actor: []const u8,
    policy: std.json.Value,
};

const StartReviewArguments = struct {
    mission: []const u8,
    wp: []const u8,
    actor: []const u8,
    policy: std.json.Value,
    review_ref: ?[]const u8,
};

const TransitionArguments = struct {
    mission: []const u8,
    wp: []const u8,
    to: []const u8,
    actor: []const u8,
    note: ?[]const u8,
    policy: ?std.json.Value,
    review_ref: ?[]const u8,
    review_result: ?std.json.Value,
    evidence: ?std.json.Value,
    subtasks_complete: bool,
    implementation_evidence_present: bool,
};

const HistoryArguments = struct {
    mission: []const u8,
    wp: []const u8,
    actor: []const u8,
    note: []const u8,
};

const AcceptanceArguments = struct {
    mission: []const u8,
    actor: []const u8,
};

fn parseStartImplementation(arguments: ?std.json.Value) !StartImplementationArguments {
    const object = try argumentsObject(arguments, 4, 4);
    try ensureOnlyKeys(object, .{ "mission", "wp", "actor", "policy" });
    return .{
        .mission = try requiredString(object, "mission"),
        .wp = try requiredString(object, "wp"),
        .actor = try requiredString(object, "actor"),
        .policy = try requiredPolicy(object),
    };
}

fn parseStartReview(arguments: ?std.json.Value) !StartReviewArguments {
    const object = try argumentsObject(arguments, 4, 5);
    try ensureOnlyKeys(object, .{ "mission", "wp", "actor", "policy", "review_ref" });
    return .{
        .mission = try requiredString(object, "mission"),
        .wp = try requiredString(object, "wp"),
        .actor = try requiredString(object, "actor"),
        .policy = try requiredPolicy(object),
        .review_ref = try optionalString(object, "review_ref"),
    };
}

fn parseTransition(arguments: ?std.json.Value) !TransitionArguments {
    const object = try argumentsObject(arguments, 4, 11);
    try ensureOnlyKeys(object, .{
        "mission",
        "wp",
        "to",
        "actor",
        "note",
        "policy",
        "review_ref",
        "review_result",
        "evidence",
        "subtasks_complete",
        "implementation_evidence_present",
    });

    const target = try requiredString(object, "to");
    const policy = try optionalPolicy(object);
    if (isRunAffectingLane(target) and policy == null) {
        return error.InvalidArguments;
    }
    return .{
        .mission = try requiredString(object, "mission"),
        .wp = try requiredString(object, "wp"),
        .to = target,
        .actor = try requiredString(object, "actor"),
        .note = try optionalString(object, "note"),
        .policy = policy,
        .review_ref = try optionalString(object, "review_ref"),
        .review_result = try optionalObject(object, "review_result"),
        .evidence = try optionalObject(object, "evidence"),
        .subtasks_complete = try optionalBoolean(object, "subtasks_complete"),
        .implementation_evidence_present = try optionalBoolean(
            object,
            "implementation_evidence_present",
        ),
    };
}

fn parseHistory(arguments: ?std.json.Value) !HistoryArguments {
    const object = try argumentsObject(arguments, 4, 4);
    try ensureOnlyKeys(object, .{ "mission", "wp", "actor", "note" });
    return .{
        .mission = try requiredString(object, "mission"),
        .wp = try requiredString(object, "wp"),
        .actor = try requiredString(object, "actor"),
        .note = try requiredString(object, "note"),
    };
}

fn parseAcceptance(arguments: ?std.json.Value) !AcceptanceArguments {
    const object = try argumentsObject(arguments, 2, 2);
    try ensureOnlyKeys(object, .{ "mission", "actor" });
    return .{
        .mission = try requiredString(object, "mission"),
        .actor = try requiredString(object, "actor"),
    };
}

fn argumentsObject(
    arguments: ?std.json.Value,
    min_count: usize,
    max_count: usize,
) !std.json.ObjectMap {
    const value = arguments orelse return error.InvalidArguments;
    const object = switch (value) {
        .object => |items| items,
        else => return error.InvalidArguments,
    };
    if (object.count() < min_count or object.count() > max_count) {
        return error.InvalidArguments;
    }
    return object;
}

fn ensureOnlyKeys(object: std.json.ObjectMap, comptime allowed: anytype) !void {
    var iterator = object.iterator();
    while (iterator.next()) |entry| {
        var known = false;
        inline for (allowed) |key| {
            if (std.mem.eql(u8, entry.key_ptr.*, key)) known = true;
        }
        if (!known) return error.InvalidArguments;
    }
}

fn requiredPolicy(object: std.json.ObjectMap) !std.json.Value {
    const value = object.get("policy") orelse return error.InvalidArguments;
    return validatePolicy(value);
}

fn optionalPolicy(object: std.json.ObjectMap) !?std.json.Value {
    const value = object.get("policy") orelse return null;
    return try validatePolicy(value);
}

fn validatePolicy(value: std.json.Value) !std.json.Value {
    if (value != .object) return error.InvalidArguments;
    const policy = value.object;
    if (policy.count() < 7 or policy.count() > 8) return error.InvalidArguments;
    try ensureOnlyKeys(policy, .{
        "orchestrator_id",
        "orchestrator_version",
        "agent_family",
        "approval_mode",
        "sandbox_mode",
        "network_mode",
        "dangerous_flags",
        "tool_restrictions",
    });

    inline for (.{
        "orchestrator_id",
        "orchestrator_version",
        "agent_family",
        "approval_mode",
        "sandbox_mode",
        "network_mode",
    }) |key| {
        _ = try requiredString(policy, key);
    }

    const dangerous_flags = policy.get("dangerous_flags") orelse
        return error.InvalidArguments;
    if (dangerous_flags != .array) return error.InvalidArguments;
    for (dangerous_flags.array.items) |flag| {
        try validateStringValue(flag);
    }

    if (policy.get("tool_restrictions")) |restrictions| {
        switch (restrictions) {
            .null => {},
            .string => |text| {
                if (std.mem.indexOfScalar(u8, text, 0) != null) {
                    return error.InvalidArguments;
                }
            },
            else => return error.InvalidArguments,
        }
    }
    return value;
}

fn serializePolicy(
    allocator: std.mem.Allocator,
    policy: std.json.Value,
) ![]u8 {
    return serializeJson(allocator, policy);
}

fn serializeJson(
    allocator: std.mem.Allocator,
    value: std.json.Value,
) ![]u8 {
    var output: Io.Writer.Allocating = .init(allocator);
    errdefer output.deinit();
    try std.json.Stringify.value(value, .{}, &output.writer);
    return output.toOwnedSlice();
}

fn isRunAffectingLane(target: []const u8) bool {
    return std.mem.eql(u8, target, "claimed") or
        std.mem.eql(u8, target, "in_progress") or
        std.mem.eql(u8, target, "for_review") or
        std.mem.eql(u8, target, "in_review");
}

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
    try validateStringValue(value);
    return value.string;
}

fn optionalString(object: std.json.ObjectMap, key: []const u8) !?[]const u8 {
    const value = object.get(key) orelse return null;
    try validateStringValue(value);
    return value.string;
}

fn optionalObject(object: std.json.ObjectMap, key: []const u8) !?std.json.Value {
    const value = object.get(key) orelse return null;
    if (value != .object) return error.InvalidArguments;
    return value;
}

fn optionalBoolean(object: std.json.ObjectMap, key: []const u8) !bool {
    const value = object.get(key) orelse return false;
    if (value != .bool) return error.InvalidArguments;
    return value.bool;
}

fn validateStringValue(value: std.json.Value) !void {
    if (value != .string or value.string.len == 0) {
        return error.InvalidArguments;
    }
    if (std.mem.indexOfScalar(u8, value.string, 0) != null) {
        return error.InvalidArguments;
    }
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
        \\position=1
        \\for arg in "$@"; do
        \\  if [ "$position" -le 9 ]; then
        \\    printf 'arg=%s\n' "$arg" >&2
        \\  fi
        \\  position=$((position + 1))
        \\done
        \\if [ "$2" = "contract-version" ]; then
        \\  if [ "$4" = "0.0.0" ]; then
        \\    printf '%s\n' '{"contract_version":"1.3.0","command":"orchestrator-api.contract-version","timestamp":"2026-08-06T00:00:00Z","correlation_id":"corr-mismatch","success":false,"error_code":"CONTRACT_VERSION_MISMATCH","data":{}}'
        \\    exit 1
        \\  fi
        \\  printf '%s\n' '{"contract_version":"1.3.0","command":"orchestrator-api.contract-version","timestamp":"2026-08-06T00:00:00Z","correlation_id":"corr-contract","success":true,"error_code":null,"data":{"api_version":"1.3.0","min_supported_provider_version":"0.1.0"}}'
        \\  exit 0
        \\fi
        \\if [ "$2" = "start-implementation" ]; then
        \\  expected_policy='{"orchestrator_id":"zig-mcp","orchestrator_version":"0.1.0","agent_family":"codex","approval_mode":"manual","sandbox_mode":"workspace-write","network_mode":"restricted","dangerous_flags":["allow-git"]}'
        \\  if [ "${10}" != "$expected_policy" ]; then
        \\    printf '%s\n' 'policy-mismatch' >&2
        \\    exit 2
        \\  fi
        \\  printf '%s\n' 'policy=validated' >&2
        \\  if [ "$8" = "other-actor" ]; then
        \\    printf '%s\n' '{"contract_version":"1.3.0","command":"orchestrator-api.start-implementation","timestamp":"2026-08-06T00:00:00Z","correlation_id":"corr-claimed","success":false,"error_code":"WP_ALREADY_CLAIMED","data":{"claiming_actor":"first-actor"}}'
        \\    exit 1
        \\  fi
        \\  printf '%s\n' '{"contract_version":"1.3.0","command":"orchestrator-api.start-implementation","timestamp":"2026-08-06T00:00:00Z","correlation_id":"corr-implementation","success":true,"error_code":null,"data":{"from_lane":"in_progress","to_lane":"in_progress","workspace_path":"/tmp/lane","prompt_path":"/tmp/WP01.md","policy_metadata_recorded":true,"no_op":true}}'
        \\  exit 0
        \\fi
        \\if [ "$2" = "start-review" ]; then
        \\  if [ "$9" = "--review-ref" ]; then
        \\    printf 'review-ref=%s\n' "${10}" >&2
        \\    policy_flag="${11}"
        \\    policy_value="${12}"
        \\  else
        \\    policy_flag="$9"
        \\    policy_value="${10}"
        \\  fi
        \\  expected_policy='{"orchestrator_id":"zig-mcp","orchestrator_version":"0.1.0","agent_family":"codex","approval_mode":"manual","sandbox_mode":"workspace-write","network_mode":"restricted","dangerous_flags":[],"tool_restrictions":null}'
        \\  if [ "$policy_flag" != "--policy" ] || [ "$policy_value" != "$expected_policy" ]; then
        \\    printf '%s\n' 'policy-mismatch' >&2
        \\    exit 2
        \\  fi
        \\  printf '%s\n' 'policy=validated' >&2
        \\  printf '%s\n' '{"contract_version":"1.3.0","command":"orchestrator-api.start-review","timestamp":"2026-08-06T00:00:00Z","correlation_id":"corr-review","success":true,"error_code":null,"data":{"from_lane":"for_review","to_lane":"in_review","prompt_path":"/tmp/WP01.md","policy_metadata_recorded":true}}'
        \\  exit 0
        \\fi
        \\if [ "$2" = "transition" ]; then
        \\  if [ "$8" = "blocked" ]; then
        \\    printf '%s\n' '{"contract_version":"1.3.0","command":"orchestrator-api.transition","timestamp":"2026-08-06T00:00:00Z","correlation_id":"corr-transition-rejected","success":false,"error_code":"TRANSITION_REJECTED","data":{"from_lane":"in_progress","requested_lane":"blocked"}}'
        \\    exit 1
        \\  fi
        \\  if [ "$8" = "approved" ] && [ "$#" -eq 10 ]; then
        \\    printf '%s\n' 'transition-argv=validated' >&2
        \\    printf '%s\n' '{"contract_version":"1.3.0","command":"orchestrator-api.transition","timestamp":"2026-08-06T00:00:00Z","correlation_id":"corr-transition","success":true,"error_code":null,"data":{"from_lane":"in_review","to_lane":"approved"}}'
        \\    exit 0
        \\  fi
        \\  expected_policy='{"orchestrator_id":"zig-mcp","orchestrator_version":"0.1.0","agent_family":"codex","approval_mode":"manual","sandbox_mode":"workspace-write","network_mode":"restricted","dangerous_flags":[]}'
        \\  expected_review='{"reviewer":"codex","verdict":"approved"}'
        \\  expected_evidence='{"review":{"reference":"PR #42"}}'
        \\  if [ "$#" -ne 22 ] || [ "${10}" != 'reviewer;$(no-shell)' ] || [ "${11}" != "--note" ] || [ "${12}" != 'Approved;$(no-shell)' ] || [ "${13}" != "--policy" ] || [ "${14}" != "$expected_policy" ] || [ "${15}" != "--review-ref" ] || [ "${16}" != 'PR #42;$(no-shell)' ] || [ "${17}" != "--review-result-json" ] || [ "${18}" != "$expected_review" ] || [ "${19}" != "--evidence-json" ] || [ "${20}" != "$expected_evidence" ] || [ "${21}" != "--subtasks-complete" ] || [ "${22}" != "--implementation-evidence-present" ]; then
        \\    printf '%s\n' 'transition-argv-mismatch' >&2
        \\    exit 2
        \\  fi
        \\  printf '%s\n' 'transition-argv=validated' >&2
        \\  printf '%s\n' '{"contract_version":"1.3.0","command":"orchestrator-api.transition","timestamp":"2026-08-06T00:00:00Z","correlation_id":"corr-transition","success":true,"error_code":null,"data":{"from_lane":"in_review","to_lane":"done"}}'
        \\  exit 0
        \\fi
        \\if [ "$2" = "append-history" ]; then
        \\  if [ "$#" -ne 10 ] || [ "$9" != "--note" ] || [ "${10}" != 'Tests passed;$(no-shell)' ]; then
        \\    printf '%s\n' 'history-argv-mismatch' >&2
        \\    exit 2
        \\  fi
        \\  printf '%s\n' 'history-argv=validated' >&2
        \\  printf '%s\n' '{"contract_version":"1.3.0","command":"orchestrator-api.append-history","timestamp":"2026-08-06T00:00:00Z","correlation_id":"corr-history","success":true,"error_code":null,"data":{"history_entry_id":"entry-1"}}'
        \\  exit 0
        \\fi
        \\if [ "$2" = "accept-mission" ]; then
        \\  if [ "$4" = "not-ready" ]; then
        \\    printf '%s\n' '{"contract_version":"1.3.0","command":"orchestrator-api.accept-mission","timestamp":"2026-08-06T00:00:00Z","correlation_id":"corr-not-ready","success":false,"error_code":"MISSION_NOT_READY","data":{"blocking_wps":["WP02"]}}'
        \\    exit 1
        \\  fi
        \\  if [ "$#" -ne 6 ] || [ "$5" != "--actor" ]; then
        \\    printf '%s\n' 'accept-argv-mismatch' >&2
        \\    exit 2
        \\  fi
        \\  printf '%s\n' 'accept-argv=validated' >&2
        \\  printf '%s\n' '{"contract_version":"1.3.0","command":"orchestrator-api.accept-mission","timestamp":"2026-08-06T00:00:00Z","correlation_id":"corr-accept","success":true,"error_code":null,"data":{"accepted":true,"accepted_wps":["WP01"],"approved_wps":["WP01"],"done_wps":[],"merge_pending_wps":["WP01"]}}'
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

test "catalog publishes typed read-only and guarded mutation tools" {
    var output: Io.Writer.Allocating = .init(std.testing.allocator);
    defer output.deinit();

    try std.json.Stringify.value(catalog, .{}, &output.writer);
    const json = output.written();

    try std.testing.expectEqual(@as(usize, 9), catalog.len);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"spec_kitty_contract_version\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"spec_kitty_mission_state\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"spec_kitty_list_ready\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"spec_kitty_resolve_workspace\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"spec_kitty_start_implementation\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"spec_kitty_start_review\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"spec_kitty_transition\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"spec_kitty_append_history\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"spec_kitty_accept_mission\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"review_result\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"implementation_evidence_present\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"orchestrator_id\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"dangerous_flags\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"additionalProperties\":false") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"readOnlyHint\":true") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"readOnlyHint\":false") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"destructiveHint\":false") != null);
    try std.testing.expect(!catalog[3].annotations.readOnlyHint);
    try std.testing.expect(catalog[3].annotations.idempotentHint);
    try std.testing.expect(!catalog[4].annotations.readOnlyHint);
    try std.testing.expect(!catalog[4].annotations.idempotentHint);
    try std.testing.expect(!catalog[5].annotations.readOnlyHint);
    try std.testing.expect(!catalog[5].annotations.idempotentHint);
    try std.testing.expect(!catalog[6].annotations.readOnlyHint);
    try std.testing.expect(!catalog[7].annotations.readOnlyHint);
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

    try std.testing.expectEqual(@as(usize, 8), catalogForVersion(null).len);
    try std.testing.expectEqual(@as(usize, 8), catalogForVersion("1.1.9").len);
    try std.testing.expectEqual(@as(usize, 8), catalogForVersion("1.2.0-rc.1").len);
    try std.testing.expectEqual(@as(usize, 9), catalogForVersion("1.2.0").len);
    try std.testing.expectEqual(@as(usize, 9), catalogForVersion("2.0.0").len);

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

test "start-implementation validates structured policy and uses exact argv" {
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
    const request =
        \\{"mission":"042 mission;$(no-shell)","wp":"WP01","actor":"same-actor","policy":{"orchestrator_id":"zig-mcp","orchestrator_version":"0.1.0","agent_family":"codex","approval_mode":"manual","sandbox_mode":"workspace-write","network_mode":"restricted","dangerous_flags":["allow-git"]}}
    ;
    var parsed = try std.json.parseFromSlice(
        std.json.Value,
        std.testing.allocator,
        request,
        .{},
    );
    defer parsed.deinit();

    var invocation = try invoke(
        client,
        std.testing.allocator,
        std.testing.io,
        "spec_kitty_start_implementation",
        parsed.value,
        "0.1.0",
        "1.3.0",
    );
    defer invocation.deinit(std.testing.allocator);

    try std.testing.expect(invocation.envelope().success);
    try std.testing.expectEqualStrings(
        "orchestrator-api.start-implementation",
        invocation.envelope().command,
    );
    try std.testing.expectEqual(true, invocation.envelope().data.object.get("no_op").?.bool);
    try std.testing.expect(std.mem.indexOf(u8, invocation.stderr, "arg=start-implementation\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, invocation.stderr, "arg=042 mission;$(no-shell)\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, invocation.stderr, "arg=--actor\narg=same-actor\narg=--policy\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, invocation.stderr, "policy=validated\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, invocation.stderr, "zig-mcp") == null);
}

test "start-run tools preserve failure envelopes and optional review references" {
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
    const implementation_request =
        \\{"mission":"042-test","wp":"WP01","actor":"other-actor","policy":{"orchestrator_id":"zig-mcp","orchestrator_version":"0.1.0","agent_family":"codex","approval_mode":"manual","sandbox_mode":"workspace-write","network_mode":"restricted","dangerous_flags":["allow-git"]}}
    ;
    var implementation = try std.json.parseFromSlice(
        std.json.Value,
        std.testing.allocator,
        implementation_request,
        .{},
    );
    defer implementation.deinit();
    var claimed = try invoke(
        client,
        std.testing.allocator,
        std.testing.io,
        "spec_kitty_start_implementation",
        implementation.value,
        "0.1.0",
        "1.3.0",
    );
    defer claimed.deinit(std.testing.allocator);
    try std.testing.expect(!claimed.envelope().success);
    try std.testing.expectEqualStrings("WP_ALREADY_CLAIMED", claimed.envelope().error_code.?);
    try std.testing.expectEqualStrings("corr-claimed", claimed.envelope().correlation_id);

    const review_request =
        \\{"mission":"042-test","wp":"WP01","actor":"reviewer;$(no-shell)","review_ref":"PR #42;$(no-shell)","policy":{"orchestrator_id":"zig-mcp","orchestrator_version":"0.1.0","agent_family":"codex","approval_mode":"manual","sandbox_mode":"workspace-write","network_mode":"restricted","dangerous_flags":[],"tool_restrictions":null}}
    ;
    var review = try std.json.parseFromSlice(
        std.json.Value,
        std.testing.allocator,
        review_request,
        .{},
    );
    defer review.deinit();
    var started = try invoke(
        client,
        std.testing.allocator,
        std.testing.io,
        "spec_kitty_start_review",
        review.value,
        "0.1.0",
        "1.3.0",
    );
    defer started.deinit(std.testing.allocator);
    try std.testing.expect(started.envelope().success);
    try std.testing.expect(std.mem.indexOf(u8, started.stderr, "arg=reviewer;$(no-shell)\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, started.stderr, "arg=--review-ref\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, started.stderr, "review-ref=PR #42;$(no-shell)\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, started.stderr, "policy=validated\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, started.stderr, "zig-mcp") == null);

    const review_without_ref_request =
        \\{"mission":"042-test","wp":"WP01","actor":"reviewer","policy":{"orchestrator_id":"zig-mcp","orchestrator_version":"0.1.0","agent_family":"codex","approval_mode":"manual","sandbox_mode":"workspace-write","network_mode":"restricted","dangerous_flags":[],"tool_restrictions":null}}
    ;
    var review_without_ref = try std.json.parseFromSlice(
        std.json.Value,
        std.testing.allocator,
        review_without_ref_request,
        .{},
    );
    defer review_without_ref.deinit();
    var started_without_ref = try invoke(
        client,
        std.testing.allocator,
        std.testing.io,
        "spec_kitty_start_review",
        review_without_ref.value,
        "0.1.0",
        "1.3.0",
    );
    defer started_without_ref.deinit(std.testing.allocator);
    try std.testing.expect(started_without_ref.envelope().success);
    try std.testing.expect(std.mem.indexOf(u8, started_without_ref.stderr, "arg=--review-ref\n") == null);
    try std.testing.expect(std.mem.indexOf(u8, started_without_ref.stderr, "arg=--policy\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, started_without_ref.stderr, "policy=validated\n") != null);
}

test "start-run tools reject raw malformed and extended policy input" {
    const client: spec_kitty.Client = .{
        .executable = "unused",
        .project_root = ".",
    };
    const invalid_requests = [_][]const u8{
        \\{"mission":"042-test","wp":"WP01","actor":"codex","policy":"{\"orchestrator_id\":\"raw-json\"}"}
        ,
        \\{"mission":"042-test","wp":"WP01","actor":"codex","policy":{"orchestrator_id":"zig-mcp","orchestrator_version":"0.1.0","agent_family":"codex","approval_mode":"manual","sandbox_mode":"workspace-write","network_mode":"restricted"}}
        ,
        \\{"mission":"042-test","wp":"WP01","actor":"codex","policy":{"orchestrator_id":"zig-mcp","orchestrator_version":"0.1.0","agent_family":"codex","approval_mode":"manual","sandbox_mode":"workspace-write","network_mode":"restricted","dangerous_flags":[1]}}
        ,
        \\{"mission":"042-test","wp":"WP01","actor":"codex","policy":{"orchestrator_id":"zig-mcp","orchestrator_version":"0.1.0","agent_family":"codex","approval_mode":"manual","sandbox_mode":"workspace-write","network_mode":"restricted","dangerous_flags":[],"extra":true}}
        ,
        \\{"mission":"042-test","wp":"WP01","actor":"codex","policy":{"orchestrator_id":"zig-mcp","orchestrator_version":"0.1.0","agent_family":"codex","approval_mode":"manual","sandbox_mode":"workspace-write","network_mode":"restricted","dangerous_flags":[]},"extra":true}
        ,
    };

    for (invalid_requests) |request| {
        var parsed = try std.json.parseFromSlice(
            std.json.Value,
            std.testing.allocator,
            request,
            .{},
        );
        defer parsed.deinit();
        try std.testing.expectError(error.InvalidArguments, invoke(
            client,
            std.testing.allocator,
            std.testing.io,
            "spec_kitty_start_implementation",
            parsed.value,
            "0.1.0",
            "1.3.0",
        ));
    }

    var invalid_review = try std.json.parseFromSlice(
        std.json.Value,
        std.testing.allocator,
        \\{"mission":"042-test","wp":"WP01","actor":"reviewer","policy":{"orchestrator_id":"zig-mcp","orchestrator_version":"0.1.0","agent_family":"codex","approval_mode":"manual","sandbox_mode":"workspace-write","network_mode":"restricted","dangerous_flags":[]},"unexpected":true}
    ,
        .{},
    );
    defer invalid_review.deinit();
    try std.testing.expectError(error.InvalidArguments, invoke(
        client,
        std.testing.allocator,
        std.testing.io,
        "spec_kitty_start_review",
        invalid_review.value,
        "0.1.0",
        "1.3.0",
    ));
}

test "transition serializes structured inputs once and uses exact optional argv" {
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
    const request =
        \\{"mission":"042 mission;$(no-shell)","wp":"WP01","to":"done","actor":"reviewer;$(no-shell)","note":"Approved;$(no-shell)","policy":{"orchestrator_id":"zig-mcp","orchestrator_version":"0.1.0","agent_family":"codex","approval_mode":"manual","sandbox_mode":"workspace-write","network_mode":"restricted","dangerous_flags":[]},"review_ref":"PR #42;$(no-shell)","review_result":{"reviewer":"codex","verdict":"approved"},"evidence":{"review":{"reference":"PR #42"}},"subtasks_complete":true,"implementation_evidence_present":true}
    ;
    var parsed = try std.json.parseFromSlice(
        std.json.Value,
        std.testing.allocator,
        request,
        .{},
    );
    defer parsed.deinit();

    var invocation = try invoke(
        client,
        std.testing.allocator,
        std.testing.io,
        "spec_kitty_transition",
        parsed.value,
        "0.1.0",
        "1.3.0",
    );
    defer invocation.deinit(std.testing.allocator);
    try std.testing.expect(invocation.envelope().success);
    try std.testing.expectEqualStrings("orchestrator-api.transition", invocation.envelope().command);
    try std.testing.expectEqualStrings("corr-transition", invocation.envelope().correlation_id);
    try std.testing.expect(std.mem.indexOf(u8, invocation.stderr, "arg=042 mission;$(no-shell)\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, invocation.stderr, "transition-argv=validated\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, invocation.stderr, "zig-mcp") == null);

    var false_flags = try std.json.parseFromSlice(
        std.json.Value,
        std.testing.allocator,
        \\{"mission":"042-test","wp":"WP01","to":"approved","actor":"reviewer","subtasks_complete":false,"implementation_evidence_present":false}
    ,
        .{},
    );
    defer false_flags.deinit();
    var approved = try invoke(
        client,
        std.testing.allocator,
        std.testing.io,
        "spec_kitty_transition",
        false_flags.value,
        "0.1.0",
        "1.3.0",
    );
    defer approved.deinit(std.testing.allocator);
    try std.testing.expect(approved.envelope().success);
    try std.testing.expect(std.mem.indexOf(u8, approved.stderr, "transition-argv=validated\n") != null);
}

test "transition preserves guard failures and rejects unsafe argument shapes" {
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
    var blocked_request = try std.json.parseFromSlice(
        std.json.Value,
        std.testing.allocator,
        \\{"mission":"042-test","wp":"WP01","to":"blocked","actor":"codex"}
    ,
        .{},
    );
    defer blocked_request.deinit();
    var blocked = try invoke(
        client,
        std.testing.allocator,
        std.testing.io,
        "spec_kitty_transition",
        blocked_request.value,
        "0.1.0",
        "1.3.0",
    );
    defer blocked.deinit(std.testing.allocator);
    try std.testing.expect(!blocked.envelope().success);
    try std.testing.expectEqualStrings("TRANSITION_REJECTED", blocked.envelope().error_code.?);
    try std.testing.expectEqualStrings("corr-transition-rejected", blocked.envelope().correlation_id);

    const invalid_requests = [_][]const u8{
        \\{"mission":"042-test","wp":"WP01","to":"for_review","actor":"codex"}
        ,
        \\{"mission":"042-test","wp":"WP01","to":"done","actor":"codex","review_result":"raw-json"}
        ,
        \\{"mission":"042-test","wp":"WP01","to":"done","actor":"codex","evidence":[]}
        ,
        \\{"mission":"042-test","wp":"WP01","to":"done","actor":"codex","force":true}
        ,
        \\{"mission":"042-test","wp":"WP01","to":"done","actor":"codex","subtasks_complete":"yes"}
        ,
    };
    for (invalid_requests) |request| {
        var parsed = try std.json.parseFromSlice(
            std.json.Value,
            std.testing.allocator,
            request,
            .{},
        );
        defer parsed.deinit();
        try std.testing.expectError(error.InvalidArguments, invoke(
            client,
            std.testing.allocator,
            std.testing.io,
            "spec_kitty_transition",
            parsed.value,
            "0.1.0",
            "1.3.0",
        ));
    }
}

test "history and acceptance use fixed argv and preserve acceptance guards" {
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
    var history_request = try std.json.parseFromSlice(
        std.json.Value,
        std.testing.allocator,
        \\{"mission":"042 mission;$(no-shell)","wp":"WP01","actor":"codex;$(no-shell)","note":"Tests passed;$(no-shell)"}
    ,
        .{},
    );
    defer history_request.deinit();
    var history = try invoke(
        client,
        std.testing.allocator,
        std.testing.io,
        "spec_kitty_append_history",
        history_request.value,
        "0.1.0",
        "1.3.0",
    );
    defer history.deinit(std.testing.allocator);
    try std.testing.expect(history.envelope().success);
    try std.testing.expectEqualStrings("corr-history", history.envelope().correlation_id);
    try std.testing.expect(std.mem.indexOf(u8, history.stderr, "history-argv=validated\n") != null);

    var acceptance_request = try std.json.parseFromSlice(
        std.json.Value,
        std.testing.allocator,
        \\{"mission":"042-test","actor":"release-manager;$(no-shell)"}
    ,
        .{},
    );
    defer acceptance_request.deinit();
    var accepted = try invoke(
        client,
        std.testing.allocator,
        std.testing.io,
        "spec_kitty_accept_mission",
        acceptance_request.value,
        "0.1.0",
        "1.3.0",
    );
    defer accepted.deinit(std.testing.allocator);
    try std.testing.expect(accepted.envelope().success);
    try std.testing.expect(std.mem.indexOf(u8, accepted.stderr, "accept-argv=validated\n") != null);

    var not_ready_request = try std.json.parseFromSlice(
        std.json.Value,
        std.testing.allocator,
        \\{"mission":"not-ready","actor":"release-manager"}
    ,
        .{},
    );
    defer not_ready_request.deinit();
    var not_ready = try invoke(
        client,
        std.testing.allocator,
        std.testing.io,
        "spec_kitty_accept_mission",
        not_ready_request.value,
        "0.1.0",
        "1.3.0",
    );
    defer not_ready.deinit(std.testing.allocator);
    try std.testing.expect(!not_ready.envelope().success);
    try std.testing.expectEqualStrings("MISSION_NOT_READY", not_ready.envelope().error_code.?);
    try std.testing.expectEqualStrings("corr-not-ready", not_ready.envelope().correlation_id);
}
