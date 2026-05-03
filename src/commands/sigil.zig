const std = @import("std");
const locator = @import("../engine/locator.zig");
const process = @import("../engine/process.zig");

pub const SigilOptions = struct {
    file_path: ?[]const u8 = null,
    json: bool = false,
    debug: bool = false,
};

const max_request_bytes = 1024 * 1024;
const usage = "Usage: ghost sigil inspect --file <request.json> [--json] [--debug]\n";

pub fn printHelp(writer: anytype) !void {
    try writer.print(
        \\sigil
        \\
        \\Usage: ghost sigil inspect --file <request.json> [--json] [--debug]
        \\
        \\Advanced/debug command group for explicit Sigil inspection.
        \\
        \\Subcommands:
        \\  inspect --file <request.json>  Run a sigil.inspect GIP request
        \\
        \\Safety:
        \\  This request runs only when this command is explicitly invoked.
        \\  Request files must be GIP-compatible JSON with kind "sigil.inspect".
        \\  Sigil inspection compiles, validates, disassembles, and renders
        \\  procedure inspection records without VM execution.
        \\  Output is READ-ONLY / NON-AUTHORIZING / CANDIDATE ONLY.
        \\  NOT PROOF.
        \\  NOT SUPPORT.
        \\  VM CODE NOT EXECUTED.
        \\  COMMANDS NOT EXECUTED.
        \\  PACKS / CORPUS / NEGATIVE KNOWLEDGE / SCRATCH STATE NOT MUTATED.
        \\  `--json` preserves raw engine stdout exactly.
        \\  `--debug` writes diagnostics to stderr only.
        \\
    , .{});
}

pub fn printHelpForArgs(writer: anytype, args: []const []const u8) !void {
    if (args.len == 0) return printHelp(writer);
    if (std.mem.eql(u8, args[0], "inspect")) return printInspectHelp(writer);
    return printHelp(writer);
}

fn printInspectHelp(writer: anytype) !void {
    try writer.print(
        \\sigil inspect
        \\
        \\Usage: ghost sigil inspect --file <request.json> [--json] [--debug]
        \\
        \\Reads a GIP-compatible Sigil inspection request from a file and sends it
        \\unchanged to ghost_gip --stdin. The request must include kind "sigil.inspect".
        \\
        \\Options:
        \\  --file <request.json>     Sigil inspection GIP request file
        \\  --json                    Preserve raw GIP stdout exactly
        \\  --debug                   Diagnostics to stderr
        \\
        \\Safety:
        \\  Explicit invocation only.
        \\  Read-only compiled-bytecode and procedure-record inspection.
        \\  Procedure inspection records are candidates only.
        \\  NOT PROOF.
        \\  NOT SUPPORT.
        \\  VM CODE NOT EXECUTED.
        \\  COMMANDS NOT EXECUTED.
        \\  NO MUTATION.
        \\
    , .{});
}

pub fn executeFromArgs(
    allocator: std.mem.Allocator,
    engine_root: ?[]const u8,
    args: []const []const u8,
    base: SigilOptions,
) !void {
    const sub = if (args.len > 0) args[0] else {
        try std.io.getStdErr().writer().print("{s}", .{usage});
        std.process.exit(1);
    };
    if (!std.mem.eql(u8, sub, "inspect")) {
        try std.io.getStdErr().writer().print("Unknown sigil command: {s}\n{s}", .{ sub, usage });
        std.process.exit(1);
    }

    var options = base;
    var i: usize = 1;
    while (i < args.len) : (i += 1) {
        const arg = args[i];
        if (std.mem.eql(u8, arg, "--file")) {
            i += 1;
            if (i >= args.len) try failMissingValue("--file");
            options.file_path = args[i];
        } else if (std.mem.startsWith(u8, arg, "--file=")) {
            const value = arg["--file=".len..];
            if (value.len == 0) try failMissingValue("--file");
            options.file_path = value;
        } else if (std.mem.startsWith(u8, arg, "--")) {
            try std.io.getStdErr().writer().print("Unknown sigil inspect option: {s}\n", .{arg});
            std.process.exit(1);
        } else {
            try std.io.getStdErr().writer().print("Unexpected sigil inspect argument: {s}\n", .{arg});
            std.process.exit(1);
        }
    }

    try executeInspect(allocator, engine_root, options);
}

