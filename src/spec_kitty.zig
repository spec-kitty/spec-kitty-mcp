const std = @import("std");
const Io = std.Io;

pub const default_timeout_ms: u64 = 30_000;
pub const default_stdout_limit: usize = 1024 * 1024;
pub const default_stderr_limit: usize = 256 * 1024;

pub const Error = error{
    AbnormalTermination,
    CommandTimedOut,
    ContractRejected,
    EnvelopeCommandMismatch,
    EnvelopeInvariantViolation,
    ExecutableNotFound,
    InvalidContractData,
    InvalidEnvelope,
    OutputLimitExceeded,
};

pub const Envelope = struct {
    contract_version: []const u8,
    command: []const u8,
    timestamp: []const u8,
    correlation_id: []const u8,
    success: bool,
    error_code: ?[]const u8,
    data: std.json.Value,
};

pub const Invocation = struct {
    term: std.process.Child.Term,
    stdout: []u8,
    stderr: []u8,
    parsed: std.json.Parsed(Envelope),

    pub fn envelope(invocation: *const Invocation) *const Envelope {
        return &invocation.parsed.value;
    }

    pub fn deinit(invocation: *Invocation, allocator: std.mem.Allocator) void {
        invocation.parsed.deinit();
        allocator.free(invocation.stdout);
        allocator.free(invocation.stderr);
        invocation.* = undefined;
    }
};

pub const Contract = struct {
    contract_version: []u8,
    api_version: []u8,
    min_supported_provider_version: []u8,

    pub fn deinit(contract: *Contract, allocator: std.mem.Allocator) void {
        allocator.free(contract.contract_version);
        allocator.free(contract.api_version);
        allocator.free(contract.min_supported_provider_version);
        contract.* = undefined;
    }
};

pub const Client = struct {
    executable: []const u8,
    project_root: []const u8,
    timeout_ms: u64 = default_timeout_ms,
    stdout_limit: usize = default_stdout_limit,
    stderr_limit: usize = default_stderr_limit,

    pub fn invoke(
        client: Client,
        allocator: std.mem.Allocator,
        io: Io,
        subcommand: []const u8,
        args: []const []const u8,
    ) !Invocation {
        var argv: std.ArrayList([]const u8) = .empty;
        defer argv.deinit(allocator);

        try argv.appendSlice(allocator, &.{
            client.executable,
            "orchestrator-api",
            subcommand,
        });
        try argv.appendSlice(allocator, args);

        const duration: Io.Clock.Duration = .{
            .clock = .awake,
            .raw = .fromMilliseconds(@intCast(client.timeout_ms)),
        };
        const deadline: Io.Timeout = .{
            .deadline = .fromNow(io, duration),
        };

        const result = std.process.run(allocator, io, .{
            .argv = argv.items,
            .cwd = .{ .path = client.project_root },
            .stdout_limit = .limited(client.stdout_limit),
            .stderr_limit = .limited(client.stderr_limit),
            .reserve_amount = @max(1, @min(@max(client.stdout_limit, client.stderr_limit), 4096)),
            .timeout = deadline,
        }) catch |err| switch (err) {
            error.FileNotFound => return error.ExecutableNotFound,
            error.StreamTooLong => return error.OutputLimitExceeded,
            error.Timeout => return error.CommandTimedOut,
            else => return err,
        };
        errdefer allocator.free(result.stdout);
        errdefer allocator.free(result.stderr);

        switch (result.term) {
            .exited => {},
            else => return error.AbnormalTermination,
        }

        var parsed = std.json.parseFromSlice(Envelope, allocator, result.stdout, .{}) catch |err| switch (err) {
            error.OutOfMemory => return err,
            else => return error.InvalidEnvelope,
        };
        errdefer parsed.deinit();

        try validateEnvelope(&parsed.value, subcommand);

        return .{
            .term = result.term,
            .stdout = result.stdout,
            .stderr = result.stderr,
            .parsed = parsed,
        };
    }

    pub fn negotiate(
        client: Client,
        allocator: std.mem.Allocator,
        io: Io,
        provider_version: []const u8,
    ) !Contract {
        var invocation = try client.invoke(
            allocator,
            io,
            "contract-version",
            &.{ "--provider-version", provider_version },
        );
        defer invocation.deinit(allocator);

        const envelope = invocation.envelope();
        const exit_code = switch (invocation.term) {
            .exited => |code| code,
            else => unreachable,
        };
        if (!envelope.success) return error.ContractRejected;
        if (exit_code != 0) return error.EnvelopeInvariantViolation;

        const data = switch (envelope.data) {
            .object => |value| value,
            else => return error.InvalidContractData,
        };
        const api_version = data.get("api_version") orelse
            return error.InvalidContractData;
        const min_provider = data.get("min_supported_provider_version") orelse
            return error.InvalidContractData;
        if (api_version != .string or min_provider != .string) {
            return error.InvalidContractData;
        }
        if (api_version.string.len == 0 or min_provider.string.len == 0) {
            return error.InvalidContractData;
        }
        _ = std.SemanticVersion.parse(api_version.string) catch
            return error.InvalidContractData;
        _ = std.SemanticVersion.parse(min_provider.string) catch
            return error.InvalidContractData;
        if (!std.mem.eql(u8, envelope.contract_version, api_version.string)) {
            return error.InvalidContractData;
        }

        const owned_contract = try allocator.dupe(u8, envelope.contract_version);
        errdefer allocator.free(owned_contract);
        const owned_api = try allocator.dupe(u8, api_version.string);
        errdefer allocator.free(owned_api);
        const owned_min = try allocator.dupe(u8, min_provider.string);
        errdefer allocator.free(owned_min);

        return .{
            .contract_version = owned_contract,
            .api_version = owned_api,
            .min_supported_provider_version = owned_min,
        };
    }
};

