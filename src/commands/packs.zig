const std = @import("std");
const runner = @import("../engine/runner.zig");
const locator = @import("../engine/locator.zig");
const process = @import("../engine/process.zig");
const json_contracts = @import("../engine/json_contracts.zig");
const terminal = @import("../render/terminal.zig");

pub const PacksOptions = struct {
    subcommand: []const u8,
    file_path: ?[]const u8 = null,
    id: ?[]const u8 = null,
    decision: ?[]const u8 = null,
    limit: ?usize = null,
    offset: ?usize = null,
    pack_id: ?[]const u8 = null,
    version: ?[]const u8 = null,
    manifest: ?[]const u8 = null,
    all_mounted: bool = false,
    project_shard: ?[]const u8 = null,
    max_guidance_bytes: ?[]const u8 = null,
    max_array_items: ?[]const u8 = null,
    max_string_bytes: ?[]const u8 = null,
    json: bool = false,
    debug: bool = false,
};

const max_request_bytes = 1024 * 1024;

pub const CapabilityDiagnostic = struct {
    binary_path: ?[]u8 = null,
    capabilities_available: bool = false,
    validate_autopsy_guidance_supported: bool = false,
    supported_schema_versions: []const []const u8 = &.{},
    supported_validation_limit_flags: ValidationLimitFlags = .{},
    warning: ?[]u8 = null,
    allocator: std.mem.Allocator,

    pub fn deinit(self: *CapabilityDiagnostic) void {
        if (self.binary_path) |path| self.allocator.free(path);
        for (self.supported_schema_versions) |schema| self.allocator.free(schema);
        self.allocator.free(self.supported_schema_versions);
        if (self.warning) |warning| self.allocator.free(warning);
    }
};

pub const ValidationLimitFlags = struct {
    max_guidance_bytes: bool = false,
    max_array_items: bool = false,
    max_string_bytes: bool = false,
};

const PackCapabilities = struct {
    binaryName: ?[]const u8 = null,
    ghostVersion: ?[]const u8 = null,
    commands: []const Command = &.{},
    validateAutopsyGuidance: ?ValidateAutopsyGuidance = null,

    const Command = struct {
        name: []const u8,
        summary: ?[]const u8 = null,
        aliases: []const []const u8 = &.{},
    };

    const ValidateAutopsyGuidance = struct {
        flags: []const []const u8 = &.{},
        supportedSchemaVersions: []const []const u8 = &.{},
        preferredShape: ?[]const u8 = null,
        legacyShapes: []const []const u8 = &.{},
        validationLimits: ?std.json.Value = null,
    };
};

const CapabilityHandshake = struct {
    binary_path: []u8,
    stdout: []u8,
    stderr: []u8,
    exit_code: u8,
    parsed: ?std.json.Parsed(PackCapabilities),
    limit_flags: ValidationLimitFlags = .{},
    allocator: std.mem.Allocator,

    fn deinit(self: *CapabilityHandshake) void {
        if (self.parsed) |*parsed| parsed.deinit();
        self.allocator.free(self.binary_path);
        self.allocator.free(self.stdout);
        self.allocator.free(self.stderr);
    }

    fn caps(self: *const CapabilityHandshake) ?PackCapabilities {
        if (self.parsed) |parsed| return parsed.value;
        return null;
    }

    fn versionLabel(self: *const CapabilityHandshake) []const u8 {
        if (self.caps()) |value| return value.ghostVersion orelse "unknown";
        return "unknown";
    }
};

const ValidationSummary = struct {
    ok: bool,
    expectedSchema: ?[]const u8 = null,
    supportedSchemaVersions: []const []const u8 = &.{},
    errorCount: usize = 0,
    warningCount: usize = 0,
    reports: []const Report = &.{},

    const Report = struct {
        packId: []const u8,
        version: []const u8,
        manifestPath: []const u8,
        guidanceDeclared: bool = false,
        guidancePath: ?[]const u8 = null,
        guidanceCount: usize = 0,
        schema: ?[]const u8 = null,
        legacyUnversionedSchema: bool = false,
        errorCount: usize = 0,
        warningCount: usize = 0,
        issues: []const Issue = &.{},
    };

    const Issue = struct {
        severity: []const u8,
        code: []const u8,
        path: []const u8,
        message: []const u8,
    };
};

pub fn printHelp(writer: anytype) !void {
    try writer.print(
        \\packs
        \\
        \\Usage: ghost packs <list|inspect|mount|unmount|validate-autopsy-guidance|candidates> [options]
        \\
        \\Manage knowledge packs
        \\
        \\Subcommands:
        \\  list
        \\  inspect <pack-id> [--version=<v>]
        \\  mount <pack-id> [--version=<v>]
        \\  unmount <pack-id> [--version=<v>]
        \\  candidates propose --file <request.json> [--json] [--debug]
        \\  candidates review --file <request.json> [--json] [--debug]
        \\  candidates reviewed list --project-shard=<id> [--decision=accepted|rejected|all] [--limit=<n>] [--offset=<n>] [--json] [--debug]
        \\  candidates reviewed get --project-shard=<id> --id=<record-id> [--json] [--debug]
        \\  validate-autopsy-guidance --manifest=<path> [--json]
        \\  validate-autopsy-guidance --pack-id=<id> --version=<v> [--json]
        \\  validate-autopsy-guidance --all-mounted --project-shard=<id> [--json]
        \\  validate-autopsy-guidance --manifest=<path> [--max-guidance-bytes=<n>] [--max-array-items=<n>] [--max-string-bytes=<n>]
        \\
        \\Safety:
        \\  Validation is explicit and review-only. It does not mutate packs,
        \\  auto-fix guidance, auto-promote guidance, or prove support. The
        \\  command checks engine capabilities before routing advanced validation.
        \\  Human output renders clean success, warning, and error summaries.
        \\  Procedure pack candidates are not installed packs. Their review
        \\  records are append-only and inspected only through ghost_gip.
        \\  Candidate commands do not mutate packs, execute procedure steps,
        \\  execute verifiers/checks, prove support, or globally promote state.
        \\  `--json` preserves raw engine stdout exactly.
        \\  Current engine schema: ghost.autopsy_guidance.v1; legacy guidance
        \\  may be accepted by the engine as a warning for compatibility.
        \\
    , .{});
}

pub fn printHelpForArgs(writer: anytype, args: []const []const u8) !void {
    if (args.len == 0) return printHelp(writer);
    if (std.mem.eql(u8, args[0], "candidates")) {
        if (args.len >= 2 and std.mem.eql(u8, args[1], "propose")) return printCandidateProposeHelp(writer);
        if (args.len >= 2 and std.mem.eql(u8, args[1], "review")) return printCandidateReviewHelp(writer);
        if (args.len >= 2 and std.mem.eql(u8, args[1], "reviewed")) {
            if (args.len >= 3 and std.mem.eql(u8, args[2], "list")) return printCandidateReviewedListHelp(writer);
            if (args.len >= 3 and std.mem.eql(u8, args[2], "get")) return printCandidateReviewedGetHelp(writer);
            return printCandidateReviewedHelp(writer);
        }
        return printCandidatesHelp(writer);
    }
    return printHelp(writer);
}

