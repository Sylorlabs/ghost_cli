const std = @import("std");
const locator = @import("../engine/locator.zig");
const process = @import("../engine/process.zig");

pub const NkOptions = struct {
    file_path: ?[]const u8 = null,
    project_shard: ?[]const u8 = null,
    id: ?[]const u8 = null,
    decision: ?[]const u8 = null,
    limit: ?usize = null,
    offset: ?usize = null,
    json: bool = false,
    debug: bool = false,
};

const max_request_bytes = 1024 * 1024;
const usage =
    \\Usage: ghost nk <review|reviewed> [options]
    \\
;

pub fn printHelp(writer: anytype) !void {
    try writer.print(
        \\nk
        \\
        \\Usage: ghost nk <review|reviewed> [options]
        \\
        \\Explicit reviewed negative-knowledge commands.
        \\
        \\Subcommands:
        \\  review --file <request.json>      Run a negative_knowledge.review GIP request
        \\  reviewed list --project-shard=<id> List reviewed negative-knowledge records
        \\  reviewed get --project-shard=<id> --id=<record-id>
        \\
        \\Safety:
        \\  This request runs only when this command is explicitly invoked.
        \\  Review request files must be GIP-compatible JSON with kind "negative_knowledge.review".
        \\  Reviewed list/get build read-only GIP requests with kind "negative_knowledge.reviewed.list" or "negative_knowledge.reviewed.get".
        \\  Reviewed negative knowledge is append-only and shard-local.
        \\  Reviewed negative knowledge is NOT PROOF and NOT EVIDENCE.
        \\  Accepted reviewed NK has no global promotion.
        \\  Phase 11A does not add broad accepted-NK future behavior influence.
        \\  Reviewed list/get are read-only.
        \\  NO CORPUS OR PACK MUTATION.
        \\  NO VERIFIERS EXECUTED.
        \\  `--json` preserves raw engine stdout exactly.
        \\  `--debug` writes diagnostics to stderr only.
        \\
    , .{});
}

pub fn printHelpForArgs(writer: anytype, args: []const []const u8) !void {
    if (args.len == 0) return printHelp(writer);
    if (std.mem.eql(u8, args[0], "review")) return printReviewHelp(writer);
    if (std.mem.eql(u8, args[0], "reviewed")) {
        if (args.len >= 2 and std.mem.eql(u8, args[1], "list")) return printReviewedListHelp(writer);
        if (args.len >= 2 and std.mem.eql(u8, args[1], "get")) return printReviewedGetHelp(writer);
        return printReviewedHelp(writer);
    }
    return printHelp(writer);
}

fn printReviewHelp(writer: anytype) !void {
    try writer.print(
        \\nk review
        \\
        \\Usage: ghost nk review --file <request.json> [--json] [--debug]
        \\
        \\Reads a full GIP-compatible reviewed negative-knowledge request from a
        \\file and sends the bytes unchanged to ghost_gip --stdin. The request
        \\must include kind "negative_knowledge.review".
        \\
        \\Options:
        \\  --file <request.json>     Reviewed NK GIP request file
        \\  --json                    Preserve raw GIP stdout exactly
        \\  --debug                   Diagnostics to stderr
        \\
        \\Safety:
        \\  Explicit invocation only.
        \\  REVIEWED NEGATIVE KNOWLEDGE RECORD.
        \\  APPEND-ONLY.
        \\  NOT PROOF.
        \\  NOT EVIDENCE.
        \\  NON-AUTHORIZING.
        \\  NO GLOBAL PROMOTION.
        \\  NO CORPUS OR PACK MUTATION.
        \\  NO VERIFIERS EXECUTED.
        \\  ACCEPTED NK DOES NOT BROADLY INFLUENCE FUTURE BEHAVIOR YET.
        \\
    , .{});
}

fn printReviewedHelp(writer: anytype) !void {
    try writer.print(
        \\nk reviewed
        \\
        \\Usage: ghost nk reviewed <list|get> [options]
        \\
        \\Read-only reviewed negative-knowledge inspection commands.
        \\
        \\Subcommands:
        \\  list --project-shard=<id> [--decision=accepted|rejected|all] [--limit=<n>] [--offset=<n>]
        \\  get --project-shard=<id> --id=<record-id>
        \\
        \\Safety:
        \\  READ-ONLY. NOT PROOF. NOT EVIDENCE. NON-AUTHORIZING.
        \\  NO KNOWLEDGE MUTATED. NO VERIFIERS EXECUTED.
        \\  Missing storage returns an empty list or not_found.
        \\  Malformed JSONL lines render as warnings.
        \\  `--json` preserves raw engine stdout exactly.
        \\  `--debug` writes diagnostics to stderr only.
        \\
    , .{});
}

