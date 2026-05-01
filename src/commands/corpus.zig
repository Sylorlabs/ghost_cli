const std = @import("std");
const locator = @import("../engine/locator.zig");
const process = @import("../engine/process.zig");

pub const CorpusAskOptions = struct {
    question: ?[]const u8 = null,
    project_shard: ?[]const u8 = null,
    max_results: ?u64 = null,
    max_snippet_bytes: ?u64 = null,
    require_citations: bool = false,
    json: bool = false,
    debug: bool = false,
};

const usage = "Usage: ghost corpus ask [--json] [--debug] [--project-shard <id>] [--max-results <n>] [--max-snippet-bytes <n>] [--require-citations] <question>\n";

pub fn printHelp(writer: anytype) !void {
    try writer.print(
        \\corpus
        \\
        \\Usage: ghost corpus ask [--json] [--debug] [--project-shard <id>] [--max-results <n>] [--max-snippet-bytes <n>] [--require-citations] <question>
        \\
        \\Ask a draft-only question from explicitly ingested live shard corpus evidence.
        \\
        \\Subcommands:
        \\  ask <question>  Run an explicit corpus.ask GIP request
        \\
        \\Options:
        \\  --project-shard <id>       Target shard id
        \\  --max-results <n>          Bound evidence result count
        \\  --max-snippet-bytes <n>    Bound snippet bytes per evidence item
        \\  --require-citations        Require cited evidence for answer drafts
        \\  --json                     Preserve raw GIP stdout exactly
        \\  --debug                    Diagnostics to stderr
        \\
        \\Safety:
        \\  This request runs only when this command is explicitly invoked.
        \\  It routes to ghost_gip --stdin with kind corpus.ask.
        \\  Output is DRAFT / NON-AUTHORIZING; corpus evidence is not proof.
        \\  Retrieval is bounded lexical matching over live shard corpus excerpts.
        \\  It is not semantic search yet, and mounted pack corpus is not included.
        \\  It does not mutate corpus, mutate packs, mutate negative knowledge,
        \\  run commands, run verifiers, or persist learning candidates.
        \\
    , .{});
}

pub fn executeFromArgs(
    allocator: std.mem.Allocator,
    engine_root: ?[]const u8,
    args: []const []const u8,
    base: CorpusAskOptions,
) !void {
    const sub = if (args.len > 0) args[0] else {
        try std.io.getStdErr().writer().print("{s}", .{usage});
        std.process.exit(1);
    };
    if (!std.mem.eql(u8, sub, "ask")) {
        try std.io.getStdErr().writer().print("Unknown corpus command: {s}\n{s}", .{ sub, usage });
        std.process.exit(1);
    }

    var options = base;
    var i: usize = 1;
    while (i < args.len) : (i += 1) {
        const arg = args[i];
        if (std.mem.eql(u8, arg, "--project-shard")) {
            i += 1;
            if (i >= args.len) try failMissingValue("--project-shard");
            options.project_shard = args[i];
        } else if (std.mem.startsWith(u8, arg, "--project-shard=")) {
            options.project_shard = arg["--project-shard=".len..];
        } else if (std.mem.eql(u8, arg, "--max-results")) {
            i += 1;
            if (i >= args.len) try failMissingValue("--max-results");
            options.max_results = try parsePositiveU64("--max-results", args[i]);
        } else if (std.mem.startsWith(u8, arg, "--max-results=")) {
            options.max_results = try parsePositiveU64("--max-results", arg["--max-results=".len..]);
        } else if (std.mem.eql(u8, arg, "--max-snippet-bytes")) {
            i += 1;
            if (i >= args.len) try failMissingValue("--max-snippet-bytes");
            options.max_snippet_bytes = try parsePositiveU64("--max-snippet-bytes", args[i]);
        } else if (std.mem.startsWith(u8, arg, "--max-snippet-bytes=")) {
            options.max_snippet_bytes = try parsePositiveU64("--max-snippet-bytes", arg["--max-snippet-bytes=".len..]);
        } else if (std.mem.eql(u8, arg, "--require-citations")) {
            options.require_citations = true;
        } else if (std.mem.startsWith(u8, arg, "--")) {
            try std.io.getStdErr().writer().print("Unknown corpus ask option: {s}\n", .{arg});
            std.process.exit(1);
        } else if (options.question == null) {
            options.question = arg;
        } else {
            try std.io.getStdErr().writer().print("Unexpected extra corpus ask argument: {s}\n", .{arg});
            std.process.exit(1);
        }
    }

    try executeAsk(allocator, engine_root, options);
}

