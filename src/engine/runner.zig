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
    const bin_path = try locator.findEngineBinary(allocator, options.engine_root, options.binary);
    defer allocator.free(bin_path);

    // If it's not in PATH and doesn't exist, it's a failure
    if (!locator.checkBinaryExists(bin_path) and std.mem.indexOfScalar(u8, bin_path, std.fs.path.sep) != null) {
        const bin_name = options.binary.toStr();
        std.debug.print("\x1b[31m[!] Error:\x1b[0m Engine binary '{s}' not found.\n", .{bin_name});
        if (options.engine_root) |root| {
            std.debug.print("\x1b[33mHint:\x1b[0m Checked engine root: {s}\n", .{root});
            std.debug.print("\x1b[33mHint:\x1b[0m If GHOST_ENGINE_ROOT points to the repo root, run `zig build` in ghost_engine.\n", .{});
        }
        std.debug.print("\x1b[33mFix:\x1b[0m Set --engine-root=<path>, GHOST_ENGINE_ROOT environment variable, or run `zig build install` in ghost_engine.\n", .{});
        std.process.exit(1);
    }

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