pub fn executeInspect(allocator: std.mem.Allocator, engine_root: ?[]const u8, options: SigilOptions) !void {
    const file_path = options.file_path orelse {
        try std.io.getStdErr().writer().print("{s}", .{usage});
        std.process.exit(1);
    };
    if (std.mem.trim(u8, file_path, " \r\n\t").len == 0) {
        try std.io.getStdErr().writer().print("sigil inspect --file must be non-empty\n", .{});
        std.process.exit(1);
    }

    const request = std.fs.cwd().readFileAlloc(allocator, file_path, max_request_bytes) catch |err| {
        try std.io.getStdErr().writer().print("Error: failed to read sigil.inspect request file '{s}': {s}\n", .{ file_path, @errorName(err) });
        std.process.exit(1);
    };
    defer allocator.free(request);

    var parsed = std.json.parseFromSlice(std.json.Value, allocator, request, .{}) catch |err| {
        if (options.debug) try std.io.getStdErr().writer().print("[DEBUG] Parse Status: FAILED ({s})\n", .{@errorName(err)});
        try std.io.getStdErr().writer().print("Error: sigil.inspect request file is not valid JSON: {s}\n", .{@errorName(err)});
        std.process.exit(1);
    };
    defer parsed.deinit();

    if (!hasSigilInspectKind(parsed.value)) {
        if (options.debug) try std.io.getStdErr().writer().print("[DEBUG] Parse Status: FAILED (kind mismatch)\n", .{});
        try std.io.getStdErr().writer().print("Error: request file must contain top-level kind \"sigil.inspect\".\n", .{});
        std.process.exit(1);
    }

    const bin_path = locator.findEngineBinary(allocator, engine_root, .ghost_gip) catch |err| {
        try locator.printLocatorError(std.io.getStdErr().writer(), .ghost_gip, engine_root, err);
        std.process.exit(1);
    };
    defer allocator.free(bin_path);

    const argv = &[_][]const u8{ bin_path, "--stdin" };
    if (options.debug) {
        try std.io.getStdErr().writer().print("[DEBUG] Engine Binary: {s}\n", .{bin_path});
        try std.io.getStdErr().writer().print("[DEBUG] GIP Kind: sigil.inspect\n", .{});
        try std.io.getStdErr().writer().print("[DEBUG] Input File: {s}\n", .{file_path});
        try std.io.getStdErr().writer().print("[DEBUG] Stdin Byte Count: {d}\n", .{request.len});
    }

    const result = process.runEngineCommandWithInput(allocator, argv, request) catch |err| {
        try std.io.getStdErr().writer().print("\x1b[31m[!] Error:\x1b[0m Failed to execute sigil.inspect: {}\n", .{err});
        try std.io.getStdErr().writer().print("\x1b[33mHint:\x1b[0m Run `ghost status` to verify your environment.\n", .{});
        std.process.exit(1);
    };
    defer {
        allocator.free(result.stdout);
        allocator.free(result.stderr);
    }

    if (options.debug) try std.io.getStdErr().writer().print("[DEBUG] Exit Code: {d}\n", .{result.exit_code});

    if (options.json) {
        if (options.debug) try std.io.getStdErr().writer().print("[DEBUG] Parse Status: SKIPPED (raw passthrough)\n", .{});
        try std.io.getStdOut().writer().writeAll(result.stdout);
        if (result.stderr.len > 0) try std.io.getStdErr().writer().writeAll(result.stderr);
        if (result.exit_code != 0) std.process.exit(result.exit_code);
        return;
    }

    if (result.exit_code != 0) {
        try std.io.getStdErr().writer().print("\x1b[31m[!] Engine Error (Exit Code {d}):\x1b[0m\n", .{result.exit_code});
        if (result.stderr.len > 0) {
            try std.io.getStdErr().writer().writeAll(result.stderr);
            if (result.stderr[result.stderr.len - 1] != '\n') try std.io.getStdErr().writer().writeByte('\n');
        } else if (result.stdout.len > 0) {
            try std.io.getStdErr().writer().writeAll(result.stdout);
            if (result.stdout[result.stdout.len - 1] != '\n') try std.io.getStdErr().writer().writeByte('\n');
        }
        std.process.exit(result.exit_code);
    }

    var out_parsed = std.json.parseFromSlice(std.json.Value, allocator, result.stdout, .{}) catch |err| {
        if (options.debug) try std.io.getStdErr().writer().print("[DEBUG] Parse Status: FAILED ({s})\n", .{@errorName(err)});
        try std.io.getStdErr().writer().print("Error: Failed to parse engine output as sigil.inspect JSON.\n", .{});
        try std.io.getStdErr().writer().print("Raw output:\n{s}\n", .{result.stdout});
        return;
    };
    defer out_parsed.deinit();

    if (options.debug) try std.io.getStdErr().writer().print("[DEBUG] Parse Status: ok\n", .{});

    try printSigilInspectionResult(std.io.getStdOut().writer(), out_parsed.value);
}

