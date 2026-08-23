const std = @import("std");

pub const help_text =
    \\Usage: spec-kitty-mcp --project-root <path> [options]
    \\
    \\Options:
    \\  --project-root <path>    Initialized Spec Kitty project to bind
    \\  --spec-kitty-bin <path>  Spec Kitty executable (default: spec-kitty)
    \\  --http <host:port>       Serve HTTP instead of stdio; read-only tools
    \\  --token-file <path>      File holding the bearer credential (mode 0600)
    \\  --insecure-bind          Permit a non-loopback --http host
    \\  -h, --help               Show this help
    \\  -V, --version            Show the version
    \\
    \\The HTTP transport requires a bearer credential, from --token-file or the
    \\SPEC_KITTY_MCP_TOKEN environment variable. It is never taken from argv,
    \\which other local processes can read.
    \\
;

pub const Options = struct {
    project_root: []const u8,
    spec_kitty_bin: []const u8 = "spec-kitty",
    /// Absent means stdio. One process serves one transport.
    http: ?Http = null,
};

pub const Http = struct {
    host: []const u8,
    port: u16,
    token_file: ?[]const u8 = null,
    insecure_bind: bool = false,
};

pub const Command = union(enum) {
    run: Options,
    help,
    version,
};

pub const ParseError = error{
    DuplicateProjectRoot,
    DuplicateSpecKittyBin,
    DuplicateHttp,
    DuplicateTokenFile,
    EmptyOptionValue,
    InvalidHttpAddress,
    MissingOptionValue,
    MissingProjectRoot,
    TokenFileWithoutHttp,
    InsecureBindWithoutHttp,
    UnexpectedArgument,
    UnknownOption,
};

pub fn parse(args: []const []const u8) ParseError!Command {
    if (args.len == 0) return error.MissingProjectRoot;
    if (args.len == 2) {
        if (isHelp(args[1])) return .help;
        if (isVersion(args[1])) return .version;
    }

    var project_root: ?[]const u8 = null;
    var spec_kitty_bin: ?[]const u8 = null;
    var http: ?Http = null;
    var token_file: ?[]const u8 = null;
    var insecure_bind = false;
    var index: usize = 1;

    while (index < args.len) : (index += 1) {
        const arg = args[index];

        if (std.mem.eql(u8, arg, "--project-root")) {
            if (project_root != null) return error.DuplicateProjectRoot;
            project_root = try optionValue(args, &index);
        } else if (std.mem.eql(u8, arg, "--spec-kitty-bin")) {
            if (spec_kitty_bin != null) return error.DuplicateSpecKittyBin;
            spec_kitty_bin = try optionValue(args, &index);
        } else if (std.mem.eql(u8, arg, "--http")) {
            if (http != null) return error.DuplicateHttp;
            http = try parseBind(try optionValue(args, &index));
        } else if (std.mem.eql(u8, arg, "--token-file")) {
            if (token_file != null) return error.DuplicateTokenFile;
            token_file = try optionValue(args, &index);
        } else if (std.mem.eql(u8, arg, "--insecure-bind")) {
            insecure_bind = true;
        } else if (isHelp(arg) or isVersion(arg)) {
            return error.UnexpectedArgument;
        } else if (std.mem.startsWith(u8, arg, "-")) {
            return error.UnknownOption;
        } else {
            return error.UnexpectedArgument;
        }
    }

    if (http) |*bind| {
        bind.token_file = token_file;
        bind.insecure_bind = insecure_bind;
    } else {
        // Credentials and bind widening only mean something for a listener, so
        // supplying them without --http is a mistake worth surfacing.
        if (token_file != null) return error.TokenFileWithoutHttp;
        if (insecure_bind) return error.InsecureBindWithoutHttp;
    }

    return .{ .run = .{
        .project_root = project_root orelse return error.MissingProjectRoot,
        .spec_kitty_bin = spec_kitty_bin orelse "spec-kitty",
        .http = http,
    } };
}

