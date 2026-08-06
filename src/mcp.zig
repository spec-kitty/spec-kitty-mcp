const std = @import("std");
const Io = std.Io;

const spec_kitty = @import("spec_kitty.zig");
const tools = @import("tools.zig");

pub const protocol_version = "2025-11-25";
pub const max_message_bytes = 1024 * 1024;

const server_name = "spec-kitty-mcp";
const server_description = "MCP adapter for the Spec Kitty orchestrator API";

pub const SessionState = enum {
    awaiting_initialize,
    awaiting_initialized,
    ready,
};

pub const Server = struct {
    state: SessionState = .awaiting_initialize,
    version: []const u8,
    runtime: ?Runtime = null,

    const Runtime = struct {
        client: spec_kitty.Client,
        io: Io,
        provider_version: []const u8,
        api_version: []const u8,
    };

    pub fn init(version: []const u8) Server {
        return .{ .version = version };
    }

    pub fn initWithTools(
        version: []const u8,
        client: spec_kitty.Client,
        io: Io,
        provider_version: []const u8,
        api_version: []const u8,
    ) Server {
        return .{
            .version = version,
            .runtime = .{
                .client = client,
                .io = io,
                .provider_version = provider_version,
                .api_version = api_version,
            },
        };
    }

    pub fn handleLine(
        server: *Server,
        allocator: std.mem.Allocator,
        raw_line: []const u8,
        writer: *Io.Writer,
    ) !void {
        const line = if (raw_line.len > 0 and raw_line[raw_line.len - 1] == '\r')
            raw_line[0 .. raw_line.len - 1]
        else
            raw_line;

        var parsed = std.json.parseFromSlice(std.json.Value, allocator, line, .{}) catch {
            return writeError(writer, .null, -32700, "Parse error");
        };
        defer parsed.deinit();

        const object = switch (parsed.value) {
            .object => |value| value,
            else => return writeError(writer, .null, -32600, "Invalid Request"),
        };

        const id = object.get("id");
        if (id) |value| {
            if (!isValidId(value)) {
                return writeError(writer, .null, -32600, "Invalid Request");
            }
        }
        const response_id: std.json.Value = if (id) |value|
            value
        else
            .null;

        const jsonrpc = object.get("jsonrpc") orelse
            return writeError(writer, response_id, -32600, "Invalid Request");
        if (jsonrpc != .string or !std.mem.eql(u8, jsonrpc.string, "2.0")) {
            return writeError(writer, response_id, -32600, "Invalid Request");
        }

        const method_value = object.get("method") orelse
            return writeError(writer, response_id, -32600, "Invalid Request");
        if (method_value != .string) {
            return writeError(writer, response_id, -32600, "Invalid Request");
        }

        const method = method_value.string;
        const is_notification = id == null;

        if (std.mem.eql(u8, method, "ping")) {
            if (!is_notification) try writeResult(writer, response_id, EmptyObject{});
            return;
        }

        if (std.mem.eql(u8, method, "initialize")) {
            if (is_notification) return;
            return server.handleInitialize(object, response_id, writer);
        }

        if (std.mem.eql(u8, method, "notifications/initialized")) {
            if (!is_notification) {
                return writeError(writer, response_id, -32600, "Invalid Request");
            }
            if (server.state == .awaiting_initialized) server.state = .ready;
            return;
        }

        if (is_notification) return;

        if (server.state != .ready) {
            return writeError(writer, response_id, -32002, "Server not initialized");
        }

        if (std.mem.eql(u8, method, "tools/list")) {
            const api_version: ?[]const u8 = if (server.runtime) |runtime|
                runtime.api_version
            else
                null;
            return writeResult(writer, response_id, ToolsListResult{
                .tools = tools.catalogForVersion(api_version),
            });
        }

        if (std.mem.eql(u8, method, "tools/call")) {
            return server.handleToolCall(
                allocator,
                object,
                response_id,
                writer,
            );
        }

        return writeError(writer, response_id, -32601, "Method not found");
    }

    fn handleToolCall(
        server: *Server,
        allocator: std.mem.Allocator,
        object: std.json.ObjectMap,
        id: std.json.Value,
        writer: *Io.Writer,
    ) !void {
        const params_value = object.get("params") orelse
            return writeError(writer, id, -32602, "Invalid tool parameters");
        if (params_value != .object) {
            return writeError(writer, id, -32602, "Invalid tool parameters");
        }

        const params = params_value.object;
        if (params.get("task") != null) {
            return writeError(writer, id, -32602, "Task-augmented calls are not supported");
        }
        const name = params.get("name") orelse
            return writeError(writer, id, -32602, "Invalid tool parameters");
        if (name != .string or name.string.len == 0) {
            return writeError(writer, id, -32602, "Invalid tool parameters");
        }

        const runtime = server.runtime orelse
            return writeError(writer, id, -32603, "Tool runtime unavailable");
        var invocation = tools.invoke(
            runtime.client,
            allocator,
            runtime.io,
            name.string,
            params.get("arguments"),
            runtime.provider_version,
            runtime.api_version,
        ) catch |err| switch (err) {
            error.UnknownTool => return writeError(writer, id, -32602, "Unknown tool"),
            error.InvalidArguments => return writeError(writer, id, -32602, "Invalid tool arguments"),
            error.OutOfMemory => return err,
            else => return writeToolExecutionError(writer, id, @errorName(err)),
        };
        defer invocation.deinit(allocator);

        const envelope = invocation.envelope();
        const text = std.mem.trimEnd(u8, invocation.stdout, "\r\n");
        const content = [_]TextContent{.{ .text = text }};
        return writeResult(writer, id, ToolEnvelopeResult{
            .content = &content,
            .structuredContent = envelope.*,
            .isError = !envelope.success,
        });
    }

    fn handleInitialize(
        server: *Server,
        object: std.json.ObjectMap,
        id: std.json.Value,
        writer: *Io.Writer,
    ) !void {
        if (server.state != .awaiting_initialize) {
            return writeError(writer, id, -32600, "Already initialized");
        }

        const params_value = object.get("params") orelse
            return writeError(writer, id, -32602, "Invalid initialize parameters");
        if (params_value != .object) {
            return writeError(writer, id, -32602, "Invalid initialize parameters");
        }

        const params = params_value.object;
        const requested_version = params.get("protocolVersion") orelse
            return writeError(writer, id, -32602, "Invalid initialize parameters");
        const capabilities = params.get("capabilities") orelse
            return writeError(writer, id, -32602, "Invalid initialize parameters");
        const client_info = params.get("clientInfo") orelse
            return writeError(writer, id, -32602, "Invalid initialize parameters");

        if (requested_version != .string or capabilities != .object or client_info != .object) {
            return writeError(writer, id, -32602, "Invalid initialize parameters");
        }

        const client_name = client_info.object.get("name") orelse
            return writeError(writer, id, -32602, "Invalid initialize parameters");
        const client_version = client_info.object.get("version") orelse
            return writeError(writer, id, -32602, "Invalid initialize parameters");
        if (client_name != .string or client_version != .string) {
            return writeError(writer, id, -32602, "Invalid initialize parameters");
        }

        server.state = .awaiting_initialized;
        try writeResult(writer, id, InitializeResult{
            .serverInfo = .{
                .version = server.version,
            },
        });
    }
};

