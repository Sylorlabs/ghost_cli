const std = @import("std");
const locator = @import("locator.zig");
const process = @import("process.zig");

pub const RunOptions = struct {
    engine_root: ?[]const u8 = null,
    binary: locator.EngineBinaries,
    argv: []const []const u8,
    json: bool = false,
    debug: bool = false,
};

pub const RunResult = struct {
    stdout: []u8,
    stderr: []u8,
    exit_code: u8,
    allocator: std.mem.Allocator,

    pub fn deinit(self: RunResult) void {
        self.allocator.free(self.stdout);
        self.allocator.free(self.stderr);
    }
};

pub fn run(allocator: std.mem.Allocator, options: RunOptions) !RunResult {
    const bin_path = locator.findEngineBinary(allocator, options.engine_root, options.binary) catch |err| {
        try locator.printLocatorError(std.io.getStdErr().writer(), options.binary, options.engine_root, err);
        std.process.exit(1);
    };
    defer allocator.free(bin_path);

    var run_args = std.ArrayList([]const u8).init(allocator);
    defer run_args.deinit();

    try run_args.append(bin_path);
    for (options.argv) |arg| {
        try run_args.append(arg);
    }

    if (options.debug) {
        std.debug.print("[DEBUG] Engine Binary: {s}\n", .{bin_path});
        std.debug.print("[DEBUG] Arguments: ", .{});
        for (run_args.items) |arg| {
            std.debug.print("'{s}' ", .{arg});
        }
        std.debug.print("\n", .{});
    }

    const result = process.runEngineCommand(allocator, run_args.items) catch |err| {
        std.debug.print("\x1b[31m[!] Error:\x1b[0m Failed to execute engine command ({})\n", .{err});
        std.debug.print("\x1b[33mHint:\x1b[0m Run `ghost status` to verify your environment.\n", .{});
        std.process.exit(1);
    };

    if (options.debug) {
        std.debug.print("[DEBUG] Exit Code: {d}\n", .{result.exit_code});
    }

    if (options.json and result.exit_code == 0) {
        // Validation of JSON could happen here if we wanted
    }

    if (result.exit_code != 0 and !options.json) {
        std.debug.print("\x1b[31m[!] Engine Error (Exit Code {d}):\x1b[0m\n", .{result.exit_code});
        if (result.stderr.len > 0) {
            std.debug.print("{s}\n", .{result.stderr});
        } else if (result.stdout.len > 0) {
            std.debug.print("{s}\n", .{result.stdout});
        }
        std.debug.print("\x1b[33mHint:\x1b[0m The engine failed to process the request. Try running with --debug or check `ghost status`.\n", .{});
    }

    return RunResult{
        .stdout = result.stdout,
        .stderr = result.stderr,
        .exit_code = result.exit_code,
        .allocator = allocator,
    };
}
