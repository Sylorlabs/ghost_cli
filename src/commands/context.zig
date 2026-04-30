const std = @import("std");
const locator = @import("../engine/locator.zig");
const process = @import("../engine/process.zig");
const json_contracts = @import("../engine/json_contracts.zig");
const terminal = @import("../render/terminal.zig");

pub const ContextAutopsyOptions = struct {
    description: ?[]const u8 = null,
    input_files: []const []const u8 = &.{},
    input_label: ?[]const u8 = null,
    input_purpose: ?[]const u8 = null,
    input_reason: ?[]const u8 = null,
    input_max_bytes: ?u64 = null,
    json: bool = false,
    debug: bool = false,
};

const usage = "Usage: ghost context autopsy [--json] [--debug] [--input-file <path>] [--input-max-bytes <bytes>] <description>\n";

pub fn printHelp(writer: anytype) !void {
    try writer.print(
        \\context
        \\
        \\Usage: ghost context autopsy [--json] [--debug] [--input-file <path>] <description>
        \\
        \\Context Autopsy pass (explicit GIP request only)
        \\
        \\Subcommands:
        \\  autopsy <description>  Run an explicit context.autopsy GIP request
        \\
        \\Options:
        \\  --json                 Preserve raw GIP stdout exactly
        \\  --debug                Diagnostics to stderr
        \\  --input-file <path>     Add an explicit bounded file input ref; repeatable
        \\  --input-max-bytes <n>   Shared maxBytes value for each input ref
        \\  --input-label <label>   Shared optional label for input refs
        \\  --input-purpose <text>  Shared optional purpose for input refs
        \\  --input-reason <text>   Shared optional reason for input refs
        \\
        \\Safety:
        \\  This request runs only when this command is explicitly invoked.
        \\  File inputs are explicit and are read by the engine through bounded refs.
        \\  Output is DRAFT / NON-AUTHORIZING.
        \\  It does not run scans, execute verifiers, mutate packs, or mutate negative knowledge.
        \\  When coverage reports truncation, skips, or unread regions, no full-content claim is made.
        \\
    , .{});
}

pub fn executeFromArgs(
    allocator: std.mem.Allocator,
    engine_root: ?[]const u8,
    args: []const []const u8,
    json: bool,
    debug: bool,
) !void {
    const sub = if (args.len > 0) args[0] else {
        try std.io.getStdErr().writer().print("{s}", .{usage});
        std.process.exit(1);
    };
    if (!std.mem.eql(u8, sub, "autopsy")) {
        try std.io.getStdErr().writer().print("Unknown context command: {s}\n{s}", .{ sub, usage });
        std.process.exit(1);
    }

    var input_files = std.ArrayList([]const u8).init(allocator);
    defer input_files.deinit();
    var input_label: ?[]const u8 = null;
    var input_purpose: ?[]const u8 = null;
    var input_reason: ?[]const u8 = null;
    var input_max_bytes: ?u64 = null;
    var description: ?[]const u8 = null;

    var i: usize = 1;
    while (i < args.len) : (i += 1) {
        const arg = args[i];
        if (std.mem.eql(u8, arg, "--input-file")) {
            i += 1;
            if (i >= args.len) try failMissingValue("--input-file");
            try input_files.append(args[i]);
        } else if (std.mem.startsWith(u8, arg, "--input-file=")) {
            const value = arg["--input-file=".len..];
            if (value.len == 0) try failMissingValue("--input-file");
            try input_files.append(value);
        } else if (std.mem.eql(u8, arg, "--input-label")) {
            i += 1;
            if (i >= args.len) try failMissingValue("--input-label");
            input_label = args[i];
        } else if (std.mem.startsWith(u8, arg, "--input-label=")) {
            input_label = arg["--input-label=".len..];
        } else if (std.mem.eql(u8, arg, "--input-purpose")) {
            i += 1;
            if (i >= args.len) try failMissingValue("--input-purpose");
            input_purpose = args[i];
        } else if (std.mem.startsWith(u8, arg, "--input-purpose=")) {
            input_purpose = arg["--input-purpose=".len..];
        } else if (std.mem.eql(u8, arg, "--input-reason")) {
            i += 1;
            if (i >= args.len) try failMissingValue("--input-reason");
            input_reason = args[i];
        } else if (std.mem.startsWith(u8, arg, "--input-reason=")) {
            input_reason = arg["--input-reason=".len..];
        } else if (std.mem.eql(u8, arg, "--input-max-bytes")) {
            i += 1;
            if (i >= args.len) try failMissingValue("--input-max-bytes");
            input_max_bytes = try parseInputMaxBytes(args[i]);
        } else if (std.mem.startsWith(u8, arg, "--input-max-bytes=")) {
            input_max_bytes = try parseInputMaxBytes(arg["--input-max-bytes=".len..]);
        } else if (std.mem.startsWith(u8, arg, "--input-")) {
            try std.io.getStdErr().writer().print("Unknown context autopsy input option: {s}\n", .{arg});
            std.process.exit(1);
        } else if (description == null) {
            description = arg;
        } else {
            try std.io.getStdErr().writer().print("Unexpected extra context autopsy argument: {s}\n", .{arg});
            std.process.exit(1);
        }
    }

    try executeAutopsy(allocator, engine_root, .{
        .description = description,
        .input_files = input_files.items,
        .input_label = input_label,
        .input_purpose = input_purpose,
        .input_reason = input_reason,
        .input_max_bytes = input_max_bytes,
        .json = json,
        .debug = debug,
    });
}

