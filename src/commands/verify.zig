const std = @import("std");
const runner = @import("../engine/runner.zig");
const locator = @import("../engine/locator.zig");
const process = @import("../engine/process.zig");
const json_contracts = @import("../engine/json_contracts.zig");
const terminal = @import("../render/terminal.zig");

pub const VerifyOptions = struct {
    reasoning: ?json_contracts.ReasoningLevel = null,
    context_artifact: ?[]const u8 = null,
    file_path: ?[]const u8 = null,
    json: bool = false,
    debug: bool = false,
};

const max_request_bytes = 1024 * 1024;

pub fn printHelp(writer: anytype) !void {
    try writer.print(
        \\verify
        \\
        \\Usage: ghost verify [options]
        \\Usage: ghost verify candidates <propose|list|review> --file <request.json> [--json] [--debug]
        \\Usage: ghost verify executions <list|get> --file <request.json> [--json] [--debug]
        \\
        \\Subcommands:
        \\  candidates propose --file <request.json>
        \\  candidates list --file <request.json>
        \\  candidates review --file <request.json>
        \\  executions list --file <request.json>
        \\  executions get --file <request.json>
        \\
        \\Safety:
        \\  Verifier candidates are candidate metadata only.
        \\  Verifier execution records are evidence candidates only.
        \\  Execution inspection is READ-ONLY and NON-AUTHORIZING.
        \\  CANDIDATE ONLY. NON-AUTHORIZING.
        \\  Approval is metadata only and does not execute anything.
        \\  Passing execution records do not grant support.
        \\  Failing execution records do not create correction or negative knowledge.
        \\  Rejection is metadata only and is not global negative evidence.
        \\  COMMANDS NOT EXECUTED. VERIFIERS NOT EXECUTED.
        \\  NO PROOF/SUPPORT GRANTED.
        \\  NO CORRECTION APPLIED. NO NEGATIVE KNOWLEDGE PROMOTED.
        \\  NO PATCH/CORPUS/PACK MUTATION.
        \\  `--json` preserves raw engine stdout exactly.
        \\  `--debug` writes diagnostics to stderr only.
        \\
    , .{});
}

pub fn printHelpForArgs(writer: anytype, args: []const []const u8) !void {
    if (args.len == 0) return printHelp(writer);
    if (std.mem.eql(u8, args[0], "candidates")) {
        if (args.len >= 2 and std.mem.eql(u8, args[1], "propose")) return printCandidateProposeHelp(writer);
        if (args.len >= 2 and std.mem.eql(u8, args[1], "list")) return printCandidateListHelp(writer);
        if (args.len >= 2 and std.mem.eql(u8, args[1], "review")) return printCandidateReviewHelp(writer);
        return printCandidatesHelp(writer);
    }
    if (std.mem.eql(u8, args[0], "executions")) {
        if (args.len >= 2 and std.mem.eql(u8, args[1], "list")) return printExecutionListHelp(writer);
        if (args.len >= 2 and std.mem.eql(u8, args[1], "get")) return printExecutionGetHelp(writer);
        return printExecutionsHelp(writer);
    }
    return printHelp(writer);
}

fn printCandidatesHelp(writer: anytype) !void {
    try writer.print(
        \\verify candidates
        \\
        \\Usage: ghost verify candidates <propose|list|review> --file <request.json> [--json] [--debug]
        \\
        \\Explicit verifier candidate lifecycle commands. All requests are full
        \\GIP JSON files sent unchanged to ghost_gip --stdin after top-level
        \\kind validation.
        \\
        \\Safety:
        \\  CANDIDATE ONLY. NON-AUTHORIZING.
        \\  APPROVAL METADATA ONLY.
        \\  COMMANDS NOT EXECUTED. VERIFIERS NOT EXECUTED.
        \\  NO EVIDENCE PRODUCED. NO PROOF/SUPPORT GRANTED.
        \\  Review metadata is append-only; list is read-only.
        \\
    , .{});
}

fn printCandidateProposeHelp(writer: anytype) !void {
    try writer.print(
        \\verify candidates propose
        \\
        \\Usage: ghost verify candidates propose --file <request.json> [--json] [--debug]
        \\
        \\Reads a GIP-compatible request file and sends the bytes unchanged to
        \\ghost_gip --stdin. The request must include kind
        \\""verifier.candidate.propose_from_learning_plan".
        \\
        \\Safety:
        \\  Converts approval-required learning.loop.plan verifier refs into
        \\  proposed metadata only. Does not execute commands or verifiers.
        \\  CANDIDATE ONLY. NON-AUTHORIZING. NO EVIDENCE PRODUCED.
        \\
    , .{});
}

