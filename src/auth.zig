//! Bearer credentials for transports that listen on a socket.
//!
//! The credential never travels through argv. `/proc/<pid>/cmdline` is readable
//! by other local processes and argv lands in shell history, which is precisely
//! the reader a localhost listener is defending against, so the secret arrives
//! either in the environment or in a file the owner alone can read.

const std = @import("std");
const builtin = @import("builtin");
const Io = std.Io;

/// Environment variable carrying the bearer secret.
pub const env_var = "SPEC_KITTY_MCP_TOKEN";

/// Shortest secret worth calling a credential.
pub const min_secret_bytes = 16;

/// Upper bound on a credential file, so a mistyped path cannot be slurped whole.
pub const max_secret_bytes = 4096;

pub const Token = struct {
    digest: [32]u8,

    pub fn fromSecret(secret: []const u8) Token {
        var digest: [32]u8 = undefined;
        std.crypto.hash.sha2.Sha256.hash(secret, &digest, .{});
        return .{ .digest = digest };
    }

    /// Compare a presented secret against this credential.
    ///
    /// Both sides are hashed to a fixed width first, so the comparison runs
    /// over equal lengths and cannot return early on a length mismatch. A
    /// direct `mem.eql` would leak the expected length through timing.
    pub fn matches(token: Token, presented: []const u8) bool {
        const candidate = Token.fromSecret(presented);
        return std.crypto.timing_safe.eql([32]u8, token.digest, candidate.digest);
    }
};

pub const LoadError = error{
    /// Neither a token file nor the environment variable supplied a secret.
    MissingCredential,
    CredentialTooShort,
    CredentialTooLarge,
    /// The token file is readable by group or others.
    CredentialFileTooPermissive,
    CredentialFileUnreadable,
};

/// Resolve the credential a listener must hold before it binds.
///
/// An explicit `token_file` wins over the environment, so a host configuration
/// cannot be silently overridden by an inherited variable. Absence of both is an
/// error: there is no anonymous listen.
pub fn load(
    io: Io,
    gpa: std.mem.Allocator,
    environ: ?*const std.process.Environ.Map,
    token_file: ?[]const u8,
) LoadError!Token {
    if (token_file) |path| return loadFile(io, gpa, path);

    const from_env = blk: {
        const map = environ orelse break :blk null;
        break :blk map.get(env_var);
    } orelse return error.MissingCredential;

    // A variable that is set but blank is an unset credential, not a short one.
    const secret = std.mem.trim(u8, from_env, " \t\r\n");
    if (secret.len == 0) return error.MissingCredential;

    return fromSecret(secret);
}

fn loadFile(io: Io, gpa: std.mem.Allocator, path: []const u8) LoadError!Token {
    const dir = Io.Dir.cwd();

    if (builtin.os.tag != .windows) {
        var file = dir.openFile(io, path, .{}) catch return error.CredentialFileUnreadable;
        defer file.close(io);
        const stat = file.stat(io) catch return error.CredentialFileUnreadable;
        if (@intFromEnum(stat.permissions) & 0o077 != 0) {
            return error.CredentialFileTooPermissive;
        }
    }

    const contents = dir.readFileAlloc(
        io,
        path,
        gpa,
        Io.Limit.limited(max_secret_bytes + 1),
    ) catch |err| return switch (err) {
        error.StreamTooLong => error.CredentialTooLarge,
        else => error.CredentialFileUnreadable,
    };
    defer gpa.free(contents);

    return fromSecret(std.mem.trim(u8, contents, " \t\r\n"));
}

fn fromSecret(secret: []const u8) LoadError!Token {
    if (secret.len > max_secret_bytes) return error.CredentialTooLarge;
    if (secret.len < min_secret_bytes) return error.CredentialTooShort;
    return Token.fromSecret(secret);
}

pub fn errorMessage(err: LoadError) []const u8 {
    return switch (err) {
        error.MissingCredential => "a bearer credential is required before listening; set " ++
            env_var ++ " or pass --token-file",
        error.CredentialTooShort => "the bearer credential is too short",
        error.CredentialTooLarge => "the bearer credential is too large",
        error.CredentialFileTooPermissive => "the token file must not be readable by group or others",
        error.CredentialFileUnreadable => "the token file could not be read",
    };
}

/// Extract the secret from an `Authorization` header value.
///
/// The scheme is matched case-insensitively per RFC 7235. Anything that is not
/// a bearer credential yields null, which the caller answers with 401.
pub fn bearerSecret(header_value: []const u8) ?[]const u8 {
    const scheme = "bearer";
    if (header_value.len <= scheme.len) return null;
    if (!std.ascii.eqlIgnoreCase(header_value[0..scheme.len], scheme)) return null;
    if (header_value[scheme.len] != ' ') return null;

    const secret = std.mem.trim(u8, header_value[scheme.len + 1 ..], " \t");
    if (secret.len == 0) return null;
    return secret;
}

