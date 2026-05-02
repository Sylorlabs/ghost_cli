const std = @import("std");
const locator = @import("../engine/locator.zig");
const process = @import("../engine/process.zig");

pub const CorrectionOptions = struct {
    file_path: ?[]const u8 = null,
    json: bool = false,
    debug: bool = false,
};

const max_request_bytes = 1024 * 1024;
const usage =
    \\Usage: ghost correction <propose|review> --file <request.json> [--json] [--debug]
    \\
;

pub fn printHelp(writer: anytype) !void {
    try writer.print(
        \\correction
        \\
        \\Usage: ghost correction <propose|review> --file <request.json> [--json] [--debug]
        \\
        \\Explicit correction proposal and review commands.
        \\
        \\Subcommands:
        \\  propose --file <request.json>  Run a correction.propose GIP request
        \\  review --file <request.json>   Run a correction.review GIP request
        \\
        \\Safety:
        \\  This request runs only when this command is explicitly invoked.
        \\  Request files must be GIP-compatible JSON with kind "correction.propose" or "correction.review".
        \\  User corrections are signals, not proof.
        \\  Correction proposals are candidate-only and review-required.
        \\  Correction reviews record explicit accept/reject decisions only.
        \\  Accepted reviewed corrections are still not proof.
        \\  Accepted reviews do not mutate corpus, packs, or negative knowledge.
        \\  No global promotion is performed by default.
        \\  correction.reviewed.list/get are not available yet.
        \\  No hidden learning is performed.
        \\  No correction.accept exists yet.
        \\  NO KNOWLEDGE MUTATED.
        \\  NO VERIFIERS EXECUTED.
        \\  NOT ACCEPTED.
        \\  NOT PERSISTED.
        \\  `--json` preserves raw engine stdout exactly.
        \\  `--debug` writes diagnostics to stderr only.
        \\
    , .{});
}

pub fn printHelpForArgs(writer: anytype, args: []const []const u8) !void {
    if (args.len == 0) return printHelp(writer);
    if (std.mem.eql(u8, args[0], "propose")) return printProposeHelp(writer);
    if (std.mem.eql(u8, args[0], "review")) return printReviewHelp(writer);
    return printHelp(writer);
}

fn printProposeHelp(writer: anytype) !void {
    try writer.print(
        \\correction propose
        \\
        \\Usage: ghost correction propose --file <request.json> [--json] [--debug]
        \\
        \\Reads a full GIP-compatible correction proposal request from a file and
        \\sends the bytes unchanged to ghost_gip --stdin. The request must include
        \\kind "correction.propose".
        \\
        \\Options:
        \\  --file <request.json>     Correction proposal GIP request file
        \\  --json                    Preserve raw GIP stdout exactly
        \\  --debug                   Diagnostics to stderr
        \\
        \\Safety:
        \\  Explicit invocation only.
        \\  User corrections are signals, not proof.
        \\  CORRECTION CANDIDATE ONLY.
        \\  NOT PROOF.
        \\  REVIEW REQUIRED.
        \\  NO KNOWLEDGE MUTATED.
        \\  NO VERIFIERS EXECUTED.
        \\  NOT ACCEPTED.
        \\  NOT PERSISTED.
        \\  Does not mutate corpus, packs, or negative knowledge.
        \\  Does not execute verifier/check candidates.
        \\  Does not affect future behavior until a separate review path exists.
        \\  No hidden learning is performed.
        \\  No correction.accept exists yet.
        \\
    , .{});
}