fn printReviewedListHelp(writer: anytype) !void {
    try writer.print(
        \\nk reviewed list
        \\
        \\Usage: ghost nk reviewed list --project-shard=<id> [--decision=accepted|rejected|all] [--limit=<n>] [--offset=<n>] [--json] [--debug]
        \\
        \\Builds a negative_knowledge.reviewed.list GIP request and sends it to ghost_gip --stdin.
        \\
        \\Options:
        \\  --project-shard=<id>      Project shard to inspect
        \\  --decision=<value>        accepted, rejected, or all
        \\  --limit=<n>               Optional numeric limit
        \\  --offset=<n>              Optional numeric offset
        \\  --cursor=<n>              Numeric alias for offset
        \\  --json                    Preserve raw GIP stdout exactly
        \\  --debug                   Diagnostics to stderr
        \\
        \\Safety:
        \\  READ-ONLY. NOT PROOF. NOT EVIDENCE. NON-AUTHORIZING.
        \\  NO KNOWLEDGE MUTATED. NO VERIFIERS EXECUTED.
        \\  Phase 11A does not add broad future behavior influence.
        \\
    , .{});
}

fn printReviewedGetHelp(writer: anytype) !void {
    try writer.print(
        \\nk reviewed get
        \\
        \\Usage: ghost nk reviewed get --project-shard=<id> --id=<record-id> [--json] [--debug]
        \\
        \\Builds a negative_knowledge.reviewed.get GIP request and sends it to ghost_gip --stdin.
        \\
        \\Options:
        \\  --project-shard=<id>      Project shard to inspect
        \\  --id=<record-id>          Reviewed NK record ID
        \\  --json                    Preserve raw GIP stdout exactly
        \\  --debug                   Diagnostics to stderr
        \\
        \\Safety:
        \\  READ-ONLY. NOT PROOF. NOT EVIDENCE. NON-AUTHORIZING.
        \\  NO KNOWLEDGE MUTATED. NO VERIFIERS EXECUTED.
        \\  Missing storage or records render cleanly as not_found.
        \\
    , .{});
}

pub fn executeFromArgs(
    allocator: std.mem.Allocator,
    engine_root: ?[]const u8,
    args: []const []const u8,
    base: NkOptions,
) !void {
    const sub = if (args.len > 0) args[0] else {
        try std.io.getStdErr().writer().print("{s}", .{usage});
        std.process.exit(1);
    };
    if (std.mem.eql(u8, sub, "review")) {
        var options = base;
        var i: usize = 1;
        while (i < args.len) : (i += 1) {
            const arg = args[i];
            if (try parseValueArg(args, &i, arg, "--file")) |value| {
                options.file_path = value;
            } else if (std.mem.startsWith(u8, arg, "--")) {
                try std.io.getStdErr().writer().print("Unknown nk review option: {s}\n", .{arg});
                std.process.exit(1);
            } else {
                try std.io.getStdErr().writer().print("Unexpected nk review argument: {s}\n", .{arg});
                std.process.exit(1);
            }
        }
        try executeReview(allocator, engine_root, options);
        return;
    }
    if (std.mem.eql(u8, sub, "reviewed")) {
        try executeReviewedFromArgs(allocator, engine_root, args[1..], base);
        return;
    }
    try std.io.getStdErr().writer().print("Unknown nk command: {s}\n{s}", .{ sub, usage });
    std.process.exit(1);
}

