const std = @import("std");
const locator = @import("../engine/locator.zig");
const process = @import("../engine/process.zig");
const runner = @import("../engine/runner.zig");
const json_contracts = @import("../engine/json_contracts.zig");
const terminal = @import("../render/terminal.zig");

pub const LearnOptions = struct {
    subcommand: []const u8,
    file_path: ?[]const u8 = null,
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

const max_request_bytes = 1024 * 1024;

pub fn printHelp(writer: anytype) !void {
    try writer.print(
        \\learn
        \\
        \\Usage: ghost learn <candidates|show|export|status|review|plan> [options]
        \\
        \\Subcommands:
        \\  candidates --project-shard=<id>
        \\  show <candidate-id> --project-shard=<id>
        \\  export <candidate-id> --project-shard=<id> --pack-id=<id> --version=<v> --approve
        \\  status --project-shard=<id> [--include-records] [--limit=<n>] [--no-warnings]
        \\  review --file <request.json> [--json] [--debug]
        \\  plan --file <request.json> [--json] [--debug]
        \\
        \\Safety:
        \\  learning.status is explicit and read-only.
        \\  learning.review is explicit, append-only, and non-authorizing.
        \\  learning.loop.plan is explicit, read-only, candidate-only, and non-authorizing.
        \\  Scoreboard counts are diagnostics only, not proof or evidence.
        \\  Learning loop plans do not execute commands or verifiers, apply patches,
        \\  apply corrections, promote negative knowledge, or mutate packs/corpus/trust/snapshots/scratch.
        \\  Failure, correction, negative-knowledge, and procedure-pack outputs are placeholders only.
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
    if (std.mem.eql(u8, args[0], "review")) return printReviewHelp(writer);
    if (std.mem.eql(u8, args[0], "plan")) return printPlanHelp(writer);
    return printHelp(writer);
}

fn printReviewHelp(writer: anytype) !void {
    try writer.print(
        \\learn review
        \\
        \\Usage: ghost learn review --file <request.json> [--json] [--debug]
        \\
        \\Reads a GIP-compatible learning review request from a file and sends
        \\the file bytes unchanged to ghost_gip --stdin. The request must include
        \\kind "learning.review".
        \\
        \\Options:
        \\  --file <request.json>     learning.review GIP request file
        \\  --json                    Preserve raw GIP stdout exactly
        \\  --debug                   Diagnostics to stderr only
        \\
        \\Safety:
        \\  APPEND-ONLY.
        \\  NON-AUTHORIZING.
        \\  NOT PROOF.
        \\  NOT EVIDENCE.
        \\  NO GLOBAL PROMOTION.
        \\  NO CORPUS / PACK / NEGATIVE-KNOWLEDGE MUTATION.
        \\  COMMANDS NOT EXECUTED.
        \\  VERIFIERS NOT EXECUTED.
        \\
    , .{});
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

fn printPlanHelp(writer: anytype) !void {
    try writer.print(
        \\learn plan
        \\
        \\Usage: ghost learn plan --file <request.json> [--json] [--debug]
        \\
        \\Reads a GIP-compatible learning loop plan request from a file and sends
        \\the file bytes unchanged to ghost_gip --stdin. The request must include
        \\kind "learning.loop.plan".
        \\
        \\Options:
        \\  --file <request.json>     learning.loop.plan GIP request file
        \\  --json                    Preserve raw GIP stdout exactly
        \\  --debug                   Diagnostics to stderr only
        \\
        \\Safety:
        \\  READ-ONLY.
        \\  NON-AUTHORIZING.
        \\  CANDIDATE ONLY.
        \\  COMMANDS NOT EXECUTED.
        \\  VERIFIERS NOT EXECUTED.
        \\  PATCHES NOT APPLIED.
        \\  CORRECTIONS NOT APPLIED.
        \\  NEGATIVE KNOWLEDGE NOT PROMOTED.
        \\  PACKS NOT MUTATED OR APPLIED.
        \\  Failure ingestion candidates are not ingested failures.
        \\  Correction/NK/procedure-pack placeholders are placeholders only.
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
    } else if (std.mem.eql(u8, options.subcommand, "review")) {
        try executeReview(allocator, engine_root, options);
    } else if (std.mem.eql(u8, options.subcommand, "plan")) {
        try executePlan(allocator, engine_root, options);
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

fn executePlan(allocator: std.mem.Allocator, engine_root: ?[]const u8, options: LearnOptions) !void {
    const file_path = options.file_path orelse {
        try std.io.getStdErr().writer().print("Usage: ghost learn plan --file <request.json> [--json] [--debug]\n", .{});
        std.process.exit(1);
    };
    if (std.mem.trim(u8, file_path, " \r\n\t").len == 0) {
        try std.io.getStdErr().writer().print("learn plan --file must be non-empty\n", .{});
        std.process.exit(1);
    }

    const request = std.fs.cwd().readFileAlloc(allocator, file_path, max_request_bytes) catch |err| {
        try std.io.getStdErr().writer().print("Error: failed to read learning.loop.plan request file '{s}': {s}\n", .{ file_path, @errorName(err) });
        std.process.exit(1);
    };
    defer allocator.free(request);

    var parsed = std.json.parseFromSlice(std.json.Value, allocator, request, .{}) catch |err| {
        if (options.debug) try std.io.getStdErr().writer().print("[DEBUG] Parse Status: FAILED ({s})\n", .{@errorName(err)});
        try std.io.getStdErr().writer().print("Error: learning.loop.plan request file is not valid JSON: {s}\n", .{@errorName(err)});
        std.process.exit(1);
    };
    defer parsed.deinit();

    if (!hasKind(parsed.value, "learning.loop.plan")) {
        if (options.debug) try std.io.getStdErr().writer().print("[DEBUG] Parse Status: FAILED (kind mismatch)\n", .{});
        try std.io.getStdErr().writer().print("Error: request file must contain top-level kind \"learning.loop.plan\".\n", .{});
        std.process.exit(1);
    }

    const bin_path = locator.findEngineBinary(allocator, engine_root, .ghost_gip) catch |err| {
        try locator.printLocatorError(std.io.getStdErr().writer(), .ghost_gip, engine_root, err);
        std.process.exit(1);
    };
    defer allocator.free(bin_path);

    const cwd = try std.process.getCwdAlloc(allocator);
    defer allocator.free(cwd);

    const argv = &[_][]const u8{ bin_path, "--stdin", "--workspace", cwd };
    if (options.debug) {
        try std.io.getStdErr().writer().print("[DEBUG] Engine Binary: {s}\n", .{bin_path});
        try std.io.getStdErr().writer().print("[DEBUG] GIP Kind: learning.loop.plan\n", .{});
        try std.io.getStdErr().writer().print("[DEBUG] Input File: {s}\n", .{file_path});
        try std.io.getStdErr().writer().print("[DEBUG] Workspace: {s}\n", .{cwd});
        try std.io.getStdErr().writer().print("[DEBUG] Stdin Byte Count: {d}\n", .{request.len});
    }

    const result = process.runEngineCommandWithInput(allocator, argv, request) catch |err| {
        try std.io.getStdErr().writer().print("\x1b[31m[!] Error:\x1b[0m Failed to execute learning.loop.plan: {}\n", .{err});
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
        try std.io.getStdErr().writer().print("Error: Failed to parse engine output as learning.loop.plan JSON.\n", .{});
        try std.io.getStdErr().writer().print("Raw output:\n{s}\n", .{result.stdout});
        return;
    };
    defer out_parsed.deinit();

    if (options.debug) try std.io.getStdErr().writer().print("[DEBUG] Parse Status: ok\n", .{});
    try printLearningLoopPlanResult(std.io.getStdOut().writer(), out_parsed.value);
}

fn executeReview(allocator: std.mem.Allocator, engine_root: ?[]const u8, options: LearnOptions) !void {
    const file_path = options.file_path orelse {
        try std.io.getStdErr().writer().print("Usage: ghost learn review --file <request.json> [--json] [--debug]\n", .{});
        std.process.exit(1);
    };
    if (std.mem.trim(u8, file_path, " \r\n\t").len == 0) {
        try std.io.getStdErr().writer().print("learn review --file must be non-empty\n", .{});
        std.process.exit(1);
    }

    const request = std.fs.cwd().readFileAlloc(allocator, file_path, max_request_bytes) catch |err| {
        try std.io.getStdErr().writer().print("Error: failed to read learning.review request file '{s}': {s}\n", .{ file_path, @errorName(err) });
        std.process.exit(1);
    };
    defer allocator.free(request);

    var parsed = std.json.parseFromSlice(std.json.Value, allocator, request, .{}) catch |err| {
        if (options.debug) try std.io.getStdErr().writer().print("[DEBUG] Parse Status: FAILED ({s})\n", .{@errorName(err)});
        try std.io.getStdErr().writer().print("Error: learning.review request file is not valid JSON: {s}\n", .{@errorName(err)});
        std.process.exit(1);
    };
    defer parsed.deinit();

    if (!hasKind(parsed.value, "learning.review")) {
        if (options.debug) try std.io.getStdErr().writer().print("[DEBUG] Parse Status: FAILED (kind mismatch)\n", .{});
        try std.io.getStdErr().writer().print("Error: request file must contain top-level kind \"learning.review\".\n", .{});
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
        try std.io.getStdErr().writer().print("[DEBUG] GIP Kind: learning.review\n", .{});
        try std.io.getStdErr().writer().print("[DEBUG] Input File: {s}\n", .{file_path});
        try std.io.getStdErr().writer().print("[DEBUG] Stdin Byte Count: {d}\n", .{request.len});
    }

    const result = process.runEngineCommandWithInput(allocator, argv, request) catch |err| {
        try std.io.getStdErr().writer().print("\x1b[31m[!] Error:\x1b[0m Failed to execute learning.review: {}\n", .{err});
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
        try std.io.getStdErr().writer().print("Error: Failed to parse engine output as learning.review JSON.\n", .{});
        try std.io.getStdErr().writer().print("Raw output:\n{s}\n", .{result.stdout});
        return;
    };
    defer out_parsed.deinit();

    if (options.debug) try std.io.getStdErr().writer().print("[DEBUG] Parse Status: ok\n", .{});
    try printLearningReviewResult(std.io.getStdOut().writer(), out_parsed.value);
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

fn printLearningLoopPlanResult(writer: anytype, value: std.json.Value) !void {
    try writer.print("LEARNING LOOP PLAN / READ-ONLY / NON-AUTHORIZING\n", .{});
    try writer.print("READ-ONLY\n", .{});
    try writer.print("NON-AUTHORIZING\n", .{});
    try writer.print("CANDIDATE ONLY\n", .{});
    try writer.print("COMMANDS NOT EXECUTED\n", .{});
    try writer.print("VERIFIERS NOT EXECUTED\n", .{});
    try writer.print("PATCHES NOT APPLIED\n", .{});
    try writer.print("CORRECTIONS NOT APPLIED\n", .{});
    try writer.print("NEGATIVE KNOWLEDGE NOT PROMOTED\n", .{});
    try writer.print("PACKS NOT MUTATED OR APPLIED\n", .{});
    try writer.print("NO CORPUS / TRUST / SNAPSHOT / SCRATCH MUTATION\n", .{});
    try writer.print("NO PROOF OR SUPPORT GRANTED\n\n", .{});

    if (findError(value)) |err_value| {
        try writer.print("Engine Rejected Request:\n", .{});
        try printJsonValue(writer, err_value, 2);
        try writer.print("\n", .{});
        return;
    }

    const plan_value = findLearningLoopPlan(value) orelse {
        try writer.print("No learningLoopPlan result payload was present.\n", .{});
        return;
    };
    const plan = switch (plan_value) {
        .object => |obj| obj,
        else => {
            try printJsonValue(writer, plan_value, 2);
            try writer.print("\n", .{});
            return;
        },
    };

    try printField(writer, plan, "plan_id", "Plan ID");
    try printField(writer, plan, "planId", "Plan ID");
    try printField(writer, plan, "source", "Source");
    try printField(writer, plan, "schema_version", "Schema Version");
    try printField(writer, plan, "schemaVersion", "Schema Version");
    try printField(writer, plan, "autopsy_schema_version", "Autopsy Schema Version");
    try printField(writer, plan, "autopsySchemaVersion", "Autopsy Schema Version");
    try printField(writer, plan, "state", "State");

    try printField(writer, plan, "read_only", "Read Only");
    try printField(writer, plan, "readOnly", "Read Only");
    try printField(writer, plan, "candidate_only", "Candidate Only");
    try printField(writer, plan, "candidateOnly", "Candidate Only");
    try printField(writer, plan, "non_authorizing", "Non-Authorizing");
    try printField(writer, plan, "nonAuthorizing", "Non-Authorizing");
    try printField(writer, plan, "commands_executed", "Commands Executed");
    try printField(writer, plan, "commandsExecuted", "Commands Executed");
    try printField(writer, plan, "verifiers_executed", "Verifiers Executed");
    try printField(writer, plan, "verifiersExecuted", "Verifiers Executed");
    try printField(writer, plan, "patches_applied", "Patches Applied");
    try printField(writer, plan, "patchesApplied", "Patches Applied");

    try printPlanSection(writer, plan, "next_steps", "Next Steps", null);
    try printPlanSection(writer, plan, "nextSteps", "Next Steps", null);
    try printPlanSection(writer, plan, "verifier_candidate_refs", "Verifier Candidate Refs", "Approval-required verifier refs only; verifiers were not executed.");
    try printPlanSection(writer, plan, "verifierCandidateRefs", "Verifier Candidate Refs", "Approval-required verifier refs only; verifiers were not executed.");
    try printPlanSection(writer, plan, "failure_ingestion_candidates", "Failure Ingestion Candidates", "Placeholders only; no failure was ingested.");
    try printPlanSection(writer, plan, "failureIngestionCandidates", "Failure Ingestion Candidates", "Placeholders only; no failure was ingested.");
    try printPlanSection(writer, plan, "correction_candidate_placeholders", "Correction Placeholders", "Placeholders only; no correction was accepted or applied.");
    try printPlanSection(writer, plan, "correctionCandidatePlaceholders", "Correction Placeholders", "Placeholders only; no correction was accepted or applied.");
    try printPlanSection(writer, plan, "negative_knowledge_candidate_placeholders", "Negative Knowledge Placeholders", "Placeholders only; no negative knowledge was accepted or promoted.");
    try printPlanSection(writer, plan, "negativeKnowledgeCandidatePlaceholders", "Negative Knowledge Placeholders", "Placeholders only; no negative knowledge was accepted or promoted.");
    try printPlanSection(writer, plan, "procedure_pack_candidate_placeholders", "Procedure Pack Placeholders", "Placeholders only; no procedure pack was mounted, applied, or mutated.");
    try printPlanSection(writer, plan, "procedurePackCandidatePlaceholders", "Procedure Pack Placeholders", "Placeholders only; no procedure pack was mounted, applied, or mutated.");
    try printPlanSection(writer, plan, "unknowns", "Unknowns", "Unknown is not false; unknowns are not negative evidence.");

    try writer.print("\nNotice: learning.loop.plan is a read-only candidate plan derived by the engine. Rendering it does not execute commands, run verifier refs, apply patches, ingest failures, accept corrections, promote negative knowledge, mutate packs/corpus/trust/snapshots/scratch, or grant proof/support.\n", .{});
}

fn printLearningReviewResult(writer: anytype, value: std.json.Value) !void {
    try writer.print("REVIEWED LEARNING RECORD / APPEND-ONLY / NON-AUTHORIZING\n", .{});
    try writer.print("APPEND-ONLY\n", .{});
    try writer.print("NON-AUTHORIZING\n", .{});
    try writer.print("NOT PROOF\n", .{});
    try writer.print("NOT EVIDENCE\n", .{});
    try writer.print("NO GLOBAL PROMOTION\n", .{});
    try writer.print("NO CORPUS / PACK / NEGATIVE-KNOWLEDGE MUTATION\n", .{});
    try writer.print("COMMANDS NOT EXECUTED\n", .{});
    try writer.print("VERIFIERS NOT EXECUTED\n\n", .{});

    if (findError(value)) |err_value| {
        if (isConflictError(err_value) or isConflictReview(findLearningReview(value))) {
            try writer.print("\x1b[33mCONFLICT WARNING\x1b[0m\n", .{});
            try writer.print("Accepted learning was refused because it overlaps contradictory same-shard learning.\n", .{});
            if (findLearningReview(value)) |review_value| {
                if (review_value == .object) {
                    try printField(writer, review_value.object, "status", "Status");
                    try printField(writer, review_value.object, "appendRefused", "Append Refused");
                    try printSection(writer, review_value.object, "conflictsWithRecordIds", "Conflicts With Record IDs");
                    try printSection(writer, review_value.object, "conflicts_with_record_ids", "Conflicts With Record IDs");
                    try printField(writer, review_value.object, "reason", "Reason");
                    try writer.print("\n", .{});
                }
            }
        }
        try writer.print("Engine Rejected Request:\n", .{});
        try printJsonValue(writer, err_value, 2);
        try writer.print("\n", .{});
        return;
    }

    const review_value = findLearningReview(value) orelse {
        try writer.print("No learningReview result payload was present.\n", .{});
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
    try printSection(writer, review, "reviewedLearningRecord", "Reviewed Learning Record");
    try printSection(writer, review, "reviewed_learning_record", "Reviewed Learning Record");
    try printSection(writer, review, "storage", "Storage Metadata");
    try printSection(writer, review, "mutationFlags", "Mutation Flags");
    try printSection(writer, review, "mutation_flags", "Mutation Flags");
    try printSection(writer, review, "authority", "Authority Flags");
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
    try printSection(writer, status, "reviewedLearningSummary", "Reviewed Learning Summary");
    try printSection(writer, status, "reviewed_learning_summary", "Reviewed Learning Summary");
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

fn findLearningLoopPlan(value: std.json.Value) ?std.json.Value {
    const obj = switch (value) {
        .object => |o| o,
        else => return null,
    };
    if (obj.get("learningLoopPlan")) |plan| return plan;
    if (obj.get("learning_loop_plan")) |plan| return plan;
    if (obj.get("result")) |result| {
        const result_obj = switch (result) {
            .object => |o| o,
            else => return result,
        };
        if (result_obj.get("learningLoopPlan")) |plan| return plan;
        if (result_obj.get("learning_loop_plan")) |plan| return plan;
        return result;
    }
    return null;
}

fn findLearningReview(value: std.json.Value) ?std.json.Value {
    const obj = switch (value) {
        .object => |o| o,
        else => return null,
    };
    if (obj.get("learningReview")) |review| return review;
    if (obj.get("learning_review")) |review| return review;
    if (obj.get("result")) |result| {
        const result_obj = switch (result) {
            .object => |o| o,
            else => return result,
        };
        if (result_obj.get("learningReview")) |review| return review;
        if (result_obj.get("learning_review")) |review| return review;
        return result;
    }
    return null;
}

fn isConflictReview(maybe_review: ?std.json.Value) bool {
    const review_value = maybe_review orelse return false;
    const obj = switch (review_value) {
        .object => |o| o,
        else => return false,
    };
    const status = obj.get("status") orelse return false;
    return status == .string and std.mem.eql(u8, status.string, "ConflictDetected");
}

fn isConflictError(value: std.json.Value) bool {
    const obj = switch (value) {
        .object => |o| o,
        else => return false,
    };
    const code = obj.get("code") orelse return false;
    return code == .string and (std.mem.eql(u8, code.string, "conflict_detected") or std.mem.eql(u8, code.string, "ConflictDetected"));
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

fn hasKind(value: std.json.Value, expected: []const u8) bool {
    const obj = switch (value) {
        .object => |o| o,
        else => return false,
    };
    const kind = obj.get("kind") orelse return false;
    return switch (kind) {
        .string => |s| std.mem.eql(u8, s, expected),
        else => false,
    };
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

fn printPlanSection(writer: anytype, obj: std.json.ObjectMap, field: []const u8, label: []const u8, notice: ?[]const u8) !void {
    const value = obj.get(field) orelse return;
    if (isEmptyJsonList(value)) return;
    try writer.print("\n{s}:\n", .{label});
    if (notice) |text| try writer.print("- {s}\n", .{text});
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