fn hasSigilInspectKind(value: std.json.Value) bool {
    const obj = switch (value) {
        .object => |o| o,
        else => return false,
    };
    const kind = obj.get("kind") orelse return false;
    return switch (kind) {
        .string => |s| std.mem.eql(u8, s, "sigil.inspect"),
        else => false,
    };
}

fn printSigilInspectionResult(writer: anytype, value: std.json.Value) !void {
    try writer.print("Sigil Inspection Result\n", .{});
    try writer.print("State: READ-ONLY / NON-AUTHORIZING / CANDIDATE ONLY\n", .{});
    try writer.print("PROCEDURE INSPECTION RECORDS ARE CANDIDATES ONLY\n", .{});
    try writer.print("NOT PROOF\n", .{});
    try writer.print("NOT SUPPORT\n", .{});
    try writer.print("VM CODE NOT EXECUTED\n", .{});
    try writer.print("COMMANDS NOT EXECUTED\n", .{});
    try writer.print("NO MUTATION\n\n", .{});

    if (findError(value)) |err_value| {
        try writer.print("Engine Rejected Request:\n", .{});
        try printJsonValue(writer, err_value, 2);
        try writer.print("\n", .{});
    }

    const inspection_value = findSigilInspection(value) orelse {
        try writer.print("No sigilInspection result payload was present.\n", .{});
        return;
    };

    const inspection = switch (inspection_value) {
        .object => |obj| obj,
        else => {
            try printJsonValue(writer, inspection_value, 2);
            try writer.print("\n", .{});
            return;
        },
    };

    try printStringField(writer, inspection, "status", "Inspection Status");
    try printIntField(writer, inspection, "sourceBytes", "Source Bytes");
    try printIntField(writer, inspection, "instructionCount", "Instruction Count");
    try printIntField(writer, inspection, "stringCount", "String Count");

    if (inspection.get("validation")) |validation| {
        try writer.print("\nValidation:\n", .{});
        try printJsonValue(writer, validation, 2);
        try writer.print("\n", .{});
    }

    if (inspection.get("safety")) |safety| {
        try writer.print("Safety:\n", .{});
        try printJsonValue(writer, safety, 2);
        try writer.print("\n", .{});
    } else {
        try writer.print("Safety: not supplied by engine; CLI does not infer support.\n\n", .{});
    }

    try printSection(writer, inspection, "procedureInspectionRecords", "Procedure Inspection Records / CANDIDATE ONLY");
    try printSection(writer, inspection, "instructions", "Instructions / DISASSEMBLY ONLY");

    if (inspection.get("disassemblyText")) |text| {
        if (text != .null) {
            try writer.print("\nDisassembly Text:\n", .{});
            try printJsonValue(writer, text, 2);
            try writer.print("\n", .{});
        }
    }

    try writer.print("\nNotice: sigil.inspect is read-only compiled-bytecode inspection. Procedure records are candidate-only and do not constitute proof, support, evidence, or authorization. The CLI does not execute VM code, execute commands, mutate state, or promote status from ok/validation text.\n", .{});
}