fn printCandidateListHelp(writer: anytype) !void {
    try writer.print(
        \\verify candidates list
        \\
        \\Usage: ghost verify candidates list --file <request.json> [--json] [--debug]
        \\
        \\Reads a GIP-compatible request file and sends the bytes unchanged to
        \\ghost_gip --stdin. The request must include kind "verifier.candidate.list".
        \\
        \\Safety:
        \\  READ-ONLY candidate metadata inspection.
        \\  NOT VERIFIED. NOT SUPPORT. NOT PROOF. NOT EVIDENCE.
        \\  COMMANDS NOT EXECUTED. VERIFIERS NOT EXECUTED.
        \\
    , .{});
}

fn printCandidateReviewHelp(writer: anytype) !void {
    try writer.print(
        \\verify candidates review
        \\
        \\Usage: ghost verify candidates review --file <request.json> [--json] [--debug]
        \\
        \\Reads a GIP-compatible request file and sends the bytes unchanged to
        \\ghost_gip --stdin. The request must include kind "verifier.candidate.review".
        \\
        \\Safety:
        \\  APPROVAL METADATA ONLY. REJECTION METADATA ONLY.
        \\  Approval does not execute commands/verifiers or create evidence.
        \\  Rejection is not global negative evidence.
        \\  CANDIDATE ONLY. NON-AUTHORIZING. NO PROOF/SUPPORT GRANTED.
        \\
    , .{});
}

fn printExecutionsHelp(writer: anytype) !void {
    try writer.print(
        \\verify executions
        \\
        \\Usage: ghost verify executions <list|get> --file <request.json> [--json] [--debug]
        \\
        \\Explicit verifier execution record inspection commands. Requests are
        \\full GIP JSON files sent unchanged to ghost_gip --stdin after
        \\top-level kind validation.
        \\
        \\Safety:
        \\  READ-ONLY INSPECTION.
        \\  NON-AUTHORIZING.
        \\  EVIDENCE CANDIDATE ONLY.
        \\  COMMANDS NOT EXECUTED BY INSPECTION.
        \\  VERIFIERS NOT EXECUTED BY INSPECTION.
        \\  NO PROOF/SUPPORT GRANTED.
        \\  NO CORRECTION APPLIED.
        \\  NO NEGATIVE KNOWLEDGE PROMOTED.
        \\  NO PATCH/CORPUS/PACK MUTATION.
        \\
    , .{});
}

fn printExecutionListHelp(writer: anytype) !void {
    try writer.print(
        \\verify executions list
        \\
        \\Usage: ghost verify executions list --file <request.json> [--json] [--debug]
        \\
        \\Reads a GIP-compatible request file and sends the bytes unchanged to
        \\ghost_gip --stdin. The request must include kind
        \\"verifier.candidate.execution.list".
        \\
        \\Safety:
        \\  READ-ONLY INSPECTION. NON-AUTHORIZING.
        \\  EVIDENCE CANDIDATE ONLY.
        \\  Listing records does not execute commands or verifiers.
        \\  Passing records do not grant support; failing records do not create
        \\  correction or negative knowledge.
        \\
    , .{});
}

fn printExecutionGetHelp(writer: anytype) !void {
    try writer.print(
        \\verify executions get
        \\
        \\Usage: ghost verify executions get --file <request.json> [--json] [--debug]
        \\
        \\Reads a GIP-compatible request file and sends the bytes unchanged to
        \\ghost_gip --stdin. The request must include kind
        \\"verifier.candidate.execution.get".
        \\
        \\Safety:
        \\  READ-ONLY INSPECTION. NON-AUTHORIZING.
        \\  EVIDENCE CANDIDATE ONLY.
        \\  Getting a record does not execute commands or verifiers.
        \\  Passing records do not grant support; failing records do not create
        \\  correction or negative knowledge.
        \\
    , .{});
}

pub fn executeFromArgs(
    allocator: std.mem.Allocator,
    engine_root: ?[]const u8,
    args: []const []const u8,
    base: VerifyOptions,
) !void {
    if (args.len == 0) return execute(allocator, engine_root, base);
    if (!std.mem.eql(u8, args[0], "candidates")) {
        if (std.mem.eql(u8, args[0], "executions")) {
            try executeExecutionsFromArgs(allocator, engine_root, args[1..], base);
            return;
        }
        try std.io.getStdErr().writer().print("Unknown verify command: {s}\n", .{args[0]});
        try printHelp(std.io.getStdErr().writer());
        std.process.exit(1);
    }
    try executeCandidatesFromArgs(allocator, engine_root, args[1..], base);
}