const EmptyObject = struct {
    pub fn jsonStringify(_: EmptyObject, stringify: anytype) !void {
        try stringify.beginObject();
        try stringify.endObject();
    }
};

const ToolsCapability = struct {
    listChanged: bool = false,
};

const ServerCapabilities = struct {
    tools: ToolsCapability = .{},
};

const ServerInfo = struct {
    name: []const u8 = server_name,
    version: []const u8,
    description: []const u8 = server_description,
};

const InitializeResult = struct {
    protocolVersion: []const u8 = protocol_version,
    capabilities: ServerCapabilities = .{},
    serverInfo: ServerInfo,
    instructions: []const u8 = "Use tools/list to discover available Spec Kitty operations.",
};

const ToolsListResult = struct {
    tools: []const tools.Definition,
};

const TextContent = struct {
    type: []const u8 = "text",
    text: []const u8,
};

const ToolEnvelopeResult = struct {
    content: []const TextContent,
    structuredContent: spec_kitty.Envelope,
    isError: bool,
};

const ToolExecutionError = struct {
    content: []const TextContent,
    isError: bool = true,
};

const RpcError = struct {
    code: i32,
    message: []const u8,
};

fn isValidId(value: std.json.Value) bool {
    return switch (value) {
        .string, .integer, .float, .number_string => true,
        else => false,
    };
}

