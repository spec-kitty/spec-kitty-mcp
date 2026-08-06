const std = @import("std");
const Io = std.Io;

pub const Project = struct {
    root: []u8,

    pub fn deinit(project: *Project, allocator: std.mem.Allocator) void {
        allocator.free(project.root);
        project.* = undefined;
    }
};

pub const ValidationError = error{
    EmptyProjectRoot,
    MissingGitMetadata,
    MissingSpecKittyConfig,
    ProjectRootNotFound,
};

pub fn validate(
    io: Io,
    allocator: std.mem.Allocator,
    raw_root: []const u8,
) !Project {
    if (raw_root.len == 0) return error.EmptyProjectRoot;

    const dir = Io.Dir.cwd().openDir(io, raw_root, .{}) catch |err| switch (err) {
        error.FileNotFound, error.NotDir => return error.ProjectRootNotFound,
        else => return err,
    };
    defer dir.close(io);

    dir.access(io, ".git", .{}) catch |err| switch (err) {
        error.FileNotFound => return error.MissingGitMetadata,
        else => return err,
    };
    dir.access(io, ".kittify/config.yaml", .{ .read = true }) catch |err| switch (err) {
        error.FileNotFound => return error.MissingSpecKittyConfig,
        else => return err,
    };

    var path_buffer: [Io.Dir.max_path_bytes]u8 = undefined;
    const path_len = try dir.realPath(io, &path_buffer);

    return .{
        .root = try allocator.dupe(u8, path_buffer[0..path_len]),
    };
}

pub fn errorMessage(err: ValidationError) []const u8 {
    return switch (err) {
        error.EmptyProjectRoot => "project root must not be empty",
        error.MissingGitMetadata => "project root is not a Git checkout",
        error.MissingSpecKittyConfig => "project root is not initialized by Spec Kitty",
        error.ProjectRootNotFound => "project root does not exist or is not a directory",
    };
}

test "validate canonicalizes an initialized Spec Kitty project" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try addProjectMarkers(tmp.dir);

    var raw_buffer: [Io.Dir.max_path_bytes]u8 = undefined;
    const raw_len = try tmp.dir.realPath(std.testing.io, &raw_buffer);

    var project = try validate(
        std.testing.io,
        std.testing.allocator,
        raw_buffer[0..raw_len],
    );
    defer project.deinit(std.testing.allocator);

    try std.testing.expect(std.fs.path.isAbsolute(project.root));
    try std.testing.expectEqualStrings(raw_buffer[0..raw_len], project.root);
}

test "validate rejects a directory without Git metadata" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    var raw_buffer: [Io.Dir.max_path_bytes]u8 = undefined;
    const raw_len = try tmp.dir.realPath(std.testing.io, &raw_buffer);

    try std.testing.expectError(error.MissingGitMetadata, validate(
        std.testing.io,
        std.testing.allocator,
        raw_buffer[0..raw_len],
    ));
}

test "validate rejects a Git checkout without Spec Kitty configuration" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const git_dir = try tmp.dir.createDirPathOpen(std.testing.io, ".git", .{});
    git_dir.close(std.testing.io);

    var raw_buffer: [Io.Dir.max_path_bytes]u8 = undefined;
    const raw_len = try tmp.dir.realPath(std.testing.io, &raw_buffer);

    try std.testing.expectError(error.MissingSpecKittyConfig, validate(
        std.testing.io,
        std.testing.allocator,
        raw_buffer[0..raw_len],
    ));
}

fn addProjectMarkers(dir: Io.Dir) !void {
    const git_dir = try dir.createDirPathOpen(std.testing.io, ".git", .{});
    git_dir.close(std.testing.io);

    const kittify_dir = try dir.createDirPathOpen(std.testing.io, ".kittify", .{});
    defer kittify_dir.close(std.testing.io);
    try kittify_dir.writeFile(std.testing.io, .{
        .sub_path = "config.yaml",
        .data = "schema_version: 1\n",
    });
}
