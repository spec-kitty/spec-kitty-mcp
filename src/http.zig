//! Localhost Streamable HTTP transport, first phase.
//!
//! POST only, read-only tools, bearer credential mandatory before the socket
//! exists. `serveConnection` is the whole protocol and takes a reader and a
//! writer, so it is exercised over memory in tests and over a socket in
//! `listen`. Resumable GET or SSE streams and `Mcp-Session-Id` belong to a
//! later phase; a GET is answered 405 rather than half-implemented.

const std = @import("std");
const Io = std.Io;

const auth = @import("auth.zig");
const mcp = @import("mcp.zig");
const spec_kitty = @import("spec_kitty.zig");

/// The only path that carries JSON-RPC.
pub const default_path = "/mcp";

pub const Options = struct {
    token: auth.Token,
    path: []const u8 = default_path,
};

/// Reasons a request never reaches the JSON-RPC handler.
///
/// The order of the checks is deliberate: the credential is settled before the
/// request shape, so an unauthenticated caller learns nothing about which paths,
/// methods or protocol versions this server would have accepted.
pub const Rejection = enum {
    unauthorized,
    method_not_allowed,
    not_found,
    forbidden_origin,
    unsupported_protocol_version,
    unsupported_media_type,
    length_required,
    payload_too_large,

    pub fn status(rejection: Rejection) std.http.Status {
        return switch (rejection) {
            .unauthorized => .unauthorized,
            .method_not_allowed => .method_not_allowed,
            .not_found => .not_found,
            .forbidden_origin => .forbidden,
            .unsupported_protocol_version => .bad_request,
            .unsupported_media_type => .unsupported_media_type,
            .length_required => .length_required,
            .payload_too_large => .payload_too_large,
        };
    }

    pub fn detail(rejection: Rejection) []const u8 {
        return switch (rejection) {
            .unauthorized => "a bearer credential is required",
            .method_not_allowed => "only POST is supported by this transport",
            .not_found => "no MCP endpoint at this path",
            .forbidden_origin => "origin is not a loopback origin",
            .unsupported_protocol_version => "unsupported MCP-Protocol-Version",
            .unsupported_media_type => "content-type must be application/json",
            .length_required => "a content-length is required",
            .payload_too_large => "message exceeds the maximum size",
        };
    }
};

/// Serve JSON-RPC over one accepted connection until the peer stops asking.
pub fn serveConnection(
    allocator: std.mem.Allocator,
    in: *Io.Reader,
    out: *Io.Writer,
    server: *mcp.Server,
    options: Options,
) !void {
    var http_server = std.http.Server.init(in, out);

    while (true) {
        var request = http_server.receiveHead() catch |err| switch (err) {
            error.HttpConnectionClosing => return,
            else => return err,
        };
        switch (try handleRequest(allocator, &request, server, options)) {
            .keep_alive => {},
            .close => return,
        }
    }
}

const Outcome = enum { keep_alive, close };

fn handleRequest(
    allocator: std.mem.Allocator,
    request: *std.http.Server.Request,
    server: *mcp.Server,
    options: Options,
) !Outcome {
    // A rejected request ends the connection. Its body was never read, so the
    // stream position is no longer trustworthy, and an unauthenticated peer has
    // no claim on a kept-alive socket either way.
    if (screen(request, options)) |rejection| {
        try reject(request, rejection);
        return .close;
    }

    const length = request.head.content_length.?;
    var body_buffer: [4096]u8 = undefined;
    const body_reader = try request.readerExpectContinue(&body_buffer);
    const body = try body_reader.readAlloc(allocator, @intCast(length));
    defer allocator.free(body);

    var response: Io.Writer.Allocating = .init(allocator);
    defer response.deinit();
    try server.handleLine(allocator, body, &response.writer);

    const framed = response.written();
    if (framed.len == 0) {
        // A notification draws no JSON-RPC response, so there is no body to
        // carry and 202 is the honest answer.
        try request.respond("", .{
            .status = .accepted,
            .extra_headers = &.{protocolHeader()},
        });
        return .keep_alive;
    }

    try request.respond(std.mem.trimEnd(u8, framed, "\n"), .{
        .status = .ok,
        .extra_headers = &.{
            .{ .name = "content-type", .value = "application/json" },
            protocolHeader(),
        },
    });
    return .keep_alive;
}