fn validateEnvelope(envelope: *const Envelope, subcommand: []const u8) !void {
    if (envelope.contract_version.len == 0 or
        envelope.command.len == 0 or
        envelope.timestamp.len == 0 or
        envelope.correlation_id.len == 0)
    {
        return error.EnvelopeInvariantViolation;
    }

    const command_prefix = "orchestrator-api.";
    if (!std.mem.startsWith(u8, envelope.command, command_prefix) or
        !std.mem.eql(u8, envelope.command[command_prefix.len..], subcommand))
    {
        return error.EnvelopeCommandMismatch;
    }

    if (envelope.success != (envelope.error_code == null)) {
        return error.EnvelopeInvariantViolation;
    }
    if (envelope.error_code) |code| {
        if (code.len == 0) return error.EnvelopeInvariantViolation;
    }
    if (envelope.data != .object) return error.EnvelopeInvariantViolation;
}

fn makeFakeExecutable(
    allocator: std.mem.Allocator,
    dir: Io.Dir,
    body: []const u8,
) ![]u8 {
    try dir.writeFile(std.testing.io, .{
        .sub_path = "fake-spec-kitty",
        .data = body,
        .flags = .{ .permissions = .executable_file },
    });

    var root_buffer: [Io.Dir.max_path_bytes]u8 = undefined;
    const root_len = try dir.realPath(std.testing.io, &root_buffer);
    return std.fs.path.join(allocator, &.{
        root_buffer[0..root_len],
        "fake-spec-kitty",
    });
}

const success_script =
    \\#!/bin/sh
    \\printf 'cwd=%s\n' "$PWD" >&2
    \\for arg in "$@"; do printf 'arg=%s\n' "$arg" >&2; done
    \\printf '%s\n' '{"contract_version":"1.3.0","command":"orchestrator-api.contract-version","timestamp":"2026-08-06T00:00:00Z","correlation_id":"corr-test","success":true,"error_code":null,"data":{"api_version":"1.3.0","min_supported_provider_version":"0.1.0"}}'
;

