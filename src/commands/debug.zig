const std = @import("std");
const locator = @import("../engine/locator.zig");
const process = @import("../engine/process.zig");

pub fn execute(allocator: std.mem.Allocator, engine_root: ?[]const u8, args: [][]const u8, json_out: bool) !void {
    _ = json_out;
    if (args.len == 0) {
        std.debug.print("Usage: ghost debug raw <engine-binary> [args...]\n", .{});
        return;
    }

    if (std.mem.eql(u8, args[0], "raw")) {
        if (args.len < 2) {
            std.debug.print("Usage: ghost debug raw <engine-binary> [args...]\n", .{});
            return;
        }

        const bin_name = args[1];
        var bin_path: []u8 = undefined;

        // Try to map to known engine binary
        var found = false;
        inline for (@typeInfo(locator.EngineBinaries).@"enum".fields) |field| {
            if (std.mem.eql(u8, bin_name, field.name)) {
                const enum_val = @field(locator.EngineBinaries, field.name);
                const p = try locator.findEngineBinary(allocator, engine_root, enum_val);
                bin_path = p;
                found = true;
            }
        }

        if (!found) {
            // Assume it's a direct path or something in PATH
            bin_path = try allocator.dupe(u8, bin_name);
        }
        defer allocator.free(bin_path);

        var run_args = std.ArrayList([]const u8).init(allocator);
        defer run_args.deinit();

        try run_args.append(bin_path);
        for (args[2..]) |arg| {
            try run_args.append(arg);
        }

        const result = try process.runEngineCommand(allocator, run_args.items);
        defer allocator.free(result.stdout);
        defer allocator.free(result.stderr);

        if (result.stdout.len > 0) std.debug.print("{s}", .{result.stdout});
        if (result.stderr.len > 0) std.debug.print("{s}", .{result.stderr});
        
        if (result.exit_code != 0) {
            std.process.exit(result.exit_code);
        }
    } else {
        std.debug.print("Unknown debug command: {s}\n", .{args[0]});
    }
}
