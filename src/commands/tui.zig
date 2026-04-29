const std = @import("std");
const app = @import("../tui/app.zig");
const json_contracts = @import("../engine/json_contracts.zig");
const locator = @import("../engine/locator.zig");

pub const TuiOptions = struct {
    reasoning: ?json_contracts.ReasoningLevel = null,
    context_artifact: ?[]const u8 = null,
    debug: bool = false,
};

pub fn execute(allocator: std.mem.Allocator, engine_root: ?[]const u8, options: TuiOptions) !void {
    const bin_path = locator.findEngineBinary(allocator, engine_root, .ghost_task_operator) catch |err| {
        try locator.printLocatorError(std.io.getStdErr().writer(), .ghost_task_operator, engine_root, err);
        return;
    };
    defer allocator.free(bin_path);

    try app.run(allocator, engine_root, options.reasoning, options.context_artifact, options.debug);
}