test "invoke uses the configured cwd and exact argument vector" {
    if (@import("builtin").os.tag == .windows) return error.SkipZigTest;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const executable = try makeFakeExecutable(std.testing.allocator, tmp.dir, success_script);
    defer std.testing.allocator.free(executable);

    var root_buffer: [Io.Dir.max_path_bytes]u8 = undefined;
    const root_len = try tmp.dir.realPath(std.testing.io, &root_buffer);
    const root = root_buffer[0..root_len];

    const client: Client = .{
        .executable = executable,
        .project_root = root,
    };
    var invocation = try client.invoke(
        std.testing.allocator,
        std.testing.io,
        "contract-version",
        &.{ "--provider-version", "value with spaces;$(no-shell)" },
    );
    defer invocation.deinit(std.testing.allocator);

    try std.testing.expect(invocation.envelope().success);
    try std.testing.expect(std.mem.startsWith(u8, invocation.stderr, "cwd="));
    try std.testing.expect(std.mem.indexOf(u8, invocation.stderr, root) != null);
    try std.testing.expect(std.mem.indexOf(u8, invocation.stderr, "arg=orchestrator-api\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, invocation.stderr, "arg=contract-version\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, invocation.stderr, "arg=value with spaces;$(no-shell)\n") != null);
}

test "negotiate returns the live contract fields" {
    if (@import("builtin").os.tag == .windows) return error.SkipZigTest;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const executable = try makeFakeExecutable(std.testing.allocator, tmp.dir, success_script);
    defer std.testing.allocator.free(executable);

    var root_buffer: [Io.Dir.max_path_bytes]u8 = undefined;
    const root_len = try tmp.dir.realPath(std.testing.io, &root_buffer);
    const client: Client = .{
        .executable = executable,
        .project_root = root_buffer[0..root_len],
    };
    var contract = try client.negotiate(
        std.testing.allocator,
        std.testing.io,
        "0.1.0",
    );
    defer contract.deinit(std.testing.allocator);

    try std.testing.expectEqualStrings("1.3.0", contract.contract_version);
    try std.testing.expectEqualStrings("1.3.0", contract.api_version);
    try std.testing.expectEqualStrings("0.1.0", contract.min_supported_provider_version);
}

test "negotiate rejects contract versions that are not semantic versions" {
    if (@import("builtin").os.tag == .windows) return error.SkipZigTest;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const executable = try makeFakeExecutable(
        std.testing.allocator,
        tmp.dir,
        \\#!/bin/sh
        \\printf '%s\n' '{"contract_version":"current","command":"orchestrator-api.contract-version","timestamp":"2026-08-06T00:00:00Z","correlation_id":"corr-test","success":true,"error_code":null,"data":{"api_version":"current","min_supported_provider_version":"0.1.0"}}'
        ,
    );
    defer std.testing.allocator.free(executable);

    var root_buffer: [Io.Dir.max_path_bytes]u8 = undefined;
    const root_len = try tmp.dir.realPath(std.testing.io, &root_buffer);
    const client: Client = .{
        .executable = executable,
        .project_root = root_buffer[0..root_len],
    };
    try std.testing.expectError(error.InvalidContractData, client.negotiate(
        std.testing.allocator,
        std.testing.io,
        "0.1.0",
    ));
}

test "valid failure envelopes remain inspectable" {
    if (@import("builtin").os.tag == .windows) return error.SkipZigTest;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const script =
        \\#!/bin/sh
        \\printf '%s\n' '{"contract_version":"1.3.0","command":"orchestrator-api.mission-state","timestamp":"2026-08-06T00:00:00Z","correlation_id":"corr-fail","success":false,"error_code":"MISSION_NOT_FOUND","data":{}}'
        \\exit 1
    ;
    const executable = try makeFakeExecutable(std.testing.allocator, tmp.dir, script);
    defer std.testing.allocator.free(executable);

    var root_buffer: [Io.Dir.max_path_bytes]u8 = undefined;
    const root_len = try tmp.dir.realPath(std.testing.io, &root_buffer);
    const client: Client = .{
        .executable = executable,
        .project_root = root_buffer[0..root_len],
    };
    var invocation = try client.invoke(
        std.testing.allocator,
        std.testing.io,
        "mission-state",
        &.{ "--mission", "missing" },
    );
    defer invocation.deinit(std.testing.allocator);

    try std.testing.expect(!invocation.envelope().success);
    try std.testing.expectEqualStrings("MISSION_NOT_FOUND", invocation.envelope().error_code.?);
    try std.testing.expectEqual(@as(u8, 1), invocation.term.exited);
}

