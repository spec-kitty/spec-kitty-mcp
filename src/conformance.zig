//! Transport conformance script.
//!
//! One ordered lifecycle script that every transport must reproduce exactly.
//! `StdioDriver` below drives it over `mcp.runSession`; a Streamable HTTP
//! transport is expected to drive the same script through its own driver and
//! produce the same payloads in the same order.
//!
//! Tool execution is deliberately out of scope. It depends on the Spec Kitty
//! binary and is not transport-specific, so it is covered by the smoke tests
//! instead. This script covers what a transport can actually break: framing,
//! response ordering, lifecycle gating, catalog gating, and error codes.

const std = @import("std");
const Io = std.Io;

const mcp = @import("mcp.zig");

/// Server version the script expects a driver to report from `initialize`.
pub const driver_version = "conformance";

pub const Expect = union(enum) {
    /// The transport must emit no response at all.
    silent,
    /// Byte-for-byte payload, with transport framing removed.
    exact: []const u8,
    /// Payload must start with `prefix` and contain every entry of `contains`.
    shape: struct {
        prefix: []const u8,
        contains: []const []const u8 = &.{},
    },
};

pub const Step = struct {
    name: []const u8,
    request: []const u8,
    expect: Expect,
};

pub const lifecycle_script = [_]Step{
    .{
        .name = "malformed payload reports a parse error against a null id",
        .request = "not-json",
        .expect = .{ .exact = "{\"jsonrpc\":\"2.0\",\"id\":null,\"error\":{\"code\":-32700,\"message\":\"Parse error\"}}" },
    },
    .{
        .name = "an id that is neither string nor number is an invalid request",
        .request = "{\"jsonrpc\":\"2.0\",\"id\":{},\"method\":\"ping\"}",
        .expect = .{ .exact = "{\"jsonrpc\":\"2.0\",\"id\":null,\"error\":{\"code\":-32600,\"message\":\"Invalid Request\"}}" },
    },
    .{
        .name = "requests are gated before initialize",
        .request = "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"tools/list\"}",
        .expect = .{ .exact = "{\"jsonrpc\":\"2.0\",\"id\":1,\"error\":{\"code\":-32002,\"message\":\"Server not initialized\"}}" },
    },
    .{
        .name = "ping answers before initialize",
        .request = "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"ping\"}",
        .expect = .{ .exact = "{\"jsonrpc\":\"2.0\",\"id\":2,\"result\":{}}" },
    },
    .{
        .name = "initialize negotiates the pinned protocol version",
        .request = "{\"jsonrpc\":\"2.0\",\"id\":3,\"method\":\"initialize\",\"params\":{\"protocolVersion\":\"2099-01-01\",\"capabilities\":{},\"clientInfo\":{\"name\":\"conformance\",\"version\":\"1\"}}}",
        .expect = .{ .shape = .{
            .prefix = "{\"jsonrpc\":\"2.0\",\"id\":3,\"result\":{",
            .contains = &.{
                "\"protocolVersion\":\"" ++ mcp.protocol_version ++ "\"",
                "\"version\":\"" ++ driver_version ++ "\"",
            },
        } },
    },
    .{
        .name = "a second initialize is rejected",
        .request = "{\"jsonrpc\":\"2.0\",\"id\":4,\"method\":\"initialize\",\"params\":{\"protocolVersion\":\"" ++ mcp.protocol_version ++ "\",\"capabilities\":{},\"clientInfo\":{}}}",
        .expect = .{ .exact = "{\"jsonrpc\":\"2.0\",\"id\":4,\"error\":{\"code\":-32600,\"message\":\"Already initialized\"}}" },
    },
    .{
        .name = "requests stay gated until the initialized notification",
        .request = "{\"jsonrpc\":\"2.0\",\"id\":5,\"method\":\"tools/list\"}",
        .expect = .{ .exact = "{\"jsonrpc\":\"2.0\",\"id\":5,\"error\":{\"code\":-32002,\"message\":\"Server not initialized\"}}" },
    },
    .{
        .name = "the initialized notification draws no response",
        .request = "{\"jsonrpc\":\"2.0\",\"method\":\"notifications/initialized\"}",
        .expect = .silent,
    },
    .{
        .name = "an unknown notification draws no response",
        .request = "{\"jsonrpc\":\"2.0\",\"method\":\"notifications/unknown\"}",
        .expect = .silent,
    },
    .{
        .name = "tools/list publishes the catalog gated for an unknown api version",
        .request = "{\"jsonrpc\":\"2.0\",\"id\":6,\"method\":\"tools/list\"}",
        .expect = .{ .shape = .{
            .prefix = "{\"jsonrpc\":\"2.0\",\"id\":6,\"result\":{\"tools\":[",
            .contains = &.{
                "\"name\":\"spec_kitty_contract_version\"",
                "\"name\":\"spec_kitty_mission_state\"",
                "\"name\":\"spec_kitty_list_ready\"",
                "\"name\":\"spec_kitty_start_implementation\"",
                "\"name\":\"spec_kitty_start_review\"",
                "\"name\":\"spec_kitty_transition\"",
                "\"name\":\"spec_kitty_append_history\"",
                "\"name\":\"spec_kitty_accept_mission\"",
                "\"name\":\"spec_kitty_merge_mission\"",
                "\"readOnlyHint\":false",
                "\"destructiveHint\":true",
            },
        } },
    },
    .{
        .name = "a tool call without a runtime reports an unavailable runtime",
        .request = "{\"jsonrpc\":\"2.0\",\"id\":7,\"method\":\"tools/call\",\"params\":{\"name\":\"spec_kitty_mission_state\",\"arguments\":{\"mission\":\"demo\"}}}",
        .expect = .{ .exact = "{\"jsonrpc\":\"2.0\",\"id\":7,\"error\":{\"code\":-32603,\"message\":\"Tool runtime unavailable\"}}" },
    },
    .{
        .name = "task-augmented tool calls are refused",
        .request = "{\"jsonrpc\":\"2.0\",\"id\":8,\"method\":\"tools/call\",\"params\":{\"name\":\"spec_kitty_mission_state\",\"task\":{}}}",
        .expect = .{ .exact = "{\"jsonrpc\":\"2.0\",\"id\":8,\"error\":{\"code\":-32602,\"message\":\"Task-augmented calls are not supported\"}}" },
    },
    .{
        .name = "unknown methods report method not found",
        .request = "{\"jsonrpc\":\"2.0\",\"id\":9,\"method\":\"unknown\"}",
        .expect = .{ .exact = "{\"jsonrpc\":\"2.0\",\"id\":9,\"error\":{\"code\":-32601,\"message\":\"Method not found\"}}" },
    },
    .{
        .name = "ping still answers after initialization",
        .request = "{\"jsonrpc\":\"2.0\",\"id\":10,\"method\":\"ping\"}",
        .expect = .{ .exact = "{\"jsonrpc\":\"2.0\",\"id\":10,\"result\":{}}" },
    },
};

