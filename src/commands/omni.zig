const std = @import("std");
const locator = @import("../engine/locator.zig");
const process = @import("../engine/process.zig");

pub const OmniOptions = struct {
    json: bool = false,
    debug: bool = false,
};

const usage =
    \\Usage: ghost omni <status|oracle|curiosity|hive|recursive> [options]
    \\
;

pub fn printHelp(writer: anytype) !void {
    try writer.writeAll(
        \\omni
        \\
        \\Usage: ghost omni <status|oracle|curiosity|hive|recursive> [options]
        \\
        \\Explicit Phase 4/5/6 control surfaces for the Ghost engine.
        \\
        \\Subcommands:
        \\  status     Render curiosity, hive, and recursive boot status
        \\  oracle     Run oracle.auto_fix on an explicit Zig test target
        \\  curiosity  Inspect curiosity guard/candidate status
        \\  hive       Inspect local Hive protocol/cache status
        \\  recursive  Measure recursive boot benchmark status
        \\
        \\Safety:
        \\  Explicit invocation only.
        \\  NON-AUTHORIZING.
        \\  Oracle auto-fix verifies temp candidates only; it does not mutate source.
        \\  Curiosity does not run in the background from this command.
        \\  Hive status does not join a network or send UDP packets.
        \\  Recursive boot status does not replace binaries or execve.
        \\  `--json` preserves raw single-operation engine stdout. For `status`,
        \\  JSON mode emits a CLI aggregate envelope over explicit GIP calls.
        \\
    );
}

pub fn printHelpForArgs(writer: anytype, args: []const []const u8) !void {
    if (args.len == 0) return printHelp(writer);
    if (std.mem.eql(u8, args[0], "oracle")) return printOracleHelp(writer);
    if (std.mem.eql(u8, args[0], "curiosity")) return printCuriosityHelp(writer);
    if (std.mem.eql(u8, args[0], "hive")) return printHiveHelp(writer);
    if (std.mem.eql(u8, args[0], "recursive")) return printRecursiveHelp(writer);
    return printHelp(writer);
}

fn printOracleHelp(writer: anytype) !void {
    try writer.writeAll(
        \\omni oracle
        \\
        \\Usage: ghost omni oracle --test-file <file.zig> [--cwd <dir>] [--max-cycles <n>] [--diagnostic-buffer-bytes <n>] [--json] [--debug]
        \\
        \\Runs GIP operation oracle.auto_fix. The engine captures Zig stderr,
        \\classifies deterministic diagnostics, and may verify temp-buffer
        \\candidate repairs. It does not edit the source target.
        \\
    );
}

fn printCuriosityHelp(writer: anytype) !void {
    try writer.writeAll(
        \\omni curiosity
        \\
        \\Usage: ghost omni curiosity [--concept <name>] [--zenith-priority] [--json] [--debug]
        \\
        \\Runs GIP operation curiosity.status. This is a read-only guard and
        \\candidate surface; it does not start a background worker.
        \\
    );
}

fn printHiveHelp(writer: anytype) !void {
    try writer.writeAll(
        \\omni hive
        \\
        \\Usage: ghost omni hive [--json] [--debug]
        \\
        \\Runs GIP operation hive.status. It does not join a network or send UDP.
        \\
    );
}

fn printRecursiveHelp(writer: anytype) !void {
    try writer.writeAll(
        \\omni recursive
        \\
        \\Usage: ghost omni recursive [--iterations <n>] [--json] [--debug]
        \\
        \\Runs GIP operation recursive_boot.status. It measures the local VSA bind
        \\path and does not generate, compile, or hot-swap a replacement binary.
        \\
    );
}

pub fn executeFromArgs(
    allocator: std.mem.Allocator,
    engine_root: ?[]const u8,
    args: []const []const u8,
    base: OmniOptions,
) !void {
    const sub = if (args.len > 0) args[0] else {
        try std.io.getStdErr().writer().writeAll(usage);
        std.process.exit(1);
    };
    if (std.mem.eql(u8, sub, "status")) return executeStatus(allocator, engine_root, base);
    if (std.mem.eql(u8, sub, "oracle")) return executeOracle(allocator, engine_root, args[1..], base);
    if (std.mem.eql(u8, sub, "curiosity")) return executeCuriosity(allocator, engine_root, args[1..], base);
    if (std.mem.eql(u8, sub, "hive")) return executeHive(allocator, engine_root, base);
    if (std.mem.eql(u8, sub, "recursive")) return executeRecursive(allocator, engine_root, args[1..], base);
    try std.io.getStdErr().writer().print("Unknown omni command: {s}\n{s}", .{ sub, usage });
    std.process.exit(1);
}

