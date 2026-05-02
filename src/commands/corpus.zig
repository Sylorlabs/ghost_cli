const std = @import("std");
const locator = @import("../engine/locator.zig");
const process = @import("../engine/process.zig");

pub const CorpusOptions = struct {
    question: ?[]const u8 = null,
    corpus_path: ?[]const u8 = null,
    project_shard: ?[]const u8 = null,
    trust_class: ?[]const u8 = null,
    source_label: ?[]const u8 = null,
    max_results: ?u64 = null,
    max_snippet_bytes: ?u64 = null,
    require_citations: bool = false,
    json: bool = false,
    debug: bool = false,
};

const usage =
    \\Usage: ghost corpus <ingest|apply-staged|ask> [options]
    \\
    \\  ghost corpus ingest <path> --project-shard=<id> --trust-class=<class> --source-label=<label>
    \\  ghost corpus apply-staged --project-shard=<id>
    \\  ghost corpus ask [--json] [--debug] [--project-shard=<id>] <question>
    \\
;

pub fn printHelp(writer: anytype) !void {
    try writer.print(
        \\corpus
        \\
        \\Usage: ghost corpus <ingest|apply-staged|ask> [options]
        \\
        \\Manage explicitly invoked corpus lifecycle commands and ask draft-only
        \\questions from live shard corpus evidence.
        \\
        \\Subcommands:
        \\  ingest <path>       Stage corpus data through ghost_corpus_ingest
        \\  apply-staged        Promote staged corpus into the live shard corpus
        \\  ask <question>      Run an explicit corpus.ask GIP request over live corpus
        \\
        \\Use:
        \\  ghost corpus ingest --help
        \\  ghost corpus apply-staged --help
        \\  ghost corpus ask --help
        \\
        \\Safety:
        \\  Ingest stages corpus only. Ask reads live shard corpus only.
        \\  Staged corpus is not visible to ask until apply-staged succeeds.
        \\  Retrieval is bounded local matching, not semantic search.
        \\  Exact evidence is required for answer drafts. Similarity hints may
        \\  appear as NON-AUTHORIZING routing hints only.
        \\  Capacity telemetry is explicit: skipped, dropped, truncated, or
        \\  capped data means partial coverage and cannot support an answer.
        \\  Accepted reviewed corrections and reviewed negative knowledge may
        \\  influence ask results as warnings, suppression, or candidate-only
        \\  future behavior, but they are not proof or evidence and do not
        \\  mutate corpus, packs, corrections, or negative knowledge.
        \\  No Transformers, embeddings, model adapters, hidden learning, pack
        \\  mutation, negative-knowledge mutation, verifier execution, or
        \\  automatic startup corpus operation is performed by this command group.
        \\
    , .{});
}

pub fn printHelpForArgs(writer: anytype, args: []const []const u8) !void {
    if (args.len == 0) return printHelp(writer);
    if (std.mem.eql(u8, args[0], "ingest")) return printIngestHelp(writer);
    if (std.mem.eql(u8, args[0], "apply-staged")) return printApplyStagedHelp(writer);
    if (std.mem.eql(u8, args[0], "ask")) return printAskHelp(writer);
    return printHelp(writer);
}

fn printIngestHelp(writer: anytype) !void {
    try writer.print(
        \\corpus ingest
        \\
        \\Usage: ghost corpus ingest <path> [--project-shard=<id>] [--trust-class=<class>] [--source-label=<label>] [--json] [--debug]
        \\
        \\Stages corpus data through ghost_corpus_ingest. Staged corpus is not live
        \\and cannot be read by corpus.ask until `ghost corpus apply-staged` is run.
        \\
        \\Options:
        \\  --project-shard <id>       Target shard id
        \\  --trust-class <class>      exploratory|project|promoted|core
        \\  --source-label <label>     Source label recorded by the engine
        \\  --json                     Preserve raw engine stdout exactly
        \\  --debug                    Diagnostics to stderr
        \\
    , .{});
}