fn executeCandidatesFromArgs(
    allocator: std.mem.Allocator,
    engine_root: ?[]const u8,
    args: []const []const u8,
    base: VerifyOptions,
) !void {
    const action = if (args.len > 0) args[0] else {
        try printCandidatesHelp(std.io.getStdErr().writer());
        std.process.exit(1);
    };
    var options = base;
    try parseCandidateFileArgs(args[1..], &options, action);
    if (std.mem.eql(u8, action, "propose")) {
        try executeCandidateFileGip(allocator, engine_root, options, "verifier.candidate.propose_from_learning_plan", printVerifierCandidateProposalResult);
        return;
    }
    if (std.mem.eql(u8, action, "list")) {
        try executeCandidateFileGip(allocator, engine_root, options, "verifier.candidate.list", printVerifierCandidateListResult);
        return;
    }
    if (std.mem.eql(u8, action, "review")) {
        try executeCandidateFileGip(allocator, engine_root, options, "verifier.candidate.review", printVerifierCandidateReviewResult);
        return;
    }
    try std.io.getStdErr().writer().print("Unknown verify candidates command: {s}\n", .{action});
    try printCandidatesHelp(std.io.getStdErr().writer());
    std.process.exit(1);
}

fn executeExecutionsFromArgs(
    allocator: std.mem.Allocator,
    engine_root: ?[]const u8,
    args: []const []const u8,
    base: VerifyOptions,
) !void {
    const action = if (args.len > 0) args[0] else {
        try printExecutionsHelp(std.io.getStdErr().writer());
        std.process.exit(1);
    };
    var options = base;
    try parseCandidateFileArgs(args[1..], &options, action);
    if (std.mem.eql(u8, action, "list")) {
        try executeCandidateFileGip(allocator, engine_root, options, "verifier.candidate.execution.list", printVerifierExecutionListResult);
        return;
    }
    if (std.mem.eql(u8, action, "get")) {
        try executeCandidateFileGip(allocator, engine_root, options, "verifier.candidate.execution.get", printVerifierExecutionGetResult);
        return;
    }
    try std.io.getStdErr().writer().print("Unknown verify executions command: {s}\n", .{action});
    try printExecutionsHelp(std.io.getStdErr().writer());
    std.process.exit(1);
}

fn parseCandidateFileArgs(args: []const []const u8, options: *VerifyOptions, action: []const u8) !void {
    var i: usize = 0;
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
            try std.io.getStdErr().writer().print("Unknown verify candidates {s} option: {s}\n", .{ action, arg });
            std.process.exit(1);
        } else {
            try std.io.getStdErr().writer().print("Unexpected verify candidates {s} argument: {s}\n", .{ action, arg });
            std.process.exit(1);
        }
    }
}

fn executeCandidateFileGip(
    allocator: std.mem.Allocator,
    engine_root: ?[]const u8,
    options: VerifyOptions,
    expected_kind: []const u8,
    comptime renderer: fn (anytype, std.json.Value) anyerror!void,
) !void {
    const file_path = requireNonEmpty(options.file_path, "verify candidates --file is required");
    const request = std.fs.cwd().readFileAlloc(allocator, file_path, max_request_bytes) catch |err| {
        try std.io.getStdErr().writer().print("Error: failed to read {s} request file '{s}': {s}\n", .{ expected_kind, file_path, @errorName(err) });
        std.process.exit(1);
    };
    defer allocator.free(request);

    var parsed = std.json.parseFromSlice(std.json.Value, allocator, request, .{}) catch |err| {
        if (options.debug) try std.io.getStdErr().writer().print("[DEBUG] Parse Status: FAILED ({s})\n", .{@errorName(err)});
        try std.io.getStdErr().writer().print("Error: {s} request file is not valid JSON: {s}\n", .{ expected_kind, @errorName(err) });
        std.process.exit(1);
    };
    defer parsed.deinit();
    if (!hasKind(parsed.value, expected_kind)) {
        if (options.debug) try std.io.getStdErr().writer().print("[DEBUG] Parse Status: FAILED (kind mismatch)\n", .{});
        try std.io.getStdErr().writer().print("Error: request file must contain top-level kind \"{s}\".\n", .{expected_kind});
        std.process.exit(1);
    }

    const bin_path = locator.findEngineBinary(allocator, engine_root, .ghost_gip) catch |err| {
        try locator.printLocatorError(std.io.getStdErr().writer(), .ghost_gip, engine_root, err);
        std.process.exit(1);
    };
    defer allocator.free(bin_path);

    if (options.debug) {
        try std.io.getStdErr().writer().print("[DEBUG] Engine Binary: {s}\n", .{bin_path});
        try std.io.getStdErr().writer().print("[DEBUG] GIP Kind: {s}\n", .{expected_kind});
        try std.io.getStdErr().writer().print("[DEBUG] Input File: {s}\n", .{file_path});
        try std.io.getStdErr().writer().print("[DEBUG] Stdin Byte Count: {d}\n", .{request.len});
    }

    const argv = &[_][]const u8{ bin_path, "--stdin" };
    const result = process.runEngineCommandWithInput(allocator, argv, request) catch |err| {
        try std.io.getStdErr().writer().print("\x1b[31m[!] Error:\x1b[0m Failed to execute {s}: {}\n", .{ expected_kind, err });
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
        try std.io.getStdErr().writer().print("Error: Failed to parse engine output as {s} JSON.\n", .{expected_kind});
        try std.io.getStdErr().writer().print("Raw output:\n{s}\n", .{result.stdout});
        return;
    };
    defer out_parsed.deinit();

    if (options.debug) try std.io.getStdErr().writer().print("[DEBUG] Parse Status: ok\n", .{});
    try renderer(std.io.getStdOut().writer(), out_parsed.value);
}

