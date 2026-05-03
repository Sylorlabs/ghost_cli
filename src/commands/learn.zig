const std = @import("std");
const locator = @import("../engine/locator.zig");
const process = @import("../engine/process.zig");
const runner = @import("../engine/runner.zig");
const json_contracts = @import("../engine/json_contracts.zig");
const terminal = @import("../render/terminal.zig");

pub const LearnOptions = struct {
    subcommand: []const u8,
    project_shard: ?[]const u8 = null,
    candidate_id: ?[]const u8 = null,
    pack_id: ?[]const u8 = null,
    version: ?[]const u8 = null,
    approve: bool = false,
    include_records: bool = false,
    include_warnings: bool = true,
    include_warnings_explicit: bool = false,
    limit: ?usize = null,
    json: bool = false,
    debug: bool = false,
};

pub fn printHelp(writer: anytype) !void {
    try writer.print(
        \\learn
        \\
        \\Usage: ghost learn <candidates|show|export|status> [options]
        \\
        \\Subcommands:
        \\  candidates --project-shard=<id>
        \\  show <candidate-id> --project-shard=<id>
        \\  export <candidate-id> --project-shard=<id> --pack-id=<id> --version=<v> --approve
        \\  status --project-shard=<id> [--include-records] [--limit=<n>] [--no-warnings]
        \\
        \\Safety:
        \\  learning.status is explicit and read-only.
        \\  Scoreboard counts are diagnostics only, not proof or evidence.
        \\  No mutation occurs and no global promotion occurs.
        \\  The engine enforces same-shard bounds and classification.
        \\  No semantic matching, model, embedding, Transformer, cloud, or network behavior is added.
        \\  `--json` preserves raw engine stdout exactly.
        \\  `--debug` writes diagnostics to stderr only.
        \\
    , .{});
}

pub fn printHelpForArgs(writer: anytype, args: []const []const u8) !void {
    if (args.len == 0) return printHelp(writer);
    if (std.mem.eql(u8, args[0], "status")) return printStatusHelp(writer);
    return printHelp(writer);
}

fn printStatusHelp(writer: anytype) !void {
    try writer.print(
        \\learn status
        \\
        \\Usage: ghost learn status --project-shard=<id> [--include-records] [--limit=<n>] [--no-warnings] [--json] [--debug]
        \\
        \\Builds a learning.status GIP request and sends it to ghost_gip --stdin.
        \\
        \\Options:
        \\  --project-shard=<id>      Project shard to inspect
        \\  --include-records         Ask the engine to include bounded sampled records
        \\  --limit=<n>               Optional numeric sampled-record limit
        \\  --include-warnings        Include warnings (default)
        \\  --no-warnings             Ask the engine to omit warnings
        \\  --json                    Preserve raw GIP stdout exactly
        \\  --debug                   Diagnostics to stderr only
        \\
        \\Safety:
        \\  READ-ONLY.
        \\  NOT PROOF.
        \\  NOT EVIDENCE.
        \\  NON-AUTHORIZING.
        \\  NO GLOBAL PROMOTION.
        \\  NO KNOWLEDGE MUTATED.
        \\  NO VERIFIERS EXECUTED.
        \\  SCOREBOARD COUNTS ARE OPERATOR DIAGNOSTICS ONLY.
        \\  Same-shard only. No semantic matching, model, embedding, Transformer, cloud, or network behavior.
        \\
    , .{});
}

pub fn execute(allocator: std.mem.Allocator, engine_root: ?[]const u8, options: LearnOptions) !void {
    if (std.mem.eql(u8, options.subcommand, "candidates")) {
        try executeCandidates(allocator, engine_root, options);
    } else if (std.mem.eql(u8, options.subcommand, "show")) {
        try executeShow(allocator, engine_root, options);
    } else if (std.mem.eql(u8, options.subcommand, "export")) {
        try executeExport(allocator, engine_root, options);
    } else if (std.mem.eql(u8, options.subcommand, "status")) {
        try executeStatus(allocator, engine_root, options);
    } else if (std.mem.eql(u8, options.subcommand, "feedback")) {
        std.debug.print("feedback submission TODO: verify engine CLI support\n", .{});
    } else {
        std.debug.print("Unknown learn subcommand: {s}\n", .{options.subcommand});
        std.process.exit(1);
    }
}

