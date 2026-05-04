const std = @import("std");
const runner = @import("../engine/runner.zig");
const terminal = @import("../render/terminal.zig");

pub const AutopsyOptions = struct {
    path: ?[]const u8 = null,
    json: bool = false,
    debug: bool = false,
};

pub fn execute(allocator: std.mem.Allocator, engine_root: ?[]const u8, options: AutopsyOptions) !void {
    const target_path = options.path orelse ".";

    const res = try runner.run(allocator, .{
        .engine_root = engine_root,
        .binary = .ghost_project_autopsy,
        .argv = &[_][]const u8{target_path},
        .json = options.json,
        .debug = options.debug,
    });
    defer res.deinit();

    if (options.json) {
        // Raw engine stdout is preserved exactly and terminal rendering is skipped.
        const stdout = std.io.getStdOut().writer();
        try stdout.print("{s}", .{res.stdout});
        return;
    }

    if (res.exit_code != 0) {
        // Error already printed by runner.run if not in json mode
        return;
    }

    const parsed = std.json.parseFromSlice(std.json.Value, allocator, res.stdout, .{
        .ignore_unknown_fields = true,
    }) catch |err| {
        if (options.debug) {
            std.debug.print("[DEBUG] JSON Parse: FAILED ({})\n", .{err});
        }
        std.debug.print("Error: Failed to parse engine output as Autopsy JSON.\n", .{});
        std.debug.print("Raw output:\n{s}\n", .{res.stdout});
        return;
    };
    defer parsed.deinit();

    if (options.debug) {
        std.debug.print("[DEBUG] JSON Parse: SUCCESS\n", .{});
    }

    const stdout = std.io.getStdOut().writer();
    try terminal.printProjectAutopsyValue(stdout, parsed.value);
}