fn executeReviewedFromArgs(
    allocator: std.mem.Allocator,
    engine_root: ?[]const u8,
    args: []const []const u8,
    base: NkOptions,
) !void {
    const action = if (args.len > 0) args[0] else {
        try printReviewedHelp(std.io.getStdErr().writer());
        std.process.exit(1);
    };
    if (!std.mem.eql(u8, action, "list") and !std.mem.eql(u8, action, "get")) {
        try std.io.getStdErr().writer().print("Unknown nk reviewed command: {s}\n", .{action});
        try printReviewedHelp(std.io.getStdErr().writer());
        std.process.exit(1);
    }

    var options = base;
    var i: usize = 1;
    while (i < args.len) : (i += 1) {
        const arg = args[i];
        if (try parseValueArg(args, &i, arg, "--project-shard")) |value| {
            options.project_shard = value;
        } else if (try parseValueArg(args, &i, arg, "--id")) |value| {
            options.id = value;
        } else if (try parseValueArg(args, &i, arg, "--decision")) |value| {
            options.decision = value;
        } else if (try parseValueArg(args, &i, arg, "--limit")) |value| {
            options.limit = parsePositiveUsize("--limit", value);
        } else if (try parseValueArg(args, &i, arg, "--offset")) |value| {
            options.offset = parseNonNegativeUsize("--offset", value);
        } else if (try parseValueArg(args, &i, arg, "--cursor")) |value| {
            options.offset = parseNonNegativeUsize("--cursor", value);
        } else if (std.mem.startsWith(u8, arg, "--")) {
            try std.io.getStdErr().writer().print("Unknown nk reviewed {s} option: {s}\n", .{ action, arg });
            std.process.exit(1);
        } else {
            try std.io.getStdErr().writer().print("Unexpected nk reviewed {s} argument: {s}\n", .{ action, arg });
            std.process.exit(1);
        }
    }

    if (std.mem.eql(u8, action, "list")) {
        try executeReviewedList(allocator, engine_root, options);
    } else {
        try executeReviewedGet(allocator, engine_root, options);
    }
}

fn executeReview(allocator: std.mem.Allocator, engine_root: ?[]const u8, options: NkOptions) !void {
    const file_path = options.file_path orelse {
        try std.io.getStdErr().writer().print("{s}", .{usage});
        std.process.exit(1);
    };
    if (std.mem.trim(u8, file_path, " \r\n\t").len == 0) {
        try std.io.getStdErr().writer().print("nk review --file must be non-empty\n", .{});
        std.process.exit(1);
    }

    const request = std.fs.cwd().readFileAlloc(allocator, file_path, max_request_bytes) catch |err| {
        try std.io.getStdErr().writer().print("Error: failed to read negative_knowledge.review request file '{s}': {s}\n", .{ file_path, @errorName(err) });
        std.process.exit(1);
    };
    defer allocator.free(request);

    var parsed = std.json.parseFromSlice(std.json.Value, allocator, request, .{}) catch |err| {
        if (options.debug) try std.io.getStdErr().writer().print("[DEBUG] Parse Status: FAILED ({s})\n", .{@errorName(err)});
        try std.io.getStdErr().writer().print("Error: negative_knowledge.review request file is not valid JSON: {s}\n", .{@errorName(err)});
        std.process.exit(1);
    };
    defer parsed.deinit();

    if (!hasKind(parsed.value, "negative_knowledge.review")) {
        if (options.debug) try std.io.getStdErr().writer().print("[DEBUG] Parse Status: FAILED (kind mismatch)\n", .{});
        try std.io.getStdErr().writer().print("Error: request file must contain top-level kind \"negative_knowledge.review\".\n", .{});
        std.process.exit(1);
    }

    try executeFileGip(allocator, engine_root, options, "negative_knowledge.review", file_path, request, printNegativeKnowledgeReviewResult);
}

fn executeReviewedList(allocator: std.mem.Allocator, engine_root: ?[]const u8, options: NkOptions) !void {
    const project_shard = requireNonEmpty(options.project_shard, "nk reviewed list --project-shard is required");
    if (options.decision) |decision| {
        if (!std.mem.eql(u8, decision, "accepted") and !std.mem.eql(u8, decision, "rejected") and !std.mem.eql(u8, decision, "all")) {
            try std.io.getStdErr().writer().print("Invalid --decision value: {s}. Use accepted|rejected|all.\n", .{decision});
            std.process.exit(1);
        }
    }

    var request = std.ArrayList(u8).init(allocator);
    defer request.deinit();
    try request.writer().writeAll("{\"gipVersion\":\"gip.v0.1\",\"kind\":\"negative_knowledge.reviewed.list\",\"projectShard\":");
    try std.json.stringify(project_shard, .{}, request.writer());
    if (options.decision) |decision| {
        try request.writer().writeAll(",\"decision\":");
        try std.json.stringify(decision, .{}, request.writer());
    }
    if (options.limit) |limit| try request.writer().print(",\"limit\":{d}", .{limit});
    if (options.offset) |offset| try request.writer().print(",\"offset\":{d}", .{offset});
    try request.writer().writeByte('}');

    try executeBuiltGip(allocator, engine_root, options, "negative_knowledge.reviewed.list", project_shard, null, request.items, printReviewedNegativeKnowledgeListResult);
}