fn executeStatus(allocator: std.mem.Allocator, engine_root: ?[]const u8, options: OmniOptions) !void {
    const curiosity_payload = "{\"gipVersion\":\"gip.v0.1\",\"kind\":\"curiosity.status\"}";
    const hive_payload = "{\"gipVersion\":\"gip.v0.1\",\"kind\":\"hive.status\"}";
    const recursive_payload = "{\"gipVersion\":\"gip.v0.1\",\"kind\":\"recursive_boot.status\",\"iterations\":512}";

    const curiosity_json = try runGip(allocator, engine_root, "curiosity.status", curiosity_payload, options.debug);
    defer allocator.free(curiosity_json);
    const hive_json = try runGip(allocator, engine_root, "hive.status", hive_payload, options.debug);
    defer allocator.free(hive_json);
    const recursive_json = try runGip(allocator, engine_root, "recursive_boot.status", recursive_payload, options.debug);
    defer allocator.free(recursive_json);

    if (options.json) {
        const stdout = std.io.getStdOut().writer();
        try stdout.writeAll("{\"omniStatus\":[");
        try stdout.writeAll(curiosity_json);
        try stdout.writeByte(',');
        try stdout.writeAll(hive_json);
        try stdout.writeByte(',');
        try stdout.writeAll(recursive_json);
        try stdout.writeAll("]}\n");
        return;
    }

    try std.io.getStdOut().writer().writeAll("Ghost Omni Status\nState: EXPLICIT / NON-AUTHORIZING\n\n");
    try printCuriosityResult(std.io.getStdOut().writer(), try parseJsonValue(allocator, curiosity_json));
    try std.io.getStdOut().writer().writeByte('\n');
    try printHiveResult(std.io.getStdOut().writer(), try parseJsonValue(allocator, hive_json));
    try std.io.getStdOut().writer().writeByte('\n');
    try printRecursiveResult(std.io.getStdOut().writer(), try parseJsonValue(allocator, recursive_json));
}

fn executeOracle(allocator: std.mem.Allocator, engine_root: ?[]const u8, args: []const []const u8, options: OmniOptions) !void {
    var test_file: ?[]const u8 = null;
    var cwd: []const u8 = ".";
    var max_cycles: u64 = 5;
    var diagnostic_buffer_bytes: u64 = 64 * 1024;

    var i: usize = 0;
    while (i < args.len) : (i += 1) {
        const arg = args[i];
        if (std.mem.eql(u8, arg, "--test-file")) {
            i += 1;
            if (i >= args.len) try failMissingValue("--test-file");
            test_file = args[i];
        } else if (std.mem.startsWith(u8, arg, "--test-file=")) {
            test_file = arg["--test-file=".len..];
        } else if (std.mem.eql(u8, arg, "--cwd")) {
            i += 1;
            if (i >= args.len) try failMissingValue("--cwd");
            cwd = args[i];
        } else if (std.mem.startsWith(u8, arg, "--cwd=")) {
            cwd = arg["--cwd=".len..];
        } else if (std.mem.eql(u8, arg, "--max-cycles")) {
            i += 1;
            if (i >= args.len) try failMissingValue("--max-cycles");
            max_cycles = try parsePositiveU64("--max-cycles", args[i]);
        } else if (std.mem.startsWith(u8, arg, "--max-cycles=")) {
            max_cycles = try parsePositiveU64("--max-cycles", arg["--max-cycles=".len..]);
        } else if (std.mem.eql(u8, arg, "--diagnostic-buffer-bytes")) {
            i += 1;
            if (i >= args.len) try failMissingValue("--diagnostic-buffer-bytes");
            diagnostic_buffer_bytes = try parsePositiveU64("--diagnostic-buffer-bytes", args[i]);
        } else if (std.mem.startsWith(u8, arg, "--diagnostic-buffer-bytes=")) {
            diagnostic_buffer_bytes = try parsePositiveU64("--diagnostic-buffer-bytes", arg["--diagnostic-buffer-bytes=".len..]);
        } else if (std.mem.startsWith(u8, arg, "--")) {
            try std.io.getStdErr().writer().print("Unknown omni oracle option: {s}\n", .{arg});
            std.process.exit(1);
        } else if (test_file == null) {
            test_file = arg;
        } else {
            try std.io.getStdErr().writer().print("Unexpected omni oracle argument: {s}\n", .{arg});
            std.process.exit(1);
        }
    }

    const file = test_file orelse {
        try printOracleHelp(std.io.getStdErr().writer());
        std.process.exit(1);
    };

    var request = std.ArrayList(u8).init(allocator);
    defer request.deinit();
    const w = request.writer();
    try w.writeAll("{\"gipVersion\":\"gip.v0.1\",\"kind\":\"oracle.auto_fix\",\"cwd\":");
    try std.json.stringify(cwd, .{}, w);
    try w.writeAll(",\"testFile\":");
    try std.json.stringify(file, .{}, w);
    try w.print(",\"maxCycles\":{d},\"diagnosticBufferBytes\":{d}}}", .{ max_cycles, diagnostic_buffer_bytes });

    const response = try runGip(allocator, engine_root, "oracle.auto_fix", request.items, options.debug);
    defer allocator.free(response);
    if (options.json) return writeRaw(response);
    try printOracleResult(std.io.getStdOut().writer(), try parseJsonValue(allocator, response));
}