pub fn executeAutopsy(allocator: std.mem.Allocator, engine_root: ?[]const u8, options: ContextAutopsyOptions) !void {
    const description = options.description orelse {
        try std.io.getStdErr().writer().print("{s}", .{usage});
        std.process.exit(1);
    };
    if (description.len == 0) {
        try std.io.getStdErr().writer().print("{s}", .{usage});
        std.process.exit(1);
    }

    const bin_path = locator.findEngineBinary(allocator, engine_root, .ghost_gip) catch |err| {
        try locator.printLocatorError(std.io.getStdErr().writer(), .ghost_gip, engine_root, err);
        std.process.exit(1);
    };
    defer allocator.free(bin_path);

    var request = std.ArrayList(u8).init(allocator);
    defer request.deinit();
    try writeContextAutopsyRequest(request.writer(), description, options);

    var cwd_buf: ?[]u8 = null;
    defer if (cwd_buf) |cwd| allocator.free(cwd);

    var argv_list = std.ArrayList([]const u8).init(allocator);
    defer argv_list.deinit();
    try argv_list.append(bin_path);
    try argv_list.append("--stdin");
    if (options.input_files.len > 0) {
        const cwd = try std.process.getCwdAlloc(allocator);
        cwd_buf = cwd;
        try argv_list.append("--workspace");
        try argv_list.append(cwd);
    }

    if (options.debug) {
        std.debug.print("[DEBUG] Engine Binary: {s}\n", .{bin_path});
        std.debug.print("[DEBUG] GIP Kind: context.autopsy\n", .{});
        std.debug.print("[DEBUG] Arguments:", .{});
        for (argv_list.items) |arg| std.debug.print(" '{s}'", .{arg});
        std.debug.print("\n", .{});
        std.debug.print("[DEBUG] Stdin Payload Summary: bytes={d} summary_bytes={d} input_file_refs={d}\n", .{
            request.items.len,
            description.len,
            options.input_files.len,
        });
        std.debug.print("[DEBUG] Input File Refs: {d}\n", .{options.input_files.len});
    }

    const result = process.runEngineCommandWithInput(allocator, argv_list.items, request.items) catch |err| {
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
        if (options.debug) std.debug.print("[DEBUG] JSON Parse: SKIPPED (raw passthrough)\n", .{});
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

fn writeContextAutopsyRequest(writer: anytype, description: []const u8, options: ContextAutopsyOptions) !void {
    try writer.writeAll("{\"gipVersion\":\"gip.v0.1\",\"kind\":\"context.autopsy\",\"context\":{\"summary\":");
    try std.json.stringify(description, .{}, writer);
    try writer.writeAll(",\"intakeType\":\"context\"");
    if (options.input_files.len > 0) {
        try writer.writeAll(",\"input_refs\":[");
        for (options.input_files, 0..) |path, i| {
            if (i > 0) try writer.writeAll(",");
            try writer.writeAll("{\"kind\":\"file\",\"path\":");
            try std.json.stringify(path, .{}, writer);
            if (options.input_label) |label| {
                try writer.writeAll(",\"label\":");
                try std.json.stringify(label, .{}, writer);
            }
            if (options.input_purpose) |purpose| {
                try writer.writeAll(",\"purpose\":");
                try std.json.stringify(purpose, .{}, writer);
            }
            if (options.input_reason) |reason| {
                try writer.writeAll(",\"reason\":");
                try std.json.stringify(reason, .{}, writer);
            }
            if (options.input_max_bytes) |max_bytes| {
                try writer.print(",\"maxBytes\":{d}", .{max_bytes});
            }
            try writer.writeAll("}");
        }
        try writer.writeAll("]");
    }
    try writer.writeAll("}}");
}

fn failMissingValue(flag: []const u8) !noreturn {
    try std.io.getStdErr().writer().print("{s} requires a value\n", .{flag});
    std.process.exit(1);
}

fn parseInputMaxBytes(value: []const u8) !u64 {
    const parsed = std.fmt.parseUnsigned(u64, value, 10) catch {
        try std.io.getStdErr().writer().print("Invalid --input-max-bytes value: {s}\n", .{value});
        std.process.exit(1);
    };
    if (parsed == 0) {
        try std.io.getStdErr().writer().print("--input-max-bytes must be greater than 0\n", .{});
        std.process.exit(1);
    }
    return parsed;
}