fn executeReviewedGet(allocator: std.mem.Allocator, engine_root: ?[]const u8, options: NkOptions) !void {
    const project_shard = requireNonEmpty(options.project_shard, "nk reviewed get --project-shard is required");
    const id = requireNonEmpty(options.id, "nk reviewed get --id is required");

    var request = std.ArrayList(u8).init(allocator);
    defer request.deinit();
    try request.writer().writeAll("{\"gipVersion\":\"gip.v0.1\",\"kind\":\"negative_knowledge.reviewed.get\",\"projectShard\":");
    try std.json.stringify(project_shard, .{}, request.writer());
    try request.writer().writeAll(",\"id\":");
    try std.json.stringify(id, .{}, request.writer());
    try request.writer().writeByte('}');

    try executeBuiltGip(allocator, engine_root, options, "negative_knowledge.reviewed.get", project_shard, id, request.items, printReviewedNegativeKnowledgeGetResult);
}

fn executeFileGip(
    allocator: std.mem.Allocator,
    engine_root: ?[]const u8,
    options: NkOptions,
    kind: []const u8,
    file_path: []const u8,
    request: []const u8,
    comptime renderer: fn (anytype, std.json.Value) anyerror!void,
) !void {
    const bin_path = try findGipOrExit(allocator, engine_root);
    defer allocator.free(bin_path);

    if (options.debug) {
        try std.io.getStdErr().writer().print("[DEBUG] Engine Binary: {s}\n", .{bin_path});
        try std.io.getStdErr().writer().print("[DEBUG] GIP Kind: {s}\n", .{kind});
        try std.io.getStdErr().writer().print("[DEBUG] Input File: {s}\n", .{file_path});
        try std.io.getStdErr().writer().print("[DEBUG] Stdin Byte Count: {d}\n", .{request.len});
    }
    try runAndRender(allocator, options, bin_path, kind, request, renderer);
}

fn executeBuiltGip(
    allocator: std.mem.Allocator,
    engine_root: ?[]const u8,
    options: NkOptions,
    kind: []const u8,
    project_shard: []const u8,
    id: ?[]const u8,
    request: []const u8,
    comptime renderer: fn (anytype, std.json.Value) anyerror!void,
) !void {
    const bin_path = try findGipOrExit(allocator, engine_root);
    defer allocator.free(bin_path);

    if (options.debug) {
        try std.io.getStdErr().writer().print("[DEBUG] Engine Binary: {s}\n", .{bin_path});
        try std.io.getStdErr().writer().print("[DEBUG] GIP Kind: {s}\n", .{kind});
        try std.io.getStdErr().writer().print("[DEBUG] Project Shard: {s}\n", .{project_shard});
        if (id) |record_id| try std.io.getStdErr().writer().print("[DEBUG] ID: {s}\n", .{record_id});
        try std.io.getStdErr().writer().print("[DEBUG] Stdin Byte Count: {d}\n", .{request.len});
    }
    try runAndRender(allocator, options, bin_path, kind, request, renderer);
}

fn runAndRender(
    allocator: std.mem.Allocator,
    options: NkOptions,
    bin_path: []const u8,
    kind: []const u8,
    request: []const u8,
    comptime renderer: fn (anytype, std.json.Value) anyerror!void,
) !void {
    const argv = &[_][]const u8{ bin_path, "--stdin" };
    const result = process.runEngineCommandWithInput(allocator, argv, request) catch |err| {
        try std.io.getStdErr().writer().print("\x1b[31m[!] Error:\x1b[0m Failed to execute {s}: {}\n", .{ kind, err });
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
        try std.io.getStdErr().writer().print("Error: Failed to parse engine output as {s} JSON.\n", .{kind});
        try std.io.getStdErr().writer().print("Raw output:\n{s}\n", .{result.stdout});
        return;
    };
    defer out_parsed.deinit();

    if (options.debug) try std.io.getStdErr().writer().print("[DEBUG] Parse Status: ok\n", .{});
    try renderer(std.io.getStdOut().writer(), out_parsed.value);
}