fn executeCuriosity(allocator: std.mem.Allocator, engine_root: ?[]const u8, args: []const []const u8, options: OmniOptions) !void {
    var concepts = std.ArrayList([]const u8).init(allocator);
    defer concepts.deinit();
    var zenith_priority = false;

    var i: usize = 0;
    while (i < args.len) : (i += 1) {
        const arg = args[i];
        if (std.mem.eql(u8, arg, "--concept")) {
            i += 1;
            if (i >= args.len) try failMissingValue("--concept");
            try concepts.append(args[i]);
        } else if (std.mem.startsWith(u8, arg, "--concept=")) {
            try concepts.append(arg["--concept=".len..]);
        } else if (std.mem.eql(u8, arg, "--zenith-priority")) {
            zenith_priority = true;
        } else if (std.mem.startsWith(u8, arg, "--")) {
            try std.io.getStdErr().writer().print("Unknown omni curiosity option: {s}\n", .{arg});
            std.process.exit(1);
        } else {
            try concepts.append(arg);
        }
    }

    var request = std.ArrayList(u8).init(allocator);
    defer request.deinit();
    const w = request.writer();
    try w.writeAll("{\"gipVersion\":\"gip.v0.1\",\"kind\":\"curiosity.status\"");
    if (zenith_priority) try w.writeAll(",\"zenithAudioPriorityRequested\":true");
    if (concepts.items.len != 0) {
        try w.writeAll(",\"concepts\":[");
        for (concepts.items, 0..) |concept, idx| {
            if (idx != 0) try w.writeByte(',');
            try std.json.stringify(concept, .{}, w);
        }
        try w.writeByte(']');
    }
    try w.writeByte('}');

    const response = try runGip(allocator, engine_root, "curiosity.status", request.items, options.debug);
    defer allocator.free(response);
    if (options.json) return writeRaw(response);
    try printCuriosityResult(std.io.getStdOut().writer(), try parseJsonValue(allocator, response));
}

fn executeHive(allocator: std.mem.Allocator, engine_root: ?[]const u8, options: OmniOptions) !void {
    const response = try runGip(allocator, engine_root, "hive.status", "{\"gipVersion\":\"gip.v0.1\",\"kind\":\"hive.status\"}", options.debug);
    defer allocator.free(response);
    if (options.json) return writeRaw(response);
    try printHiveResult(std.io.getStdOut().writer(), try parseJsonValue(allocator, response));
}

