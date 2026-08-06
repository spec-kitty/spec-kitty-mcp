pub const cli = @import("cli.zig");
pub const mcp = @import("mcp.zig");
pub const project = @import("project.zig");
pub const spec_kitty = @import("spec_kitty.zig");

pub const version = "0.1.0-dev";
pub const provider_version = "0.1.0";

test {
    _ = cli;
    _ = mcp;
    _ = project;
    _ = spec_kitty;
}
