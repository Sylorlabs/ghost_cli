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

pub fn executeAutopsy(allocator: std.mem.Allocator, engine_root: ?[]const u8, options: ContextAutopsyOptions) !void {
    const description = options.description orelse {
        try std.io.getStdErr().writer().print("Usage: ghost context autopsy [--json] [--debug] [--input-file <path>] [--input-max-bytes <bytes>] <description>\n", .{});
        std.process.exit(1);
    };
    if (description.len == 0) {
        try std.io.getStdErr().writer().print("Usage: ghost context autopsy [--json] [--debug] [--input-file <path>] [--input-max-bytes <bytes>] <description>\n", .{});
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