fn printCandidatesHelp(writer: anytype) !void {
    try writer.print(
        \\packs candidates
        \\
        \\Usage: ghost packs candidates <propose|review|reviewed> [options]
        \\
        \\Explicit procedure pack candidate lifecycle commands.
        \\
        \\Subcommands:
        \\  propose --file <request.json>
        \\  review --file <request.json>
        \\  reviewed list --project-shard=<id> [--decision=accepted|rejected|all] [--limit=<n>] [--offset=<n>]
        \\  reviewed get --project-shard=<id> --id=<record-id>
        \\
        \\Safety:
        \\  Procedure pack candidates are not installed packs.
        \\  Review records are append-only.
        \\  The CLI does not read or write reviewed_pack_candidates.jsonl.
        \\  CANDIDATE ONLY. READ-ONLY inspection.
        \\  NOT PROOF. NOT EVIDENCE. NOT INSTALLED. NOT EXECUTED.
        \\  NO PACK MUTATION. NO GLOBAL PROMOTION. NO VERIFIERS EXECUTED.
        \\  `--json` preserves raw engine stdout exactly.
        \\  `--debug` writes diagnostics to stderr only.
        \\
    , .{});
}

fn printCandidateProposeHelp(writer: anytype) !void {
    try writer.print(
        \\packs candidates propose
        \\
        \\Usage: ghost packs candidates propose --file <request.json> [--json] [--debug]
        \\
        \\Reads a full GIP-compatible procedure pack candidate proposal request
        \\from a file and sends the bytes unchanged to ghost_gip --stdin. The
        \\request must include kind "procedure_pack.candidate.propose".
        \\
        \\Safety:
        \\  CANDIDATE ONLY. NOT PROOF. NOT EVIDENCE.
        \\  NOT INSTALLED. NOT EXECUTED.
        \\  NO PACK MUTATION. NO GLOBAL PROMOTION. NO VERIFIERS EXECUTED.
        \\  Proposals are non-persistent by default.
        \\
    , .{});
}

fn printCandidateReviewHelp(writer: anytype) !void {
    try writer.print(
        \\packs candidates review
        \\
        \\Usage: ghost packs candidates review --file <request.json> [--json] [--debug]
        \\
        \\Reads a full GIP-compatible procedure pack candidate review request
        \\from a file and sends the bytes unchanged to ghost_gip --stdin. The
        \\request must include kind "procedure_pack.candidate.review".
        \\
        \\Safety:
        \\  REVIEWED PROCEDURE PACK CANDIDATE. APPEND-ONLY.
        \\  NOT PROOF. NOT EVIDENCE. NOT INSTALLED. NOT EXECUTED.
        \\  NO PACK MUTATION. NO GLOBAL PROMOTION. NO VERIFIERS EXECUTED.
        \\
    , .{});
}

fn printCandidateReviewedHelp(writer: anytype) !void {
    try writer.print(
        \\packs candidates reviewed
        \\
        \\Usage: ghost packs candidates reviewed <list|get> [options]
        \\
        \\Read-only reviewed procedure pack candidate inspection commands.
        \\
        \\Subcommands:
        \\  list --project-shard=<id> [--decision=accepted|rejected|all] [--limit=<n>] [--offset=<n>]
        \\  get --project-shard=<id> --id=<record-id>
        \\
        \\Safety:
        \\  READ-ONLY. NOT PROOF. NOT EVIDENCE. NOT INSTALLED.
        \\  NO PACK MUTATION. NO VERIFIERS EXECUTED. NO GLOBAL PROMOTION.
        \\  The CLI does not read or write reviewed_pack_candidates.jsonl.
        \\
    , .{});
}

fn printCandidateReviewedListHelp(writer: anytype) !void {
    try writer.print(
        \\packs candidates reviewed list
        \\
        \\Usage: ghost packs candidates reviewed list --project-shard=<id> [--decision=accepted|rejected|all] [--limit=<n>] [--offset=<n>] [--json] [--debug]
        \\
        \\Builds a procedure_pack.candidate.reviewed.list GIP request and sends it to ghost_gip --stdin.
        \\
        \\Safety:
        \\  READ-ONLY. NOT PROOF. NOT EVIDENCE. NOT INSTALLED.
        \\  NO PACK MUTATION. NO VERIFIERS EXECUTED. NO GLOBAL PROMOTION.
        \\
    , .{});
}

fn printCandidateReviewedGetHelp(writer: anytype) !void {
    try writer.print(
        \\packs candidates reviewed get
        \\
        \\Usage: ghost packs candidates reviewed get --project-shard=<id> --id=<record-id> [--json] [--debug]
        \\
        \\Builds a procedure_pack.candidate.reviewed.get GIP request and sends it to ghost_gip --stdin.
        \\
        \\Safety:
        \\  READ-ONLY. NOT PROOF. NOT EVIDENCE. NOT INSTALLED.
        \\  NO PACK MUTATION. NO VERIFIERS EXECUTED. Missing records render as not_found.
        \\
    , .{});
}

pub fn executeFromArgs(
    allocator: std.mem.Allocator,
    engine_root: ?[]const u8,
    args: []const []const u8,
    base: PacksOptions,
) !void {
    const sub = if (args.len > 0) args[0] else "list";
    if (std.mem.eql(u8, sub, "candidates")) {
        try executeCandidatesFromArgs(allocator, engine_root, args[1..], base);
        return;
    }
    const p_id = if (base.pack_id) |pack_id| pack_id else if (args.len > 1 and !std.mem.startsWith(u8, args[1], "--")) args[1] else null;
    var options = base;
    options.subcommand = sub;
    options.pack_id = p_id;

    var i: usize = 1;
    while (i < args.len) : (i += 1) {
        const arg = args[i];
        if (std.mem.eql(u8, arg, "--manifest")) {
            i += 1;
            if (i >= args.len) try failMissingValue("--manifest");
            options.manifest = args[i];
        } else if (std.mem.startsWith(u8, arg, "--manifest=")) {
            options.manifest = arg["--manifest=".len..];
        } else if (std.mem.eql(u8, arg, "--project-shard")) {
            i += 1;
            if (i >= args.len) try failMissingValue("--project-shard");
            options.project_shard = args[i];
        } else if (std.mem.startsWith(u8, arg, "--project-shard=")) {
            options.project_shard = arg["--project-shard=".len..];
        } else if (std.mem.eql(u8, arg, "--all-mounted")) {
            options.all_mounted = true;
        } else if (std.mem.eql(u8, arg, "--max-guidance-bytes")) {
            i += 1;
            if (i >= args.len) try failMissingValue("--max-guidance-bytes");
            options.max_guidance_bytes = args[i];
        } else if (std.mem.startsWith(u8, arg, "--max-guidance-bytes=")) {
            options.max_guidance_bytes = arg["--max-guidance-bytes=".len..];
        } else if (std.mem.eql(u8, arg, "--max-array-items")) {
            i += 1;
            if (i >= args.len) try failMissingValue("--max-array-items");
            options.max_array_items = args[i];
        } else if (std.mem.startsWith(u8, arg, "--max-array-items=")) {
            options.max_array_items = arg["--max-array-items=".len..];
        } else if (std.mem.eql(u8, arg, "--max-string-bytes")) {
            i += 1;
            if (i >= args.len) try failMissingValue("--max-string-bytes");
            options.max_string_bytes = args[i];
        } else if (std.mem.startsWith(u8, arg, "--max-string-bytes=")) {
            options.max_string_bytes = arg["--max-string-bytes=".len..];
        }
    }

    try execute(allocator, engine_root, options);
}