fn executeCandidates(allocator: std.mem.Allocator, engine_root: ?[]const u8, options: LearnOptions) !void {
    const shard = options.project_shard orelse {
        std.debug.print("\x1b[31m[!] Error:\x1b[0m --project-shard is required for learn candidates\n", .{});
        std.process.exit(1);
    };

    var argv = std.ArrayList([]const u8).init(allocator);
    defer argv.deinit();

    try argv.append("distill-list");
    try argv.append("--project-shard");
    try argv.append(shard);
    try argv.append("--json");

    const res = try runner.run(allocator, .{
        .engine_root = engine_root,
        .binary = .ghost_knowledge_pack,
        .argv = argv.items,
        .json = true,
        .debug = options.debug,
    });
    defer res.deinit();

    if (options.json) {
        try std.io.getStdOut().writer().writeAll(res.stdout);
        return;
    }

    if (res.exit_code != 0) {
        std.process.exit(res.exit_code);
    }

    const parsed = json_contracts.parseCandidateListJson(allocator, res.stdout) catch |err| {
        std.debug.print("\x1b[31m[!] Error:\x1b[0m Failed to parse engine JSON: {}\n", .{err});
        if (options.debug) std.debug.print("\x1b[33mRaw Output:\x1b[0m\n{s}\n", .{res.stdout});
        return;
    };
    defer parsed.deinit();

    try terminal.printCandidateList(std.io.getStdOut().writer(), parsed.value);
}

fn executeShow(allocator: std.mem.Allocator, engine_root: ?[]const u8, options: LearnOptions) !void {
    const shard = options.project_shard orelse {
        std.debug.print("\x1b[31m[!] Error:\x1b[0m --project-shard is required for learn show\n", .{});
        std.process.exit(1);
    };
    const cand_id = options.candidate_id orelse {
        std.debug.print("\x1b[31m[!] Error:\x1b[0m candidate-id is required for learn show\n", .{});
        std.process.exit(1);
    };

    var argv = std.ArrayList([]const u8).init(allocator);
    defer argv.deinit();

    try argv.append("distill-show");
    try argv.append("--project-shard");
    try argv.append(shard);
    try argv.append("--candidate-id");
    try argv.append(cand_id);
    try argv.append("--json");

    const res = try runner.run(allocator, .{
        .engine_root = engine_root,
        .binary = .ghost_knowledge_pack,
        .argv = argv.items,
        .json = true,
        .debug = options.debug,
    });
    defer res.deinit();

    if (options.json) {
        try std.io.getStdOut().writer().writeAll(res.stdout);
        return;
    }

    if (res.exit_code != 0) {
        std.process.exit(res.exit_code);
    }

    const parsed = json_contracts.parseCandidateInfoJson(allocator, res.stdout) catch |err| {
        std.debug.print("\x1b[31m[!] Error:\x1b[0m Failed to parse engine JSON: {}\n", .{err});
        if (options.debug) std.debug.print("\x1b[33mRaw Output:\x1b[0m\n{s}\n", .{res.stdout});
        return;
    };
    defer parsed.deinit();

    try terminal.printCandidateDetail(std.io.getStdOut().writer(), parsed.value);
}

fn executeExport(allocator: std.mem.Allocator, engine_root: ?[]const u8, options: LearnOptions) !void {
    const shard = options.project_shard orelse {
        std.debug.print("\x1b[31m[!] Error:\x1b[0m --project-shard is required for learn export\n", .{});
        std.process.exit(1);
    };
    const cand_id = options.candidate_id orelse {
        std.debug.print("\x1b[31m[!] Error:\x1b[0m candidate-id is required for learn export\n", .{});
        std.process.exit(1);
    };
    const pack_id = options.pack_id orelse {
        std.debug.print("\x1b[31m[!] Error:\x1b[0m --pack-id is required for learn export\n", .{});
        std.process.exit(1);
    };
    const version = options.version orelse {
        std.debug.print("\x1b[31m[!] Error:\x1b[0m --version is required for learn export\n", .{});
        std.process.exit(1);
    };

    if (!options.approve) {
        std.debug.print("\x1b[31m[!] Error:\x1b[0m --approve is required to export a candidate to a knowledge pack.\n", .{});
        std.process.exit(1);
    }

    var argv = std.ArrayList([]const u8).init(allocator);
    defer argv.deinit();

    try argv.append("distill-export");
    try argv.append("--project-shard");
    try argv.append(shard);
    try argv.append("--candidate-id");
    try argv.append(cand_id);
    try argv.append("--pack-id");
    try argv.append(pack_id);
    try argv.append("--version");
    try argv.append(version);
    try argv.append("--approve");
    try argv.append("--json");

    const res = try runner.run(allocator, .{
        .engine_root = engine_root,
        .binary = .ghost_knowledge_pack,
        .argv = argv.items,
        .json = true,
        .debug = options.debug,
    });
    defer res.deinit();

    if (options.json) {
        try std.io.getStdOut().writer().writeAll(res.stdout);
        return;
    }

    if (res.exit_code != 0) {
        std.process.exit(res.exit_code);
    }

    const parsed = json_contracts.parseExportResultJson(allocator, res.stdout) catch |err| {
        std.debug.print("\x1b[31m[!] Error:\x1b[0m Failed to parse engine JSON: {}\n", .{err});
        if (options.debug) std.debug.print("\x1b[33mRaw Output:\x1b[0m\n{s}\n", .{res.stdout});
        return;
    };
    defer parsed.deinit();

    try terminal.printExportResult(std.io.getStdOut().writer(), parsed.value);
}

