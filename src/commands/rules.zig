const std = @import("std");
const locator = @import("../engine/locator.zig");
const process = @import("../engine/process.zig");

pub const RulesOptions = struct {
    file_path: ?[]const u8 = null,
    json: bool = false,
    debug: bool = false,
};

const max_request_bytes = 1024 * 1024;
const usage = "Usage: ghost rules evaluate --file <request.json> [--json] [--debug]\n";

pub fn printHelp(writer: anytype) !void {
    try writer.print(
        \\rules
        \\
        \\Usage: ghost rules evaluate --file <request.json> [--json] [--debug]
        \\
        \\Advanced/debug command group for explicit deterministic rule evaluation.
        \\
        \\Subcommands:
        \\  evaluate --file <request.json>  Run a rule.evaluate GIP request
        \\
        \\Safety:
        \\  This request runs only when this command is explicitly invoked.
        \\  Request files must be GIP-compatible JSON with kind "rule.evaluate".
        \\  Rule evaluation is deterministic, bounded, and read-only.
        \\  It is structural matching only: no recursive inference, no Prolog,
        \\  no Transformers, embeddings, model adapters, semantic search, or network calls.
        \\  RULE OUTPUTS ARE CANDIDATES ONLY.
        \\  Capacity telemetry is explicit: capped or rejected rule outputs mean
        \\  incomplete candidate evaluation, not proof or support.
        \\  NOT PROOF.
        \\  VERIFIERS NOT EXECUTED.
        \\  PACKS / CORPUS / NEGATIVE KNOWLEDGE NOT MUTATED.
        \\  `--json` preserves raw engine stdout exactly.
        \\  `--debug` writes diagnostics to stderr only.
        \\
    , .{});
}

pub fn printHelpForArgs(writer: anytype, args: []const []const u8) !void {
    if (args.len == 0) return printHelp(writer);
    if (std.mem.eql(u8, args[0], "evaluate")) return printEvaluateHelp(writer);
    return printHelp(writer);
}

fn printEvaluateHelp(writer: anytype) !void {
    try writer.print(
        \\rules evaluate
        \\
        \\Usage: ghost rules evaluate --file <request.json> [--json] [--debug]
        \\
        \\Reads a GIP-compatible rule evaluation request from a file and sends it
        \\unchanged to ghost_gip --stdin. The request must include kind "rule.evaluate".
        \\
        \\Options:
        \\  --file <request.json>     Rule evaluation GIP request file
        \\  --json                    Preserve raw GIP stdout exactly
        \\  --debug                   Diagnostics to stderr
        \\
        \\Safety:
        \\  Explicit invocation only.
        \\  Deterministic bounded rule evaluation over request-local facts/rules.
        \\  No recursive inference / no Prolog.
        \\  RULE OUTPUTS ARE CANDIDATES ONLY.
        \\  Capacity warnings mean incomplete candidate evaluation.
        \\  NOT PROOF.
        \\  VERIFIERS NOT EXECUTED.
        \\  PACKS / CORPUS / NEGATIVE KNOWLEDGE NOT MUTATED.
        \\  No Transformers / embeddings / semantic search.
        \\
    , .{});
}

pub fn executeFromArgs(
    allocator: std.mem.Allocator,
    engine_root: ?[]const u8,
    args: []const []const u8,
    base: RulesOptions,
) !void {
    const sub = if (args.len > 0) args[0] else {
        try std.io.getStdErr().writer().print("{s}", .{usage});
        std.process.exit(1);
    };
    if (!std.mem.eql(u8, sub, "evaluate")) {
        try std.io.getStdErr().writer().print("Unknown rules command: {s}\n{s}", .{ sub, usage });
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
            try std.io.getStdErr().writer().print("Unknown rules evaluate option: {s}\n", .{arg});
            std.process.exit(1);
        } else {
            try std.io.getStdErr().writer().print("Unexpected rules evaluate argument: {s}\n", .{arg});
            std.process.exit(1);
        }
    }

    try executeEvaluate(allocator, engine_root, options);
}