pub fn execute(allocator: std.mem.Allocator, engine_root: ?[]const u8, options: PacksOptions) !void {
    if (std.mem.eql(u8, options.subcommand, "list")) {
        try executeList(allocator, engine_root, options);
    } else if (std.mem.eql(u8, options.subcommand, "inspect")) {
        try executeInspect(allocator, engine_root, options);
    } else if (std.mem.eql(u8, options.subcommand, "mount")) {
        try executeMount(allocator, engine_root, options);
    } else if (std.mem.eql(u8, options.subcommand, "unmount")) {
        try executeUnmount(allocator, engine_root, options);
    } else if (std.mem.eql(u8, options.subcommand, "validate-autopsy-guidance")) {
        try executeValidateAutopsyGuidance(allocator, engine_root, options);
    } else {
        std.debug.print("Unknown packs subcommand: {s}\n", .{options.subcommand});
        std.process.exit(1);
    }
}

fn executeCandidatesFromArgs(
    allocator: std.mem.Allocator,
    engine_root: ?[]const u8,
    args: []const []const u8,
    base: PacksOptions,
) !void {
    const action = if (args.len > 0) args[0] else {
        try printCandidatesHelp(std.io.getStdErr().writer());
        std.process.exit(1);
    };
    if (std.mem.eql(u8, action, "propose")) {
        var options = base;
        try parseCandidateFileArgs(args[1..], &options, "propose");
        try executeCandidateFileGip(allocator, engine_root, options, "procedure_pack.candidate.propose", printProcedurePackCandidateProposalResult);
        return;
    }
    if (std.mem.eql(u8, action, "review")) {
        var options = base;
        try parseCandidateFileArgs(args[1..], &options, "review");
        try executeCandidateFileGip(allocator, engine_root, options, "procedure_pack.candidate.review", printProcedurePackCandidateReviewResult);
        return;
    }
    if (std.mem.eql(u8, action, "reviewed")) {
        try executeCandidateReviewedFromArgs(allocator, engine_root, args[1..], base);
        return;
    }
    try std.io.getStdErr().writer().print("Unknown packs candidates command: {s}\n", .{action});
    try printCandidatesHelp(std.io.getStdErr().writer());
    std.process.exit(1);
}

fn parseCandidateFileArgs(args: []const []const u8, options: *PacksOptions, action: []const u8) !void {
    var i: usize = 0;
    while (i < args.len) : (i += 1) {
        const arg = args[i];
        if (try parseValueArg(args, &i, arg, "--file")) |value| {
            options.file_path = value;
        } else if (std.mem.startsWith(u8, arg, "--")) {
            try std.io.getStdErr().writer().print("Unknown packs candidates {s} option: {s}\n", .{ action, arg });
            std.process.exit(1);
        } else {
            try std.io.getStdErr().writer().print("Unexpected packs candidates {s} argument: {s}\n", .{ action, arg });
            std.process.exit(1);
        }
    }
}

fn executeCandidateReviewedFromArgs(
    allocator: std.mem.Allocator,
    engine_root: ?[]const u8,
    args: []const []const u8,
    base: PacksOptions,
) !void {
    const action = if (args.len > 0) args[0] else {
        try printCandidateReviewedHelp(std.io.getStdErr().writer());
        std.process.exit(1);
    };
    if (!std.mem.eql(u8, action, "list") and !std.mem.eql(u8, action, "get")) {
        try std.io.getStdErr().writer().print("Unknown packs candidates reviewed command: {s}\n", .{action});
        try printCandidateReviewedHelp(std.io.getStdErr().writer());
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
            try std.io.getStdErr().writer().print("Unknown packs candidates reviewed {s} option: {s}\n", .{ action, arg });
            std.process.exit(1);
        } else {
            try std.io.getStdErr().writer().print("Unexpected packs candidates reviewed {s} argument: {s}\n", .{ action, arg });
            std.process.exit(1);
        }
    }

    if (std.mem.eql(u8, action, "list")) {
        try executeCandidateReviewedList(allocator, engine_root, options);
    } else {
        try executeCandidateReviewedGet(allocator, engine_root, options);
    }
}

fn executeCandidateFileGip(
    allocator: std.mem.Allocator,
    engine_root: ?[]const u8,
    options: PacksOptions,
    expected_kind: []const u8,
    comptime renderer: fn (anytype, std.json.Value) anyerror!void,
) !void {
    const file_path = requireNonEmpty(options.file_path, "packs candidates --file is required");
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

    const bin_path = try findGipOrExit(allocator, engine_root);
    defer allocator.free(bin_path);
    if (options.debug) {
        try std.io.getStdErr().writer().print("[DEBUG] Engine Binary: {s}\n", .{bin_path});
        try std.io.getStdErr().writer().print("[DEBUG] GIP Kind: {s}\n", .{expected_kind});
        try std.io.getStdErr().writer().print("[DEBUG] Input File: {s}\n", .{file_path});
        try std.io.getStdErr().writer().print("[DEBUG] Stdin Byte Count: {d}\n", .{request.len});
    }
    try runCandidateGip(allocator, options, bin_path, expected_kind, request, renderer);
}

fn executeCandidateReviewedList(allocator: std.mem.Allocator, engine_root: ?[]const u8, options: PacksOptions) !void {
    const project_shard = requireNonEmpty(options.project_shard, "packs candidates reviewed list --project-shard is required");
    if (options.decision) |decision| {
        if (!std.mem.eql(u8, decision, "accepted") and !std.mem.eql(u8, decision, "rejected") and !std.mem.eql(u8, decision, "all")) {
            try std.io.getStdErr().writer().print("Invalid --decision value: {s}. Use accepted|rejected|all.\n", .{decision});
            std.process.exit(1);
        }
    }

    var request = std.ArrayList(u8).init(allocator);
    defer request.deinit();
    try request.writer().writeAll("{\"gipVersion\":\"gip.v0.1\",\"kind\":\"procedure_pack.candidate.reviewed.list\",\"projectShard\":");
    try std.json.stringify(project_shard, .{}, request.writer());
    if (options.decision) |decision| {
        try request.writer().writeAll(",\"decision\":");
        try std.json.stringify(decision, .{}, request.writer());
    }
    if (options.limit) |limit| try request.writer().print(",\"limit\":{d}", .{limit});
    if (options.offset) |offset| try request.writer().print(",\"offset\":{d}", .{offset});
    try request.writer().writeByte('}');

    const bin_path = try findGipOrExit(allocator, engine_root);
    defer allocator.free(bin_path);
    if (options.debug) {
        try std.io.getStdErr().writer().print("[DEBUG] Engine Binary: {s}\n", .{bin_path});
        try std.io.getStdErr().writer().print("[DEBUG] GIP Kind: procedure_pack.candidate.reviewed.list\n", .{});
        try std.io.getStdErr().writer().print("[DEBUG] Project Shard: {s}\n", .{project_shard});
        try std.io.getStdErr().writer().print("[DEBUG] Stdin Byte Count: {d}\n", .{request.items.len});
    }
    try runCandidateGip(allocator, options, bin_path, "procedure_pack.candidate.reviewed.list", request.items, printProcedurePackCandidateReviewedListResult);
}