/// Decide whether a request may reach the JSON-RPC handler.
fn screen(request: *const std.http.Server.Request, options: Options) ?Rejection {
    var authorized = false;
    var origin: ?[]const u8 = null;
    var protocol_version: ?[]const u8 = null;
    var content_type: ?[]const u8 = null;

    var headers = request.iterateHeaders();
    while (headers.next()) |header| {
        if (std.ascii.eqlIgnoreCase(header.name, "authorization")) {
            const presented = auth.bearerSecret(header.value) orelse continue;
            // Every candidate is compared, so a caller cannot learn anything
            // from how early a wrong credential appears.
            if (options.token.matches(presented)) authorized = true;
        } else if (std.ascii.eqlIgnoreCase(header.name, "origin")) {
            origin = header.value;
        } else if (std.ascii.eqlIgnoreCase(header.name, "mcp-protocol-version")) {
            protocol_version = header.value;
        } else if (std.ascii.eqlIgnoreCase(header.name, "content-type")) {
            content_type = header.value;
        }
    }

    if (!authorized) return .unauthorized;
    if (request.head.method != .POST) return .method_not_allowed;
    if (!std.mem.eql(u8, request.head.target, options.path)) return .not_found;

    if (origin) |value| {
        if (!isLoopbackOrigin(value)) return .forbidden_origin;
    }
    if (protocol_version) |value| {
        if (!std.mem.eql(u8, value, mcp.protocol_version)) return .unsupported_protocol_version;
    }
    if (content_type) |value| {
        if (!isJson(value)) return .unsupported_media_type;
    } else return .unsupported_media_type;

    // The size cap is settled from the declared length, so an oversized body is
    // refused before a byte of it is buffered.
    const length = request.head.content_length orelse return .length_required;
    if (length > mcp.max_message_bytes) return .payload_too_large;

    return null;
}

fn reject(request: *std.http.Server.Request, rejection: Rejection) !void {
    const allow_header: []const std.http.Header = if (rejection == .method_not_allowed)
        &.{.{ .name = "allow", .value = "POST" }}
    else
        &.{};

    const challenge: []const std.http.Header = if (rejection == .unauthorized)
        &.{.{ .name = "www-authenticate", .value = "Bearer" }}
    else
        &.{};

    var headers: [3]std.http.Header = undefined;
    var len: usize = 0;
    headers[len] = protocolHeader();
    len += 1;
    for (allow_header) |header| {
        headers[len] = header;
        len += 1;
    }
    for (challenge) |header| {
        headers[len] = header;
        len += 1;
    }

    return request.respond(rejection.detail(), .{
        .status = rejection.status(),
        .extra_headers = headers[0..len],
        .keep_alive = false,
    });
}

fn protocolHeader() std.http.Header {
    return .{ .name = "mcp-protocol-version", .value = mcp.protocol_version };
}

fn isJson(content_type: []const u8) bool {
    const media = std.mem.trim(
        u8,
        content_type[0 .. std.mem.indexOfScalar(u8, content_type, ';') orelse content_type.len],
        " \t",
    );
    return std.ascii.eqlIgnoreCase(media, "application/json");
}

/// Whether an `Origin` header names a loopback host.
///
/// A browser page on any other origin must not be able to drive this server,
/// which is what stops DNS rebinding from reaching a localhost listener.
pub fn isLoopbackOrigin(origin: []const u8) bool {
    const without_scheme = if (std.mem.startsWith(u8, origin, "http://"))
        origin["http://".len..]
    else if (std.mem.startsWith(u8, origin, "https://"))
        origin["https://".len..]
    else
        return false;

    const host = if (std.mem.startsWith(u8, without_scheme, "["))
        // Bracketed IPv6 literal, so the port colon is the one after the bracket.
        without_scheme[0 .. (std.mem.indexOfScalar(u8, without_scheme, ']') orelse return false) + 1]
    else
        without_scheme[0 .. std.mem.indexOfScalar(u8, without_scheme, ':') orelse without_scheme.len];

    return std.mem.eql(u8, host, "localhost") or
        std.mem.eql(u8, host, "127.0.0.1") or
        std.mem.eql(u8, host, "[::1]");
}