fn printApplyStagedHelp(writer: anytype) !void {
    try writer.print(
        \\corpus apply-staged
        \\
        \\Usage: ghost corpus apply-staged [--project-shard=<id>] [--json] [--debug]
        \\
        \\Promotes the selected shard's staged corpus into the live corpus. After
        \\apply-staged succeeds, `ghost corpus ask` can read the live shard corpus.
        \\
        \\Options:
        \\  --project-shard <id>       Target shard id
        \\  --json                     Preserve raw engine stdout exactly
        \\  --debug                    Diagnostics to stderr
        \\
    , .{});
}

fn printAskHelp(writer: anytype) !void {
    try writer.print(
        \\corpus ask
        \\
        \\Usage: ghost corpus ask [--json] [--debug] [--project-shard <id>] [--max-results <n>] [--max-snippet-bytes <n>] [--require-citations] <question>
        \\
        \\Ask a draft-only question from explicitly applied live shard corpus evidence.
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
        \\  It reads live shard corpus only; staged corpus is invisible until apply-staged.
        \\  Retrieval is bounded local matching over live shard corpus excerpts.
        \\  Exact evidence is required for answer drafts. Similarity hints may
        \\  appear as NON-AUTHORIZING routing hints only, never as evidence.
        \\  Capacity warnings mean partial coverage: skipped, dropped,
        \\  truncated, or capped data cannot support an answer.
        \\  Accepted reviewed corrections and reviewed negative knowledge may
        \\  appear as NON-AUTHORIZING influence, warnings, telemetry, or future
        \\  behavior candidates. They are not proof, not evidence, and may
        \\  suppress exact repeated bad answer patterns without globally
        \\  promoting anything.
        \\  It is not semantic search, and mounted pack corpus is not included.
        \\  It does not use Transformers, embeddings, or model adapters.
        \\  It does not mutate corpus, mutate packs, mutate negative knowledge,
        \\  run commands, run verifiers, or persist learning candidates.
        \\
    , .{});
}

pub fn executeFromArgs(
    allocator: std.mem.Allocator,
    engine_root: ?[]const u8,
    args: []const []const u8,
    base: CorpusOptions,
) !void {
    const sub = if (args.len > 0) args[0] else {
        try std.io.getStdErr().writer().print("{s}", .{usage});
        std.process.exit(1);
    };
    if (std.mem.eql(u8, sub, "ingest")) {
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
            } else if (std.mem.eql(u8, arg, "--trust-class")) {
                i += 1;
                if (i >= args.len) try failMissingValue("--trust-class");
                options.trust_class = args[i];
            } else if (std.mem.startsWith(u8, arg, "--trust-class=")) {
                options.trust_class = arg["--trust-class=".len..];
            } else if (std.mem.eql(u8, arg, "--source-label")) {
                i += 1;
                if (i >= args.len) try failMissingValue("--source-label");
                options.source_label = args[i];
            } else if (std.mem.startsWith(u8, arg, "--source-label=")) {
                options.source_label = arg["--source-label=".len..];
            } else if (std.mem.startsWith(u8, arg, "--")) {
                try std.io.getStdErr().writer().print("Unknown corpus ingest option: {s}\n", .{arg});
                std.process.exit(1);
            } else if (options.corpus_path == null) {
                options.corpus_path = arg;
            } else {
                try std.io.getStdErr().writer().print("Unexpected extra corpus ingest argument: {s}\n", .{arg});
                std.process.exit(1);
            }
        }
        try executeIngest(allocator, engine_root, options);
        return;
    }

    if (std.mem.eql(u8, sub, "apply-staged")) {
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
            } else if (std.mem.startsWith(u8, arg, "--")) {
                try std.io.getStdErr().writer().print("Unknown corpus apply-staged option: {s}\n", .{arg});
                std.process.exit(1);
            } else {
                try std.io.getStdErr().writer().print("Unexpected corpus apply-staged argument: {s}\n", .{arg});
                std.process.exit(1);
            }
        }
        try executeApplyStaged(allocator, engine_root, options);
        return;
    }

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