/// Split `host:port`, honoring a bracketed IPv6 literal.
fn parseBind(value: []const u8) ParseError!Http {
    const separator = std.mem.lastIndexOfScalar(u8, value, ':') orelse
        return error.InvalidHttpAddress;
    if (std.mem.indexOfScalar(u8, value, ']')) |bracket| {
        if (separator < bracket) return error.InvalidHttpAddress;
    }

    const host = value[0..separator];
    const port_text = value[separator + 1 ..];
    if (host.len == 0 or port_text.len == 0) return error.InvalidHttpAddress;

    const unbracketed = if (host[0] == '[' and host[host.len - 1] == ']')
        host[1 .. host.len - 1]
    else
        host;
    if (unbracketed.len == 0) return error.InvalidHttpAddress;

    return .{
        .host = unbracketed,
        .port = std.fmt.parseInt(u16, port_text, 10) catch return error.InvalidHttpAddress,
    };
}

pub fn errorMessage(err: ParseError) []const u8 {
    return switch (err) {
        error.DuplicateProjectRoot => "--project-root may be supplied only once",
        error.DuplicateSpecKittyBin => "--spec-kitty-bin may be supplied only once",
        error.DuplicateHttp => "--http may be supplied only once",
        error.DuplicateTokenFile => "--token-file may be supplied only once",
        error.InvalidHttpAddress => "--http expects host:port",
        error.TokenFileWithoutHttp => "--token-file requires --http",
        error.InsecureBindWithoutHttp => "--insecure-bind requires --http",
        error.EmptyOptionValue => "option values must not be empty",
        error.MissingOptionValue => "option requires a value",
        error.MissingProjectRoot => "--project-root is required",
        error.UnexpectedArgument => "unexpected argument",
        error.UnknownOption => "unknown option",
    };
}

fn optionValue(args: []const []const u8, index: *usize) ParseError![]const u8 {
    index.* += 1;
    if (index.* >= args.len) return error.MissingOptionValue;

    const value = args[index.*];
    if (value.len == 0) return error.EmptyOptionValue;
    if (std.mem.startsWith(u8, value, "--")) return error.MissingOptionValue;
    return value;
}

fn isHelp(arg: []const u8) bool {
    return std.mem.eql(u8, arg, "-h") or std.mem.eql(u8, arg, "--help");
}

fn isVersion(arg: []const u8) bool {
    return std.mem.eql(u8, arg, "-V") or std.mem.eql(u8, arg, "--version");
}

test "parse requires a project root" {
    try std.testing.expectError(error.MissingProjectRoot, parse(&.{"spec-kitty-mcp"}));
}

test "parse uses the default Spec Kitty executable" {
    const command = try parse(&.{ "spec-kitty-mcp", "--project-root", "/tmp/project" });
    const options = switch (command) {
        .run => |value| value,
        else => return error.TestUnexpectedResult,
    };

    try std.testing.expectEqualStrings("/tmp/project", options.project_root);
    try std.testing.expectEqualStrings("spec-kitty", options.spec_kitty_bin);
}

test "parse accepts a custom Spec Kitty executable" {
    const command = try parse(&.{
        "spec-kitty-mcp",
        "--spec-kitty-bin",
        "/opt/spec-kitty",
        "--project-root",
        "/tmp/project",
    });
    const options = switch (command) {
        .run => |value| value,
        else => return error.TestUnexpectedResult,
    };

    try std.testing.expectEqualStrings("/tmp/project", options.project_root);
    try std.testing.expectEqualStrings("/opt/spec-kitty", options.spec_kitty_bin);
}

test "parse recognizes help and version commands" {
    switch (try parse(&.{ "spec-kitty-mcp", "--help" })) {
        .help => {},
        else => return error.TestUnexpectedResult,
    }
    switch (try parse(&.{ "spec-kitty-mcp", "-V" })) {
        .version => {},
        else => return error.TestUnexpectedResult,
    }
}

