const std = @import("std");
const locator = @import("../engine/locator.zig");
const process = @import("../engine/process.zig");
const json_contracts = @import("../engine/json_contracts.zig");
const terminal = @import("../render/terminal.zig");

pub const ArtifactAutopsyOptions = struct {
    file: ?[]const u8 = null,
    workspace: ?[]const u8 = null,
    json: bool = false,
    debug: bool = false,
};

const usage = "Usage: ghost artifact autopsy inspect --file <request.json> [--workspace <path>] [--json] [--debug]\n";

pub fn printHelp(writer: anytype) !void {
    try writer.print(
        \\artifact
        \\
        \\Usage: ghost artifact autopsy inspect --file <request.json> [--workspace <path>] [--json] [--debug]
        \\
        \\Artifact Autopsy pass (explicit GIP request only)
        \\
        \\Subcommands:
        \\  autopsy inspect --file <path>  Run an explicit artifact.autopsy.inspect GIP request
        \\
        \\Options:
        \\  --file <path>          Path to the request JSON file
        \\  --workspace <path>     Workspace root for bounded file autopsy
        \\  --json                 Preserve raw GIP stdout exactly
        \\  --debug                Diagnostics to stderr
        \\
        \\Safety:
        \\  This request runs only when this command is explicitly invoked.
        \\  Output is READ-ONLY, NON-AUTHORIZING, and CANDIDATE ONLY.
        \\  It does not run scans, execute verifiers, mutate state, or execute commands.
        \\
    , .{});
}

pub fn printHelpForArgs(writer: anytype, args: []const []const u8) !void {
    if (args.len > 0 and std.mem.eql(u8, args[0], "autopsy")) {
        if (args.len > 1 and std.mem.eql(u8, args[1], "inspect")) {
            try printHelp(writer);
            return;
        }
    }
    try printHelp(writer);
}

pub fn executeFromArgs(
    allocator: std.mem.Allocator,
    engine_root: ?[]const u8,
    args: []const []const u8,
    json: bool,
    debug: bool,
) !void {
    if (args.len < 2) {
        try std.io.getStdErr().writer().print("{s}", .{usage});
        std.process.exit(1);
    }

    const sub1 = args[0];
    const sub2 = args[1];

    if (!std.mem.eql(u8, sub1, "autopsy") or !std.mem.eql(u8, sub2, "inspect")) {
        try std.io.getStdErr().writer().print("Unknown artifact command: {s} {s}\n{s}", .{ sub1, sub2, usage });
        std.process.exit(1);
    }

    var file_path: ?[]const u8 = null;
    var workspace: ?[]const u8 = null;

    var i: usize = 2;
    while (i < args.len) : (i += 1) {
        const arg = args[i];
        if (std.mem.eql(u8, arg, "--file")) {
            i += 1;
            if (i >= args.len) try failMissingValue("--file");
            file_path = args[i];
        } else if (std.mem.startsWith(u8, arg, "--file=")) {
            file_path = arg["--file=".len..];
        } else if (std.mem.eql(u8, arg, "--workspace") or std.mem.eql(u8, arg, "-w")) {
            i += 1;
            if (i >= args.len) try failMissingValue("--workspace");
            workspace = args[i];
        } else if (std.mem.startsWith(u8, arg, "--workspace=")) {
            workspace = arg["--workspace=".len..];
        } else {
            try std.io.getStdErr().writer().print("Unexpected artifact autopsy inspect argument: {s}\n", .{arg});
            std.process.exit(1);
        }
    }

    if (file_path == null) {
        try std.io.getStdErr().writer().print("--file <path> is required\n{s}", .{usage});
        std.process.exit(1);
    }

    try executeInspect(allocator, engine_root, .{
        .file = file_path,
        .workspace = workspace,
        .json = json,
        .debug = debug,
    });
}

pub fn executeInspect(allocator: std.mem.Allocator, engine_root: ?[]const u8, options: ArtifactAutopsyOptions) !void {
    const file_path = options.file orelse unreachable;

    const request_bytes = std.fs.cwd().readFileAlloc(allocator, file_path, 10 * 1024 * 1024) catch |err| {
        std.debug.print("Error: Failed to read request file {s} ({})\n", .{ file_path, err });
        std.process.exit(1);
    };
    defer allocator.free(request_bytes);

    // Validate kind "artifact.autopsy.inspect"
    const parsed_request = std.json.parseFromSlice(std.json.Value, allocator, request_bytes, .{ .ignore_unknown_fields = true }) catch |err| {
        std.debug.print("Error: Failed to parse request file as JSON ({})\n", .{err});
        std.process.exit(1);
    };
    defer parsed_request.deinit();

    const kind = switch (parsed_request.value) {
        .object => |obj| if (obj.get("kind")) |k| k.string else null,
        else => null,
    };

    if (kind == null or !std.mem.eql(u8, kind.?, "artifact.autopsy.inspect")) {
        std.debug.print("Error: Invalid GIP kind. Expected 'artifact.autopsy.inspect', found '{s}'\n", .{kind orelse "null"});
        std.process.exit(1);
    }

    const bin_path = locator.findEngineBinary(allocator, engine_root, .ghost_gip) catch |err| {
        try locator.printLocatorError(std.io.getStdErr().writer(), .ghost_gip, engine_root, err);
        std.process.exit(1);
    };
    defer allocator.free(bin_path);

    var argv_list = std.ArrayList([]const u8).init(allocator);
    defer argv_list.deinit();
    try argv_list.append(bin_path);
    try argv_list.append("--stdin");

    if (options.workspace) |ws| {
        try argv_list.append("--workspace");
        try argv_list.append(ws);
    }

    if (options.debug) {
        std.debug.print("[DEBUG] Engine Binary: {s}\n", .{bin_path});
        std.debug.print("[DEBUG] GIP Kind: artifact.autopsy.inspect\n", .{});
        std.debug.print("[DEBUG] Request File: {s}\n", .{file_path});
        if (options.workspace) |ws| std.debug.print("[DEBUG] Workspace: {s}\n", .{ws});
        std.debug.print("[DEBUG] Stdin Payload Size: {d} bytes\n", .{request_bytes.len});
    }

    const result = process.runEngineCommandWithInput(allocator, argv_list.items, request_bytes) catch |err| {
        std.debug.print("\x1b[31m[!] Error:\x1b[0m Failed to execute engine command ({})\n", .{err});
        std.process.exit(1);
    };
    defer {
        allocator.free(result.stdout);
        allocator.free(result.stderr);
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

    const parsed = json_contracts.parseArtifactAutopsyJson(allocator, result.stdout) catch |err| {
        if (options.debug) std.debug.print("[DEBUG] JSON Parse: FAILED ({})\n", .{err});
        std.debug.print("Error: Failed to parse engine output as Artifact Autopsy JSON.\n", .{});
        std.debug.print("Raw output:\n{s}\n", .{result.stdout});
        return;
    };
    defer parsed.deinit();

    try terminal.printArtifactAutopsyResult(std.io.getStdOut().writer(), parsed.value);
}

fn failMissingValue(flag: []const u8) !noreturn {
    try std.io.getStdErr().writer().print("{s} requires a value\n", .{flag});
    std.process.exit(1);
}