fn executeCandidateReviewedGet(allocator: std.mem.Allocator, engine_root: ?[]const u8, options: PacksOptions) !void {
    const project_shard = requireNonEmpty(options.project_shard, "packs candidates reviewed get --project-shard is required");
    const id = requireNonEmpty(options.id, "packs candidates reviewed get --id is required");

    var request = std.ArrayList(u8).init(allocator);
    defer request.deinit();
    try request.writer().writeAll("{\"gipVersion\":\"gip.v0.1\",\"kind\":\"procedure_pack.candidate.reviewed.get\",\"projectShard\":");
    try std.json.stringify(project_shard, .{}, request.writer());
    try request.writer().writeAll(",\"id\":");
    try std.json.stringify(id, .{}, request.writer());
    try request.writer().writeByte('}');

    const bin_path = try findGipOrExit(allocator, engine_root);
    defer allocator.free(bin_path);
    if (options.debug) {
        try std.io.getStdErr().writer().print("[DEBUG] Engine Binary: {s}\n", .{bin_path});
        try std.io.getStdErr().writer().print("[DEBUG] GIP Kind: procedure_pack.candidate.reviewed.get\n", .{});
        try std.io.getStdErr().writer().print("[DEBUG] Project Shard: {s}\n", .{project_shard});
        try std.io.getStdErr().writer().print("[DEBUG] ID: {s}\n", .{id});
        try std.io.getStdErr().writer().print("[DEBUG] Stdin Byte Count: {d}\n", .{request.items.len});
    }
    try runCandidateGip(allocator, options, bin_path, "procedure_pack.candidate.reviewed.get", request.items, printProcedurePackCandidateReviewedGetResult);
}