test "a credential matches only its own secret" {
    const token = Token.fromSecret("correct-horse-battery-staple");
    try std.testing.expect(token.matches("correct-horse-battery-staple"));
    try std.testing.expect(!token.matches("correct-horse-battery-stapl"));
    try std.testing.expect(!token.matches("correct-horse-battery-staple-"));
    try std.testing.expect(!token.matches(""));
    try std.testing.expect(!token.matches("x"));
}

test "bearer parsing accepts the RFC 7235 shape and rejects the rest" {
    try std.testing.expectEqualStrings("abc", bearerSecret("Bearer abc").?);
    try std.testing.expectEqualStrings("abc", bearerSecret("bearer abc").?);
    try std.testing.expectEqualStrings("abc", bearerSecret("BEARER abc  ").?);
    try std.testing.expect(bearerSecret("Bearer") == null);
    try std.testing.expect(bearerSecret("Bearer ") == null);
    try std.testing.expect(bearerSecret("Bearer  \t ") == null);
    try std.testing.expect(bearerSecret("Basic abc") == null);
    try std.testing.expect(bearerSecret("Bearerabc") == null);
    try std.testing.expect(bearerSecret("") == null);
}

test "loading refuses an absent credential" {
    try std.testing.expectError(
        error.MissingCredential,
        load(std.testing.io, std.testing.allocator, null, null),
    );
}

test "a short secret is not accepted as a credential" {
    try std.testing.expectError(error.CredentialTooShort, fromSecret("short"));
    try std.testing.expectError(
        error.CredentialTooShort,
        fromSecret("x" ** (min_secret_bytes - 1)),
    );
    _ = try fromSecret("x" ** min_secret_bytes);
}

test "a token file must not be readable by group or others" {
    if (builtin.os.tag == .windows) return error.SkipZigTest;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const secret = "a-sufficiently-long-secret";
    try tmp.dir.writeFile(std.testing.io, .{
        .sub_path = "loose",
        .data = secret,
        .flags = .{ .permissions = @enumFromInt(0o644) },
    });
    try tmp.dir.writeFile(std.testing.io, .{
        .sub_path = "tight",
        .data = secret,
        .flags = .{ .permissions = @enumFromInt(0o600) },
    });

    var root_buffer: [Io.Dir.max_path_bytes]u8 = undefined;
    const root_len = try tmp.dir.realPath(std.testing.io, &root_buffer);
    const root = root_buffer[0..root_len];

    const loose = try std.fs.path.join(std.testing.allocator, &.{ root, "loose" });
    defer std.testing.allocator.free(loose);
    const tight = try std.fs.path.join(std.testing.allocator, &.{ root, "tight" });
    defer std.testing.allocator.free(tight);

    try std.testing.expectError(
        error.CredentialFileTooPermissive,
        load(std.testing.io, std.testing.allocator, null, loose),
    );

    const token = try load(std.testing.io, std.testing.allocator, null, tight);
    try std.testing.expect(token.matches(secret));
}

test "a token file surrenders its trailing newline" {
    if (builtin.os.tag == .windows) return error.SkipZigTest;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    try tmp.dir.writeFile(std.testing.io, .{
        .sub_path = "token",
        .data = "a-sufficiently-long-secret\n",
        .flags = .{ .permissions = @enumFromInt(0o600) },
    });

    var root_buffer: [Io.Dir.max_path_bytes]u8 = undefined;
    const root_len = try tmp.dir.realPath(std.testing.io, &root_buffer);
    const path = try std.fs.path.join(
        std.testing.allocator,
        &.{ root_buffer[0..root_len], "token" },
    );
    defer std.testing.allocator.free(path);

    const token = try load(std.testing.io, std.testing.allocator, null, path);
    try std.testing.expect(token.matches("a-sufficiently-long-secret"));
    try std.testing.expect(!token.matches("a-sufficiently-long-secret\n"));
}

test "a blank environment variable reads as an absent credential" {
    var map: std.process.Environ.Map = .init(std.testing.allocator);
    defer map.deinit();

    try map.put(env_var, "   \n");
    try std.testing.expectError(
        error.MissingCredential,
        load(std.testing.io, std.testing.allocator, &map, null),
    );

    try map.put(env_var, "a-sufficiently-long-secret\n");
    const token = try load(std.testing.io, std.testing.allocator, &map, null);
    try std.testing.expect(token.matches("a-sufficiently-long-secret"));
}