pub fn executeIngest(allocator: std.mem.Allocator, engine_root: ?[]const u8, options: CorpusOptions) !void {
    const corpus_path = options.corpus_path orelse {
        try printIngestHelp(std.io.getStdErr().writer());
        std.process.exit(1);
    };
    if (std.mem.trim(u8, corpus_path, " \r\n\t").len == 0) {
        try std.io.getStdErr().writer().print("corpus ingest path must be non-empty\n", .{});
        std.process.exit(1);
    }
    try runCorpusIngest(allocator, engine_root, .ingest, corpus_path, options);
}

pub fn executeApplyStaged(allocator: std.mem.Allocator, engine_root: ?[]const u8, options: CorpusOptions) !void {
    try runCorpusIngest(allocator, engine_root, .apply_staged, null, options);
}

const IngestMode = enum { ingest, apply_staged };

fn runCorpusIngest(
    allocator: std.mem.Allocator,
    engine_root: ?[]const u8,
    mode: IngestMode,
    corpus_path: ?[]const u8,
    options: CorpusOptions,
) !void {
    const bin_path = locator.findEngineBinary(allocator, engine_root, .ghost_corpus_ingest) catch |err| {
        try locator.printLocatorError(std.io.getStdErr().writer(), .ghost_corpus_ingest, engine_root, err);
        std.process.exit(1);
    };
    defer allocator.free(bin_path);

    var argv_list = std.ArrayList([]const u8).init(allocator);
    defer argv_list.deinit();
    try argv_list.append(bin_path);
    switch (mode) {
        .ingest => try argv_list.append(corpus_path.?),
        .apply_staged => try argv_list.append("--apply-staged"),
    }
    if (options.project_shard) |value| try argv_list.append(try std.fmt.allocPrint(allocator, "--project-shard={s}", .{value}));
    if (mode == .ingest) {
        if (options.trust_class) |value| try argv_list.append(try std.fmt.allocPrint(allocator, "--trust-class={s}", .{value}));
        if (options.source_label) |value| try argv_list.append(try std.fmt.allocPrint(allocator, "--source-label={s}", .{value}));
    }
    defer {
        for (argv_list.items[2..]) |arg| {
            if (std.mem.startsWith(u8, arg, "--project-shard=") or
                std.mem.startsWith(u8, arg, "--trust-class=") or
                std.mem.startsWith(u8, arg, "--source-label="))
            {
                allocator.free(arg);
            }
        }
    }

    if (options.debug) {
        try std.io.getStdErr().writer().print("[DEBUG] Engine Binary: {s}\n", .{bin_path});
        try std.io.getStdErr().writer().print("[DEBUG] Corpus Operation: {s}\n", .{if (mode == .ingest) "ingest" else "apply-staged"});
        try printDebugArgv(std.io.getStdErr().writer(), argv_list.items);
        if (options.json) try std.io.getStdErr().writer().print("[DEBUG] JSON Flag: not forwarded; ghost_corpus_ingest emits JSON without --json at engine 707ae0c\n", .{});
    }

    const result = process.runEngineCommand(allocator, argv_list.items) catch |err| {
        try std.io.getStdErr().writer().print("\x1b[31m[!] Error:\x1b[0m Failed to execute corpus {s}: {}\n", .{ if (mode == .ingest) "ingest" else "apply-staged", err });
        try std.io.getStdErr().writer().print("\x1b[33mHint:\x1b[0m Run `ghost status` to verify your environment.\n", .{});
        std.process.exit(1);
    };
    defer {
        allocator.free(result.stdout);
        allocator.free(result.stderr);
    }

    if (options.debug) try std.io.getStdErr().writer().print("[DEBUG] Exit Code: {d}\n", .{result.exit_code});

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
        try std.io.getStdOut().writer().writeAll(result.stdout);
        return;
    };
    defer parsed.deinit();
    if (options.debug) try std.io.getStdErr().writer().print("[DEBUG] JSON Parse: SUCCESS\n", .{});

    if (mode == .ingest) {
        try printCorpusIngestResult(std.io.getStdOut().writer(), parsed.value);
    } else {
        try printCorpusApplyResult(std.io.getStdOut().writer(), parsed.value);
    }
}