test "invoke rejects invalid and mismatched envelopes" {
    if (@import("builtin").os.tag == .windows) return error.SkipZigTest;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const invalid_executable = try makeFakeExecutable(
        std.testing.allocator,
        tmp.dir,
        "#!/bin/sh\nprintf '%s\\n' 'not-json'\n",
    );
    defer std.testing.allocator.free(invalid_executable);

    var root_buffer: [Io.Dir.max_path_bytes]u8 = undefined;
    const root_len = try tmp.dir.realPath(std.testing.io, &root_buffer);
    const invalid_client: Client = .{
        .executable = invalid_executable,
        .project_root = root_buffer[0..root_len],
    };
    try std.testing.expectError(error.InvalidEnvelope, invalid_client.invoke(
        std.testing.allocator,
        std.testing.io,
        "contract-version",
        &.{},
    ));

    const mismatch_script =
        \\#!/bin/sh
        \\printf '%s\n' '{"contract_version":"1.3.0","command":"orchestrator-api.list-ready","timestamp":"2026-08-06T00:00:00Z","correlation_id":"corr-test","success":true,"error_code":null,"data":{}}'
    ;
    const mismatch_executable = try makeFakeExecutable(
        std.testing.allocator,
        tmp.dir,
        mismatch_script,
    );
    defer std.testing.allocator.free(mismatch_executable);
    const mismatch_client: Client = .{
        .executable = mismatch_executable,
        .project_root = root_buffer[0..root_len],
    };
    try std.testing.expectError(error.EnvelopeCommandMismatch, mismatch_client.invoke(
        std.testing.allocator,
        std.testing.io,
        "mission-state",
        &.{},
    ));
}

test "invoke enforces timeout and output limits" {
    if (@import("builtin").os.tag == .windows) return error.SkipZigTest;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var root_buffer: [Io.Dir.max_path_bytes]u8 = undefined;
    const root_len = try tmp.dir.realPath(std.testing.io, &root_buffer);
    const root = root_buffer[0..root_len];

    const timeout_executable = try makeFakeExecutable(
        std.testing.allocator,
        tmp.dir,
        "#!/bin/sh\nsleep 1\n",
    );
    defer std.testing.allocator.free(timeout_executable);
    const timeout_client: Client = .{
        .executable = timeout_executable,
        .project_root = root,
        .timeout_ms = 10,
    };
    try std.testing.expectError(error.CommandTimedOut, timeout_client.invoke(
        std.testing.allocator,
        std.testing.io,
        "contract-version",
        &.{},
    ));

    const output_executable = try makeFakeExecutable(
        std.testing.allocator,
        tmp.dir,
        "#!/bin/sh\nprintf '0123456789abcdef'\n",
    );
    defer std.testing.allocator.free(output_executable);
    const output_client: Client = .{
        .executable = output_executable,
        .project_root = root,
        .stdout_limit = 8,
    };
    try std.testing.expectError(error.OutputLimitExceeded, output_client.invoke(
        std.testing.allocator,
        std.testing.io,
        "contract-version",
        &.{},
    ));

    const stderr_executable = try makeFakeExecutable(
        std.testing.allocator,
        tmp.dir,
        "#!/bin/sh\nprintf '0123456789abcdef' >&2\n",
    );
    defer std.testing.allocator.free(stderr_executable);
    const stderr_client: Client = .{
        .executable = stderr_executable,
        .project_root = root,
        .stderr_limit = 8,
    };
    try std.testing.expectError(error.OutputLimitExceeded, stderr_client.invoke(
        std.testing.allocator,
        std.testing.io,
        "contract-version",
        &.{},
    ));
}

test "invoke reports a missing executable" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var root_buffer: [Io.Dir.max_path_bytes]u8 = undefined;
    const root_len = try tmp.dir.realPath(std.testing.io, &root_buffer);

    const client: Client = .{
        .executable = "/definitely/missing/spec-kitty",
        .project_root = root_buffer[0..root_len],
    };
    try std.testing.expectError(error.ExecutableNotFound, client.invoke(
        std.testing.allocator,
        std.testing.io,
        "contract-version",
        &.{},
    ));
}