fn executeRecursive(allocator: std.mem.Allocator, engine_root: ?[]const u8, args: []const []const u8, options: OmniOptions) !void {
    var iterations: u64 = 4096;
    var i: usize = 0;
    while (i < args.len) : (i += 1) {
        const arg = args[i];
        if (std.mem.eql(u8, arg, "--iterations")) {
            i += 1;
            if (i >= args.len) try failMissingValue("--iterations");
            iterations = try parsePositiveU64("--iterations", args[i]);
        } else if (std.mem.startsWith(u8, arg, "--iterations=")) {
            iterations = try parsePositiveU64("--iterations", arg["--iterations=".len..]);
        } else if (std.mem.startsWith(u8, arg, "--")) {
            try std.io.getStdErr().writer().print("Unknown omni recursive option: {s}\n", .{arg});
            std.process.exit(1);
        } else {
            try std.io.getStdErr().writer().print("Unexpected omni recursive argument: {s}\n", .{arg});
            std.process.exit(1);
        }
    }

    var request = std.ArrayList(u8).init(allocator);
    defer request.deinit();
    try request.writer().print("{{\"gipVersion\":\"gip.v0.1\",\"kind\":\"recursive_boot.status\",\"iterations\":{d}}}", .{iterations});
    const response = try runGip(allocator, engine_root, "recursive_boot.status", request.items, options.debug);
    defer allocator.free(response);
    if (options.json) return writeRaw(response);
    try printRecursiveResult(std.io.getStdOut().writer(), try parseJsonValue(allocator, response));
}

fn runGip(allocator: std.mem.Allocator, engine_root: ?[]const u8, kind: []const u8, request: []const u8, debug: bool) ![]u8 {
    const bin_path = locator.findEngineBinary(allocator, engine_root, .ghost_gip) catch |err| {
        try locator.printLocatorError(std.io.getStdErr().writer(), .ghost_gip, engine_root, err);
        std.process.exit(1);
    };
    defer allocator.free(bin_path);

    const argv = &[_][]const u8{ bin_path, "--stdin" };
    if (debug) {
        try std.io.getStdErr().writer().print("[DEBUG] Engine Binary: {s}\n", .{bin_path});
        try std.io.getStdErr().writer().print("[DEBUG] GIP Kind: {s}\n", .{kind});
        try std.io.getStdErr().writer().print("[DEBUG] Stdin Byte Count: {d}\n", .{request.len});
    }
    const result = process.runEngineCommandWithInput(allocator, argv, request) catch |err| {
        try std.io.getStdErr().writer().print("Error: failed to execute {s}: {s}\n", .{ kind, @errorName(err) });
        std.process.exit(1);
    };
    defer {
        allocator.free(result.stderr);
    }
    if (debug) try std.io.getStdErr().writer().print("[DEBUG] Exit Code: {d}\n", .{result.exit_code});
    if (result.exit_code != 0) {
        try std.io.getStdErr().writer().print("Engine Error ({d}) while executing {s}\n", .{ result.exit_code, kind });
        if (result.stdout.len != 0) try std.io.getStdErr().writer().writeAll(result.stdout);
        allocator.free(result.stdout);
        std.process.exit(result.exit_code);
    }
    return result.stdout;
}

const ParsedValue = struct {
    parsed: std.json.Parsed(std.json.Value),

    fn deinit(self: *ParsedValue) void {
        self.parsed.deinit();
    }
};

fn parseJsonValue(allocator: std.mem.Allocator, bytes: []const u8) !ParsedValue {
    return .{ .parsed = try std.json.parseFromSlice(std.json.Value, allocator, bytes, .{}) };
}

fn writeRaw(bytes: []const u8) !void {
    try std.io.getStdOut().writer().writeAll(bytes);
    if (bytes.len == 0 or bytes[bytes.len - 1] != '\n') try std.io.getStdOut().writer().writeByte('\n');
}

fn printOracleResult(writer: anytype, parsed_value: ParsedValue) !void {
    var owned = parsed_value;
    defer owned.deinit();
    const obj = resultObject(owned.parsed.value, "autoFix") orelse {
        try writer.writeAll("Oracle Auto-Fix Result\nRaw engine response did not include autoFix.\n");
        return;
    };
    try writer.writeAll("Oracle Auto-Fix Result\nState: TEMP-CANDIDATE / NON-AUTHORIZING\n");
    try printStringField(writer, obj, "status", "Status");
    try printStringField(writer, obj, "finalTier", "Final Tier");
    try printBoolField(writer, obj, "candidateVerified", "Candidate Verified");
    try printBoolField(writer, obj, "unstableCoordinates", "Unstable Coordinates");
    try printIntField(writer, obj, "cycleCount", "Cycles");
    try writer.writeAll("Source Mutation: false\n");
}