fn printReviewHelp(writer: anytype) !void {
    try writer.print(
        \\correction review
        \\
        \\Usage: ghost correction review --file <request.json> [--json] [--debug]
        \\
        \\Reads a full GIP-compatible correction review request from a file and
        \\sends the bytes unchanged to ghost_gip --stdin. The request must include
        \\kind "correction.review".
        \\
        \\Options:
        \\  --file <request.json>     Correction review GIP request file
        \\  --json                    Preserve raw GIP stdout exactly
        \\  --debug                   Diagnostics to stderr
        \\
        \\Safety:
        \\  Explicit invocation only.
        \\  Records accepted/rejected review decisions only.
        \\  REVIEWED CORRECTION RECORD.
        \\  APPEND-ONLY.
        \\  NOT PROOF.
        \\  NON-AUTHORIZING.
        \\  NO GLOBAL PROMOTION.
        \\  NO KNOWLEDGE MUTATED.
        \\  NO VERIFIERS EXECUTED.
        \\  FUTURE BEHAVIOR IS CANDIDATE-ONLY.
        \\  Accepted reviews do not mutate corpus, packs, or negative knowledge.
        \\  Does not execute verifier/check candidates.
        \\  Does not run from correction.propose or any startup/diagnostic path.
        \\  correction.reviewed.list/get are not available yet.
        \\
    , .{});
}

pub fn executeFromArgs(
    allocator: std.mem.Allocator,
    engine_root: ?[]const u8,
    args: []const []const u8,
    base: CorrectionOptions,
) !void {
    const sub = if (args.len > 0) args[0] else {
        try std.io.getStdErr().writer().print("{s}", .{usage});
        std.process.exit(1);
    };
    if (!std.mem.eql(u8, sub, "propose") and !std.mem.eql(u8, sub, "review")) {
        try std.io.getStdErr().writer().print("Unknown correction command: {s}\n{s}", .{ sub, usage });
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
            try std.io.getStdErr().writer().print("Unknown correction {s} option: {s}\n", .{ sub, arg });
            std.process.exit(1);
        } else {
            try std.io.getStdErr().writer().print("Unexpected correction {s} argument: {s}\n", .{ sub, arg });
            std.process.exit(1);
        }
    }

    if (std.mem.eql(u8, sub, "propose")) {
        try executePropose(allocator, engine_root, options);
    } else {
        try executeReview(allocator, engine_root, options);
    }
}

pub fn executePropose(allocator: std.mem.Allocator, engine_root: ?[]const u8, options: CorrectionOptions) !void {
    const file_path = options.file_path orelse {
        try std.io.getStdErr().writer().print("{s}", .{usage});
        std.process.exit(1);
    };
    if (std.mem.trim(u8, file_path, " \r\n\t").len == 0) {
        try std.io.getStdErr().writer().print("correction propose --file must be non-empty\n", .{});
        std.process.exit(1);
    }

    const request = std.fs.cwd().readFileAlloc(allocator, file_path, max_request_bytes) catch |err| {
        try std.io.getStdErr().writer().print("Error: failed to read correction.propose request file '{s}': {s}\n", .{ file_path, @errorName(err) });
        std.process.exit(1);
    };
    defer allocator.free(request);

    var parsed = std.json.parseFromSlice(std.json.Value, allocator, request, .{}) catch |err| {
        if (options.debug) try std.io.getStdErr().writer().print("[DEBUG] Parse Status: FAILED ({s})\n", .{@errorName(err)});
        try std.io.getStdErr().writer().print("Error: correction.propose request file is not valid JSON: {s}\n", .{@errorName(err)});
        std.process.exit(1);
    };
    defer parsed.deinit();

    if (!hasCorrectionProposeKind(parsed.value)) {
        if (options.debug) try std.io.getStdErr().writer().print("[DEBUG] Parse Status: FAILED (kind mismatch)\n", .{});
        try std.io.getStdErr().writer().print("Error: request file must contain top-level kind \"correction.propose\".\n", .{});
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
        try std.io.getStdErr().writer().print("[DEBUG] GIP Kind: correction.propose\n", .{});
        try std.io.getStdErr().writer().print("[DEBUG] Input File: {s}\n", .{file_path});
        try std.io.getStdErr().writer().print("[DEBUG] Stdin Byte Count: {d}\n", .{request.len});
    }

    const result = process.runEngineCommandWithInput(allocator, argv, request) catch |err| {
        try std.io.getStdErr().writer().print("\x1b[31m[!] Error:\x1b[0m Failed to execute correction.propose: {}\n", .{err});
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
        try std.io.getStdErr().writer().print("Error: Failed to parse engine output as correction.propose JSON.\n", .{});
        try std.io.getStdErr().writer().print("Raw output:\n{s}\n", .{result.stdout});
        return;
    };
    defer out_parsed.deinit();

    if (options.debug) try std.io.getStdErr().writer().print("[DEBUG] Parse Status: ok\n", .{});

    try printCorrectionProposalResult(std.io.getStdOut().writer(), out_parsed.value);
}