pub fn executeAsk(allocator: std.mem.Allocator, engine_root: ?[]const u8, options: CorpusAskOptions) !void {
    const question = options.question orelse {
        try std.io.getStdErr().writer().print("{s}", .{usage});
        std.process.exit(1);
    };
    if (std.mem.trim(u8, question, " \r\n\t").len == 0) {
        try std.io.getStdErr().writer().print("corpus ask question must be non-empty\n", .{});
        std.process.exit(1);
    }

    const bin_path = locator.findEngineBinary(allocator, engine_root, .ghost_gip) catch |err| {
        try locator.printLocatorError(std.io.getStdErr().writer(), .ghost_gip, engine_root, err);
        std.process.exit(1);
    };
    defer allocator.free(bin_path);

    var request = std.ArrayList(u8).init(allocator);
    defer request.deinit();
    try writeCorpusAskRequest(request.writer(), question, options);

    const argv = &[_][]const u8{ bin_path, "--stdin" };
    if (options.debug) {
        try std.io.getStdErr().writer().print("[DEBUG] Engine Binary: {s}\n", .{bin_path});
        try std.io.getStdErr().writer().print("[DEBUG] GIP Kind: corpus.ask\n", .{});
        try printDebugArgv(std.io.getStdErr().writer(), argv);
        try std.io.getStdErr().writer().print("[DEBUG] Stdin Payload Summary: bytes={d} question_bytes={d} project_shard={s} max_results={s} max_snippet_bytes={s} require_citations={s}\n", .{
            request.items.len,
            question.len,
            if (options.project_shard != null) "set" else "unset",
            if (options.max_results != null) "set" else "unset",
            if (options.max_snippet_bytes != null) "set" else "unset",
            if (options.require_citations) "set" else "unset",
        });
    }

    const result = process.runEngineCommandWithInput(allocator, argv, request.items) catch |err| {
        try std.io.getStdErr().writer().print("\x1b[31m[!] Error:\x1b[0m Failed to execute corpus.ask: {}\n", .{err});
        try std.io.getStdErr().writer().print("\x1b[33mHint:\x1b[0m Run `ghost status` to verify your environment.\n", .{});
        std.process.exit(1);
    };
    defer {
        allocator.free(result.stdout);
        allocator.free(result.stderr);
    }

    if (options.debug) {
        try std.io.getStdErr().writer().print("[DEBUG] Exit Code: {d}\n", .{result.exit_code});
    }

    if (options.json) {
        if (options.debug) try std.io.getStdErr().writer().print("[DEBUG] JSON Parse: SKIPPED (raw passthrough)\n", .{});
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
        if (options.debug) try std.io.getStdErr().writer().print("[DEBUG] JSON Parse: FAILED ({s})\n", .{@errorName(err)});
        try std.io.getStdErr().writer().print("Error: Failed to parse engine output as corpus.ask JSON.\n", .{});
        try std.io.getStdErr().writer().print("Raw output:\n{s}\n", .{result.stdout});
        return;
    };
    defer parsed.deinit();

    if (options.debug) {
        try std.io.getStdErr().writer().print("[DEBUG] JSON Parse: SUCCESS\n", .{});
    }

    try printCorpusAskResult(std.io.getStdOut().writer(), parsed.value);
}

fn writeCorpusAskRequest(writer: anytype, question: []const u8, options: CorpusAskOptions) !void {
    try writer.writeAll("{\"gipVersion\":\"gip.v0.1\",\"kind\":\"corpus.ask\",\"question\":");
    try std.json.stringify(question, .{}, writer);
    if (options.project_shard) |project_shard| {
        try writer.writeAll(",\"projectShard\":");
        try std.json.stringify(project_shard, .{}, writer);
    }
    if (options.max_results) |max_results| try writer.print(",\"maxResults\":{d}", .{max_results});
    if (options.max_snippet_bytes) |max_snippet_bytes| try writer.print(",\"maxSnippetBytes\":{d}", .{max_snippet_bytes});
    if (options.require_citations) try writer.writeAll(",\"requireCitations\":true");
    try writer.writeAll("}");
}