pub fn execute(allocator: std.mem.Allocator, engine_root: ?[]const u8, options: VerifyOptions) !void {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const aa = arena.allocator();

    var argv = std.ArrayList([]const u8).init(aa);

    // We use chat command as the verify endpoint per requirements if no dedicated verify exists
    try argv.append("chat");
    try argv.append("--message");
    try argv.append("verify current workspace/task");

    const reasoning = options.reasoning orelse .deep;
    var buf: [64]u8 = undefined;
    const reasoning_arg = try std.fmt.bufPrint(&buf, "--reasoning={s}", .{reasoning.toStr()});
    try argv.append(try aa.dupe(u8, reasoning_arg));

    if (options.context_artifact) |art| {
        try argv.append("--context-artifact");
        try argv.append(art);
    }

    try argv.append("--render=json");

    const res = try runner.run(allocator, .{
        .engine_root = engine_root,
        .binary = .ghost_task_operator,
        .argv = argv.items,
        .json = true,
        .debug = options.debug,
    });
    defer res.deinit();

    if (options.json) {
        try std.io.getStdOut().writer().writeAll(res.stdout);
        if (res.stderr.len > 0) try std.io.getStdErr().writer().writeAll(res.stderr);
        if (res.exit_code != 0) std.process.exit(res.exit_code);
        return;
    }

    if (res.exit_code != 0) {
        // runner.run already printed failure if not json, but we might want to exit
        std.process.exit(res.exit_code);
    }

    if (res.stdout.len > 0) {
        if (json_contracts.parseEngineJson(allocator, res.stdout)) |parsed| {
            defer parsed.deinit();
            try terminal.printEngineOutput(std.io.getStdOut().writer(), parsed.value);
        } else |err| {
            if (options.debug) std.debug.print("[DEBUG] JSON Parse FAILED: {}\n", .{err});
            std.debug.print("\x1b[31m[!] Error:\x1b[0m Failed to parse engine JSON.\n", .{});
            std.debug.print("\x1b[33mRaw Output:\x1b[0m\n{s}\n", .{res.stdout});
        }
    }
}

fn printVerifierCandidateProposalResult(writer: anytype, value: std.json.Value) !void {
    try writer.print("VERIFIER CANDIDATE PROPOSAL / NON-AUTHORIZING\n", .{});
    try writer.print("CANDIDATE ONLY\nCOMMANDS NOT EXECUTED\nVERIFIERS NOT EXECUTED\nNO EVIDENCE PRODUCED\nNO PROOF/SUPPORT GRANTED\n\n", .{});
    if (findError(value)) |err_value| return printEngineRejected(writer, err_value);
    const proposal = findVerifierCandidatePayload(value) orelse {
        try writer.print("No verifier candidate proposal payload was present.\n", .{});
        return;
    };
    if (proposal != .object) return printJsonValue(writer, proposal, 2);
    const obj = proposal.object;
    try printField(writer, obj, "candidateCount", "Candidate Count");
    try printField(writer, obj, "reviewRequired", "Review Required");
    try printField(writer, obj, "candidateOnly", "Candidate Only");
    try printField(writer, obj, "nonAuthorizing", "Non-Authorizing");
    try printField(writer, obj, "executed", "Executed");
    try printField(writer, obj, "producedEvidence", "Produced Evidence");
    try printField(writer, obj, "commandsExecuted", "Commands Executed");
    try printField(writer, obj, "verifiersExecuted", "Verifiers Executed");
    try printField(writer, obj, "authorityEffect", "Authority Effect");
    if (obj.get("records")) |records| {
        try writer.print("\nCandidates:\n", .{});
        if (records == .array) {
            for (records.array.items, 0..) |record, index| {
                try writer.print("- Candidate {d}:\n", .{index + 1});
                try printVerifierCandidateRecordSummary(writer, record, 4);
            }
        } else {
            try printJsonValue(writer, records, 2);
        }
    }
}