pub fn executeEvaluate(allocator: std.mem.Allocator, engine_root: ?[]const u8, options: RulesOptions) !void {
    const file_path = options.file_path orelse {
        try std.io.getStdErr().writer().print("{s}", .{usage});
        std.process.exit(1);
    };
    if (std.mem.trim(u8, file_path, " \r\n\t").len == 0) {
        try std.io.getStdErr().writer().print("rules evaluate --file must be non-empty\n", .{});
        std.process.exit(1);
    }

    const request = std.fs.cwd().readFileAlloc(allocator, file_path, max_request_bytes) catch |err| {
        try std.io.getStdErr().writer().print("Error: failed to read rule.evaluate request file '{s}': {s}\n", .{ file_path, @errorName(err) });
        std.process.exit(1);
    };
    defer allocator.free(request);

    var parsed = std.json.parseFromSlice(std.json.Value, allocator, request, .{}) catch |err| {
        if (options.debug) try std.io.getStdErr().writer().print("[DEBUG] Parse Status: FAILED ({s})\n", .{@errorName(err)});
        try std.io.getStdErr().writer().print("Error: rule.evaluate request file is not valid JSON: {s}\n", .{@errorName(err)});
        std.process.exit(1);
    };
    defer parsed.deinit();

    if (!hasRuleEvaluateKind(parsed.value)) {
        if (options.debug) try std.io.getStdErr().writer().print("[DEBUG] Parse Status: FAILED (kind mismatch)\n", .{});
        try std.io.getStdErr().writer().print("Error: request file must contain top-level kind \"rule.evaluate\".\n", .{});
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
        try std.io.getStdErr().writer().print("[DEBUG] GIP Kind: rule.evaluate\n", .{});
        try std.io.getStdErr().writer().print("[DEBUG] Input File: {s}\n", .{file_path});
        try std.io.getStdErr().writer().print("[DEBUG] Stdin Byte Count: {d}\n", .{request.len});
    }

    const result = process.runEngineCommandWithInput(allocator, argv, request) catch |err| {
        try std.io.getStdErr().writer().print("\x1b[31m[!] Error:\x1b[0m Failed to execute rule.evaluate: {}\n", .{err});
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
        try std.io.getStdErr().writer().print("Error: Failed to parse engine output as rule.evaluate JSON.\n", .{});
        try std.io.getStdErr().writer().print("Raw output:\n{s}\n", .{result.stdout});
        return;
    };
    defer out_parsed.deinit();

    if (options.debug) try std.io.getStdErr().writer().print("[DEBUG] Parse Status: ok\n", .{});

    try printRuleEvaluationResult(std.io.getStdOut().writer(), out_parsed.value);
}

fn hasRuleEvaluateKind(value: std.json.Value) bool {
    const obj = switch (value) {
        .object => |o| o,
        else => return false,
    };
    const kind = obj.get("kind") orelse return false;
    return switch (kind) {
        .string => |s| std.mem.eql(u8, s, "rule.evaluate"),
        else => false,
    };
}

fn printRuleEvaluationResult(writer: anytype, value: std.json.Value) !void {
    try writer.print("Rule Evaluation Result\n", .{});
    try writer.print("State: DRAFT / NON-AUTHORIZING\n", .{});
    try writer.print("RULE OUTPUTS ARE CANDIDATES ONLY\n", .{});
    try writer.print("NOT PROOF\n", .{});
    try writer.print("VERIFIERS NOT EXECUTED\n", .{});
    try writer.print("PACKS / CORPUS / NEGATIVE KNOWLEDGE NOT MUTATED\n\n", .{});

    if (findError(value)) |err_value| {
        try writer.print("Engine Rejected Request:\n", .{});
        try printJsonValue(writer, err_value, 2);
        try writer.print("\n", .{});
        return;
    }

    const rule_value = findRuleEvaluation(value) orelse {
        try writer.print("No ruleEvaluation result payload was present.\n", .{});
        return;
    };

    const rule = switch (rule_value) {
        .object => |obj| obj,
        else => {
            try printJsonValue(writer, rule_value, 2);
            try writer.print("\n", .{});
            return;
        },
    };

    try printBoolField(writer, rule, "nonAuthorizing", "Non-Authorizing");
    try printBoolField(writer, rule, "candidateOnly", "Candidate Only");
    try printBoolField(writer, rule, "proofDischarged", "Proof Discharged");
    try printBoolField(writer, rule, "supportGranted", "Support Granted");
    try printIntField(writer, rule, "factsConsidered", "Facts Considered");
    try printIntField(writer, rule, "rulesConsidered", "Rules Considered");
    try printIntField(writer, rule, "outputsEmitted", "Outputs Emitted");
    try printBoolField(writer, rule, "budgetExhausted", "Budget Exhausted");

    if (rule.get("capacityTelemetry")) |telemetry| {
        if (hasCapacityPressure(telemetry)) try printRuleCapacityWarning(writer, telemetry);
    }

    try printSection(writer, rule, "firedRules", "Fired Rules");
    try printSection(writer, rule, "emittedCandidates", "Emitted Candidates");
    try printSection(writer, rule, "emittedObligations", "Emitted Obligations");
    try printSection(writer, rule, "emittedUnknowns", "Unknowns");
    try printSection(writer, rule, "explanationTrace", "Explanation Trace");
    try printSection(writer, rule, "safetyFlags", "Safety Flags");

    try writer.print("\nNotice: rule.evaluate is deterministic bounded rule matching only. It does not infer recursive facts, execute verifiers, mutate packs/corpus/negative knowledge, or grant proof/support.\n", .{});
}