fn executeStatus(allocator: std.mem.Allocator, engine_root: ?[]const u8, options: LearnOptions) !void {
    const shard = options.project_shard orelse {
        std.debug.print("\x1b[31m[!] Error:\x1b[0m --project-shard is required for learn status\n", .{});
        std.process.exit(1);
    };
    if (std.mem.trim(u8, shard, " \r\n\t").len == 0) {
        std.debug.print("\x1b[31m[!] Error:\x1b[0m --project-shard is required for learn status\n", .{});
        std.process.exit(1);
    }

    var request = std.ArrayList(u8).init(allocator);
    defer request.deinit();
    try request.writer().writeAll("{\"gipVersion\":\"gip.v0.1\",\"kind\":\"learning.status\",\"projectShard\":");
    try std.json.stringify(shard, .{}, request.writer());
    if (options.include_records) try request.writer().writeAll(",\"includeRecords\":true");
    if (options.include_warnings_explicit or !options.include_warnings) {
        try request.writer().writeAll(",\"includeWarnings\":");
        try request.writer().writeAll(if (options.include_warnings) "true" else "false");
    }
    if (options.limit) |limit| try request.writer().print(",\"limit\":{d}", .{limit});
    try request.writer().writeByte('}');

    const bin_path = locator.findEngineBinary(allocator, engine_root, .ghost_gip) catch |err| {
        try locator.printLocatorError(std.io.getStdErr().writer(), .ghost_gip, engine_root, err);
        std.process.exit(1);
    };
    defer allocator.free(bin_path);

    if (options.debug) {
        try std.io.getStdErr().writer().print("[DEBUG] Engine Binary: {s}\n", .{bin_path});
        try std.io.getStdErr().writer().print("[DEBUG] GIP Kind: learning.status\n", .{});
        try std.io.getStdErr().writer().print("[DEBUG] Project Shard: {s}\n", .{shard});
        try std.io.getStdErr().writer().print("[DEBUG] includeRecords: {s}\n", .{if (options.include_records) "true" else "false"});
        try std.io.getStdErr().writer().print("[DEBUG] includeWarnings: {s}\n", .{if (options.include_warnings) "true" else "false"});
        if (options.limit) |limit| try std.io.getStdErr().writer().print("[DEBUG] limit: {d}\n", .{limit});
        try std.io.getStdErr().writer().print("[DEBUG] Request Byte Count: {d}\n", .{request.items.len});
    }

    const argv = &[_][]const u8{ bin_path, "--stdin" };
    const result = process.runEngineCommandWithInput(allocator, argv, request.items) catch |err| {
        try std.io.getStdErr().writer().print("\x1b[31m[!] Error:\x1b[0m Failed to execute learning.status: {}\n", .{err});
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

    var parsed = std.json.parseFromSlice(std.json.Value, allocator, result.stdout, .{}) catch |err| {
        if (options.debug) try std.io.getStdErr().writer().print("[DEBUG] Parse Status: FAILED ({s})\n", .{@errorName(err)});
        try std.io.getStdErr().writer().print("Error: Failed to parse engine output as learning.status JSON.\n", .{});
        try std.io.getStdErr().writer().print("Raw output:\n{s}\n", .{result.stdout});
        return;
    };
    defer parsed.deinit();

    if (options.debug) try std.io.getStdErr().writer().print("[DEBUG] Parse Status: ok\n", .{});
    try printLearningStatusResult(std.io.getStdOut().writer(), parsed.value);
}

fn printLearningStatusResult(writer: anytype, value: std.json.Value) !void {
    try writer.print("LEARNING LOOP STATUS / READ-ONLY\n", .{});
    try writer.print("READ-ONLY\n", .{});
    try writer.print("NOT PROOF\n", .{});
    try writer.print("NOT EVIDENCE\n", .{});
    try writer.print("NON-AUTHORIZING\n", .{});
    try writer.print("NO GLOBAL PROMOTION\n", .{});
    try writer.print("NO KNOWLEDGE MUTATED\n", .{});
    try writer.print("NO VERIFIERS EXECUTED\n", .{});
    try writer.print("SCOREBOARD COUNTS ARE OPERATOR DIAGNOSTICS ONLY\n\n", .{});

    if (findError(value)) |err_value| {
        try writer.print("Engine Rejected Request:\n", .{});
        try printJsonValue(writer, err_value, 2);
        try writer.print("\n", .{});
        return;
    }

    const status_value = findLearningStatus(value) orelse {
        try writer.print("No learningStatus result payload was present.\n", .{});
        return;
    };
    const status = switch (status_value) {
        .object => |obj| obj,
        else => {
            try printJsonValue(writer, status_value, 2);
            try writer.print("\n", .{});
            return;
        },
    };

    try printField(writer, status, "projectShard", "Project Shard");
    try printField(writer, status, "project_shard", "Project Shard");
    try printField(writer, status, "status", "Status");
    try printField(writer, status, "readOnly", "Read Only");
    try printField(writer, status, "read_only", "Read Only");
    try printSection(writer, status, "correctionSummary", "Correction Summary");
    try printSection(writer, status, "correction_summary", "Correction Summary");
    try printSection(writer, status, "negativeKnowledgeSummary", "Negative Knowledge Summary");
    try printSection(writer, status, "negative_knowledge_summary", "Negative Knowledge Summary");
    try printSection(writer, status, "influenceSummary", "Influence Summary");
    try printSection(writer, status, "influence_summary", "Influence Summary");
    try printSection(writer, status, "warningSummary", "Warning Summary");
    try printSection(writer, status, "warning_summary", "Warning Summary");
    try printSection(writer, status, "capacityTelemetry", "Capacity Telemetry");
    try printSection(writer, status, "capacity_telemetry", "Capacity Telemetry");
    try printSection(writer, status, "storage", "Storage Metadata");
    try printSection(writer, status, "sampledRecords", "Sampled Records");
    try printSection(writer, status, "sampled_records", "Sampled Records");
    try printSection(writer, status, "records", "Sampled Records");
    try printSection(writer, status, "mutationFlags", "Mutation Flags");
    try printSection(writer, status, "mutation_flags", "Mutation Flags");
    try printSection(writer, status, "authority", "Authority Flags");
    try printSection(writer, status, "authorityFlags", "Authority Flags");
    try printSection(writer, status, "authority_flags", "Authority Flags");
}

fn findLearningStatus(value: std.json.Value) ?std.json.Value {
    const obj = switch (value) {
        .object => |o| o,
        else => return null,
    };
    if (obj.get("learningStatus")) |status| return status;
    if (obj.get("learning_status")) |status| return status;
    if (obj.get("result")) |result| {
        const result_obj = switch (result) {
            .object => |o| o,
            else => return result,
        };
        if (result_obj.get("learningStatus")) |status| return status;
        if (result_obj.get("learning_status")) |status| return status;
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

fn printField(writer: anytype, obj: std.json.ObjectMap, field: []const u8, label: []const u8) !void {
    const value = obj.get(field) orelse return;
    try writer.print("{s}: ", .{label});
    try printInlineJsonValue(writer, value);
    try writer.print("\n", .{});
}

fn printSection(writer: anytype, obj: std.json.ObjectMap, field: []const u8, label: []const u8) !void {
    const value = obj.get(field) orelse return;
    if (isEmptyJsonList(value)) return;
    try writer.print("\n{s}:\n", .{label});
    try printJsonValue(writer, value, 2);
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

fn isEmptyJsonList(value: std.json.Value) bool {
    return switch (value) {
        .array => |arr| arr.items.len == 0,
        .object => |obj| obj.count() == 0,
        else => false,
    };
}