fn printVerifierCandidateListResult(writer: anytype, value: std.json.Value) !void {
    try writer.print("VERIFIER CANDIDATES / READ-ONLY / NON-AUTHORIZING\n", .{});
    try writer.print("CANDIDATE ONLY\nREAD-ONLY\nCOMMANDS NOT EXECUTED\nVERIFIERS NOT EXECUTED\nNO EVIDENCE PRODUCED\nNOT VERIFIED\nNOT SUPPORT\nNOT PROOF\n\n", .{});
    if (findError(value)) |err_value| return printEngineRejected(writer, err_value);
    const list = findVerifierCandidatePayload(value) orelse {
        try writer.print("No verifier candidate list payload was present.\n", .{});
        return;
    };
    if (list != .object) return printJsonValue(writer, list, 2);
    const obj = list.object;
    try printField(writer, obj, "totalRead", "Total Read");
    try printField(writer, obj, "malformedLines", "Malformed Lines");
    try printField(writer, obj, "missingFile", "Missing File");
    try printField(writer, obj, "truncated", "Truncated");
    try printField(writer, obj, "readOnly", "Read Only");
    try printField(writer, obj, "candidateOnly", "Candidate Only");
    try printField(writer, obj, "nonAuthorizing", "Non-Authorizing");
    try printField(writer, obj, "executed", "Executed");
    try printField(writer, obj, "producedEvidence", "Produced Evidence");
    try printField(writer, obj, "commandsExecuted", "Commands Executed");
    try printField(writer, obj, "verifiersExecuted", "Verifiers Executed");
    try printField(writer, obj, "authorityEffect", "Authority Effect");
    if (obj.get("candidates")) |candidates| {
        try writer.print("\nCandidates:\n", .{});
        if (candidates == .array) {
            for (candidates.array.items, 0..) |candidate, index| {
                try writer.print("- Candidate {d}:\n", .{index + 1});
                try printVerifierCandidateRecordSummary(writer, candidate, 4);
            }
        } else {
            try printJsonValue(writer, candidates, 2);
        }
    }
}

fn printVerifierCandidateReviewResult(writer: anytype, value: std.json.Value) !void {
    try writer.print("VERIFIER CANDIDATE REVIEW / NON-AUTHORIZING\n", .{});
    try writer.print("CANDIDATE ONLY\nAPPROVAL METADATA ONLY\nREJECTION METADATA ONLY\nCOMMANDS NOT EXECUTED\nVERIFIERS NOT EXECUTED\nNO EVIDENCE PRODUCED\nNO PROOF/SUPPORT GRANTED\nREJECTION IS NOT GLOBAL NEGATIVE EVIDENCE\n\n", .{});
    if (findError(value)) |err_value| return printEngineRejected(writer, err_value);
    const review = findVerifierCandidatePayload(value) orelse {
        try writer.print("No verifier candidate review payload was present.\n", .{});
        return;
    };
    try printVerifierCandidateRecordSummary(writer, review, 0);
}

fn printVerifierExecutionListResult(writer: anytype, value: std.json.Value) !void {
    try printVerifierExecutionInspectionHeader(writer, "VERIFIER EXECUTION RECORDS / READ-ONLY INSPECTION / NON-AUTHORIZING");
    if (findError(value)) |err_value| return printEngineRejected(writer, err_value);
    const list = findVerifierExecutionPayload(value) orelse {
        try writer.print("No verifier execution list payload was present.\n", .{});
        return;
    };
    if (list != .object) return printJsonValue(writer, list, 2);
    const obj = list.object;
    try printField(writer, obj, "totalRead", "Total Read");
    try printField(writer, obj, "returnedCount", "Returned Count");
    try printField(writer, obj, "malformedLines", "Malformed Lines");
    try printField(writer, obj, "missingFile", "Missing File");
    try printField(writer, obj, "truncated", "Truncated");
    try printField(writer, obj, "readOnly", "Read Only");
    try printFieldAliases(writer, obj, &.{ "evidenceCandidate", "evidence_candidate" }, "Evidence Candidate");
    try printFieldAliases(writer, obj, &.{ "nonAuthorizing", "non_authorizing" }, "Non-Authorizing");
    try printFalseAuthorityFieldAliases(writer, obj, &.{ "supportGranted", "support_granted" }, "Support Granted");
    try printFalseAuthorityFieldAliases(writer, obj, &.{ "proofGranted", "proof_granted" }, "Proof Granted");
    try printFalseAuthorityFieldAliases(writer, obj, &.{ "proofDischarged", "proof_discharged" }, "Proof Discharged");
    try printField(writer, obj, "commandsExecuted", "Commands Executed");
    try printField(writer, obj, "verifiersExecuted", "Verifiers Executed");
    try printSectionIfPresent(writer, obj, "warnings", "Warnings", 0);
    try printSectionIfPresent(writer, obj, "capacityTelemetry", "Capacity Telemetry", 0);
    if (firstObjectField(obj, &.{ "records", "executions", "executionRecords", "verifierExecutionRecords", "verifier_execution_records" })) |records| {
        try writer.print("\nExecution Records:\n", .{});
        if (records == .array) {
            for (records.array.items, 0..) |record, index| {
                try writer.print("- Execution {d}:\n", .{index + 1});
                try printVerifierExecutionRecordSummary(writer, record, 4);
            }
        } else {
            try printJsonValue(writer, records, 2);
        }
    }
}