/// Whether an address is safe to bind without an explicit insecure opt-in.
pub fn isLoopbackAddress(address: Io.net.IpAddress) bool {
    return switch (address) {
        // Only 127.0.0.1 and ::1 exactly. The wider 127/8 range is not treated
        // as safe, so a bind there still needs the insecure opt-in.
        .ip4 => |ip4| std.mem.eql(u8, &ip4.bytes, &.{ 127, 0, 0, 1 }),
        .ip6 => |ip6| std.mem.eql(u8, &ip6.bytes, &([_]u8{0} ** 15 ++ [_]u8{1})),
    };
}

/// What a fresh session needs to reach Spec Kitty.
///
/// A connection is a session in this phase. There is no `Mcp-Session-Id`, so
/// each connection runs its own `initialize` handshake against its own server
/// state and nothing leaks between clients.
pub const Session = struct {
    version: []const u8,
    client: spec_kitty.Client,
    provider_version: []const u8,
    api_version: []const u8,
};

/// Bind and serve until cancelled. One connection at a time is deliberate: the
/// adapter fronts a single project and a single Spec Kitty process.
pub fn listen(
    io: Io,
    allocator: std.mem.Allocator,
    address: Io.net.IpAddress,
    session: Session,
    options: Options,
) !void {
    var net_server = try address.listen(io, .{ .reuse_address = true });
    defer net_server.deinit(io);

    std.log.info("serving read-only MCP over HTTP on {f}{s}", .{ address, options.path });

    const in_buffer = try allocator.alloc(u8, mcp.max_message_bytes);
    defer allocator.free(in_buffer);
    const out_buffer = try allocator.alloc(u8, 64 * 1024);
    defer allocator.free(out_buffer);

    while (true) {
        const stream = net_server.accept(io) catch |err| switch (err) {
            error.ConnectionAborted, error.WouldBlock => continue,
            else => return err,
        };
        defer stream.close(io);

        var reader = stream.reader(io, in_buffer);
        var writer = stream.writer(io, out_buffer);

        var server = mcp.Server.initWithTools(
            session.version,
            session.client,
            io,
            session.provider_version,
            session.api_version,
        );
        server.access = .read_only;

        // One bad peer must not take the listener down with it.
        serveConnection(
            allocator,
            &reader.interface,
            &writer.interface,
            &server,
            options,
        ) catch |err| {
            std.log.warn("connection ended: {s}", .{@errorName(err)});
            continue;
        };
    }
}

const conformance = @import("conformance.zig");

const test_secret = "a-sufficiently-long-secret";

fn testOptions() Options {
    return .{ .token = auth.Token.fromSecret(test_secret) };
}

const Response = struct {
    status: u16,
    headers: []const u8,
    body: []const u8,

    fn header(response: Response, name: []const u8) ?[]const u8 {
        var lines = std.mem.splitSequence(u8, response.headers, "\r\n");
        _ = lines.next();
        while (lines.next()) |line| {
            const colon = std.mem.indexOfScalar(u8, line, ':') orelse continue;
            if (!std.ascii.eqlIgnoreCase(std.mem.trim(u8, line[0..colon], " \t"), name)) continue;
            return std.mem.trim(u8, line[colon + 1 ..], " \t");
        }
        return null;
    }
};