fn printCuriosityResult(writer: anytype, parsed_value: ParsedValue) !void {
    var owned = parsed_value;
    defer owned.deinit();
    const obj = resultObject(owned.parsed.value, "curiosity") orelse {
        try writer.writeAll("Curiosity Status\nRaw engine response did not include curiosity.\n");
        return;
    };
    try writer.writeAll("Curiosity Status\nState: READ-ONLY / NON-AUTHORIZING\n");
    try printStringField(writer, obj, "status", "Status");
    if (objectField(obj, "guard")) |guard| {
        try printBoolField(writer, guard, "canRun", "Guard Can Run");
        try printBoolField(writer, guard, "zenithAudioPriorityRequested", "Zenith Priority Requested");
    }
    try printArrayCount(writer, obj, "coldZones", "Cold Zones");
    try printArrayCount(writer, obj, "speculativeInventions", "Speculative Inventions");
}

fn printHiveResult(writer: anytype, parsed_value: ParsedValue) !void {
    var owned = parsed_value;
    defer owned.deinit();
    const obj = resultObject(owned.parsed.value, "hive") orelse {
        try writer.writeAll("Hive Status\nRaw engine response did not include hive.\n");
        return;
    };
    try writer.writeAll("Hive Status\nState: OFFLINE-READY / NON-AUTHORIZING\n");
    try printStringField(writer, obj, "status", "Status");
    try printBoolField(writer, obj, "networkEnabledByDefault", "Network Enabled By Default");
    try printIntField(writer, obj, "remoteCacheTier", "Remote Cache Tier");
    try printBoolField(writer, obj, "localOracleGateRequired", "Local Oracle Gate Required");
}

fn printRecursiveResult(writer: anytype, parsed_value: ParsedValue) !void {
    var owned = parsed_value;
    defer owned.deinit();
    const obj = resultObject(owned.parsed.value, "recursiveBoot") orelse {
        try writer.writeAll("Recursive Boot Status\nRaw engine response did not include recursiveBoot.\n");
        return;
    };
    try writer.writeAll("Recursive Boot Status\nState: MEASUREMENT-ONLY / NON-AUTHORIZING\n");
    try printStringField(writer, obj, "status", "Status");
    try printBoolField(writer, obj, "hotSwapEnabledByDefault", "Hot Swap Enabled By Default");
    if (objectField(obj, "benchmark")) |bench| {
        try printIntField(writer, bench, "nsPerOperation", "ns Per Operation");
    }
    if (objectField(obj, "swapDecision")) |decision| {
        try printBoolField(writer, decision, "shouldSwap", "Should Swap");
    }
}

fn resultObject(value: std.json.Value, field: []const u8) ?std.json.ObjectMap {
    if (value != .object) return null;
    const result = value.object.get("result") orelse return null;
    if (result != .object) return null;
    const inner = result.object.get(field) orelse return null;
    return if (inner == .object) inner.object else null;
}

fn objectField(obj: std.json.ObjectMap, field: []const u8) ?std.json.ObjectMap {
    const value = obj.get(field) orelse return null;
    return if (value == .object) value.object else null;
}

fn printStringField(writer: anytype, obj: std.json.ObjectMap, field: []const u8, label: []const u8) !void {
    const value = obj.get(field) orelse return;
    if (value == .string) try writer.print("{s}: {s}\n", .{ label, value.string });
}

fn printBoolField(writer: anytype, obj: std.json.ObjectMap, field: []const u8, label: []const u8) !void {
    const value = obj.get(field) orelse return;
    if (value == .bool) try writer.print("{s}: {s}\n", .{ label, if (value.bool) "true" else "false" });
}

fn printIntField(writer: anytype, obj: std.json.ObjectMap, field: []const u8, label: []const u8) !void {
    const value = obj.get(field) orelse return;
    if (value == .integer) try writer.print("{s}: {d}\n", .{ label, value.integer });
}

fn printArrayCount(writer: anytype, obj: std.json.ObjectMap, field: []const u8, label: []const u8) !void {
    const value = obj.get(field) orelse return;
    if (value == .array) try writer.print("{s}: {d}\n", .{ label, value.array.items.len });
}

fn parsePositiveU64(flag: []const u8, raw: []const u8) !u64 {
    const value = std.fmt.parseUnsigned(u64, raw, 10) catch {
        try std.io.getStdErr().writer().print("{s} must be a positive integer, got: {s}\n", .{ flag, raw });
        std.process.exit(1);
    };
    if (value == 0) {
        try std.io.getStdErr().writer().print("{s} must be greater than zero\n", .{flag});
        std.process.exit(1);
    }
    return value;
}

fn failMissingValue(flag: []const u8) !void {
    try std.io.getStdErr().writer().print("{s} requires a value\n", .{flag});
    std.process.exit(1);
}