fn printVerifierExecutionGetResult(writer: anytype, value: std.json.Value) !void {
    try printVerifierExecutionInspectionHeader(writer, "VERIFIER EXECUTION RECORD / READ-ONLY INSPECTION / NON-AUTHORIZING");
    if (findError(value)) |err_value| return printEngineRejected(writer, err_value);
    const payload = findVerifierExecutionPayload(value) orelse {
        try writer.print("No verifier execution get payload was present.\n", .{});
        return;
    };
    if (payload != .object) return printJsonValue(writer, payload, 2);
    const obj = payload.object;
    try printField(writer, obj, "status", "Status");
    try printField(writer, obj, "id", "Execution ID");
    try printField(writer, obj, "executionId", "Execution ID");
    try printField(writer, obj, "execution_id", "Execution ID");
    try printField(writer, obj, "readOnly", "Read Only");
    try printSectionIfPresent(writer, obj, "warnings", "Warnings", 0);
    if (firstObjectField(obj, &.{ "record", "executionRecord", "execution_record", "verifierExecutionRecord", "verifier_execution_record" })) |record| {
        try writer.print("\nExecution Record:\n", .{});
        try printVerifierExecutionRecordSummary(writer, record, 2);
    } else {
        try printVerifierExecutionRecordSummary(writer, payload, 0);
    }
}

fn printVerifierExecutionInspectionHeader(writer: anytype, title: []const u8) !void {
    try writer.print("{s}\n", .{title});
    try writer.print("READ-ONLY INSPECTION\n", .{});
    try writer.print("NON-AUTHORIZING\n", .{});
    try writer.print("EVIDENCE CANDIDATE ONLY\n", .{});
    try writer.print("COMMANDS NOT EXECUTED BY INSPECTION\n", .{});
    try writer.print("VERIFIERS NOT EXECUTED BY INSPECTION\n", .{});
    try writer.print("NO PROOF/SUPPORT GRANTED\n", .{});
    try writer.print("NO CORRECTION APPLIED\n", .{});
    try writer.print("NO NEGATIVE KNOWLEDGE PROMOTED\n", .{});
    try writer.print("NO PATCH/CORPUS/PACK MUTATION\n", .{});
    try writer.print("Passing execution records remain evidence candidates only.\n", .{});
    try writer.print("Failing execution records are not correction or negative-knowledge records.\n", .{});
    try writer.print("Support Granted: false\n", .{});
    try writer.print("Proof Granted: false\n\n", .{});
}

fn printVerifierExecutionRecordSummary(writer: anytype, record: std.json.Value, indent: usize) !void {
    const obj = switch (record) {
        .object => |o| o,
        else => return printJsonValue(writer, record, indent),
    };
    try printIndentedFieldAliases(writer, obj, &.{ "id", "executionId", "execution_id" }, "Execution ID", indent);
    try printIndentedFieldAliases(writer, obj, &.{ "candidateId", "candidate_id", "verifierCandidateId", "verifier_candidate_id" }, "Candidate ID", indent);
    try printIndentedFieldAliases(writer, obj, &.{"status"}, "Status", indent);
    try printIndentedSectionAliases(writer, obj, &.{ "argv", "argvTokens", "argv_tokens" }, "Argv Tokens", indent);
    try printIndentedFieldAliases(writer, obj, &.{ "workspaceRef", "workspace_ref" }, "Workspace Ref", indent);
    try printIndentedFieldAliases(writer, obj, &.{ "workspaceRoot", "workspace_root" }, "Workspace Root", indent);
    try printIndentedFieldAliases(writer, obj, &.{ "exitCode", "exit_code" }, "Exit Code", indent);
    try printIndentedFieldAliases(writer, obj, &.{ "failureSignal", "failure_signal" }, "Failure Signal", indent);
    try printIndentedFieldAliases(writer, obj, &.{ "stdoutSnippet", "stdout_snippet" }, "Stdout Snippet", indent);
    try printIndentedFieldAliases(writer, obj, &.{ "stderrSnippet", "stderr_snippet" }, "Stderr Snippet", indent);
    try printIndentedFieldAliases(writer, obj, &.{ "evidenceCandidate", "evidence_candidate" }, "Evidence Candidate", indent);
    try printIndentedFieldAliases(writer, obj, &.{ "nonAuthorizing", "non_authorizing" }, "Non-Authorizing", indent);
    try printIndentedFalseAuthorityFieldAliases(writer, obj, &.{ "supportGranted", "support_granted" }, "Support Granted", indent);
    try printIndentedFalseAuthorityFieldAliases(writer, obj, &.{ "proofGranted", "proof_granted" }, "Proof Granted", indent);
    try printIndentedFalseAuthorityFieldAliases(writer, obj, &.{ "proofDischarged", "proof_discharged" }, "Proof Discharged", indent);
    try printIndentedSectionAliases(writer, obj, &.{ "authority", "authorityFlags", "authority_flags" }, "Authority Flags", indent);
    try printIndentedSectionAliases(writer, obj, &.{ "mutationFlags", "mutation_flags" }, "Mutation Flags", indent);
}

