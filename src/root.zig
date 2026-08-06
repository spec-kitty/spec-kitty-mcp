pub const cli = @import("cli.zig");
pub const mcp = @import("mcp.zig");
pub const project = @import("project.zig");

pub const version = "0.1.0-dev";

test {
    _ = cli;
    _ = mcp;
    _ = project;
}