fn printCorpusAskResult(writer: anytype, value: std.json.Value) !void {
    try writer.print("Corpus Ask Result\n", .{});
    try writer.print("State: DRAFT\n", .{});
    try writer.print("Authority: NON-AUTHORIZING\n\n", .{});

    const corpus_value = findCorpusAsk(value) orelse {
        try writer.print("No corpus.ask result payload was present.\n", .{});
        return;
    };
    const corpus = switch (corpus_value) {
        .object => |obj| obj,
        else => {
            try printJsonValue(writer, corpus_value, 2);
            try writer.print("\n", .{});
            return;
        },
    };

    if (getString(corpus, "status")) |status| try writer.print("Status: {s}\n", .{status});
    if (getString(corpus, "state")) |state| try writer.print("Engine State: {s}\n", .{state});
    if (getString(corpus, "permission")) |permission| try writer.print("Permission: {s}\n", .{permission});

    const unknowns = corpus.get("unknowns");
    if (corpus.get("answerDraft")) |answer| {
        try writer.print("\nAnswer Draft:\n", .{});
        try printJsonValue(writer, answer, 2);
        try writer.print("\n", .{});
    } else {
        try writer.print("\nNo answer was produced.\n", .{});
        if (hasUnknownKind(unknowns, "no_corpus_available")) {
            try writer.print("No live shard corpus is available for this ask request.\n", .{});
        } else if (hasUnknownKind(unknowns, "conflicting_evidence")) {
            try writer.print("Conflicting corpus evidence was reported, so no answer draft is rendered.\n", .{});
        } else if (hasUnknownKind(unknowns, "insufficient_evidence")) {
            try writer.print("Corpus evidence was insufficient, so no answer draft is rendered.\n", .{});
        }
    }

    if (corpus.get("evidenceUsed")) |evidence| {
        if (!isEmptyJsonList(evidence)) {
            try writer.print("\nEvidence Used:\n", .{});
            try printEvidenceUsed(writer, evidence);
        }
    }

    if (unknowns) |u| {
        if (!isEmptyJsonList(u)) {
            try writer.print("\nUnknowns:\n", .{});
            try printJsonValue(writer, u, 2);
        }
    }

    if (corpus.get("candidateFollowups")) |followups| {
        if (!isEmptyJsonList(followups)) {
            try writer.print("\nCandidate Followups:\n", .{});
            try printJsonValue(writer, followups, 2);
        }
    }

    if (corpus.get("learningCandidates")) |candidates| {
        if (!isEmptyJsonList(candidates)) {
            try writer.print("\nLearning Candidates: CANDIDATE ONLY / NOT PERSISTED\n", .{});
            try printJsonValue(writer, candidates, 2);
        }
    }

    if (corpus.get("trace")) |trace| {
        try writer.print("\nTrace Flags:\n", .{});
        try printTraceFlag(writer, trace, "corpusMutation");
        try printTraceFlag(writer, trace, "packMutation");
        try printTraceFlag(writer, trace, "negativeKnowledgeMutation");
        try printTraceFlag(writer, trace, "commandsExecuted");
        try printTraceFlag(writer, trace, "verifiersExecuted");
        try printOptionalTraceField(writer, trace, "corpusEntriesConsidered");
        try printOptionalTraceField(writer, trace, "maxResults");
        try printOptionalTraceField(writer, trace, "maxSnippetBytes");
        try printOptionalTraceField(writer, trace, "requireCitations");
    }

    try writer.print("\nNotice: This output is a DRAFT and NON-AUTHORIZING.\n", .{});
    try writer.print("Corpus ask uses bounded lexical matching over live corpus excerpts only; it is not semantic search and it does not include mounted pack corpus yet.\n", .{});
}