fn printVerifierCandidateRecordSummary(writer: anytype, record: std.json.Value, indent: usize) !void {
    const obj = switch (record) {
        .object => |o| o,
        else => return printJsonValue(writer, record, indent),
    };
    try printIndentedField(writer, obj, "id", "Candidate ID", indent);
    try printIndentedField(writer, obj, "candidateId", "Candidate ID", indent);
    try printIndentedField(writer, obj, "recordType", "Record Type", indent);
    try printIndentedField(writer, obj, "status", "Status", indent);
    try printIndentedField(writer, obj, "sourceKind", "Source Kind", indent);
    try printIndentedField(writer, obj, "sourceRef", "Source Ref", indent);
    try printIndentedField(writer, obj, "sourcePlanId", "Source Plan ID", indent);
    try printIndentedField(writer, obj, "sourceCommandCandidateId", "Source Command Candidate ID", indent);
    try printIndentedSection(writer, obj, "argv", "Argv", indent);
    try printIndentedField(writer, obj, "cwdHint", "CWD Hint", indent);
    try printIndentedField(writer, obj, "purpose", "Purpose", indent);
    try printIndentedField(writer, obj, "reason", "Reason", indent);
    try printIndentedField(writer, obj, "riskLevel", "Risk Level", indent);
    try printIndentedField(writer, obj, "mutationRiskDisclosure", "Mutation Risk Disclosure", indent);
    try printIndentedSection(writer, obj, "evidencePaths", "Evidence Paths", indent);
    try printIndentedField(writer, obj, "reviewRequired", "Review Required", indent);
    try printIndentedField(writer, obj, "reviewDecision", "Review Decision", indent);
    try printIndentedField(writer, obj, "reviewedBy", "Reviewed By", indent);
    try printIndentedField(writer, obj, "reviewReason", "Review Reason", indent);
    try printIndentedField(writer, obj, "approvalMeaning", "Approval Meaning", indent);
    try printIndentedField(writer, obj, "candidateOnly", "Candidate Only", indent);
    try printIndentedField(writer, obj, "nonAuthorizing", "Non-Authorizing", indent);
    try printIndentedField(writer, obj, "executesByDefault", "Executes By Default", indent);
    try printIndentedField(writer, obj, "executed", "Executed", indent);
    try printIndentedField(writer, obj, "producedEvidence", "Produced Evidence", indent);
    try printIndentedField(writer, obj, "commandsExecuted", "Commands Executed", indent);
    try printIndentedField(writer, obj, "verifiersExecuted", "Verifiers Executed", indent);
    try printIndentedField(writer, obj, "approvalCreatesEvidence", "Approval Creates Evidence", indent);
    try printIndentedField(writer, obj, "treatedAsProof", "Treated As Proof", indent);
    try printIndentedField(writer, obj, "supportGranted", "Support Granted", indent);
    try printIndentedField(writer, obj, "proofDischarged", "Proof Discharged", indent);
    try printIndentedSection(writer, obj, "appendOnly", "Append-Only Metadata", indent);
    try printIndentedSection(writer, obj, "authority", "Authority Flags", indent);
    try printIndentedSection(writer, obj, "authorityFlags", "Authority Flags", indent);
}

fn findVerifierCandidatePayload(value: std.json.Value) ?std.json.Value {
    const obj = switch (value) {
        .object => |o| o,
        else => return null,
    };
    inline for (.{ "verifierCandidateProposal", "verifierCandidateList", "verifierCandidateReview", "verifier_candidate_proposal", "verifier_candidate_list", "verifier_candidate_review" }) |key| {
        if (obj.get(key)) |payload| return payload;
    }
    if (obj.get("result")) |result| {
        const result_obj = switch (result) {
            .object => |o| o,
            else => return result,
        };
        inline for (.{ "verifierCandidateProposal", "verifierCandidateList", "verifierCandidateReview", "verifier_candidate_proposal", "verifier_candidate_list", "verifier_candidate_review" }) |key| {
            if (result_obj.get(key)) |payload| return payload;
        }
        return result;
    }
    return null;
}

