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
    // Preliminary check for engine binary
    const bin_path = try locator.findEngineBinary(allocator, engine_root, .ghost_task_operator);
    defer allocator.free(bin_path);

    if (!locator.checkBinaryExists(bin_path) and std.mem.indexOfScalar(u8, bin_path, std.fs.path.sep) != null) {
        std.debug.print("Engine binary missing: ghost_task_operator\n", .{});
        std.debug.print("Engine root: {s}\n", .{engine_root orelse "Not Found"});
        std.debug.print("\nFix:\n", .{});
        std.debug.print("1. cd ghost_engine && zig build\n", .{});
        std.debug.print("2. export GHOST_ENGINE_ROOT=\"<repo root>\"\n", .{});
        std.debug.print("3. run ghost status\n", .{});
        return;
    }

    try app.run(allocator, engine_root, options.reasoning, options.context_artifact, options.debug);
}
