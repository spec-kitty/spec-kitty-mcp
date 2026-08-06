const std = @import("std");

pub const help_text =
    \\Usage: spec-kitty-mcp --project-root <path> [options]
    \\
    \\Options:
    \\  --project-root <path>    Initialized Spec Kitty project to bind
    \\  --spec-kitty-bin <path>  Spec Kitty executable (default: spec-kitty)
    \\  -h, --help               Show this help
    \\  -V, --version            Show the version
    \\
;

pub const Options = struct {
    project_root: []const u8,
    spec_kitty_bin: []const u8 = "spec-kitty",
};

pub const Command = union(enum) {
    run: Options,
    help,
    version,
};

pub const ParseError = error{
    DuplicateProjectRoot,
    DuplicateSpecKittyBin,
    EmptyOptionValue,
    MissingOptionValue,
    MissingProjectRoot,
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
    var index: usize = 1;

    while (index < args.len) : (index += 1) {
        const arg = args[index];

        if (std.mem.eql(u8, arg, "--project-root")) {
            if (project_root != null) return error.DuplicateProjectRoot;
            project_root = try optionValue(args, &index);
        } else if (std.mem.eql(u8, arg, "--spec-kitty-bin")) {
            if (spec_kitty_bin != null) return error.DuplicateSpecKittyBin;
            spec_kitty_bin = try optionValue(args, &index);
        } else if (isHelp(arg) or isVersion(arg)) {
            return error.UnexpectedArgument;
        } else if (std.mem.startsWith(u8, arg, "-")) {
            return error.UnknownOption;
        } else {
            return error.UnexpectedArgument;
        }
    }

    return .{ .run = .{
        .project_root = project_root orelse return error.MissingProjectRoot,
        .spec_kitty_bin = spec_kitty_bin orelse "spec-kitty",
    } };
}

pub fn errorMessage(err: ParseError) []const u8 {
    return switch (err) {
        error.DuplicateProjectRoot => "--project-root may be supplied only once",
        error.DuplicateSpecKittyBin => "--spec-kitty-bin may be supplied only once",
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