/// Split a raw response stream into responses. Every response this transport
/// writes is content-length delimited, so no chunk decoding is needed.
fn parseResponses(allocator: std.mem.Allocator, raw: []const u8) ![]Response {
    var responses: std.ArrayList(Response) = .empty;
    errdefer responses.deinit(allocator);

    var rest = raw;
    while (rest.len != 0) {
        const split = std.mem.indexOf(u8, rest, "\r\n\r\n") orelse return error.TruncatedResponse;
        const headers = rest[0..split];
        rest = rest[split + 4 ..];

        const status_end = std.mem.indexOfScalarPos(
            u8,
            headers,
            std.mem.indexOfScalar(u8, headers, ' ').? + 1,
            ' ',
        ) orelse headers.len;
        const status_start = std.mem.indexOfScalar(u8, headers, ' ').? + 1;
        const status = try std.fmt.parseInt(u16, headers[status_start..status_end], 10);

        var length: usize = 0;
        var lines = std.mem.splitSequence(u8, headers, "\r\n");
        _ = lines.next();
        while (lines.next()) |line| {
            const colon = std.mem.indexOfScalar(u8, line, ':') orelse continue;
            if (!std.ascii.eqlIgnoreCase(std.mem.trim(u8, line[0..colon], " \t"), "content-length")) continue;
            length = try std.fmt.parseInt(usize, std.mem.trim(u8, line[colon + 1 ..], " \t"), 10);
        }

        if (rest.len < length) return error.TruncatedResponse;
        try responses.append(allocator, .{
            .status = status,
            .headers = headers,
            .body = rest[0..length],
        });
        rest = rest[length..];
    }

    return responses.toOwnedSlice(allocator);
}

const RequestSpec = struct {
    method: []const u8 = "POST",
    target: []const u8 = default_path,
    authorization: ?[]const u8 = "Bearer " ++ test_secret,
    origin: ?[]const u8 = null,
    protocol_version: ?[]const u8 = null,
    content_type: ?[]const u8 = "application/json",
    /// Declared length, when it must differ from the real body length.
    declared_length: ?u64 = null,
    body: []const u8 = "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"ping\"}",
};

fn writeRequest(writer: *Io.Writer, spec: RequestSpec) !void {
    try writer.print("{s} {s} HTTP/1.1\r\nhost: 127.0.0.1\r\n", .{ spec.method, spec.target });
    if (spec.authorization) |value| try writer.print("authorization: {s}\r\n", .{value});
    if (spec.origin) |value| try writer.print("origin: {s}\r\n", .{value});
    if (spec.protocol_version) |value| try writer.print("mcp-protocol-version: {s}\r\n", .{value});
    if (spec.content_type) |value| try writer.print("content-type: {s}\r\n", .{value});
    try writer.print("content-length: {d}\r\n\r\n", .{spec.declared_length orelse spec.body.len});
    try writer.writeAll(spec.body);
}

const Exchange = struct {
    allocator: std.mem.Allocator,
    buffer: []u8,
    responses: []Response,

    fn deinit(exchange: *Exchange) void {
        exchange.allocator.free(exchange.responses);
        exchange.allocator.free(exchange.buffer);
        exchange.* = undefined;
    }
};

/// Drive one connection and return the parsed responses.
fn roundTrip(allocator: std.mem.Allocator, specs: []const RequestSpec) !Exchange {
    var request_bytes: Io.Writer.Allocating = .init(allocator);
    defer request_bytes.deinit();
    for (specs) |spec| try writeRequest(&request_bytes.writer, spec);

    var in = Io.Reader.fixed(request_bytes.written());
    var out: Io.Writer.Allocating = .init(allocator);
    errdefer out.deinit();

    var server = mcp.Server.init("test");
    server.access = .read_only;
    server.state = .ready;

    try serveConnection(allocator, &in, &out.writer, &server, testOptions());

    const buffer = try out.toOwnedSlice();
    errdefer allocator.free(buffer);
    return .{
        .allocator = allocator,
        .buffer = buffer,
        .responses = try parseResponses(allocator, buffer),
    };
}

/// Assert one request drew one response with `status`, and hand it back for
/// header checks. The exchange is released, so callers must not retain slices.
fn expectStatus(spec: RequestSpec, status: u16) !void {
    var exchange = try roundTrip(std.testing.allocator, &.{spec});
    defer exchange.deinit();
    try std.testing.expectEqual(@as(usize, 1), exchange.responses.len);
    try std.testing.expectEqual(status, exchange.responses[0].status);
}

