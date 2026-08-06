const std = @import("std");
const Io = std.Io;

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

    pub fn init(version: []const u8) Server {
        return .{ .version = version };
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
            return writeResult(writer, response_id, ToolsListResult{});
        }

        return writeError(writer, response_id, -32601, "Method not found");
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

const Tool = struct {
    name: []const u8,
};

const ToolsListResult = struct {
    tools: []const Tool = &.{},
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

pub fn runSession(
    allocator: std.mem.Allocator,
    reader: *Io.Reader,
    writer: *Io.Writer,
    version: []const u8,
) !void {
    var server = Server.init(version);

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

pub fn serve(io: Io, allocator: std.mem.Allocator, version: []const u8) !void {
    const input_buffer = try allocator.alloc(u8, max_message_bytes);
    defer allocator.free(input_buffer);

    var stdin_reader = Io.File.stdin().readerStreaming(io, input_buffer);
    var output_buffer: [64 * 1024]u8 = undefined;
    var stdout_writer = Io.File.stdout().writerStreaming(io, &output_buffer);

    try runSession(
        allocator,
        &stdin_reader.interface,
        &stdout_writer.interface,
        version,
    );
    try stdout_writer.interface.flush();
}

fn exchange(server: *Server, line: []const u8) ![]u8 {
    var output: Io.Writer.Allocating = .init(std.testing.allocator);
    errdefer output.deinit();

    try server.handleLine(std.testing.allocator, line, &output.writer);
    return output.toOwnedSlice();
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
    try std.testing.expectEqualStrings(
        "{\"jsonrpc\":\"2.0\",\"id\":3,\"result\":{\"tools\":[]}}\n",
        ready,
    );
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
    try std.testing.expect(std.mem.endsWith(u8, output.written(), "{\"jsonrpc\":\"2.0\",\"id\":2,\"result\":{\"tools\":[]}}\n"));
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