fn findGipOrExit(allocator: std.mem.Allocator, engine_root: ?[]const u8) ![]u8 {
    return locator.findEngineBinary(allocator, engine_root, .ghost_gip) catch |err| {
        try locator.printLocatorError(std.io.getStdErr().writer(), .ghost_gip, engine_root, err);
        std.process.exit(1);
    };
}

fn printNegativeKnowledgeReviewResult(writer: anytype, value: std.json.Value) !void {
    try writer.print("Negative Knowledge Review Result\n", .{});
    try writer.print("REVIEWED NEGATIVE KNOWLEDGE RECORD\n", .{});
    try writer.print("APPEND-ONLY\n", .{});
    try writer.print("NOT PROOF\n", .{});
    try writer.print("NOT EVIDENCE\n", .{});
    try writer.print("NON-AUTHORIZING\n", .{});
    try writer.print("NO GLOBAL PROMOTION\n", .{});
    try writer.print("NO CORPUS OR PACK MUTATION\n", .{});
    try writer.print("NO VERIFIERS EXECUTED\n", .{});
    try writer.print("ACCEPTED NK DOES NOT BROADLY INFLUENCE FUTURE BEHAVIOR YET\n\n", .{});

    if (findError(value)) |err_value| {
        try writer.print("Engine Rejected Request:\n", .{});
        try printJsonValue(writer, err_value, 2);
        try writer.print("\n", .{});
        return;
    }

    const review_value = findNegativeKnowledgeReview(value) orelse {
        try writer.print("No negativeKnowledgeReview result payload was present.\n", .{});
        return;
    };
    const review = switch (review_value) {
        .object => |obj| obj,
        else => {
            try printJsonValue(writer, review_value, 2);
            try writer.print("\n", .{});
            return;
        },
    };

    try printField(writer, review, "status", "Status");
    try printField(writer, review, "requiredReview", "Required Review");
    try printField(writer, review, "readOnly", "Read Only");
    try printField(writer, review, "appendOnly", "Append Only");

    const record_value = review.get("reviewedNegativeKnowledgeRecord") orelse review.get("reviewed_negative_knowledge_record");
    if (record_value) |record| {
        try writer.print("\nReviewed Negative Knowledge Record:\n", .{});
        try printReviewedNkRecordSummary(writer, record, 2);
    }

    try printSection(writer, review, "storage", "Append-Only Storage");
    try printSection(writer, review, "appendOnlyMetadata", "Append-Only Metadata");
    try printSection(writer, review, "appendOnly", "Append-Only Metadata");
    try printSection(writer, review, "mutationFlags", "Mutation Flags");
    try printSection(writer, review, "mutation_flags", "Mutation Flags");
    try printSection(writer, review, "authority", "Authority Flags");
    try printSection(writer, review, "authorityFlags", "Authority Flags");
    try printSection(writer, review, "futureInfluenceCandidate", "Future Influence Candidate / NOT APPLIED");
    try printSection(writer, review, "future_influence_candidate", "Future Influence Candidate / NOT APPLIED");

    try writer.print("\nNotice: reviewed negative knowledge records explicit accept/reject decisions only. Accepted reviewed NK remains non-authorizing, not proof, not evidence, shard-local, and not broad future behavior influence in Phase 11A.\n", .{});
}