fn expectHeader(spec: RequestSpec, status: u16, name: []const u8, value: []const u8) !void {
    var exchange = try roundTrip(std.testing.allocator, &.{spec});
    defer exchange.deinit();
    try std.testing.expectEqual(@as(usize, 1), exchange.responses.len);
    try std.testing.expectEqual(status, exchange.responses[0].status);
    try std.testing.expectEqualStrings(value, exchange.responses[0].header(name).?);
}

test "an authenticated ping is answered as JSON" {
    var exchange = try roundTrip(std.testing.allocator, &.{.{}});
    defer exchange.deinit();

    try std.testing.expectEqual(@as(usize, 1), exchange.responses.len);
    try std.testing.expectEqual(@as(u16, 200), exchange.responses[0].status);
    try std.testing.expectEqualStrings(
        "{\"jsonrpc\":\"2.0\",\"id\":1,\"result\":{}}",
        exchange.responses[0].body,
    );
    try std.testing.expectEqualStrings(
        "application/json",
        exchange.responses[0].header("content-type").?,
    );
    try std.testing.expectEqualStrings(
        mcp.protocol_version,
        exchange.responses[0].header("mcp-protocol-version").?,
    );
}

test "a missing or wrong credential is refused with a challenge" {
    try expectHeader(.{ .authorization = null }, 401, "www-authenticate", "Bearer");
    try expectStatus(.{ .authorization = "Bearer wrong-but-long-enough" }, 401);
    try expectStatus(.{ .authorization = "Basic " ++ test_secret }, 401);
    // A prefix of the real secret must not pass.
    try expectStatus(.{ .authorization = "Bearer " ++ test_secret[0 .. test_secret.len - 1] }, 401);
    // Neither must the secret with anything appended.
    try expectStatus(.{ .authorization = "Bearer " ++ test_secret ++ "x" }, 401);
}

test "the credential is settled before the request shape" {
    // An unauthenticated request that is also malformed still answers 401, so a
    // caller cannot probe paths, methods or origins without a credential.
    try expectStatus(.{ .authorization = null, .method = "GET" }, 401);
    try expectStatus(.{ .authorization = null, .target = "/elsewhere" }, 401);
    try expectStatus(.{ .authorization = null, .origin = "http://evil.example" }, 401);
    try expectStatus(.{ .authorization = null, .content_type = "text/plain" }, 401);
}

test "this phase serves POST only" {
    try expectHeader(.{ .method = "GET" }, 405, "allow", "POST");
    try expectStatus(.{ .method = "PUT" }, 405);
    try expectStatus(.{ .method = "DELETE" }, 405);
}

test "only the MCP path answers" {
    try expectStatus(.{ .target = "/" }, 404);
    try expectStatus(.{ .target = "/mcp/extra" }, 404);
    try expectStatus(.{ .target = default_path }, 200);
}

test "a non-loopback origin is forbidden" {
    try expectStatus(.{ .origin = "http://evil.example" }, 403);
    try expectStatus(.{ .origin = "https://spec-kitty.ai" }, 403);
    try expectStatus(.{ .origin = "http://127.0.0.1.evil.example" }, 403);
    try expectStatus(.{ .origin = "http://localhost:1234" }, 200);
    try expectStatus(.{ .origin = "http://127.0.0.1:1234" }, 200);
    try expectStatus(.{ .origin = "http://[::1]:1234" }, 200);
}

test "a mismatched protocol version is a bad request" {
    try expectStatus(.{ .protocol_version = "2026-07-28" }, 400);
    try expectStatus(.{ .protocol_version = "2025-03-26" }, 400);
    try expectStatus(.{ .protocol_version = mcp.protocol_version }, 200);
}

test "the body must be declared as JSON" {
    try expectStatus(.{ .content_type = null }, 415);
    try expectStatus(.{ .content_type = "text/plain" }, 415);
    try expectStatus(.{ .content_type = "application/json; charset=utf-8" }, 200);
}