fn printRuleCapacityWarning(writer: anytype, telemetry: std.json.Value) !void {
    try writer.print("\nRULE CAPACITY WARNING / NON-AUTHORIZING\n", .{});
    try writer.print("- Rule outputs are candidates only.\n", .{});
    try writer.print("- Capacity-limited rule evaluation is incomplete.\n", .{});
    try writer.print("- No proof/support gate was discharged.\n", .{});

    const obj = switch (telemetry) {
        .object => |obj| obj,
        else => {
            try writer.print("capacityTelemetry:\n", .{});
            try printJsonValue(writer, telemetry, 2);
            try writer.print("\n", .{});
            return;
        },
    };
    try printCapacityField(writer, obj, "maxOutputsHit");
    try printCapacityField(writer, obj, "maxRulesHit");
    try printCapacityField(writer, obj, "maxFiredRulesHit");
    try printCapacityField(writer, obj, "rejectedOutputs");
    try printCapacityField(writer, obj, "budgetHits");
    try printCapacityField(writer, obj, "capacityWarnings");
    try writer.print("\n", .{});
}

fn findRuleEvaluation(value: std.json.Value) ?std.json.Value {
    const obj = switch (value) {
        .object => |o| o,
        else => return null,
    };
    if (obj.get("ruleEvaluation")) |rule| return rule;
    if (obj.get("rule_evaluation")) |rule| return rule;
    if (obj.get("result")) |result| {
        const result_obj = switch (result) {
            .object => |o| o,
            else => return result,
        };
        if (result_obj.get("ruleEvaluation")) |rule| return rule;
        if (result_obj.get("rule_evaluation")) |rule| return rule;
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

fn printBoolField(writer: anytype, obj: std.json.ObjectMap, field: []const u8, label: []const u8) !void {
    const value = obj.get(field) orelse return;
    switch (value) {
        .bool => |b| try writer.print("{s}: {s}\n", .{ label, if (b) "true" else "false" }),
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

fn printCapacityField(writer: anytype, obj: std.json.ObjectMap, field: []const u8) !void {
    const value = obj.get(field) orelse return;
    try writer.print("- {s}: ", .{field});
    try printInlineJsonValue(writer, value);
    try writer.print("\n", .{});
}

fn printInlineJsonValue(writer: anytype, value: std.json.Value) !void {
    switch (value) {
        .string => |s| try writer.print("{s}", .{s}),
        .integer => |i| try writer.print("{d}", .{i}),
        .float => |f| try writer.print("{d}", .{f}),
        .bool => |b| try writer.print("{s}", .{if (b) "true" else "false"}),
        .null => try writer.print("null", .{}),
        else => try std.json.stringify(value, .{}, writer),
    }
}

fn hasCapacityPressure(value: std.json.Value) bool {
    const obj = switch (value) {
        .object => |obj| obj,
        else => return true,
    };
    return hasPressureField(obj, "maxOutputsHit") or
        hasPressureField(obj, "maxRulesHit") or
        hasPressureField(obj, "maxFiredRulesHit") or
        hasPressureField(obj, "rejectedOutputs") or
        hasPressureField(obj, "budgetHits") or
        hasPressureField(obj, "capacityWarnings");
}

fn hasPressureField(obj: std.json.ObjectMap, field: []const u8) bool {
    const value = obj.get(field) orelse return false;
    return isPressureValue(value);
}

fn isPressureValue(value: std.json.Value) bool {
    return switch (value) {
        .bool => |b| b,
        .integer => |i| i != 0,
        .float => |f| f != 0,
        .string => |s| s.len > 0,
        .array => |arr| arr.items.len > 0,
        .object => |obj| obj.count() > 0,
        .null => false,
        else => true,
    };
}

fn isEmptyJsonList(value: std.json.Value) bool {
    return switch (value) {
        .array => |arr| arr.items.len == 0,
        .object => |obj| obj.count() == 0,
        else => false,
    };
}

fn printJsonValue(writer: anytype, value: std.json.Value, indent: usize) !void {
    var string = std.ArrayList(u8).init(std.heap.page_allocator);
    defer string.deinit();
    try std.json.stringify(value, .{ .whitespace = .indent_2 }, string.writer());
    var lines = std.mem.splitScalar(u8, string.items, '\n');
    while (lines.next()) |line| {
        try writer.writeByteNTimes(' ', indent);
        try writer.print("{s}\n", .{line});
    }
}

fn failMissingValue(flag: []const u8) !noreturn {
    try std.io.getStdErr().writer().print("{s} requires a value\n", .{flag});
    std.process.exit(1);
}