fn printReviewedNegativeKnowledgeListResult(writer: anytype, value: std.json.Value) !void {
    try writer.print("REVIEWED NEGATIVE KNOWLEDGE RECORDS / READ-ONLY\n", .{});
    try writer.print("READ-ONLY\n", .{});
    try writer.print("NOT PROOF\n", .{});
    try writer.print("NOT EVIDENCE\n", .{});
    try writer.print("NON-AUTHORIZING\n", .{});
    try writer.print("NO KNOWLEDGE MUTATED\n", .{});
    try writer.print("NO VERIFIERS EXECUTED\n\n", .{});

    if (findError(value)) |err_value| {
        try writer.print("Engine Rejected Request:\n", .{});
        try printJsonValue(writer, err_value, 2);
        try writer.print("\n", .{});
        return;
    }

    const list_value = findReviewedNegativeKnowledge(value) orelse {
        try writer.print("No reviewedNegativeKnowledge result payload was present.\n", .{});
        return;
    };
    const list = switch (list_value) {
        .object => |obj| obj,
        else => {
            try printJsonValue(writer, list_value, 2);
            try writer.print("\n", .{});
            return;
        },
    };

    try printField(writer, list, "status", "Status");
    try printField(writer, list, "projectShard", "Project Shard");
    try printField(writer, list, "project_shard", "Project Shard");
    try printField(writer, list, "decision", "Decision Filter");
    try printField(writer, list, "totalRead", "Total Read");
    try printField(writer, list, "returnedCount", "Returned Count");
    try printField(writer, list, "malformedLines", "Malformed Lines");
    try printSection(writer, list, "warnings", "Warnings");
    try printSection(writer, list, "capacityTelemetry", "Capacity Telemetry");
    try printSection(writer, list, "capacity_telemetry", "Capacity Telemetry");

    if (list.get("records")) |records| {
        try writer.print("\nRecords (append order):\n", .{});
        if (records == .array) {
            for (records.array.items, 0..) |record, index| {
                try writer.print("- Record {d}:\n", .{index + 1});
                try printReviewedNkRecordSummary(writer, record, 4);
            }
        } else {
            try printJsonValue(writer, records, 2);
        }
    }

    try printSection(writer, list, "mutationFlags", "Mutation Flags");
    try printSection(writer, list, "mutation_flags", "Mutation Flags");
    try printSection(writer, list, "authority", "Authority Flags");
    try printSection(writer, list, "authorityFlags", "Authority Flags");

    try writer.print("\nNotice: reviewed negative knowledge records are read-only inspection data. They are non-authorizing, not proof, not evidence, and this command mutates no knowledge or verifier state.\n", .{});
}

fn printReviewedNegativeKnowledgeGetResult(writer: anytype, value: std.json.Value) !void {
    try writer.print("REVIEWED NEGATIVE KNOWLEDGE RECORD / READ-ONLY\n", .{});
    try writer.print("READ-ONLY\n", .{});
    try writer.print("NOT PROOF\n", .{});
    try writer.print("NOT EVIDENCE\n", .{});
    try writer.print("NON-AUTHORIZING\n", .{});
    try writer.print("NO KNOWLEDGE MUTATED\n", .{});
    try writer.print("NO VERIFIERS EXECUTED\n\n", .{});

    if (findError(value)) |err_value| {
        try writer.print("Engine Rejected Request:\n", .{});
        try printJsonValue(writer, err_value, 2);
        try writer.print("\n", .{});
        return;
    }

    const get_value = findReviewedNegativeKnowledge(value) orelse {
        try writer.print("No reviewedNegativeKnowledge result payload was present.\n", .{});
        return;
    };
    const get = switch (get_value) {
        .object => |obj| obj,
        else => {
            try printJsonValue(writer, get_value, 2);
            try writer.print("\n", .{});
            return;
        },
    };

    try printField(writer, get, "status", "Status");
    try printField(writer, get, "projectShard", "Project Shard");
    try printField(writer, get, "project_shard", "Project Shard");
    try printField(writer, get, "id", "ID");
    try printField(writer, get, "totalRead", "Total Read");
    try printField(writer, get, "malformedLines", "Malformed Lines");
    try printSection(writer, get, "warnings", "Warnings");
    try printSection(writer, get, "unknown", "Unknown");
    try printSection(writer, get, "capacityTelemetry", "Capacity Telemetry");
    try printSection(writer, get, "capacity_telemetry", "Capacity Telemetry");

    const record_value = get.get("reviewedNegativeKnowledgeRecord") orelse get.get("reviewed_negative_knowledge_record");
    if (record_value) |record| {
        if (record == .null) {
            try writer.print("\nReviewed negative knowledge record not_found.\n", .{});
        } else {
            try writer.print("\nReviewed Negative Knowledge Record:\n", .{});
            try printReviewedNkRecordSummary(writer, record, 2);
        }
    } else if (getString(get, "status")) |status| {
        if (std.mem.eql(u8, status, "not_found")) try writer.print("\nReviewed negative knowledge record not_found.\n", .{});
    }

    try printSection(writer, get, "mutationFlags", "Mutation Flags");
    try printSection(writer, get, "mutation_flags", "Mutation Flags");
    try printSection(writer, get, "authority", "Authority Flags");
    try printSection(writer, get, "authorityFlags", "Authority Flags");

    try writer.print("\nNotice: this reviewed negative knowledge record is read-only inspection data. It is non-authorizing, not proof, not evidence, and this command mutates no knowledge or verifier state.\n", .{});
}