/// Ordered payloads a transport emitted for a script, framing removed.
pub const Transcript = struct {
    allocator: std.mem.Allocator,
    buffer: []u8,
    responses: [][]const u8,

    pub fn deinit(transcript: *Transcript) void {
        transcript.allocator.free(transcript.responses);
        transcript.allocator.free(transcript.buffer);
        transcript.* = undefined;
    }
};

/// Drive `script` through `driver` and assert every step.
///
/// `driver` must expose `run(allocator, requests) !Transcript`, returning one
/// entry per response the transport emitted, in order, with framing removed.
/// Silent steps must contribute no entry, which is how a transport that
/// answers a notification gets caught.
pub fn verify(
    allocator: std.mem.Allocator,
    script: []const Step,
    driver: anytype,
) !void {
    const requests = try allocator.alloc([]const u8, script.len);
    defer allocator.free(requests);
    for (script, 0..) |step, index| requests[index] = step.request;

    var transcript = try driver.run(allocator, requests);
    defer transcript.deinit();

    var next: usize = 0;
    for (script) |step| {
        switch (step.expect) {
            .silent => continue,
            .exact => |expected| {
                const actual = try take(step, transcript.responses, &next);
                std.testing.expectEqualStrings(expected, actual) catch |err| {
                    std.debug.print("conformance step failed: {s}\n", .{step.name});
                    return err;
                };
            },
            .shape => |expected| {
                const actual = try take(step, transcript.responses, &next);
                if (!std.mem.startsWith(u8, actual, expected.prefix)) {
                    std.debug.print(
                        "conformance step failed: {s}\nexpected prefix: {s}\nactual: {s}\n",
                        .{ step.name, expected.prefix, actual },
                    );
                    return error.TestUnexpectedResult;
                }
                for (expected.contains) |needle| {
                    if (std.mem.indexOf(u8, actual, needle) == null) {
                        std.debug.print(
                            "conformance step failed: {s}\nmissing: {s}\nactual: {s}\n",
                            .{ step.name, needle, actual },
                        );
                        return error.TestUnexpectedResult;
                    }
                }
            },
        }
    }

    if (next != transcript.responses.len) {
        std.debug.print(
            "transport emitted {d} responses for {d} expected\n",
            .{ transcript.responses.len, next },
        );
        return error.TestUnexpectedResult;
    }
}

fn take(step: Step, responses: []const []const u8, next: *usize) ![]const u8 {
    if (next.* >= responses.len) {
        std.debug.print("transport emitted no response for step: {s}\n", .{step.name});
        return error.TestUnexpectedResult;
    }
    defer next.* += 1;
    return responses[next.*];
}

/// Drives a script over the newline-framed stdio transport as one stream, so
/// the split back into payloads exercises the real framing.
pub const StdioDriver = struct {
    pub fn run(
        _: StdioDriver,
        allocator: std.mem.Allocator,
        requests: []const []const u8,
    ) !Transcript {
        var input: Io.Writer.Allocating = .init(allocator);
        defer input.deinit();
        for (requests) |request| {
            try input.writer.writeAll(request);
            try input.writer.writeByte('\n');
        }

        var reader = Io.Reader.fixed(input.written());
        var output: Io.Writer.Allocating = .init(allocator);
        errdefer output.deinit();
        try mcp.runSession(allocator, &reader, &output.writer, driver_version);

        const buffer = try output.toOwnedSlice();
        errdefer allocator.free(buffer);
        return .{
            .allocator = allocator,
            .buffer = buffer,
            .responses = try splitFrames(allocator, buffer),
        };
    }

    fn splitFrames(allocator: std.mem.Allocator, buffer: []const u8) ![][]const u8 {
        var frames: std.ArrayList([]const u8) = .empty;
        errdefer frames.deinit(allocator);

        var rest = buffer;
        while (std.mem.indexOfScalar(u8, rest, '\n')) |end| {
            try frames.append(allocator, rest[0..end]);
            rest = rest[end + 1 ..];
        }
        if (rest.len != 0) return error.UnterminatedFrame;
        return frames.toOwnedSlice(allocator);
    }
};

test "the stdio transport satisfies the conformance script" {
    try verify(std.testing.allocator, &lifecycle_script, StdioDriver{});
}
