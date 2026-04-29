const std = @import("std");
const locator = @import("../engine/locator.zig");
const process = @import("../engine/process.zig");
const json_contracts = @import("../engine/json_contracts.zig");
const terminal = @import("../render/terminal.zig");

pub const ContextAutopsyOptions = struct {
    description: ?[]const u8 = null,
    json: bool = false,
    debug: bool = false,
};

pub fn executeAutopsy(allocator: std.mem.Allocator, engine_root: ?[]const u8, options: ContextAutopsyOptions) !void {
    const description = options.description orelse {
        try std.io.getStdErr().writer().print("Usage: ghost context autopsy [--json] [--debug] <description>\n", .{});
        std.process.exit(1);
    };
    if (description.len == 0) {
        try std.io.getStdErr().writer().print("Usage: ghost context autopsy [--json] [--debug] <description>\n", .{});
        std.process.exit(1);
    }

    const bin_path = locator.findEngineBinary(allocator, engine_root, .ghost_gip) catch |err| {
        try locator.printLocatorError(std.io.getStdErr().writer(), .ghost_gip, engine_root, err);
        std.process.exit(1);
    };
    defer allocator.free(bin_path);

    var request = std.ArrayList(u8).init(allocator);
    defer request.deinit();
    try std.json.stringify(.{
        .gipVersion = "gip.v0.1",
        .kind = "context.autopsy",
        .context = .{
            .summary = description,
            .intakeType = "context",
        },
    }, .{}, request.writer());

    const argv = [_][]const u8{ bin_path, "--stdin" };
    if (options.debug) {
        std.debug.print("[DEBUG] Engine Binary: {s}\n", .{bin_path});
        std.debug.print("[DEBUG] GIP Kind: context.autopsy\n", .{});
        std.debug.print("[DEBUG] Arguments: '{s}' '--stdin'\n", .{bin_path});
    }

    const result = process.runEngineCommandWithInput(allocator, &argv, request.items) catch |err| {
        std.debug.print("\x1b[31m[!] Error:\x1b[0m Failed to execute engine command ({})\n", .{err});
        std.debug.print("\x1b[33mHint:\x1b[0m Run `ghost status` to verify your environment.\n", .{});
        std.process.exit(1);
    };
    defer {
        allocator.free(result.stdout);
        allocator.free(result.stderr);
    }

    if (options.debug) {
        std.debug.print("[DEBUG] Exit Code: {d}\n", .{result.exit_code});
    }

    if (options.json) {
        try std.io.getStdOut().writer().print("{s}", .{result.stdout});
        if (result.stderr.len > 0) try std.io.getStdErr().writer().print("{s}", .{result.stderr});
        return;
    }

    if (result.exit_code != 0) {
        std.debug.print("\x1b[31m[!] Engine Error (Exit Code {d}):\x1b[0m\n", .{result.exit_code});
        if (result.stderr.len > 0) {
            std.debug.print("{s}\n", .{result.stderr});
        } else if (result.stdout.len > 0) {
            std.debug.print("{s}\n", .{result.stdout});
        }
        return;
    }

    const parsed = json_contracts.parseContextAutopsyJson(allocator, result.stdout) catch |err| {
        if (options.debug) std.debug.print("[DEBUG] JSON Parse: FAILED ({})\n", .{err});
        std.debug.print("Error: Failed to parse engine output as Context Autopsy JSON.\n", .{});
        std.debug.print("Raw output:\n{s}\n", .{result.stdout});
        return;
    };
    defer parsed.deinit();

    if (options.debug) {
        std.debug.print("[DEBUG] JSON Parse: SUCCESS\n", .{});
    }

    try terminal.printContextAutopsyResult(std.io.getStdOut().writer(), parsed.value);
}