fn writeResult(writer: *Io.Writer, id: std.json.Value, result: anytype) !void {
    try std.json.Stringify.value(.{
        .jsonrpc = "2.0",
        .id = id,
        .result = result,
    }, .{}, writer);
    try writer.writeByte('\n');
}

fn writeError(
    writer: *Io.Writer,
    id: std.json.Value,
    code: i32,
    message: []const u8,
) !void {
    try std.json.Stringify.value(.{
        .jsonrpc = "2.0",
        .id = id,
        .@"error" = RpcError{
            .code = code,
            .message = message,
        },
    }, .{}, writer);
    try writer.writeByte('\n');
}

fn writeToolExecutionError(
    writer: *Io.Writer,
    id: std.json.Value,
    message: []const u8,
) !void {
    const content = [_]TextContent{.{ .text = message }};
    return writeResult(writer, id, ToolExecutionError{ .content = &content });
}

fn runSessionWithServer(
    allocator: std.mem.Allocator,
    reader: *Io.Reader,
    writer: *Io.Writer,
    server: *Server,
) !void {
    while (true) {
        const framed = reader.takeDelimiterInclusive('\n') catch |err| switch (err) {
            error.EndOfStream => return,
            else => return err,
        };
        const line = framed[0 .. framed.len - 1];
        try server.handleLine(allocator, line, writer);
        try writer.flush();
    }
}

pub fn runSession(
    allocator: std.mem.Allocator,
    reader: *Io.Reader,
    writer: *Io.Writer,
    version: []const u8,
) !void {
    var server = Server.init(version);
    return runSessionWithServer(allocator, reader, writer, &server);
}

pub fn serve(
    io: Io,
    allocator: std.mem.Allocator,
    version: []const u8,
    client: spec_kitty.Client,
    provider_version: []const u8,
    api_version: []const u8,
) !void {
    const input_buffer = try allocator.alloc(u8, max_message_bytes);
    defer allocator.free(input_buffer);

    var stdin_reader = Io.File.stdin().readerStreaming(io, input_buffer);
    var output_buffer: [64 * 1024]u8 = undefined;
    var stdout_writer = Io.File.stdout().writerStreaming(io, &output_buffer);

    var server = Server.initWithTools(
        version,
        client,
        io,
        provider_version,
        api_version,
    );
    try runSessionWithServer(
        allocator,
        &stdin_reader.interface,
        &stdout_writer.interface,
        &server,
    );
    try stdout_writer.interface.flush();
}

fn exchange(server: *Server, line: []const u8) ![]u8 {
    var output: Io.Writer.Allocating = .init(std.testing.allocator);
    errdefer output.deinit();

    try server.handleLine(std.testing.allocator, line, &output.writer);
    return output.toOwnedSlice();
}