fn findVerifierExecutionPayload(value: std.json.Value) ?std.json.Value {
    const obj = switch (value) {
        .object => |o| o,
        else => return null,
    };
    const keys = .{
        "verifierExecutionList",
        "verifierExecutionGet",
        "verifierExecutionRecordList",
        "verifierExecutionRecordGet",
        "verifierCandidateExecutionList",
        "verifierCandidateExecutionGet",
        "verifier_execution_list",
        "verifier_execution_get",
        "verifier_execution_record_list",
        "verifier_execution_record_get",
        "verifier_candidate_execution_list",
        "verifier_candidate_execution_get",
    };
    inline for (keys) |key| {
        if (obj.get(key)) |payload| return payload;
    }
    if (obj.get("result")) |result| {
        const result_obj = switch (result) {
            .object => |o| o,
            else => return result,
        };
        inline for (keys) |key| {
            if (result_obj.get(key)) |payload| return payload;
        }
        return result;
    }
    return null;
}

fn printEngineRejected(writer: anytype, value: std.json.Value) !void {
    try writer.print("Engine Rejected Request:\n", .{});
    try printJsonValue(writer, value, 2);
    try writer.print("\n", .{});
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

fn hasKind(value: std.json.Value, expected: []const u8) bool {
    const obj = switch (value) {
        .object => |o| o,
        else => return false,
    };
    const kind = obj.get("kind") orelse return false;
    return kind == .string and std.mem.eql(u8, kind.string, expected);
}

fn requireNonEmpty(value: ?[]const u8, message: []const u8) []const u8 {
    const actual = value orelse {
        std.debug.print("{s}\n", .{message});
        std.process.exit(1);
    };
    if (std.mem.trim(u8, actual, " \r\n\t").len == 0) {
        std.debug.print("{s}\n", .{message});
        std.process.exit(1);
    }
    return actual;
}

fn failMissingValue(flag: []const u8) !void {
    try std.io.getStdErr().writer().print("{s} requires a value\n", .{flag});
    std.process.exit(1);
}

fn printField(writer: anytype, obj: std.json.ObjectMap, field: []const u8, label: []const u8) !void {
    const value = obj.get(field) orelse return;
    try writer.print("{s}: ", .{label});
    try printInlineJsonValue(writer, value);
    try writer.print("\n", .{});
}

fn printIndentedField(writer: anytype, obj: std.json.ObjectMap, field: []const u8, label: []const u8, indent: usize) !void {
    const value = obj.get(field) orelse return;
    try writer.writeByteNTimes(' ', indent);
    try writer.print("{s}: ", .{label});
    try printInlineJsonValue(writer, value);
    try writer.print("\n", .{});
}

fn printFieldAliases(writer: anytype, obj: std.json.ObjectMap, fields: []const []const u8, label: []const u8) !void {
    const value = firstObjectField(obj, fields) orelse return;
    try writer.print("{s}: ", .{label});
    try printInlineJsonValue(writer, value);
    try writer.print("\n", .{});
}

fn printFalseAuthorityFieldAliases(writer: anytype, obj: std.json.ObjectMap, fields: []const []const u8, label: []const u8) !void {
    const value = firstObjectField(obj, fields) orelse return;
    if (value == .bool and value.bool) return;
    try writer.print("{s}: ", .{label});
    try printInlineJsonValue(writer, value);
    try writer.print("\n", .{});
}

fn printIndentedFieldAliases(writer: anytype, obj: std.json.ObjectMap, fields: []const []const u8, label: []const u8, indent: usize) !void {
    const value = firstObjectField(obj, fields) orelse return;
    try writer.writeByteNTimes(' ', indent);
    try writer.print("{s}: ", .{label});
    try printInlineJsonValue(writer, value);
    try writer.print("\n", .{});
}

fn printIndentedFalseAuthorityFieldAliases(writer: anytype, obj: std.json.ObjectMap, fields: []const []const u8, label: []const u8, indent: usize) !void {
    const value = firstObjectField(obj, fields) orelse return;
    if (value == .bool and value.bool) return;
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

fn printIndentedSectionAliases(writer: anytype, obj: std.json.ObjectMap, fields: []const []const u8, label: []const u8, indent: usize) !void {
    const value = firstObjectField(obj, fields) orelse return;
    if (isEmptyJsonList(value)) return;
    try writer.writeByteNTimes(' ', indent);
    try writer.print("{s}:\n", .{label});
    try printJsonValue(writer, value, indent + 2);
}

fn printSectionIfPresent(writer: anytype, obj: std.json.ObjectMap, field: []const u8, label: []const u8, indent: usize) !void {
    const value = obj.get(field) orelse return;
    if (isEmptyJsonList(value)) return;
    try writer.writeByteNTimes(' ', indent);
    try writer.print("{s}:\n", .{label});
    try printJsonValue(writer, value, indent + 2);
}

fn firstObjectField(obj: std.json.ObjectMap, fields: []const []const u8) ?std.json.Value {
    for (fields) |field| {
        if (obj.get(field)) |value| return value;
    }
    return null;
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