test "an oversized body is refused from its declared length" {
    // The body is never sent, so the refusal cannot have come from reading it.
    try expectStatus(.{ .declared_length = mcp.max_message_bytes + 1, .body = "" }, 413);
}

test "a notification is accepted without a body" {
    var exchange = try roundTrip(std.testing.allocator, &.{.{
        .body = "{\"jsonrpc\":\"2.0\",\"method\":\"notifications/initialized\"}",
    }});
    defer exchange.deinit();

    try std.testing.expectEqual(@as(usize, 1), exchange.responses.len);
    try std.testing.expectEqual(@as(u16, 202), exchange.responses[0].status);
    try std.testing.expectEqualStrings("", exchange.responses[0].body);
}

test "mutating tools are absent over HTTP" {
    var exchange = try roundTrip(std.testing.allocator, &.{
        .{ .body = "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"tools/list\"}" },
        .{ .body = "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"tools/call\",\"params\":{\"name\":\"spec_kitty_merge_mission\",\"arguments\":{\"mission\":\"demo\"}}}" },
    });
    defer exchange.deinit();

    try std.testing.expectEqual(@as(usize, 2), exchange.responses.len);
    const listed = exchange.responses[0].body;
    try std.testing.expect(std.mem.indexOf(u8, listed, "spec_kitty_mission_state") != null);
    try std.testing.expect(std.mem.indexOf(u8, listed, "spec_kitty_merge_mission") == null);
    try std.testing.expect(std.mem.indexOf(u8, listed, "spec_kitty_transition") == null);
    try std.testing.expectEqualStrings(
        "{\"jsonrpc\":\"2.0\",\"id\":2,\"error\":{\"code\":-32602,\"message\":\"Unknown tool\"}}",
        exchange.responses[1].body,
    );
}

test "a bind address is loopback or it is not" {
    try std.testing.expect(isLoopbackAddress(try .parse("127.0.0.1", 0)));
    try std.testing.expect(isLoopbackAddress(try .parse("::1", 0)));
    try std.testing.expect(!isLoopbackAddress(try .parse("0.0.0.0", 0)));
    try std.testing.expect(!isLoopbackAddress(try .parse("192.168.1.10", 0)));
    try std.testing.expect(!isLoopbackAddress(try .parse("127.0.0.2", 0)));
    try std.testing.expect(!isLoopbackAddress(try .parse("::", 0)));
}

/// Runs the shared conformance script over HTTP, one POST per step on a single
/// keep-alive connection.
const ConformanceDriver = struct {
    pub fn run(
        _: ConformanceDriver,
        allocator: std.mem.Allocator,
        requests: []const []const u8,
    ) !conformance.Transcript {
        var request_bytes: Io.Writer.Allocating = .init(allocator);
        defer request_bytes.deinit();
        for (requests) |request| {
            try writeRequest(&request_bytes.writer, .{ .body = request });
        }

        var in = Io.Reader.fixed(request_bytes.written());
        var out: Io.Writer.Allocating = .init(allocator);
        errdefer out.deinit();

        var server = mcp.Server.init(conformance.driver_version);
        try serveConnection(allocator, &in, &out.writer, &server, testOptions());

        const buffer = try out.toOwnedSlice();
        errdefer allocator.free(buffer);

        const responses = try parseResponses(allocator, buffer);
        defer allocator.free(responses);

        var payloads: std.ArrayList([]const u8) = .empty;
        errdefer payloads.deinit(allocator);
        for (responses) |response| {
            // 202 carries no JSON-RPC response, which is how a notification
            // stays silent on a transport that must answer every request.
            if (response.status == 202) continue;
            try payloads.append(allocator, response.body);
        }

        return .{
            .allocator = allocator,
            .buffer = buffer,
            .responses = try payloads.toOwnedSlice(allocator),
        };
    }
};

test "the HTTP transport satisfies the same conformance script as stdio" {
    try conformance.verify(
        std.testing.allocator,
        &conformance.lifecycle_script,
        ConformanceDriver{},
    );
}