fn printReviewedNkRecordSummary(writer: anytype, record: std.json.Value, indent: usize) !void {
    const obj = switch (record) {
        .object => |o| o,
        else => {
            try printJsonValue(writer, record, indent);
            return;
        },
    };
    try printIndentedField(writer, obj, "id", "ID", indent);
    try printIndentedField(writer, obj, "schemaVersion", "Schema Version", indent);
    try printIndentedField(writer, obj, "projectShard", "Project Shard", indent);
    try printIndentedField(writer, obj, "sourceNegativeKnowledgeCandidateId", "Source NK Candidate ID", indent);
    try printIndentedField(writer, obj, "source_negative_knowledge_candidate_id", "Source NK Candidate ID", indent);
    try printIndentedField(writer, obj, "sourceCorrectionReviewId", "Source Correction Review ID", indent);
    try printIndentedField(writer, obj, "source_correction_review_id", "Source Correction Review ID", indent);
    try printIndentedField(writer, obj, "reviewDecision", "Decision", indent);
    try printIndentedField(writer, obj, "decision", "Decision", indent);
    try printIndentedField(writer, obj, "reviewerNote", "Reviewer Note", indent);
    try printIndentedField(writer, obj, "reviewer_note", "Reviewer Note", indent);
    try printIndentedField(writer, obj, "reviewerNoteSummary", "Reviewer Note Summary", indent);
    try printIndentedField(writer, obj, "rejectedReason", "Rejected Reason", indent);
    try printIndentedField(writer, obj, "rejected_reason", "Rejected Reason", indent);
    try printIndentedField(writer, obj, "createdAt", "Created At", indent);
    try printIndentedField(writer, obj, "appendOrderTimestamp", "Append Order Timestamp", indent);
    try printIndentedField(writer, obj, "influenceScope", "Influence Scope", indent);
    try printIndentedField(writer, obj, "nonAuthorizing", "Non-Authorizing", indent);
    try printIndentedField(writer, obj, "treatedAsProof", "Treated As Proof", indent);
    try printIndentedField(writer, obj, "usedAsEvidence", "Used As Evidence", indent);
    try printIndentedField(writer, obj, "globalPromotion", "Global Promotion", indent);
    try printIndentedField(writer, obj, "commandsExecuted", "Commands Executed", indent);
    try printIndentedField(writer, obj, "verifiersExecuted", "Verifiers Executed", indent);
    try printIndentedField(writer, obj, "corpusMutation", "Corpus Mutation", indent);
    try printIndentedField(writer, obj, "packMutation", "Pack Mutation", indent);
    try printIndentedField(writer, obj, "negativeKnowledgeMutation", "Negative Knowledge Mutation", indent);
    try printIndentedSection(writer, obj, "negativeKnowledgeCandidate", "Candidate Snapshot", indent);
    try printIndentedSection(writer, obj, "negative_knowledge_candidate", "Candidate Snapshot", indent);
    try printIndentedSection(writer, obj, "candidateSnapshot", "Candidate Snapshot", indent);
    try printIndentedSection(writer, obj, "appendOnly", "Append-Only Metadata", indent);
    try printIndentedSection(writer, obj, "append_only", "Append-Only Metadata", indent);
    try printIndentedSection(writer, obj, "mutationFlags", "Mutation Flags", indent);
    try printIndentedSection(writer, obj, "authority", "Authority Flags", indent);
    try printIndentedSection(writer, obj, "authorityFlags", "Authority Flags", indent);
}

fn findNegativeKnowledgeReview(value: std.json.Value) ?std.json.Value {
    const obj = switch (value) {
        .object => |o| o,
        else => return null,
    };
    if (obj.get("negativeKnowledgeReview")) |review| return review;
    if (obj.get("negative_knowledge_review")) |review| return review;
    if (obj.get("result")) |result| {
        const result_obj = switch (result) {
            .object => |o| o,
            else => return result,
        };
        if (result_obj.get("negativeKnowledgeReview")) |review| return review;
        if (result_obj.get("negative_knowledge_review")) |review| return review;
        return result;
    }
    return null;
}

