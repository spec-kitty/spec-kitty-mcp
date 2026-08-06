const std = @import("std");
const Io = std.Io;

const app = @import("spec_kitty_mcp");

pub fn main(init: std.process.Init) !void {
    const exit_code = try run(init);
    if (exit_code != 0) std.process.exit(exit_code);
}

fn run(init: std.process.Init) !u8 {
    const arena = init.arena.allocator();
    const args = try init.minimal.args.toSlice(arena);
    const command = app.cli.parse(args) catch |err| {
        std.log.err("{s}", .{app.cli.errorMessage(err)});
        std.debug.print("\n{s}", .{app.cli.help_text});
        return 2;
    };

    switch (command) {
        .help => try writeStdout(init.io, app.cli.help_text),
        .version => try writeStdout(init.io, "spec-kitty-mcp " ++ app.version ++ "\n"),
        .run => |options| {
            var project = app.project.validate(init.io, arena, options.project_root) catch |err| {
                const message = switch (err) {
                    error.EmptyProjectRoot,
                    error.MissingGitMetadata,
                    error.MissingSpecKittyConfig,
                    error.ProjectRootNotFound,
                    => app.project.errorMessage(@errorCast(err)),
                    else => return err,
                };
                std.log.err("{s}: {s}", .{ message, options.project_root });
                return 2;
            };
            defer project.deinit(arena);

            std.log.info("bound to Spec Kitty project: {s}", .{project.root});
            std.log.info("Spec Kitty executable: {s}", .{options.spec_kitty_bin});
            try app.mcp.serve(init.io, init.gpa, app.version);
        },
    }

    return 0;
}

fn writeStdout(io: Io, bytes: []const u8) !void {
    var buffer: [4096]u8 = undefined;
    var file_writer: Io.File.Writer = .init(.stdout(), io, &buffer);
    const writer = &file_writer.interface;
    try writer.writeAll(bytes);
    try writer.flush();
}