fn findSigilInspection(value: std.json.Value) ?std.json.Value {
    const obj = switch (value) {
        .object => |o| o,
        else => return null,
    };
    if (obj.get("sigilInspection")) |inspection| return inspection;
    if (obj.get("sigil_inspection")) |inspection| return inspection;
    if (obj.get("result")) |result| {
        const result_obj = switch (result) {
            .object => |o| o,
            else => return result,
        };
        if (result_obj.get("sigilInspection")) |inspection| return inspection;
        if (result_obj.get("sigil_inspection")) |inspection| return inspection;
        return result;
    }
    return null;
}

fn findError(value: std.json.Value) ?std.json.Value {
    const obj = switch (value) {
        .object => |o| o,
        else => return null,
    };
    if (obj.get("error")) |err| return err;
    if (obj.get("err")) |err| return err;
    if (obj.get("status")) |status| {
        if (status == .string and std.mem.eql(u8, status.string, "rejected")) return value;
    }
    return null;
}

fn printSection(writer: anytype, obj: std.json.ObjectMap, field: []const u8, label: []const u8) !void {
    const value = obj.get(field) orelse return;
    if (isEmptyJsonList(value)) return;
    try writer.print("\n{s}:\n", .{label});
    try printJsonValue(writer, value, 2);
    try writer.print("\n", .{});
}

fn printStringField(writer: anytype, obj: std.json.ObjectMap, field: []const u8, label: []const u8) !void {
    const value = obj.get(field) orelse return;
    switch (value) {
        .string => |s| try writer.print("{s}: {s}\n", .{ label, s }),
        else => {},
    }
}

fn printIntField(writer: anytype, obj: std.json.ObjectMap, field: []const u8, label: []const u8) !void {
    const value = obj.get(field) orelse return;
    switch (value) {
        .integer => |i| try writer.print("{s}: {d}\n", .{ label, i }),
        else => {},
    }
}

fn isEmptyJsonList(value: std.json.Value) bool {
    return switch (value) {
        .array => |arr| arr.items.len == 0,
        .object => |obj| obj.count() == 0,
        else => false,
    };
}

fn printJsonValue(writer: anytype, value: std.json.Value, indent: usize) !void {
    switch (value) {
        .string => |s| try writer.print("{s}", .{s}),
        .integer => |i| try writer.print("{d}", .{i}),
        .float => |f| try writer.print("{d}", .{f}),
        .bool => |b| try writer.print("{s}", .{if (b) "true" else "false"}),
        .null => try writer.print("null", .{}),
        .array => |arr| {
            for (arr.items) |item| {
                try printIndent(writer, indent);
                try writer.print("- ", .{});
                try printJsonValue(writer, item, indent + 2);
                try writer.print("\n", .{});
            }
        },
        .object => |obj| {
            var it = obj.iterator();
            while (it.next()) |entry| {
                try printIndent(writer, indent);
                try writer.print("{s}: ", .{entry.key_ptr.*});
                try printJsonValue(writer, entry.value_ptr.*, indent + 2);
                try writer.print("\n", .{});
            }
        },
        else => try writer.print("{}", .{value}),
    }
}

fn printIndent(writer: anytype, indent: usize) !void {
    var i: usize = 0;
    while (i < indent) : (i += 1) {
        try writer.print(" ", .{});
    }
}

fn failMissingValue(flag: []const u8) !noreturn {
    try std.io.getStdErr().writer().print("{s} requires a value\n", .{flag});
    std.process.exit(1);
}