fn findReviewedNegativeKnowledge(value: std.json.Value) ?std.json.Value {
    const obj = switch (value) {
        .object => |o| o,
        else => return null,
    };
    if (obj.get("reviewedNegativeKnowledge")) |reviewed| return reviewed;
    if (obj.get("reviewed_negative_knowledge")) |reviewed| return reviewed;
    if (obj.get("result")) |result| {
        const result_obj = switch (result) {
            .object => |o| o,
            else => return result,
        };
        if (result_obj.get("reviewedNegativeKnowledge")) |reviewed| return reviewed;
        if (result_obj.get("reviewed_negative_knowledge")) |reviewed| return reviewed;
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

fn hasKind(value: std.json.Value, expected_kind: []const u8) bool {
    const obj = switch (value) {
        .object => |o| o,
        else => return false,
    };
    const kind = obj.get("kind") orelse return false;
    return switch (kind) {
        .string => |s| std.mem.eql(u8, s, expected_kind),
        else => false,
    };
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

fn printIndentedField(writer: anytype, obj: std.json.ObjectMap, field: []const u8, label: []const u8, indent: usize) !void {
    const value = obj.get(field) orelse return;
    try writer.writeByteNTimes(' ', indent);
    try writer.print("{s}: ", .{label});
    try printInlineJsonValue(writer, value);
    try writer.print("\n", .{});
}

fn printIndentedSection(writer: anytype, obj: std.json.ObjectMap, field: []const u8, label: []const u8, indent: usize) !void {
    const value = obj.get(field) orelse return;
    if (isEmptyJsonList(value)) return;
    try writer.writeByteNTimes(' ', indent);
    try writer.print("{s}:\n", .{label});
    try printJsonValue(writer, value, indent + 2);
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

fn getString(obj: std.json.ObjectMap, field: []const u8) ?[]const u8 {
    const value = obj.get(field) orelse return null;
    return switch (value) {
        .string => |s| s,
        else => null,
    };
}

fn parseValueArg(args: []const []const u8, index: *usize, arg: []const u8, flag: []const u8) !?[]const u8 {
    if (std.mem.eql(u8, arg, flag)) {
        index.* += 1;
        if (index.* >= args.len) try failMissingValue(flag);
        const value = args[index.*];
        if (std.mem.trim(u8, value, " \r\n\t").len == 0) try failMissingValue(flag);
        return value;
    }
    if (arg.len > flag.len + 1 and std.mem.startsWith(u8, arg, flag) and arg[flag.len] == '=') {
        const value = arg[flag.len + 1 ..];
        if (value.len == 0) try failMissingValue(flag);
        return value;
    }
    return null;
}

fn parsePositiveUsize(flag: []const u8, raw: []const u8) usize {
    const value = std.fmt.parseInt(usize, raw, 10) catch {
        std.io.getStdErr().writer().print("Invalid {s} value: {s}. Use a positive integer.\n", .{ flag, raw }) catch {};
        std.process.exit(1);
    };
    if (value == 0) {
        std.io.getStdErr().writer().print("Invalid {s} value: 0. Use a positive integer.\n", .{flag}) catch {};
        std.process.exit(1);
    }
    return value;
}

fn parseNonNegativeUsize(flag: []const u8, raw: []const u8) usize {
    return std.fmt.parseInt(usize, raw, 10) catch {
        std.io.getStdErr().writer().print("Invalid {s} value: {s}. Use a non-negative integer.\n", .{ flag, raw }) catch {};
        std.process.exit(1);
    };
}

fn requireNonEmpty(value: ?[]const u8, message: []const u8) []const u8 {
    const actual = value orelse {
        std.io.getStdErr().writer().print("{s}\n", .{message}) catch {};
        std.process.exit(1);
    };
    if (std.mem.trim(u8, actual, " \r\n\t").len == 0) {
        std.io.getStdErr().writer().print("{s}\n", .{message}) catch {};
        std.process.exit(1);
    }
    return actual;
}

fn failMissingValue(flag: []const u8) !noreturn {
    try std.io.getStdErr().writer().print("{s} requires a value\n", .{flag});
    std.process.exit(1);
}
