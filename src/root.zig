pub const cli = @import("cli.zig");
pub const conformance = @import("conformance.zig");
pub const mcp = @import("mcp.zig");
pub const project = @import("project.zig");
pub const spec_kitty = @import("spec_kitty.zig");
pub const tools = @import("tools.zig");

pub const version = @import("build_options").version;
pub const provider_version = "0.1.0";

test {
    _ = cli;
    _ = conformance;
    _ = mcp;
    _ = project;
    _ = spec_kitty;
    _ = tools;
}