pub fn executeReview(allocator: std.mem.Allocator, engine_root: ?[]const u8, options: CorrectionOptions) !void {
    try executeCorrectionGip(allocator, engine_root, options, "review", "correction.review");
}

fn executeCorrectionGip(
    allocator: std.mem.Allocator,
    engine_root: ?[]const u8,
    options: CorrectionOptions,
    subcommand: []const u8,
    expected_kind: []const u8,
) !void {
    const file_path = options.file_path orelse {
        try std.io.getStdErr().writer().print("{s}", .{usage});
        std.process.exit(1);
    };
    if (std.mem.trim(u8, file_path, " \r\n\t").len == 0) {
        try std.io.getStdErr().writer().print("correction {s} --file must be non-empty\n", .{subcommand});
        std.process.exit(1);
    }

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

    const argv = &[_][]const u8{ bin_path, "--stdin" };
    if (options.debug) {
        try std.io.getStdErr().writer().print("[DEBUG] Engine Binary: {s}\n", .{bin_path});
        try std.io.getStdErr().writer().print("[DEBUG] GIP Kind: {s}\n", .{expected_kind});
        try std.io.getStdErr().writer().print("[DEBUG] Input File: {s}\n", .{file_path});
        try std.io.getStdErr().writer().print("[DEBUG] Stdin Byte Count: {d}\n", .{request.len});
    }

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

    if (std.mem.eql(u8, expected_kind, "correction.review")) {
        try printCorrectionReviewResult(std.io.getStdOut().writer(), out_parsed.value);
    } else {
        try printCorrectionProposalResult(std.io.getStdOut().writer(), out_parsed.value);
    }
}