fn executeList(allocator: std.mem.Allocator, engine_root: ?[]const u8, options: PacksOptions) !void {
    const res = try runner.run(allocator, .{
        .engine_root = engine_root,
        .binary = .ghost_knowledge_pack,
        .argv = &[_][]const u8{ "list", "--json" },
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

    const parsed = json_contracts.parsePackListJson(allocator, res.stdout) catch |err| {
        std.debug.print("\x1b[31m[!] Error:\x1b[0m Failed to parse engine JSON: {}\n", .{err});
        std.debug.print("\x1b[33mRaw Output:\x1b[0m\n{s}\n", .{res.stdout});
        return;
    };
    defer parsed.deinit();

    try terminal.printPackList(std.io.getStdOut().writer(), parsed.value);
}

fn executeInspect(allocator: std.mem.Allocator, engine_root: ?[]const u8, options: PacksOptions) !void {
    const pack_id = options.pack_id orelse {
        std.debug.print("\x1b[31m[!] Error:\x1b[0m Usage: ghost packs inspect <pack-id>\n", .{});
        std.process.exit(1);
    };

    var argv = std.ArrayList([]const u8).init(allocator);
    defer argv.deinit();

    try argv.append("inspect");
    try argv.append(pack_id);
    try argv.append("--json");

    if (options.version) |v| {
        try argv.append("--version");
        try argv.append(v);
    }

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

    const parsed = json_contracts.parsePackInfoJson(allocator, res.stdout) catch |err| {
        std.debug.print("\x1b[31m[!] Error:\x1b[0m Failed to parse engine JSON: {}\n", .{err});
        std.debug.print("\x1b[33mRaw Output:\x1b[0m\n{s}\n", .{res.stdout});
        return;
    };
    defer parsed.deinit();

    try terminal.printPackInfo(std.io.getStdOut().writer(), parsed.value);
}

fn executeMount(allocator: std.mem.Allocator, engine_root: ?[]const u8, options: PacksOptions) !void {
    const pack_id = options.pack_id orelse {
        std.debug.print("\x1b[31m[!] Error:\x1b[0m Usage: ghost packs mount <pack-id>\n", .{});
        std.process.exit(1);
    };

    var argv = std.ArrayList([]const u8).init(allocator);
    defer argv.deinit();

    try argv.append("mount");
    try argv.append(pack_id);

    if (options.version) |v| {
        try argv.append("--version");
        try argv.append(v);
    }

    const res = try runner.run(allocator, .{
        .engine_root = engine_root,
        .binary = .ghost_knowledge_pack,
        .argv = argv.items,
        .debug = options.debug,
    });
    defer res.deinit();

    if (res.exit_code == 0) {
        std.debug.print("Successfully mounted pack '{s}'\n", .{pack_id});
        std.debug.print("Run 'ghost packs list' to see current state.\n", .{});
    } else {
        std.process.exit(res.exit_code);
    }
}

fn executeUnmount(allocator: std.mem.Allocator, engine_root: ?[]const u8, options: PacksOptions) !void {
    const pack_id = options.pack_id orelse {
        std.debug.print("\x1b[31m[!] Error:\x1b[0m Usage: ghost packs unmount <pack-id>\n", .{});
        std.process.exit(1);
    };

    var argv = std.ArrayList([]const u8).init(allocator);
    defer argv.deinit();

    try argv.append("unmount");
    try argv.append(pack_id);

    if (options.version) |v| {
        try argv.append("--version");
        try argv.append(v);
    }

    const res = try runner.run(allocator, .{
        .engine_root = engine_root,
        .binary = .ghost_knowledge_pack,
        .argv = argv.items,
        .debug = options.debug,
    });
    defer res.deinit();

    if (res.exit_code == 0) {
        std.debug.print("Successfully unmounted pack '{s}'\n", .{pack_id});
        std.debug.print("Run 'ghost packs list' to see current state.\n", .{});
    } else {
        std.process.exit(res.exit_code);
    }
}

fn executeValidateAutopsyGuidance(allocator: std.mem.Allocator, engine_root: ?[]const u8, options: PacksOptions) !void {
    if (options.manifest == null and options.pack_id == null and !options.all_mounted) {
        std.debug.print("\x1b[31m[!] Error:\x1b[0m Usage: ghost packs validate-autopsy-guidance (--manifest=<path> | --pack-id=<id> --version=<v> | --all-mounted --project-shard=<id>) [--json]\n", .{});
        std.process.exit(1);
    }
    if (options.pack_id != null and options.version == null) {
        std.debug.print("\x1b[31m[!] Error:\x1b[0m --version is required with --pack-id for validate-autopsy-guidance\n", .{});
        std.process.exit(1);
    }
    if (options.all_mounted and options.project_shard == null) {
        std.debug.print("\x1b[31m[!] Error:\x1b[0m --project-shard is required with --all-mounted for validate-autopsy-guidance\n", .{});
        std.process.exit(1);
    }

    var handshake = try capabilityHandshake(allocator, engine_root, options.debug);
    defer handshake.deinit();
    try ensureValidateAutopsyGuidanceSupported(&handshake, options);

    var argv = std.ArrayList([]const u8).init(allocator);
    defer argv.deinit();
    var owned_args = std.ArrayList([]u8).init(allocator);
    defer {
        for (owned_args.items) |arg| allocator.free(arg);
        owned_args.deinit();
    }

    try argv.append("validate-autopsy-guidance");
    if (options.manifest) |manifest| {
        const arg = try std.fmt.allocPrint(allocator, "--manifest={s}", .{manifest});
        try owned_args.append(arg);
        try argv.append(arg);
    }
    if (options.pack_id) |pack_id| {
        const arg = try std.fmt.allocPrint(allocator, "--pack-id={s}", .{pack_id});
        try owned_args.append(arg);
        try argv.append(arg);
    }
    if (options.version) |version| {
        const arg = try std.fmt.allocPrint(allocator, "--version={s}", .{version});
        try owned_args.append(arg);
        try argv.append(arg);
    }
    if (options.all_mounted) {
        try argv.append("--all-mounted");
    }
    if (options.project_shard) |project_shard| {
        const arg = try std.fmt.allocPrint(allocator, "--project-shard={s}", .{project_shard});
        try owned_args.append(arg);
        try argv.append(arg);
    }
    try appendSupportedLimitFlag(allocator, &argv, &owned_args, "--max-guidance-bytes", options.max_guidance_bytes, handshake.limit_flags.max_guidance_bytes);
    try appendSupportedLimitFlag(allocator, &argv, &owned_args, "--max-array-items", options.max_array_items, handshake.limit_flags.max_array_items);
    try appendSupportedLimitFlag(allocator, &argv, &owned_args, "--max-string-bytes", options.max_string_bytes, handshake.limit_flags.max_string_bytes);
    if (options.json) {
        try argv.append("--json");
    } else {
        // Human mode still asks the engine for structured validation output so
        // engine traces or low-level stderr never become the user-facing UI.
        try argv.append("--json");
    }

    var run_args = std.ArrayList([]const u8).init(allocator);
    defer run_args.deinit();
    try run_args.append(handshake.binary_path);
    for (argv.items) |arg| try run_args.append(arg);

    if (options.debug) {
        try printDebugArgv(std.io.getStdErr().writer(), "validation argv", run_args.items);
    }

    const result = process.runEngineCommand(allocator, run_args.items) catch |err| {
        try std.io.getStdErr().writer().print("\x1b[31m[!] Error:\x1b[0m Failed to execute validation command: {}\n", .{err});
        try std.io.getStdErr().writer().print("\x1b[33mHint:\x1b[0m Run `ghost doctor` or upgrade/rebuild ghost_engine.\n", .{});
        std.process.exit(1);
    };
    defer {
        allocator.free(result.stdout);
        allocator.free(result.stderr);
    }

    if (options.debug) {
        try std.io.getStdErr().writer().print("[DEBUG] validation exit_code={d}\n", .{result.exit_code});
    }

    if (options.json) {
        if (result.stdout.len > 0) try std.io.getStdOut().writer().writeAll(result.stdout);
        if (result.stderr.len > 0 and options.debug) try std.io.getStdErr().writer().writeAll(result.stderr);
        if (result.exit_code != 0) std.process.exit(result.exit_code);
        return;
    }

    var parsed = std.json.parseFromSlice(ValidationSummary, allocator, result.stdout, .{ .ignore_unknown_fields = true }) catch |err| {
        if (options.debug) {
            try std.io.getStdErr().writer().print("[DEBUG] validation parse_status=error:{s}\n", .{@errorName(err)});
        }
        try printCleanValidationProcessFailure(std.io.getStdErr().writer(), result.exit_code, result.stderr.len, result.stdout.len);
        std.process.exit(if (result.exit_code == 0) 1 else result.exit_code);
    };
    defer parsed.deinit();

    if (options.debug) {
        try std.io.getStdErr().writer().print("[DEBUG] validation parse_status=ok\n", .{});
    }

    try printValidationSummary(std.io.getStdOut().writer(), parsed.value);
    if (result.exit_code != 0) std.process.exit(result.exit_code);
    if (!parsed.value.ok or parsed.value.errorCount > 0) std.process.exit(1);
}

fn appendSupportedLimitFlag(
    allocator: std.mem.Allocator,
    argv: *std.ArrayList([]const u8),
    owned_args: *std.ArrayList([]u8),
    flag: []const u8,
    value: ?[]const u8,
    supported: bool,
) !void {
    const actual = value orelse return;
    if (!supported) {
        try std.io.getStdErr().writer().print("\x1b[31m[!] Compatibility Error:\x1b[0m Engine does not advertise {s} for validate-autopsy-guidance.\n", .{flag});
        try std.io.getStdErr().writer().print("\x1b[33mHint:\x1b[0m Run `ghost doctor` or upgrade/rebuild ghost_engine.\n", .{});
        std.process.exit(1);
    }
    const arg = try std.fmt.allocPrint(allocator, "{s}={s}", .{ flag, actual });
    try owned_args.append(arg);
    try argv.append(arg);
}

fn capabilityHandshake(allocator: std.mem.Allocator, engine_root: ?[]const u8, debug: bool) !CapabilityHandshake {
    const bin_path = locator.findEngineBinary(allocator, engine_root, .ghost_knowledge_pack) catch |err| {
        try locator.printLocatorError(std.io.getStdErr().writer(), .ghost_knowledge_pack, engine_root, err);
        std.process.exit(1);
    };
    errdefer allocator.free(bin_path);

    const args = &[_][]const u8{ bin_path, "capabilities", "--json" };
    if (debug) {
        try std.io.getStdErr().writer().print("[DEBUG] capability engine_path={s}\n", .{bin_path});
        try printDebugArgv(std.io.getStdErr().writer(), "capability argv", args);
    }

    const result = process.runEngineCommand(allocator, args) catch |err| {
        try std.io.getStdErr().writer().print("\x1b[31m[!] Compatibility Error:\x1b[0m Could not query ghost_knowledge_pack capabilities: {}\n", .{err});
        try std.io.getStdErr().writer().print("Engine binary: {s}\nEngine version: unknown\n", .{bin_path});
        try std.io.getStdErr().writer().print("\x1b[33mHint:\x1b[0m Run `ghost doctor` or upgrade/rebuild ghost_engine.\n", .{});
        std.process.exit(1);
    };

    var handshake = CapabilityHandshake{
        .binary_path = bin_path,
        .stdout = result.stdout,
        .stderr = result.stderr,
        .exit_code = result.exit_code,
        .parsed = null,
        .allocator = allocator,
    };
    errdefer handshake.deinit();

    if (debug) {
        try std.io.getStdErr().writer().print("[DEBUG] capability exit_code={d}\n", .{handshake.exit_code});
    }

    if (handshake.exit_code == 0) {
        handshake.parsed = std.json.parseFromSlice(PackCapabilities, allocator, handshake.stdout, .{ .ignore_unknown_fields = true }) catch null;
    }
    if (debug) {
        try std.io.getStdErr().writer().print("[DEBUG] capability parse_status={s}\n", .{if (handshake.parsed != null) "ok" else "unavailable"});
    }

    return handshake;
}

fn ensureValidateAutopsyGuidanceSupported(handshake: *CapabilityHandshake, options: PacksOptions) !void {
    const caps = handshake.caps() orelse {
        try printCapabilityUnavailable(handshake, "capabilities JSON could not be parsed");
        std.process.exit(1);
    };
    if (handshake.exit_code != 0) {
        try printCapabilityUnavailable(handshake, "capabilities command failed");
        std.process.exit(1);
    }
    if (!hasCommand(caps.commands, "validate-autopsy-guidance")) {
        try printCapabilityUnavailable(handshake, "validate-autopsy-guidance is not advertised by this engine");
        std.process.exit(1);
    }
    const validation = caps.validateAutopsyGuidance orelse {
        try printCapabilityUnavailable(handshake, "validateAutopsyGuidance capability details are missing");
        std.process.exit(1);
    };
    if (validation.supportedSchemaVersions.len == 0) {
        try printCapabilityUnavailable(handshake, "supported schema versions are unknown");
        std.process.exit(1);
    }

    const required_flags = &[_][]const u8{ "--manifest", "--pack-id", "--version", "--all-mounted", "--project-shard", "--json" };
    for (required_flags) |flag| {
        if (!hasFlag(validation.flags, flag)) {
            try printCapabilityUnavailable(handshake, "required validation flags are not fully advertised");
            std.process.exit(1);
        }
    }

    handshake.limit_flags = .{
        .max_guidance_bytes = hasFlag(validation.flags, "--max-guidance-bytes"),
        .max_array_items = hasFlag(validation.flags, "--max-array-items"),
        .max_string_bytes = hasFlag(validation.flags, "--max-string-bytes"),
    };

    if (options.max_guidance_bytes != null and !handshake.limit_flags.max_guidance_bytes) {
        try printCapabilityUnavailable(handshake, "--max-guidance-bytes is not advertised by this engine");
        std.process.exit(1);
    }
    if (options.max_array_items != null and !handshake.limit_flags.max_array_items) {
        try printCapabilityUnavailable(handshake, "--max-array-items is not advertised by this engine");
        std.process.exit(1);
    }
    if (options.max_string_bytes != null and !handshake.limit_flags.max_string_bytes) {
        try printCapabilityUnavailable(handshake, "--max-string-bytes is not advertised by this engine");
        std.process.exit(1);
    }
}

fn printCapabilityUnavailable(handshake: *const CapabilityHandshake, reason: []const u8) !void {
    const writer = std.io.getStdErr().writer();
    try writer.print("\x1b[31m[!] Compatibility Error:\x1b[0m Cannot run `ghost packs validate-autopsy-guidance` with this engine.\n", .{});
    try writer.print("Reason: {s}\n", .{reason});
    try writer.print("Engine binary: {s}\n", .{handshake.binary_path});
    try writer.print("Engine version: {s}\n", .{handshake.versionLabel()});
    try writer.print("\x1b[33mHint:\x1b[0m Run `ghost doctor` or upgrade/rebuild ghost_engine.\n", .{});
}

fn printCleanValidationProcessFailure(writer: anytype, exit_code: u8, stderr_len: usize, stdout_len: usize) !void {
    try writer.print("\x1b[31m[!] Validation failed:\x1b[0m Engine returned non-JSON validation output.\n", .{});
    try writer.print("Exit code: {d}\n", .{exit_code});
    try writer.print("Output: {d} stdout bytes, {d} stderr bytes suppressed from human output.\n", .{ stdout_len, stderr_len });
    try writer.print("\x1b[33mHint:\x1b[0m Run again with --debug for diagnostics, or run `ghost doctor` to check engine compatibility.\n", .{});
}

fn printValidationSummary(writer: anytype, summary: ValidationSummary) !void {
    if (summary.ok and summary.errorCount == 0) {
        if (summary.warningCount == 0) {
            try writer.print("Autopsy guidance validation passed.\n", .{});
        } else {
            try writer.print("Autopsy guidance validation passed with {d} warning(s).\n", .{summary.warningCount});
        }
    } else {
        try writer.print("Autopsy guidance validation failed: {d} error(s), {d} warning(s).\n", .{ summary.errorCount, summary.warningCount });
    }

    if (summary.supportedSchemaVersions.len > 0) {
        try writer.print("Supported schema versions: ", .{});
        for (summary.supportedSchemaVersions, 0..) |schema, idx| {
            if (idx != 0) try writer.print(", ", .{});
            try writer.print("{s}", .{schema});
        }
        try writer.print("\n", .{});
    }

    for (summary.reports) |report| {
        try writer.print("\n{s}@{s}\n", .{ report.packId, report.version });
        try writer.print("  manifest: {s}\n", .{report.manifestPath});
        if (report.guidancePath) |path| try writer.print("  guidance: {s}\n", .{path});
        try writer.print("  entries: {d}\n", .{report.guidanceCount});
        if (report.schema) |schema| {
            try writer.print("  schema: {s}\n", .{schema});
        } else if (report.legacyUnversionedSchema) {
            try writer.print("  schema: legacy unversioned guidance\n", .{});
        }
        if (report.issues.len == 0) {
            try writer.print("  result: pass\n", .{});
        } else {
            for (report.issues) |issue| {
                const label = if (std.mem.eql(u8, issue.severity, "warning")) "warning" else "error";
                try writer.print("  {s}: {s} at {s}: {s}\n", .{ label, issue.code, issue.path, issue.message });
            }
        }
    }
}

fn hasCommand(commands: []const PackCapabilities.Command, name: []const u8) bool {
    for (commands) |command| {
        if (std.mem.eql(u8, command.name, name)) return true;
        for (command.aliases) |alias| if (std.mem.eql(u8, alias, name)) return true;
    }
    return false;
}

fn hasFlag(flags: []const []const u8, name: []const u8) bool {
    for (flags) |flag| if (std.mem.eql(u8, flag, name)) return true;
    return false;
}

pub fn collectCapabilityDiagnostic(allocator: std.mem.Allocator, engine_root: ?[]const u8, debug: bool) !CapabilityDiagnostic {
    var diagnostic = CapabilityDiagnostic{ .allocator = allocator };

    const bin_path = locator.findEngineBinary(allocator, engine_root, .ghost_knowledge_pack) catch |err| {
        diagnostic.warning = try std.fmt.allocPrint(allocator, "ghost_knowledge_pack capabilities unavailable: {s}", .{@errorName(err)});
        return diagnostic;
    };
    diagnostic.binary_path = bin_path;

    const args = &[_][]const u8{ bin_path, "capabilities", "--json" };
    if (debug) try printDebugArgv(std.io.getStdErr().writer(), "knowledge-pack capability diagnostic argv", args);

    const result = process.runEngineCommand(allocator, args) catch |err| {
        diagnostic.warning = try std.fmt.allocPrint(allocator, "ghost_knowledge_pack capabilities failed: {s}", .{@errorName(err)});
        return diagnostic;
    };
    defer {
        allocator.free(result.stdout);
        allocator.free(result.stderr);
    }

    if (debug) {
        try std.io.getStdErr().writer().print("[DEBUG] knowledge-pack capability diagnostic exit_code={d}\n", .{result.exit_code});
    }

    if (result.exit_code != 0) {
        diagnostic.warning = try std.fmt.allocPrint(allocator, "ghost_knowledge_pack capabilities exited {d}", .{result.exit_code});
        return diagnostic;
    }

    var parsed = std.json.parseFromSlice(PackCapabilities, allocator, result.stdout, .{ .ignore_unknown_fields = true }) catch |err| {
        diagnostic.warning = try std.fmt.allocPrint(allocator, "ghost_knowledge_pack capabilities JSON could not be parsed: {s}", .{@errorName(err)});
        return diagnostic;
    };
    defer parsed.deinit();

    diagnostic.capabilities_available = true;
    diagnostic.validate_autopsy_guidance_supported = hasCommand(parsed.value.commands, "validate-autopsy-guidance") and parsed.value.validateAutopsyGuidance != null;
    if (parsed.value.validateAutopsyGuidance) |validation| {
        diagnostic.supported_validation_limit_flags = .{
            .max_guidance_bytes = hasFlag(validation.flags, "--max-guidance-bytes"),
            .max_array_items = hasFlag(validation.flags, "--max-array-items"),
            .max_string_bytes = hasFlag(validation.flags, "--max-string-bytes"),
        };
        var schemas = std.ArrayList([]const u8).init(allocator);
        errdefer {
            for (schemas.items) |schema| allocator.free(schema);
            schemas.deinit();
        }
        for (validation.supportedSchemaVersions) |schema| {
            try schemas.append(try allocator.dupe(u8, schema));
        }
        diagnostic.supported_schema_versions = try schemas.toOwnedSlice();
    }
    if (!diagnostic.validate_autopsy_guidance_supported) {
        diagnostic.warning = try allocator.dupe(u8, "validate-autopsy-guidance is not advertised; upgrade/rebuild ghost_engine for advanced validation UX");
    }
    return diagnostic;
}

fn printDebugArgv(writer: anytype, label: []const u8, argv: []const []const u8) !void {
    try writer.print("[DEBUG] {s}=", .{label});
    for (argv, 0..) |arg, idx| {
        if (idx != 0) try writer.print(" ", .{});
        try writer.print("'{s}'", .{arg});
    }
    try writer.print("\n", .{});
}

fn runCandidateGip(
    allocator: std.mem.Allocator,
    options: PacksOptions,
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

fn printProcedurePackCandidateProposalResult(writer: anytype, value: std.json.Value) !void {
    try writer.print("PROCEDURE PACK CANDIDATE / NON-AUTHORIZING\n", .{});
    try writer.print("CANDIDATE ONLY\nNOT PROOF\nNOT EVIDENCE\nNOT INSTALLED\nNOT EXECUTED\nNO PACK MUTATION\nNO GLOBAL PROMOTION\n\n", .{});
    if (findError(value)) |err_value| return printEngineRejected(writer, err_value);
    const proposal = findProcedurePackCandidatePayload(value) orelse {
        try writer.print("No procedure pack candidate proposal payload was present.\n", .{});
        return;
    };
    if (proposal != .object) return printJsonValue(writer, proposal, 2);
    const obj = proposal.object;
    try printField(writer, obj, "status", "Status");
    try printField(writer, obj, "id", "Candidate ID");
    try printField(writer, obj, "candidateId", "Candidate ID");
    try printField(writer, obj, "candidateKind", "Candidate Kind");
    try printField(writer, obj, "kind", "Candidate Kind");
    try printField(writer, obj, "summary", "Summary");
    try printSection(writer, obj, "triggers", "Triggers");
    try printSection(writer, obj, "steps", "Steps");
    try printSection(writer, obj, "requiredEvidence", "Required Evidence");
    try printSection(writer, obj, "required_evidence", "Required Evidence");
    try printSection(writer, obj, "safetyBoundaries", "Safety Boundaries");
    try printSection(writer, obj, "safety_boundaries", "Safety Boundaries");
    try printField(writer, obj, "sourceCorrectionId", "Source Correction ID");
    try printField(writer, obj, "sourceCorrectionReviewId", "Source Correction Review ID");
    try printField(writer, obj, "sourceNegativeKnowledgeId", "Source NK ID");
    try printField(writer, obj, "sourceNegativeKnowledgeReviewId", "Source NK Review ID");
    const candidate = obj.get("procedurePackCandidate") orelse obj.get("candidate");
    if (candidate) |candidate_value| {
        try writer.print("\nProcedure Pack Candidate:\n", .{});
        try printProcedurePackCandidateRecordSummary(writer, candidate_value, 2);
    }
    try printSection(writer, obj, "mutationFlags", "Mutation Flags");
    try printSection(writer, obj, "authorityFlags", "Authority Flags");
    try printSection(writer, obj, "authority", "Authority Flags");
}

fn printProcedurePackCandidateReviewResult(writer: anytype, value: std.json.Value) !void {
    try writer.print("REVIEWED PROCEDURE PACK CANDIDATE\n", .{});
    try writer.print("APPEND-ONLY\nNOT PROOF\nNOT EVIDENCE\nNOT INSTALLED\nNOT EXECUTED\nNO PACK MUTATION\nNO GLOBAL PROMOTION\n\n", .{});
    if (findError(value)) |err_value| return printEngineRejected(writer, err_value);
    const review = findProcedurePackCandidatePayload(value) orelse {
        try writer.print("No procedure pack candidate review payload was present.\n", .{});
        return;
    };
    if (review != .object) return printJsonValue(writer, review, 2);
    const obj = review.object;
    try printField(writer, obj, "status", "Status");
    try printField(writer, obj, "decision", "Decision");
    try printField(writer, obj, "reviewDecision", "Decision");
    try printField(writer, obj, "reviewerNote", "Reviewer Note");
    try printField(writer, obj, "reviewer_note", "Reviewer Note");
    try printField(writer, obj, "rejectedReason", "Rejected Reason");
    try printField(writer, obj, "rejected_reason", "Rejected Reason");
    const reviewed_record = obj.get("reviewedProcedurePackCandidateRecord") orelse obj.get("reviewedPackCandidateRecord");
    if (reviewed_record) |record| {
        try writer.print("\nReviewed Record:\n", .{});
        try printProcedurePackCandidateRecordSummary(writer, record, 2);
    }
    try printSection(writer, obj, "candidateSnapshot", "Candidate Snapshot Summary");
    try printSection(writer, obj, "procedurePackCandidate", "Candidate Snapshot Summary");
    try printSection(writer, obj, "appendOnlyMetadata", "Append-Only Metadata");
    try printSection(writer, obj, "appendOnly", "Append-Only Metadata");
    try printSection(writer, obj, "mutationFlags", "Mutation Flags");
    try printSection(writer, obj, "authorityFlags", "Authority Flags");
    try printSection(writer, obj, "authority", "Authority Flags");
}

fn printProcedurePackCandidateReviewedListResult(writer: anytype, value: std.json.Value) !void {
    try writer.print("REVIEWED PROCEDURE PACK CANDIDATES / READ-ONLY\n", .{});
    try writer.print("READ-ONLY\nNOT PROOF\nNOT EVIDENCE\nNOT INSTALLED\nNO PACK MUTATION\nNO VERIFIERS EXECUTED\n\n", .{});
    if (findError(value)) |err_value| return printEngineRejected(writer, err_value);
    const list = findProcedurePackCandidatePayload(value) orelse {
        try writer.print("No reviewed procedure pack candidate list payload was present.\n", .{});
        return;
    };
    if (list != .object) return printJsonValue(writer, list, 2);
    const obj = list.object;
    try printField(writer, obj, "status", "Status");
    try printField(writer, obj, "projectShard", "Project Shard");
    try printField(writer, obj, "decision", "Decision Filter");
    try printField(writer, obj, "totalRead", "Total Read");
    try printField(writer, obj, "returnedCount", "Returned Count");
    try printField(writer, obj, "malformedLines", "Malformed Lines");
    try printSection(writer, obj, "counts", "Counts");
    try printSection(writer, obj, "warnings", "Warnings");
    try printSection(writer, obj, "capacityTelemetry", "Capacity Telemetry");
    if (obj.get("records")) |records| {
        try writer.print("\nRecords (append order):\n", .{});
        if (records == .array) {
            for (records.array.items, 0..) |record, index| {
                try writer.print("- Record {d}:\n", .{index + 1});
                try printProcedurePackCandidateRecordSummary(writer, record, 4);
            }
        } else {
            try printJsonValue(writer, records, 2);
        }
    }
    try printSection(writer, obj, "mutationFlags", "Mutation Flags");
    try printSection(writer, obj, "authorityFlags", "Authority Flags");
    try printSection(writer, obj, "authority", "Authority Flags");
}

fn printProcedurePackCandidateReviewedGetResult(writer: anytype, value: std.json.Value) !void {
    try writer.print("REVIEWED PROCEDURE PACK CANDIDATE / READ-ONLY\n", .{});
    try writer.print("READ-ONLY\nNOT PROOF\nNOT EVIDENCE\nNOT INSTALLED\nNO PACK MUTATION\nNO VERIFIERS EXECUTED\n\n", .{});
    if (findError(value)) |err_value| return printEngineRejected(writer, err_value);
    const get = findProcedurePackCandidatePayload(value) orelse {
        try writer.print("No reviewed procedure pack candidate get payload was present.\n", .{});
        return;
    };
    if (get != .object) return printJsonValue(writer, get, 2);
    const obj = get.object;
    try printField(writer, obj, "status", "Status");
    try printField(writer, obj, "projectShard", "Project Shard");
    try printField(writer, obj, "id", "ID");
    try printField(writer, obj, "malformedLines", "Malformed Lines");
    try printSection(writer, obj, "warnings", "Warnings");
    try printSection(writer, obj, "capacityTelemetry", "Capacity Telemetry");
    const record = obj.get("reviewedProcedurePackCandidateRecord") orelse obj.get("reviewedPackCandidateRecord") orelse obj.get("record");
    if (record) |record_value| {
        if (record_value == .null) {
            try writer.print("\nReviewed procedure pack candidate not_found.\n", .{});
        } else {
            try writer.print("\nReviewed Procedure Pack Candidate Record:\n", .{});
            try printProcedurePackCandidateRecordSummary(writer, record_value, 2);
        }
    } else if (getString(obj, "status")) |status| {
        if (std.mem.eql(u8, status, "not_found")) try writer.print("\nReviewed procedure pack candidate not_found.\n", .{});
    }
    try printSection(writer, obj, "mutationFlags", "Mutation Flags");
    try printSection(writer, obj, "authorityFlags", "Authority Flags");
    try printSection(writer, obj, "authority", "Authority Flags");
}

fn printProcedurePackCandidateRecordSummary(writer: anytype, record: std.json.Value, indent: usize) !void {
    const obj = switch (record) {
        .object => |o| o,
        else => return printJsonValue(writer, record, indent),
    };
    try printIndentedField(writer, obj, "id", "ID", indent);
    try printIndentedField(writer, obj, "projectShard", "Project Shard", indent);
    try printIndentedField(writer, obj, "decision", "Decision", indent);
    try printIndentedField(writer, obj, "reviewDecision", "Decision", indent);
    try printIndentedField(writer, obj, "candidateKind", "Candidate Kind", indent);
    try printIndentedField(writer, obj, "kind", "Candidate Kind", indent);
    try printIndentedField(writer, obj, "summary", "Summary", indent);
    try printIndentedField(writer, obj, "sourceKind", "Source Kind", indent);
    try printIndentedField(writer, obj, "sourceReviewId", "Source Review ID", indent);
    try printIndentedField(writer, obj, "reviewerNote", "Reviewer Note", indent);
    try printIndentedField(writer, obj, "reviewerNoteSummary", "Reviewer Note Summary", indent);
    try printIndentedField(writer, obj, "rejectedReason", "Rejected Reason", indent);
    try printIndentedField(writer, obj, "nonAuthorizing", "Non-Authorizing", indent);
    try printIndentedField(writer, obj, "treatedAsProof", "Treated As Proof", indent);
    try printIndentedField(writer, obj, "usedAsEvidence", "Used As Evidence", indent);
    try printIndentedField(writer, obj, "executesByDefault", "Executes By Default", indent);
    try printIndentedField(writer, obj, "packMutation", "Pack Mutation", indent);
    try printIndentedField(writer, obj, "globalPromotion", "Global Promotion", indent);
    try printIndentedField(writer, obj, "commandsExecuted", "Commands Executed", indent);
    try printIndentedField(writer, obj, "verifiersExecuted", "Verifiers Executed", indent);
    try printIndentedSection(writer, obj, "triggers", "Triggers", indent);
    try printIndentedSection(writer, obj, "steps", "Steps", indent);
    try printIndentedSection(writer, obj, "requiredEvidence", "Required Evidence", indent);
    try printIndentedSection(writer, obj, "safetyBoundaries", "Safety Boundaries", indent);
    try printIndentedSection(writer, obj, "candidateSnapshot", "Candidate Snapshot", indent);
    try printIndentedSection(writer, obj, "procedurePackCandidate", "Candidate Snapshot", indent);
    try printIndentedSection(writer, obj, "reviewedProcedurePackCandidateRecord", "Reviewed Procedure Pack Candidate Record", indent);
    try printIndentedSection(writer, obj, "appendOnly", "Append-Only Metadata", indent);
    try printIndentedSection(writer, obj, "appendOnlyMetadata", "Append-Only Metadata", indent);
    try printIndentedSection(writer, obj, "mutationFlags", "Mutation Flags", indent);
    try printIndentedSection(writer, obj, "authorityFlags", "Authority Flags", indent);
    try printIndentedSection(writer, obj, "authority", "Authority Flags", indent);
}

fn findProcedurePackCandidatePayload(value: std.json.Value) ?std.json.Value {
    const obj = switch (value) {
        .object => |o| o,
        else => return null,
    };
    inline for (.{ "procedurePackCandidate", "procedure_pack_candidate", "procedurePackCandidatePropose", "procedurePackCandidateReview", "procedurePackCandidateProposal", "procedurePackCandidateReviewed", "procedurePackCandidateReviewedList", "procedurePackCandidateReviewedGet", "reviewedProcedurePackCandidate", "reviewedPackCandidate", "packCandidateReview", "packCandidateProposal" }) |key| {
        if (obj.get(key)) |payload| return payload;
    }
    if (obj.get("result")) |result| {
        const result_obj = switch (result) {
            .object => |o| o,
            else => return result,
        };
        inline for (.{ "procedurePackCandidate", "procedure_pack_candidate", "procedurePackCandidatePropose", "procedurePackCandidateReview", "procedurePackCandidateProposal", "procedurePackCandidateReviewed", "procedurePackCandidateReviewedList", "procedurePackCandidateReviewedGet", "reviewedProcedurePackCandidate", "reviewedPackCandidate", "packCandidateReview", "packCandidateProposal" }) |key| {
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
    if (obj.get("status")) |status| if (status == .string and std.mem.eql(u8, status.string, "rejected")) return value;
    return null;
}

fn hasKind(value: std.json.Value, expected_kind: []const u8) bool {
    const obj = switch (value) {
        .object => |o| o,
        else => return false,
    };
    const kind = obj.get("kind") orelse return false;
    return kind == .string and std.mem.eql(u8, kind.string, expected_kind);
}

fn parseValueArg(args: []const []const u8, index: *usize, arg: []const u8, flag: []const u8) !?[]const u8 {
    if (std.mem.eql(u8, arg, flag)) {
        index.* += 1;
        if (index.* >= args.len) try failMissingValue(flag);
        return args[index.*];
    }
    const prefix = try std.fmt.allocPrint(std.heap.page_allocator, "{s}=", .{flag});
    defer std.heap.page_allocator.free(prefix);
    if (std.mem.startsWith(u8, arg, prefix)) return arg[prefix.len..];
    return null;
}

fn parsePositiveUsize(flag: []const u8, raw: []const u8) usize {
    const parsed = std.fmt.parseInt(usize, raw, 10) catch {
        std.debug.print("Invalid {s} value: {s}. Use a positive integer.\n", .{ flag, raw });
        std.process.exit(1);
    };
    if (parsed == 0) {
        std.debug.print("Invalid {s} value: 0. Use a positive integer.\n", .{flag});
        std.process.exit(1);
    }
    return parsed;
}

fn parseNonNegativeUsize(flag: []const u8, raw: []const u8) usize {
    return std.fmt.parseInt(usize, raw, 10) catch {
        std.debug.print("Invalid {s} value: {s}. Use a non-negative integer.\n", .{ flag, raw });
        std.process.exit(1);
    };
}

fn requireNonEmpty(value: ?[]const u8, message: []const u8) []const u8 {
    const actual = value orelse {
        std.debug.print("{s}\n", .{message});
        std.process.exit(1);
    };
    if (std.mem.trim(u8, actual, " \t\r\n").len == 0) {
        std.debug.print("{s}\n", .{message});
        std.process.exit(1);
    }
    return actual;
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
    return if (value == .string) value.string else null;
}

fn failMissingValue(flag: []const u8) !noreturn {
    try std.io.getStdErr().writer().print("{s} requires a value\n", .{flag});
    std.process.exit(1);
}