fn findCorpusAsk(value: std.json.Value) ?std.json.Value {
    const obj = switch (value) {
        .object => |obj| obj,
        else => return null,
    };
    if (obj.get("corpusAsk")) |corpus| return corpus;
    if (obj.get("corpus_ask")) |corpus| return corpus;
    if (obj.get("result")) |result| {
        const result_obj = switch (result) {
            .object => |o| o,
            else => return result,
        };
        if (result_obj.get("corpusAsk")) |corpus| return corpus;
        if (result_obj.get("corpus_ask")) |corpus| return corpus;
        return result;
    }
    return null;
}

fn printEvidenceUsed(writer: anytype, value: std.json.Value) !void {
    switch (value) {
        .array => |arr| {
            for (arr.items, 0..) |item, idx| {
                try writer.print("  - evidence #{d}\n", .{idx + 1});
                try printEvidenceItem(writer, item);
            }
        },
        else => try printEvidenceItem(writer, value),
    }
}

fn printEvidenceItem(writer: anytype, value: std.json.Value) !void {
    const obj = switch (value) {
        .object => |obj| obj,
        else => {
            try writer.print("    ", .{});
            try printJsonValue(writer, value, 4);
            try writer.print("\n", .{});
            return;
        },
    };
    try printOptionalEvidenceField(writer, obj, "itemId", "itemId");
    try printOptionalEvidenceField(writer, obj, "path", "path");
    try printOptionalEvidenceField(writer, obj, "sourcePath", "sourcePath");
    try printOptionalEvidenceField(writer, obj, "class", "class");
    try printOptionalEvidenceField(writer, obj, "snippet", "snippet");
    try printOptionalEvidenceField(writer, obj, "reason", "reason");
    try printOptionalEvidenceField(writer, obj, "provenance", "provenance");
    try printOptionalEvidenceField(writer, obj, "score", "score");
}

fn printOptionalEvidenceField(writer: anytype, obj: std.json.ObjectMap, field: []const u8, label: []const u8) !void {
    if (obj.get(field)) |value| {
        try writer.print("    {s}: ", .{label});
        try printJsonValue(writer, value, 6);
        try writer.print("\n", .{});
    }
}

fn printTraceFlag(writer: anytype, trace: std.json.Value, field: []const u8) !void {
    const obj = switch (trace) {
        .object => |obj| obj,
        else => return,
    };
    if (obj.get(field)) |value| {
        try writer.print("  {s}: ", .{field});
        try printJsonValue(writer, value, 4);
        try writer.print("\n", .{});
    }
}

fn printOptionalTraceField(writer: anytype, trace: std.json.Value, field: []const u8) !void {
    try printTraceFlag(writer, trace, field);
}

fn hasUnknownKind(value: ?std.json.Value, kind: []const u8) bool {
    const actual = value orelse return false;
    return switch (actual) {
        .array => |arr| blk: {
            for (arr.items) |item| {
                if (hasUnknownKind(item, kind)) break :blk true;
            }
            break :blk false;
        },
        .object => |obj| blk: {
            if (getString(obj, "kind")) |actual_kind| {
                if (std.mem.eql(u8, actual_kind, kind)) break :blk true;
            }
            break :blk false;
        },
        else => false,
    };
}

fn isEmptyJsonList(value: std.json.Value) bool {
    return switch (value) {
        .array => |arr| arr.items.len == 0,
        .null => true,
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
    while (i < indent) : (i += 1) try writer.writeByte(' ');
}

fn printDebugArgv(writer: anytype, argv: []const []const u8) !void {
    try writer.print("[DEBUG] Arguments:", .{});
    for (argv) |arg| try writer.print(" '{s}'", .{arg});
    try writer.print("\n", .{});
}

fn failMissingValue(flag: []const u8) !noreturn {
    try std.io.getStdErr().writer().print("{s} requires a value\n", .{flag});
    std.process.exit(1);
}

fn parsePositiveU64(flag: []const u8, value: []const u8) !u64 {
    const parsed = std.fmt.parseUnsigned(u64, value, 10) catch {
        try std.io.getStdErr().writer().print("Invalid {s} value: {s}\n", .{ flag, value });
        std.process.exit(1);
    };
    if (parsed == 0) {
        try std.io.getStdErr().writer().print("{s} must be greater than 0\n", .{flag});
        std.process.exit(1);
    }
    return parsed;
}