fn hasCorrectionProposeKind(value: std.json.Value) bool {
    return hasKind(value, "correction.propose");
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

fn printCorrectionProposalResult(writer: anytype, value: std.json.Value) !void {
    try writer.print("Correction Proposal Result\n", .{});
    try writer.print("CORRECTION CANDIDATE ONLY\n", .{});
    try writer.print("NOT PROOF\n", .{});
    try writer.print("REVIEW REQUIRED\n", .{});
    try writer.print("NO KNOWLEDGE MUTATED\n", .{});
    try writer.print("NO VERIFIERS EXECUTED\n", .{});
    try writer.print("NOT ACCEPTED\n", .{});
    try writer.print("NOT PERSISTED\n\n", .{});

    if (findError(value)) |err_value| {
        try writer.print("Engine Rejected Request:\n", .{});
        try printJsonValue(writer, err_value, 2);
        try writer.print("\n", .{});
        return;
    }

    const proposal_value = findCorrectionProposal(value) orelse {
        try writer.print("No correctionProposal result payload was present.\n", .{});
        return;
    };
    const proposal = switch (proposal_value) {
        .object => |obj| obj,
        else => {
            try printJsonValue(writer, proposal_value, 2);
            try writer.print("\n", .{});
            return;
        },
    };

    try printField(writer, proposal, "status", "Status");
    try printField(writer, proposal, "requiredReview", "Required Review");
    try printField(writer, proposal, "required_review", "Required Review");
    try printField(writer, proposal, "nonAuthorizing", "Non-Authorizing");
    try printField(writer, proposal, "treatedAsProof", "Treated As Proof");

    const candidate_value = proposal.get("correctionCandidate") orelse proposal.get("correction_candidate");
    if (candidate_value) |candidate| {
        try writer.print("\nCorrection Candidate:\n", .{});
        if (candidate == .object) {
            const obj = candidate.object;
            try printField(writer, obj, "correctionType", "Correction Type");
            try printField(writer, obj, "correction_type", "Correction Type");
            try printField(writer, obj, "originalOperation", "Original Operation");
            try printField(writer, obj, "original_operation", "Original Operation");
            try printField(writer, obj, "originalRequestId", "Original Request ID");
            try printField(writer, obj, "original_request_id", "Original Request ID");
            try printField(writer, obj, "originalRequestSummary", "Original Request Summary");
            try printField(writer, obj, "original_request_summary", "Original Request Summary");
            try printField(writer, obj, "disputedOutput", "Disputed Output");
            try printField(writer, obj, "disputed_output", "Disputed Output");
            try printField(writer, obj, "userCorrection", "User Correction");
            try printField(writer, obj, "user_correction", "User Correction");
            try printField(writer, obj, "state", "State");
            try printField(writer, obj, "nonAuthorizing", "Non-Authorizing");
            try printField(writer, obj, "treatedAsProof", "Treated As Proof");
            try printSection(writer, obj, "evidenceRefs", "Evidence Refs");
            try printSection(writer, obj, "evidence_refs", "Evidence Refs");
            try printSection(writer, obj, "proposedLearningOutputs", "Proposed Learning Outputs");
            try printSection(writer, obj, "proposed_learning_outputs", "Proposed Learning Outputs");
        } else {
            try printJsonValue(writer, candidate, 2);
            try writer.print("\n", .{});
        }
    }

    try printSection(writer, proposal, "learningCandidates", "Learning Candidates");
    try printSection(writer, proposal, "learning_candidates", "Learning Candidates");
    try printSection(writer, proposal, "unknowns", "Unknowns");
    try printSection(writer, proposal, "mutationFlags", "Mutation Flags");
    try printSection(writer, proposal, "mutation_flags", "Mutation Flags");
    try printSection(writer, proposal, "authorityFlags", "Authority Flags");
    try printSection(writer, proposal, "authority_flags", "Authority Flags");
    try printSection(writer, proposal, "authority", "Authority Flags");

    try writer.print("\nNotice: user corrections are signals, not proof. This proposal does not mutate corpus, packs, negative knowledge, or verifier state, and no hidden learning or correction.accept path is run.\n", .{});
}

fn printCorrectionReviewResult(writer: anytype, value: std.json.Value) !void {
    try writer.print("Correction Review Result\n", .{});
    try writer.print("REVIEWED CORRECTION RECORD\n", .{});
    try writer.print("APPEND-ONLY\n", .{});
    try writer.print("NOT PROOF\n", .{});
    try writer.print("NON-AUTHORIZING\n", .{});
    try writer.print("NO GLOBAL PROMOTION\n", .{});
    try writer.print("NO KNOWLEDGE MUTATED\n", .{});
    try writer.print("NO VERIFIERS EXECUTED\n", .{});
    try writer.print("FUTURE BEHAVIOR IS CANDIDATE-ONLY\n\n", .{});

    if (findError(value)) |err_value| {
        try writer.print("Engine Rejected Request:\n", .{});
        try printJsonValue(writer, err_value, 2);
        try writer.print("\n", .{});
        return;
    }

    const review_value = findCorrectionReview(value) orelse {
        try writer.print("No correctionReview result payload was present.\n", .{});
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
    try printField(writer, review, "required_review", "Required Review");

    const record_value = review.get("reviewedCorrectionRecord") orelse review.get("reviewed_correction_record");
    if (record_value) |record| {
        try writer.print("\nReviewed Correction Record:\n", .{});
        if (record == .object) {
            const obj = record.object;
            try printField(writer, obj, "id", "ID");
            try printField(writer, obj, "schemaVersion", "Schema Version");
            try printField(writer, obj, "schema_version", "Schema Version");
            try printField(writer, obj, "projectShard", "Project Shard");
            try printField(writer, obj, "project_shard", "Project Shard");
            try printField(writer, obj, "sourceCorrectionCandidateId", "Source Correction Candidate ID");
            try printField(writer, obj, "source_correction_candidate_id", "Source Correction Candidate ID");
            try printField(writer, obj, "reviewDecision", "Decision");
            try printField(writer, obj, "review_decision", "Decision");
            try printField(writer, obj, "decision", "Decision");
            try printField(writer, obj, "reviewerNote", "Reviewer Note");
            try printField(writer, obj, "reviewer_note", "Reviewer Note");
            try printField(writer, obj, "rejectedReason", "Rejected Reason");
            try printField(writer, obj, "rejected_reason", "Rejected Reason");
            try printField(writer, obj, "nonAuthorizing", "Non-Authorizing");
            try printField(writer, obj, "treatedAsProof", "Treated As Proof");
            try printField(writer, obj, "globalPromotion", "Global Promotion");
            try printField(writer, obj, "commandsExecuted", "Commands Executed");
            try printField(writer, obj, "verifiersExecuted", "Verifiers Executed");
            try printField(writer, obj, "corpusMutation", "Corpus Mutation");
            try printField(writer, obj, "packMutation", "Pack Mutation");
            try printField(writer, obj, "negativeKnowledgeMutation", "Negative Knowledge Mutation");
            try printSection(writer, obj, "correctionCandidate", "Correction Candidate");
            try printSection(writer, obj, "correction_candidate", "Correction Candidate");
            try printSection(writer, obj, "acceptedLearningOutputs", "Accepted Learning Outputs");
            try printSection(writer, obj, "accepted_learning_outputs", "Accepted Learning Outputs");
            try printSection(writer, obj, "futureBehaviorCandidate", "Future Behavior Candidate");
            try printSection(writer, obj, "future_behavior_candidate", "Future Behavior Candidate");
            try printSection(writer, obj, "appendOnly", "Append-Only Metadata");
            try printSection(writer, obj, "append_only", "Append-Only Metadata");
        } else {
            try printJsonValue(writer, record, 2);
            try writer.print("\n", .{});
        }
    }

    try printSection(writer, review, "storage", "Append-Only Storage");
    try printSection(writer, review, "appendOnly", "Append-Only Metadata");
    try printSection(writer, review, "append_only", "Append-Only Metadata");
    try printSection(writer, review, "mutationFlags", "Mutation Flags");
    try printSection(writer, review, "mutation_flags", "Mutation Flags");
    try printSection(writer, review, "authorityFlags", "Authority Flags");
    try printSection(writer, review, "authority_flags", "Authority Flags");
    try printSection(writer, review, "authority", "Authority Flags");
    try printSection(writer, review, "futureBehaviorCandidate", "Future Behavior Candidate");
    try printSection(writer, review, "future_behavior_candidate", "Future Behavior Candidate");

    try writer.print("\nNotice: reviewed corrections record explicit accept/reject decisions only. Accepted reviews remain non-authorizing candidate signals, not proof, and do not mutate corpus, packs, negative knowledge, or verifier state.\n", .{});
}

fn findCorrectionProposal(value: std.json.Value) ?std.json.Value {
    const obj = switch (value) {
        .object => |o| o,
        else => return null,
    };
    if (obj.get("correctionProposal")) |proposal| return proposal;
    if (obj.get("correction_proposal")) |proposal| return proposal;
    if (obj.get("result")) |result| {
        const result_obj = switch (result) {
            .object => |o| o,
            else => return result,
        };
        if (result_obj.get("correctionProposal")) |proposal| return proposal;
        if (result_obj.get("correction_proposal")) |proposal| return proposal;
        return result;
    }
    return null;
}

fn findCorrectionReview(value: std.json.Value) ?std.json.Value {
    const obj = switch (value) {
        .object => |o| o,
        else => return null,
    };
    if (obj.get("correctionReview")) |review| return review;
    if (obj.get("correction_review")) |review| return review;
    if (obj.get("result")) |result| {
        const result_obj = switch (result) {
            .object => |o| o,
            else => return result,
        };
        if (result_obj.get("correctionReview")) |review| return review;
        if (result_obj.get("correction_review")) |review| return review;
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

fn failMissingValue(flag: []const u8) !noreturn {
    try std.io.getStdErr().writer().print("{s} requires a value\n", .{flag});
    std.process.exit(1);
}