test "parse rejects duplicate and incomplete options" {
    try std.testing.expectError(error.DuplicateProjectRoot, parse(&.{
        "spec-kitty-mcp",
        "--project-root",
        "one",
        "--project-root",
        "two",
    }));
    try std.testing.expectError(error.MissingOptionValue, parse(&.{
        "spec-kitty-mcp",
        "--project-root",
    }));
    try std.testing.expectError(error.MissingOptionValue, parse(&.{
        "spec-kitty-mcp",
        "--project-root",
        "--version",
    }));
}

test "parse rejects unknown options and positional arguments" {
    try std.testing.expectError(error.UnknownOption, parse(&.{
        "spec-kitty-mcp",
        "--wat",
    }));
    try std.testing.expectError(error.UnexpectedArgument, parse(&.{
        "spec-kitty-mcp",
        "project",
    }));
}

test "http bind parsing accepts host:port and rejects the rest" {
    const ipv4 = try parseBind("127.0.0.1:8765");
    try std.testing.expectEqualStrings("127.0.0.1", ipv4.host);
    try std.testing.expectEqual(@as(u16, 8765), ipv4.port);

    const ipv6 = try parseBind("[::1]:8765");
    try std.testing.expectEqualStrings("::1", ipv6.host);
    try std.testing.expectEqual(@as(u16, 8765), ipv6.port);

    try std.testing.expectError(error.InvalidHttpAddress, parseBind("127.0.0.1"));
    try std.testing.expectError(error.InvalidHttpAddress, parseBind(":8765"));
    try std.testing.expectError(error.InvalidHttpAddress, parseBind("127.0.0.1:"));
    try std.testing.expectError(error.InvalidHttpAddress, parseBind("127.0.0.1:99999"));
    try std.testing.expectError(error.InvalidHttpAddress, parseBind("[::1]"));
    try std.testing.expectError(error.InvalidHttpAddress, parseBind("[]:8765"));
}

test "stdio remains the default transport" {
    const command = try parse(&.{ "spec-kitty-mcp", "--project-root", "/tmp/project" });
    try std.testing.expect(command.run.http == null);
}

test "http options carry the credential and the bind widening" {
    const command = try parse(&.{
        "spec-kitty-mcp",
        "--project-root",
        "/tmp/project",
        "--http",
        "127.0.0.1:8765",
        "--token-file",
        "/run/secrets/token",
        "--insecure-bind",
    });

    const http = command.run.http.?;
    try std.testing.expectEqualStrings("127.0.0.1", http.host);
    try std.testing.expectEqual(@as(u16, 8765), http.port);
    try std.testing.expectEqualStrings("/run/secrets/token", http.token_file.?);
    try std.testing.expect(http.insecure_bind);
}

test "credential and bind options are meaningless without a listener" {
    try std.testing.expectError(error.TokenFileWithoutHttp, parse(&.{
        "spec-kitty-mcp",
        "--project-root",
        "/tmp/project",
        "--token-file",
        "/run/secrets/token",
    }));
    try std.testing.expectError(error.InsecureBindWithoutHttp, parse(&.{
        "spec-kitty-mcp",
        "--project-root",
        "/tmp/project",
        "--insecure-bind",
    }));
}

test "http options reject duplicates" {
    try std.testing.expectError(error.DuplicateHttp, parse(&.{
        "spec-kitty-mcp",
        "--project-root",
        "/tmp/project",
        "--http",
        "127.0.0.1:1",
        "--http",
        "127.0.0.1:2",
    }));
    try std.testing.expectError(error.DuplicateTokenFile, parse(&.{
        "spec-kitty-mcp",
        "--project-root",
        "/tmp/project",
        "--http",
        "127.0.0.1:1",
        "--token-file",
        "/a",
        "--token-file",
        "/b",
    }));
}