pub fn executeAsk(allocator: std.mem.Allocator, engine_root: ?[]const u8, options: CorpusOptions) !void {
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

fn writeCorpusAskRequest(writer: anytype, question: []const u8, options: CorpusOptions) !void {
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

fn printCorpusIngestResult(writer: anytype, value: std.json.Value) !void {
    try writer.print("Corpus Ingest Result\n", .{});
    try writer.print("State: STAGED\n", .{});
    try writer.print("Visibility: NOT LIVE until `ghost corpus apply-staged` succeeds.\n\n", .{});
    try printTopLevelString(writer, value, "status", "Status");
    try printTopLevelString(writer, value, "manifest", "Staged Manifest");
    try printTopLevelString(writer, value, "stagedManifest", "Staged Manifest");
    try printTopLevelString(writer, value, "stagedFilesRoot", "Staged Files Root");
    try printTopLevelString(writer, value, "sourceLabel", "Source Label");
    try printTopLevelString(writer, value, "trustClass", "Trust Class");
    try printTopLevelInt(writer, value, "fileCount", "Files Staged");
    try printTopLevelInt(writer, value, "itemCount", "Items Staged");
    try printTopLevelInt(writer, value, "bytesRead", "Bytes Read");
    try writer.print("\nNotice: staged corpus is not visible to `ghost corpus ask` until apply-staged.\n", .{});
}

fn printCorpusApplyResult(writer: anytype, value: std.json.Value) !void {
    try writer.print("Corpus Apply-Staged Result\n", .{});
    try writer.print("State: LIVE\n", .{});
    try writer.print("Visibility: staged corpus was applied/promoted to the live shard corpus.\n\n", .{});
    try printTopLevelString(writer, value, "status", "Status");
    try printTopLevelString(writer, value, "liveManifest", "Live Manifest");
    try printTopLevelString(writer, value, "liveFilesRoot", "Live Files Root");
    if (topObject(value)) |obj| {
        if (obj.get("shard")) |shard| {
            try writer.print("Shard:\n", .{});
            try printJsonValue(writer, shard, 2);
        }
    }
    try writer.print("\nNotice: `ghost corpus ask` reads live shard corpus only and remains DRAFT / NON-AUTHORIZING.\n", .{});
}

fn topObject(value: std.json.Value) ?std.json.ObjectMap {
    return switch (value) {
        .object => |obj| obj,
        else => null,
    };
}

fn printTopLevelString(writer: anytype, value: std.json.Value, field: []const u8, label: []const u8) !void {
    const obj = topObject(value) orelse return;
    if (getString(obj, field)) |s| try writer.print("{s}: {s}\n", .{ label, s });
}

fn printTopLevelInt(writer: anytype, value: std.json.Value, field: []const u8, label: []const u8) !void {
    const obj = topObject(value) orelse return;
    const v = obj.get(field) orelse return;
    switch (v) {
        .integer => |i| try writer.print("{s}: {d}\n", .{ label, i }),
        else => {},
    }
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
    const capacity_telemetry = corpus.get("capacityTelemetry");
    const evidence = corpus.get("evidenceUsed");
    const similar_candidates = corpus.get("similarCandidates");
    const accepted_correction_warnings = corpus.get("acceptedCorrectionWarnings");
    const correction_influences = corpus.get("correctionInfluences");
    const accepted_nk_warnings = corpus.get("acceptedNegativeKnowledgeWarnings");
    const nk_influences = corpus.get("negativeKnowledgeInfluences");
    const nk_telemetry = corpus.get("negativeKnowledgeTelemetry");
    const future_behavior_candidates = corpus.get("futureBehaviorCandidates");
    const influence_telemetry = corpus.get("influenceTelemetry");
    const has_answer = corpus.get("answerDraft") != null;
    const has_evidence = if (evidence) |e| !isEmptyJsonList(e) else false;
    const has_similar_candidates = if (similar_candidates) |s| !isEmptyJsonList(s) else false;
    const has_correction_influence = hasAcceptedCorrectionInfluence(
        accepted_correction_warnings,
        correction_influences,
        future_behavior_candidates,
        influence_telemetry,
    );
    const has_nk_influence = hasReviewedNegativeKnowledgeInfluence(
        accepted_nk_warnings,
        nk_influences,
        future_behavior_candidates,
        nk_telemetry,
    );
    const answer_suppressed_by_correction = !has_answer and hasCorrectionSuppression(
        accepted_correction_warnings,
        correction_influences,
        future_behavior_candidates,
        influence_telemetry,
    );
    const answer_suppressed_by_nk = !has_answer and hasReviewedNegativeKnowledgeSuppression(
        accepted_nk_warnings,
        nk_influences,
        future_behavior_candidates,
        nk_telemetry,
    );
    if ((if (capacity_telemetry) |telemetry| hasCapacityPressure(telemetry) else false) or hasUnknownKind(unknowns, "capacity_limited")) {
        try printCorpusCapacityWarning(writer, capacity_telemetry);
    }
    if (has_correction_influence) {
        try printAcceptedCorrectionInfluence(
            writer,
            accepted_correction_warnings,
            correction_influences,
            future_behavior_candidates,
            influence_telemetry,
        );
    }
    if (has_nk_influence) {
        try printReviewedNegativeKnowledgeInfluence(
            writer,
            "corpus answer",
            accepted_nk_warnings,
            nk_influences,
            future_behavior_candidates,
            nk_telemetry,
        );
    }
    if (corpus.get("answerDraft")) |answer| {
        try writer.print("\nAnswer Draft:\n", .{});
        try printJsonValue(writer, answer, 2);
        try writer.print("\n", .{});
    } else {
        try writer.print("\nNo answer was produced.\n", .{});
        if (answer_suppressed_by_nk) {
            try writer.print("The answer draft was suppressed by reviewed negative knowledge influence from an exact repeated known-bad answer pattern.\n", .{});
        } else if (answer_suppressed_by_correction) {
            try writer.print("The answer draft was suppressed by accepted correction influence from an exact repeated wrong_answer pattern.\n", .{});
        } else if (hasUnknownKind(unknowns, "no_corpus_available")) {
            try writer.print("No live shard corpus is available for this ask request.\n", .{});
        } else if (hasUnknownKind(unknowns, "conflicting_evidence")) {
            try writer.print("Conflicting corpus evidence was reported, so no answer draft is rendered.\n", .{});
        } else if (hasUnknownKind(unknowns, "insufficient_evidence")) {
            try writer.print("Corpus evidence was insufficient, so no answer draft is rendered.\n", .{});
        }
        if (has_similar_candidates and !has_evidence and !has_answer) {
            try writer.print("Similar corpus candidates were found, but no exact evidence supported an answer draft.\n", .{});
        }
    }

    if (evidence) |evidence_value| {
        if (!isEmptyJsonList(evidence_value)) {
            try writer.print("\nEvidence Used:\n", .{});
            try printEvidenceUsed(writer, evidence_value);
        }
    }

    if (similar_candidates) |candidates| {
        if (!isEmptyJsonList(candidates)) {
            try writer.print("\nSimilarity Hints / NON-AUTHORIZING\n", .{});
            try writer.print("These are routing hints, not evidence.\n", .{});
            try writer.print("Exact evidence is still required before Ghost renders an answer draft.\n", .{});
            try printSimilarCandidates(writer, candidates);
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
    try writer.print("Corpus ask uses bounded local matching over live corpus excerpts only; similarity hints are not evidence, it is not semantic search, and it does not include mounted pack corpus yet.\n", .{});
}

fn printCorpusCapacityWarning(writer: anytype, telemetry: ?std.json.Value) !void {
    try writer.print("\nCAPACITY / COVERAGE WARNING\n", .{});
    try writer.print("- Ghost did not inspect or retain all potentially relevant data.\n", .{});
    try writer.print("- Results are partial and non-authorizing.\n", .{});
    try writer.print("- Dropped, skipped, truncated, or capped data cannot support an answer.\n", .{});

    const value = telemetry orelse return;
    const obj = switch (value) {
        .object => |obj| obj,
        else => {
            try writer.print("capacityTelemetry:\n", .{});
            try printJsonValue(writer, value, 2);
            return;
        },
    };
    try printCapacityField(writer, obj, "truncatedInputs");
    try printCapacityField(writer, obj, "truncatedSnippets");
    try printCapacityField(writer, obj, "skippedInputs");
    try printCapacityField(writer, obj, "skippedFiles");
    try printCapacityField(writer, obj, "budgetHits");
    try printCapacityField(writer, obj, "maxResultsHit");
    try printCapacityField(writer, obj, "exactCandidateCapHit");
    try printCapacityField(writer, obj, "sketchCandidateCapHit");
    try printCapacityField(writer, obj, "capacityWarnings");
    try printCapacityField(writer, obj, "expansionRecommended");
    try printCapacityField(writer, obj, "spilloverRecommended");
}

fn hasAcceptedCorrectionInfluence(
    warnings: ?std.json.Value,
    influences: ?std.json.Value,
    future_candidates: ?std.json.Value,
    telemetry: ?std.json.Value,
) bool {
    return (if (warnings) |v| !isEmptyJsonList(v) else false) or
        (if (influences) |v| !isEmptyJsonList(v) else false) or
        (if (future_candidates) |v| hasCorrectionFutureCandidate(v) else false) or
        (if (telemetry) |v| hasInfluenceTelemetrySignal(v) else false);
}

fn hasReviewedNegativeKnowledgeInfluence(
    warnings: ?std.json.Value,
    influences: ?std.json.Value,
    future_candidates: ?std.json.Value,
    telemetry: ?std.json.Value,
) bool {
    return (if (warnings) |v| !isEmptyJsonList(v) else false) or
        (if (influences) |v| !isEmptyJsonList(v) else false) or
        (if (future_candidates) |v| hasReviewedNegativeKnowledgeFutureCandidate(v) else false) or
        (if (telemetry) |v| hasNegativeKnowledgeTelemetrySignal(v) else false);
}

fn hasCorrectionSuppression(
    warnings: ?std.json.Value,
    influences: ?std.json.Value,
    future_candidates: ?std.json.Value,
    telemetry: ?std.json.Value,
) bool {
    return (if (warnings) |v| jsonContainsAny(v, &.{ "wrong_answer", "suppress", "suppressed", "repeated" }) else false) or
        (if (influences) |v| jsonContainsAny(v, &.{ "wrong_answer", "suppress", "suppressed", "repeated" }) else false) or
        (if (future_candidates) |v| jsonContainsAny(v, &.{ "wrong_answer", "suppress", "suppressed", "repeated" }) else false) or
        (if (telemetry) |v| jsonContainsAny(v, &.{ "wrong_answer", "suppress", "suppressed", "repeated" }) else false);
}

fn hasReviewedNegativeKnowledgeSuppression(
    warnings: ?std.json.Value,
    influences: ?std.json.Value,
    future_candidates: ?std.json.Value,
    telemetry: ?std.json.Value,
) bool {
    return (if (warnings) |v| jsonContainsAny(v, &.{ "known-bad", "suppress", "suppressed", "repeated" }) else false) or
        (if (influences) |v| jsonContainsAny(v, &.{ "known-bad", "suppress", "suppressed", "repeated", "suppress_exact_repeat" }) else false) or
        (if (future_candidates) |v| jsonContainsAny(v, &.{ "known-bad", "suppress", "suppressed", "repeated" }) else false) or
        (if (telemetry) |v| hasBoolOrPressureField(v, "answerSuppressed") else false);
}

fn printAcceptedCorrectionInfluence(
    writer: anytype,
    warnings: ?std.json.Value,
    influences: ?std.json.Value,
    future_candidates: ?std.json.Value,
    telemetry: ?std.json.Value,
) !void {
    try writer.print("\nACCEPTED CORRECTION INFLUENCE / NON-AUTHORIZING\n", .{});
    try writer.print("- Accepted corrections influenced this result.\n", .{});
    try writer.print("- This is not proof.\n", .{});
    try writer.print("- This is not evidence.\n", .{});
    try writer.print("- No corpus, pack, or negative-knowledge mutation occurred.\n", .{});
    try writer.print("- Future behavior remains candidate-only unless separately reviewed/applied.\n", .{});
    if (warnings) |value| {
        if (!isEmptyJsonList(value)) {
            try writer.print("acceptedCorrectionWarnings:\n", .{});
            try printJsonValue(writer, value, 2);
        }
    }
    if (influences) |value| {
        if (!isEmptyJsonList(value)) {
            try writer.print("correctionInfluences:\n", .{});
            try printJsonValue(writer, value, 2);
        }
    }
    if (telemetry) |value| {
        if (!isEmptyJsonList(value)) {
            try writer.print("influenceTelemetry:\n", .{});
            try printJsonValue(writer, value, 2);
        }
    }
    if (future_candidates) |value| {
        if (!isEmptyJsonList(value)) {
            try printFutureBehaviorCandidates(writer, value);
        }
    }
}

fn printFutureBehaviorCandidates(writer: anytype, value: std.json.Value) !void {
    try writer.print("\nFUTURE BEHAVIOR CANDIDATES / NOT APPLIED\n", .{});
    try writer.print("- Candidates only.\n", .{});
    try writer.print("- Not persisted as corpus, pack, rule, correction, or negative-knowledge updates by this operation.\n", .{});
    try writer.print("- No verifier/check executed.\n", .{});
    try printJsonValue(writer, value, 2);
}

fn printReviewedNegativeKnowledgeInfluence(
    writer: anytype,
    target: []const u8,
    warnings: ?std.json.Value,
    influences: ?std.json.Value,
    future_candidates: ?std.json.Value,
    telemetry: ?std.json.Value,
) !void {
    try writer.print("\nREVIEWED NEGATIVE KNOWLEDGE INFLUENCE / NON-AUTHORIZING\n", .{});
    try writer.print("- Reviewed negative knowledge influenced this {s}.\n", .{target});
    try writer.print("- This is not proof.\n", .{});
    try writer.print("- This is not evidence.\n", .{});
    try writer.print("- No corpus, pack, correction, or negative-knowledge mutation occurred.\n", .{});
    try writer.print("- Future behavior remains candidate-only unless separately reviewed/applied.\n", .{});
    if (hasReviewedNegativeKnowledgeSuppression(warnings, influences, future_candidates, telemetry)) {
        try writer.print("- The output was suppressed by reviewed negative knowledge influence and is not rendered as active.\n", .{});
    }
    if (warnings) |value| {
        if (!isEmptyJsonList(value)) {
            try writer.print("acceptedNegativeKnowledgeWarnings:\n", .{});
            try printJsonValue(writer, value, 2);
        }
    }
    if (influences) |value| {
        if (!isEmptyJsonList(value)) {
            try writer.print("negativeKnowledgeInfluences:\n", .{});
            try printJsonValue(writer, value, 2);
        }
    }
    if (telemetry) |value| {
        if (hasNegativeKnowledgeTelemetrySignal(value)) {
            try writer.print("negativeKnowledgeTelemetry:\n", .{});
            try printJsonValue(writer, value, 2);
        }
    }
    if (future_candidates) |value| {
        if (!isEmptyJsonList(value)) {
            try printFutureBehaviorCandidates(writer, value);
        }
    }
}

fn hasInfluenceTelemetrySignal(value: std.json.Value) bool {
    const obj = switch (value) {
        .object => |obj| obj,
        else => return !isEmptyJsonList(value),
    };
    return hasPressureField(obj, "reviewedRecordsRead") or
        hasPressureField(obj, "acceptedRecordsRead") or
        hasPressureField(obj, "rejectedRecordsRead") or
        hasPressureField(obj, "malformedLines") or
        hasPressureField(obj, "warnings") or
        hasPressureField(obj, "matchedInfluences") or
        hasPressureField(obj, "answerSuppressed") or
        hasPressureField(obj, "boundedReadTruncated");
}

fn hasNegativeKnowledgeTelemetrySignal(value: std.json.Value) bool {
    const obj = switch (value) {
        .object => |obj| obj,
        else => return !isEmptyJsonList(value),
    };
    return hasPressureField(obj, "recordsRead") or
        hasPressureField(obj, "acceptedRecords") or
        hasPressureField(obj, "rejectedRecords") or
        hasPressureField(obj, "malformedLines") or
        hasPressureField(obj, "warnings") or
        hasPressureField(obj, "influencesLoaded") or
        hasPressureField(obj, "influencesApplied") or
        hasPressureField(obj, "answerSuppressed") or
        hasPressureField(obj, "outputsSuppressed") or
        hasPressureField(obj, "truncated") or
        hasPressureField(obj, "mutationPerformed") or
        hasPressureField(obj, "commandsExecuted") or
        hasPressureField(obj, "verifiersExecuted");
}

fn hasCorrectionFutureCandidate(value: std.json.Value) bool {
    return jsonContainsAny(value, &.{ "sourceReviewedCorrectionId", "source_reviewed_correction_id" });
}

fn hasReviewedNegativeKnowledgeFutureCandidate(value: std.json.Value) bool {
    return jsonContainsAny(value, &.{ "sourceReviewedNegativeKnowledgeId", "source_reviewed_negative_knowledge_id", "reviewed_negative_knowledge" });
}

fn hasBoolOrPressureField(value: std.json.Value, field: []const u8) bool {
    const obj = switch (value) {
        .object => |obj| obj,
        else => return jsonContainsAny(value, &.{field}),
    };
    return hasPressureField(obj, field);
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
    return hasPressureField(obj, "truncatedInputs") or
        hasPressureField(obj, "truncatedSnippets") or
        hasPressureField(obj, "skippedInputs") or
        hasPressureField(obj, "skippedFiles") or
        hasPressureField(obj, "budgetHits") or
        hasPressureField(obj, "maxResultsHit") or
        hasPressureField(obj, "exactCandidateCapHit") or
        hasPressureField(obj, "sketchCandidateCapHit") or
        hasPressureField(obj, "capacityWarnings") or
        hasPressureField(obj, "expansionRecommended") or
        hasPressureField(obj, "spilloverRecommended");
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

fn printSimilarCandidates(writer: anytype, value: std.json.Value) !void {
    switch (value) {
        .array => |arr| {
            for (arr.items, 0..) |item, idx| {
                try writer.print("  - hint #{d}\n", .{idx + 1});
                try printSimilarCandidate(writer, item);
            }
        },
        else => try printSimilarCandidate(writer, value),
    }
}

fn printSimilarCandidate(writer: anytype, value: std.json.Value) !void {
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
    try printOptionalEvidenceField(writer, obj, "ref", "ref");
    try printOptionalEvidenceField(writer, obj, "path", "path");
    try printOptionalEvidenceField(writer, obj, "sourcePath", "sourcePath");
    try printOptionalEvidenceField(writer, obj, "sourceLabel", "sourceLabel");
    try printOptionalEvidenceField(writer, obj, "trustClass", "trustClass");
    try printOptionalEvidenceField(writer, obj, "similarityScore", "similarityScore");
    try printOptionalEvidenceField(writer, obj, "hammingDistance", "hammingDistance");
    try printOptionalEvidenceField(writer, obj, "reason", "reason");
    try printOptionalEvidenceField(writer, obj, "nonAuthorizing", "nonAuthorizing");
    try printOptionalEvidenceField(writer, obj, "rank", "rank");
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

fn jsonContainsAny(value: std.json.Value, needles: []const []const u8) bool {
    switch (value) {
        .string => |s| {
            for (needles) |needle| {
                if (std.ascii.indexOfIgnoreCase(s, needle) != null) return true;
            }
            return false;
        },
        .array => |arr| {
            for (arr.items) |item| {
                if (jsonContainsAny(item, needles)) return true;
            }
            return false;
        },
        .object => |obj| {
            var it = obj.iterator();
            while (it.next()) |entry| {
                for (needles) |needle| {
                    if (std.ascii.indexOfIgnoreCase(entry.key_ptr.*, needle) != null) return true;
                }
                if (jsonContainsAny(entry.value_ptr.*, needles)) return true;
            }
            return false;
        },
        else => return false,
    }
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