fn makeFakeToolExecutable(
    allocator: std.mem.Allocator,
    dir: Io.Dir,
) ![]u8 {
    const script =
        \\#!/bin/sh
        \\if [ "$2" = "start-implementation" ]; then
        \\  if [ "$8" = "other-actor" ]; then
        \\    printf '%s\n' '{"contract_version":"1.3.0","command":"orchestrator-api.start-implementation","timestamp":"2026-08-06T00:00:00Z","correlation_id":"corr-claimed","success":false,"error_code":"WP_ALREADY_CLAIMED","data":{"claiming_actor":"first-actor"}}'
        \\    exit 1
        \\  fi
        \\  printf '%s\n' '{"contract_version":"1.3.0","command":"orchestrator-api.start-implementation","timestamp":"2026-08-06T00:00:00Z","correlation_id":"corr-no-op","success":true,"error_code":null,"data":{"from_lane":"in_progress","to_lane":"in_progress","policy_metadata_recorded":true,"no_op":true}}'
        \\  exit 0
        \\fi
        \\if [ "$4" = "missing" ]; then
        \\  printf '{"contract_version":"1.3.0","command":"orchestrator-api.%s","timestamp":"2026-08-06T00:00:00Z","correlation_id":"corr-missing","success":false,"error_code":"MISSION_NOT_FOUND","data":{}}\n' "$2"
        \\  exit 1
        \\fi
        \\printf '{"contract_version":"1.3.0","command":"orchestrator-api.%s","timestamp":"2026-08-06T00:00:00Z","correlation_id":"corr-success","success":true,"error_code":null,"data":{"mission_slug":"%s"}}\n' "$2" "$4"
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

test "parse errors use a null response id" {
    var server = Server.init("test");
    const response = try exchange(&server, "not-json");
    defer std.testing.allocator.free(response);

    try std.testing.expectEqualStrings(
        "{\"jsonrpc\":\"2.0\",\"id\":null,\"error\":{\"code\":-32700,\"message\":\"Parse error\"}}\n",
        response,
    );
}

test "initialize negotiates the supported version" {
    var server = Server.init("0.1.0-test");
    const response = try exchange(
        &server,
        "{\"jsonrpc\":\"2.0\",\"id\":7,\"method\":\"initialize\",\"params\":{\"protocolVersion\":\"2099-01-01\",\"capabilities\":{},\"clientInfo\":{\"name\":\"test\",\"version\":\"1\"}}}",
    );
    defer std.testing.allocator.free(response);

    try std.testing.expectEqual(.awaiting_initialized, server.state);
    try std.testing.expect(std.mem.indexOf(u8, response, "\"protocolVersion\":\"2025-11-25\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, response, "\"version\":\"0.1.0-test\"") != null);
    try std.testing.expect(std.mem.startsWith(u8, response, "{\"jsonrpc\":\"2.0\",\"id\":7,"));
}

test "initialize requires the MCP parameter shape" {
    var server = Server.init("test");
    const response = try exchange(
        &server,
        "{\"jsonrpc\":\"2.0\",\"id\":\"init\",\"method\":\"initialize\",\"params\":{}}",
    );
    defer std.testing.allocator.free(response);

    try std.testing.expectEqual(.awaiting_initialize, server.state);
    try std.testing.expectEqualStrings(
        "{\"jsonrpc\":\"2.0\",\"id\":\"init\",\"error\":{\"code\":-32602,\"message\":\"Invalid initialize parameters\"}}\n",
        response,
    );
}

test "request ids must be strings or numbers" {
    var server = Server.init("test");
    const response = try exchange(
        &server,
        "{\"jsonrpc\":\"2.0\",\"id\":{},\"method\":\"ping\"}",
    );
    defer std.testing.allocator.free(response);

    try std.testing.expectEqualStrings(
        "{\"jsonrpc\":\"2.0\",\"id\":null,\"error\":{\"code\":-32600,\"message\":\"Invalid Request\"}}\n",
        response,
    );
}

test "requests are gated until the initialized notification" {
    var server = Server.init("test");
    server.state = .awaiting_initialized;

    const blocked = try exchange(
        &server,
        "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"tools/list\"}",
    );
    defer std.testing.allocator.free(blocked);
    try std.testing.expectEqualStrings(
        "{\"jsonrpc\":\"2.0\",\"id\":2,\"error\":{\"code\":-32002,\"message\":\"Server not initialized\"}}\n",
        blocked,
    );

    const notification = try exchange(
        &server,
        "{\"jsonrpc\":\"2.0\",\"method\":\"notifications/initialized\"}",
    );
    defer std.testing.allocator.free(notification);
    try std.testing.expectEqualStrings("", notification);
    try std.testing.expectEqual(.ready, server.state);

    const ready = try exchange(
        &server,
        "{\"jsonrpc\":\"2.0\",\"id\":3,\"method\":\"tools/list\"}",
    );
    defer std.testing.allocator.free(ready);
    try std.testing.expect(std.mem.startsWith(u8, ready, "{\"jsonrpc\":\"2.0\",\"id\":3,\"result\":{\"tools\":["));
    try std.testing.expect(std.mem.indexOf(u8, ready, "\"name\":\"spec_kitty_mission_state\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, ready, "\"name\":\"spec_kitty_list_ready\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, ready, "\"name\":\"spec_kitty_start_implementation\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, ready, "\"name\":\"spec_kitty_start_review\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, ready, "\"name\":\"spec_kitty_transition\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, ready, "\"name\":\"spec_kitty_append_history\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, ready, "\"name\":\"spec_kitty_accept_mission\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, ready, "\"readOnlyHint\":false") != null);
}

test "ping is available throughout the lifecycle" {
    var server = Server.init("test");
    const response = try exchange(
        &server,
        "{\"jsonrpc\":\"2.0\",\"id\":99,\"method\":\"ping\"}",
    );
    defer std.testing.allocator.free(response);

    try std.testing.expectEqualStrings(
        "{\"jsonrpc\":\"2.0\",\"id\":99,\"result\":{}}\n",
        response,
    );
}

test "unknown notifications are ignored and unknown requests receive an error" {
    var server = Server.init("test");
    server.state = .ready;

    const notification = try exchange(
        &server,
        "{\"jsonrpc\":\"2.0\",\"method\":\"notifications/unknown\"}",
    );
    defer std.testing.allocator.free(notification);
    try std.testing.expectEqualStrings("", notification);

    const request = try exchange(
        &server,
        "{\"jsonrpc\":\"2.0\",\"id\":4,\"method\":\"unknown\"}",
    );
    defer std.testing.allocator.free(request);
    try std.testing.expectEqualStrings(
        "{\"jsonrpc\":\"2.0\",\"id\":4,\"error\":{\"code\":-32601,\"message\":\"Method not found\"}}\n",
        request,
    );
}

test "tool calls preserve successful and failed Spec Kitty envelopes" {
    if (@import("builtin").os.tag == .windows) return error.SkipZigTest;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const executable = try makeFakeToolExecutable(std.testing.allocator, tmp.dir);
    defer std.testing.allocator.free(executable);

    var root_buffer: [Io.Dir.max_path_bytes]u8 = undefined;
    const root_len = try tmp.dir.realPath(std.testing.io, &root_buffer);
    const client: spec_kitty.Client = .{
        .executable = executable,
        .project_root = root_buffer[0..root_len],
    };
    var server = Server.initWithTools(
        "test",
        client,
        std.testing.io,
        "0.1.0",
        "1.3.0",
    );
    server.state = .ready;

    const success = try exchange(
        &server,
        "{\"jsonrpc\":\"2.0\",\"id\":10,\"method\":\"tools/call\",\"params\":{\"name\":\"spec_kitty_mission_state\",\"arguments\":{\"mission\":\"042-test\"}}}",
    );
    defer std.testing.allocator.free(success);
    try std.testing.expect(std.mem.indexOf(u8, success, "\"structuredContent\":{\"contract_version\":\"1.3.0\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, success, "\"command\":\"orchestrator-api.mission-state\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, success, "\"mission_slug\":\"042-test\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, success, "\"isError\":false") != null);

    const failure = try exchange(
        &server,
        "{\"jsonrpc\":\"2.0\",\"id\":11,\"method\":\"tools/call\",\"params\":{\"name\":\"spec_kitty_list_ready\",\"arguments\":{\"mission\":\"missing\"}}}",
    );
    defer std.testing.allocator.free(failure);
    try std.testing.expect(std.mem.indexOf(u8, failure, "\"command\":\"orchestrator-api.list-ready\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, failure, "\"correlation_id\":\"corr-missing\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, failure, "\"error_code\":\"MISSION_NOT_FOUND\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, failure, "\"isError\":true") != null);
}

test "tool calls reject unknown tools and invalid arguments" {
    const client: spec_kitty.Client = .{
        .executable = "unused",
        .project_root = ".",
    };
    var server = Server.initWithTools(
        "test",
        client,
        std.testing.io,
        "0.1.0",
        "1.3.0",
    );
    server.state = .ready;

    const unknown = try exchange(
        &server,
        "{\"jsonrpc\":\"2.0\",\"id\":12,\"method\":\"tools/call\",\"params\":{\"name\":\"not_a_tool\",\"arguments\":{}}}",
    );
    defer std.testing.allocator.free(unknown);
    try std.testing.expectEqualStrings(
        "{\"jsonrpc\":\"2.0\",\"id\":12,\"error\":{\"code\":-32602,\"message\":\"Unknown tool\"}}\n",
        unknown,
    );

    const invalid = try exchange(
        &server,
        "{\"jsonrpc\":\"2.0\",\"id\":13,\"method\":\"tools/call\",\"params\":{\"name\":\"spec_kitty_mission_state\",\"arguments\":{\"mission\":\"\",\"extra\":true}}}",
    );
    defer std.testing.allocator.free(invalid);
    try std.testing.expectEqualStrings(
        "{\"jsonrpc\":\"2.0\",\"id\":13,\"error\":{\"code\":-32602,\"message\":\"Invalid tool arguments\"}}\n",
        invalid,
    );
}

test "mutation tool calls preserve idempotent and guard outcomes" {
    if (@import("builtin").os.tag == .windows) return error.SkipZigTest;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const executable = try makeFakeToolExecutable(std.testing.allocator, tmp.dir);
    defer std.testing.allocator.free(executable);

    var root_buffer: [Io.Dir.max_path_bytes]u8 = undefined;
    const root_len = try tmp.dir.realPath(std.testing.io, &root_buffer);
    const client: spec_kitty.Client = .{
        .executable = executable,
        .project_root = root_buffer[0..root_len],
    };
    var server = Server.initWithTools(
        "test",
        client,
        std.testing.io,
        "0.1.0",
        "1.3.0",
    );
    server.state = .ready;

    const no_op_request =
        \\{"jsonrpc":"2.0","id":17,"method":"tools/call","params":{"name":"spec_kitty_start_implementation","arguments":{"mission":"042-test","wp":"WP01","actor":"same-actor","policy":{"orchestrator_id":"zig-mcp","orchestrator_version":"0.1.0","agent_family":"codex","approval_mode":"manual","sandbox_mode":"workspace-write","network_mode":"restricted","dangerous_flags":[]}}}}
    ;
    const no_op = try exchange(&server, no_op_request);
    defer std.testing.allocator.free(no_op);
    try std.testing.expect(std.mem.indexOf(u8, no_op, "\"correlation_id\":\"corr-no-op\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, no_op, "\"no_op\":true") != null);
    try std.testing.expect(std.mem.indexOf(u8, no_op, "\"isError\":false") != null);

    const claimed_request =
        \\{"jsonrpc":"2.0","id":18,"method":"tools/call","params":{"name":"spec_kitty_start_implementation","arguments":{"mission":"042-test","wp":"WP01","actor":"other-actor","policy":{"orchestrator_id":"zig-mcp","orchestrator_version":"0.1.0","agent_family":"codex","approval_mode":"manual","sandbox_mode":"workspace-write","network_mode":"restricted","dangerous_flags":[]}}}}
    ;
    const claimed = try exchange(&server, claimed_request);
    defer std.testing.allocator.free(claimed);
    try std.testing.expect(std.mem.indexOf(u8, claimed, "\"correlation_id\":\"corr-claimed\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, claimed, "\"error_code\":\"WP_ALREADY_CLAIMED\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, claimed, "\"isError\":true") != null);

    const invalid = try exchange(
        &server,
        "{\"jsonrpc\":\"2.0\",\"id\":19,\"method\":\"tools/call\",\"params\":{\"name\":\"spec_kitty_start_implementation\",\"arguments\":{\"mission\":\"042-test\",\"wp\":\"WP01\",\"actor\":\"codex\",\"policy\":\"raw-json\"}}}",
    );
    defer std.testing.allocator.free(invalid);
    try std.testing.expectEqualStrings(
        "{\"jsonrpc\":\"2.0\",\"id\":19,\"error\":{\"code\":-32602,\"message\":\"Invalid tool arguments\"}}\n",
        invalid,
    );

    const forced = try exchange(
        &server,
        "{\"jsonrpc\":\"2.0\",\"id\":20,\"method\":\"tools/call\",\"params\":{\"name\":\"spec_kitty_transition\",\"arguments\":{\"mission\":\"042-test\",\"wp\":\"WP01\",\"to\":\"done\",\"actor\":\"codex\",\"force\":true}}}",
    );
    defer std.testing.allocator.free(forced);
    try std.testing.expectEqualStrings(
        "{\"jsonrpc\":\"2.0\",\"id\":20,\"error\":{\"code\":-32602,\"message\":\"Invalid tool arguments\"}}\n",
        forced,
    );
}

test "workspace tool discovery and calls honor the negotiated contract" {
    const client: spec_kitty.Client = .{
        .executable = "unused",
        .project_root = ".",
    };
    var server = Server.initWithTools(
        "test",
        client,
        std.testing.io,
        "0.1.0",
        "1.1.9",
    );
    server.state = .ready;

    const listed = try exchange(
        &server,
        "{\"jsonrpc\":\"2.0\",\"id\":15,\"method\":\"tools/list\"}",
    );
    defer std.testing.allocator.free(listed);
    try std.testing.expect(std.mem.indexOf(u8, listed, "spec_kitty_mission_state") != null);
    try std.testing.expect(std.mem.indexOf(u8, listed, "spec_kitty_resolve_workspace") == null);

    const called = try exchange(
        &server,
        "{\"jsonrpc\":\"2.0\",\"id\":16,\"method\":\"tools/call\",\"params\":{\"name\":\"spec_kitty_resolve_workspace\",\"arguments\":{\"mission\":\"042-test\",\"wp\":\"WP01\"}}}",
    );
    defer std.testing.allocator.free(called);
    try std.testing.expectEqualStrings(
        "{\"jsonrpc\":\"2.0\",\"id\":16,\"error\":{\"code\":-32602,\"message\":\"Unknown tool\"}}\n",
        called,
    );
}

test "tool execution failures are visible to the model" {
    const client: spec_kitty.Client = .{
        .executable = "/definitely/missing/spec-kitty",
        .project_root = ".",
    };
    var server = Server.initWithTools(
        "test",
        client,
        std.testing.io,
        "0.1.0",
        "1.3.0",
    );
    server.state = .ready;

    const response = try exchange(
        &server,
        "{\"jsonrpc\":\"2.0\",\"id\":14,\"method\":\"tools/call\",\"params\":{\"name\":\"spec_kitty_mission_state\",\"arguments\":{\"mission\":\"042-test\"}}}",
    );
    defer std.testing.allocator.free(response);
    try std.testing.expectEqualStrings(
        "{\"jsonrpc\":\"2.0\",\"id\":14,\"result\":{\"content\":[{\"type\":\"text\",\"text\":\"ExecutableNotFound\"}],\"isError\":true}}\n",
        response,
    );
}

test "duplicate initialize requests are rejected" {
    var server = Server.init("test");
    server.state = .awaiting_initialized;
    const response = try exchange(
        &server,
        "{\"jsonrpc\":\"2.0\",\"id\":5,\"method\":\"initialize\",\"params\":{\"protocolVersion\":\"2025-11-25\",\"capabilities\":{},\"clientInfo\":{}}}",
    );
    defer std.testing.allocator.free(response);

    try std.testing.expectEqualStrings(
        "{\"jsonrpc\":\"2.0\",\"id\":5,\"error\":{\"code\":-32600,\"message\":\"Already initialized\"}}\n",
        response,
    );
}

test "stdio transcript is newline framed" {
    const transcript =
        "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":{\"protocolVersion\":\"2025-11-25\",\"capabilities\":{},\"clientInfo\":{\"name\":\"test\",\"version\":\"1\"}}}\n" ++
        "{\"jsonrpc\":\"2.0\",\"method\":\"notifications/initialized\"}\n" ++
        "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"tools/list\"}\n";
    var reader = Io.Reader.fixed(transcript);
    var output: Io.Writer.Allocating = .init(std.testing.allocator);
    defer output.deinit();

    try runSession(std.testing.allocator, &reader, &output.writer, "test");

    try std.testing.expectEqual(@as(usize, 2), std.mem.count(u8, output.written(), "\n"));
    try std.testing.expect(std.mem.indexOf(u8, output.written(), "\"id\":1") != null);
    try std.testing.expect(std.mem.indexOf(u8, output.written(), "\"id\":2,\"result\":{\"tools\":[") != null);
    try std.testing.expect(std.mem.endsWith(u8, output.written(), "}}\n"));
}

test "an unterminated stdio frame is not processed" {
    var reader = Io.Reader.fixed(
        "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"ping\"}",
    );
    var output: Io.Writer.Allocating = .init(std.testing.allocator);
    defer output.deinit();

    try runSession(std.testing.allocator, &reader, &output.writer, "test");
    try std.testing.expectEqualStrings("", output.written());
}
