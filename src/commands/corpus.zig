const std = @import("std");
const locator = @import("../engine/locator.zig");
const process = @import("../engine/process.zig");

pub const CorpusOptions = struct {
    question: ?[]const u8 = null,
    corpus_path: ?[]const u8 = null,
    project_shard: ?[]const u8 = null,
    trust_class: ?[]const u8 = null,
    source_label: ?[]const u8 = null,
    deep_research: bool = false,
    deep_research_root: ?[]const u8 = null,
    max_results: ?u64 = null,
    max_snippet_bytes: ?u64 = null,
    mounted_packs: []const MountedPackRef = &.{},
    require_citations: bool = false,
    json: bool = false,
    debug: bool = false,
};

pub const MountedPackRef = struct {
    pack_id: []const u8,
    pack_version: []const u8 = "v1",
};

pub const LicenseRank = enum(u8) {
    root = 0,
    verified = 1,
    unverified = 2,
    shadow = 3,
    trash = 4,

    fn parse(raw: []const u8) ?LicenseRank {
        if (std.mem.eql(u8, raw, "root")) return .root;
        if (std.mem.eql(u8, raw, "verified")) return .verified;
        if (std.mem.eql(u8, raw, "unverified")) return .unverified;
        if (std.mem.eql(u8, raw, "shadow")) return .shadow;
        if (std.mem.eql(u8, raw, "trash")) return .trash;
        return null;
    }

    fn status(self: LicenseRank) []const u8 {
        return @tagName(self);
    }

    fn action(self: LicenseRank) []const u8 {
        return switch (self) {
            .root, .verified => "promoted",
            .unverified, .shadow => "demoted",
            .trash => "trashed",
        };
    }
};

const usage =
    \\Usage: ghost corpus <ingest|apply-staged|ask> [options]
    \\
    \\  ghost corpus ingest <path> --project-shard=<id> --trust-class=<class> --source-label=<label>
    \\  ghost corpus ingest <path> --deep-research
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
        \\Usage: ghost corpus ingest <path> [--project-shard=<id>] [--trust-class=<class>] [--source-label=<label>] [--deep-research] [--deep-research-root=<path>] [--json] [--debug]
        \\
        \\Stages corpus data through ghost_corpus_ingest. Staged corpus is not live
        \\and cannot be read by corpus.ask until `ghost corpus apply-staged` is run.
        \\
        \\Options:
        \\  --project-shard <id>       Target shard id
        \\  --trust-class <class>      exploratory|project|promoted|core
        \\  --source-label <label>     Source label recorded by the engine
        \\  --deep-research            Build a local forever_shard research corpus first
        \\  --deep-research-root <path> Secondary drive vault root for forever_shard
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
        \\Usage: ghost corpus ask [--json] [--debug] [--project-shard <id>] [--mounted-pack <id[@version]>] [--max-results <n>] [--max-snippet-bytes <n>] [--require-citations] <question>
        \\
        \\Ask a draft-only question from explicitly applied live shard corpus evidence.
        \\
        \\Options:
        \\  --project-shard <id>       Target shard id
        \\  --max-results <n>          Bound evidence result count
        \\  --max-snippet-bytes <n>    Bound snippet bytes per evidence item
        \\  --mounted-pack <id[@v]>    Include explicit mounted Knowledge Pack corpus
        \\  --require-citations        Require cited evidence for answer drafts
        \\  --json                     Preserve raw GIP stdout exactly
        \\  --debug                    Diagnostics to stderr
        \\
        \\Safety:
        \\  This request runs only when this command is explicitly invoked.
        \\  It routes to ghost_gip --stdin with kind corpus.ask.
        \\  Output is DRAFT / NON-AUTHORIZING; corpus evidence is not proof.
        \\  It reads live shard corpus and explicitly supplied mounted pack corpus only;
        \\  staged corpus is invisible until apply-staged.
        \\  Retrieval is bounded local matching over live corpus excerpts.
        \\  Exact evidence is required for answer drafts. Similarity hints may
        \\  appear as NON-AUTHORIZING routing hints only, never as evidence.
        \\  Capacity warnings mean partial coverage: skipped, dropped,
        \\  truncated, or capped data cannot support an answer.
        \\  Accepted reviewed corrections and reviewed negative knowledge may
        \\  appear as NON-AUTHORIZING influence, warnings, telemetry, or future
        \\  behavior candidates. They are not proof, not evidence, and may
        \\  suppress exact repeated bad answer patterns without globally
        \\  promoting anything.
        \\  It is not semantic search; mounted pack corpus is included only through
        \\  explicit --mounted-pack / mountedPacks request fields.
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
            } else if (std.mem.eql(u8, arg, "--deep-research")) {
                options.deep_research = true;
            } else if (std.mem.eql(u8, arg, "--deep-research-root")) {
                i += 1;
                if (i >= args.len) try failMissingValue("--deep-research-root");
                options.deep_research_root = args[i];
            } else if (std.mem.startsWith(u8, arg, "--deep-research-root=")) {
                options.deep_research_root = arg["--deep-research-root=".len..];
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
    var mounted_packs = std.ArrayList(MountedPackRef).init(allocator);
    defer mounted_packs.deinit();
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
        } else if (std.mem.eql(u8, arg, "--mounted-pack")) {
            i += 1;
            if (i >= args.len) try failMissingValue("--mounted-pack");
            try mounted_packs.append(parseMountedPackArg(args[i]));
        } else if (std.mem.startsWith(u8, arg, "--mounted-pack=")) {
            try mounted_packs.append(parseMountedPackArg(arg["--mounted-pack=".len..]));
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

    options.mounted_packs = mounted_packs.items;
    try executeAsk(allocator, engine_root, options);
}

pub fn executeVerifyPromotionFromArgs(allocator: std.mem.Allocator, args: []const []const u8) !void {
    var target_path: ?[]const u8 = null;
    var rank: ?LicenseRank = null;

    var i: usize = 0;
    while (i < args.len) : (i += 1) {
        const arg = args[i];
        if (std.mem.eql(u8, arg, "--rank")) {
            i += 1;
            if (i >= args.len) try failMissingValue("--rank");
            rank = LicenseRank.parse(args[i]) orelse {
                try std.io.getStdErr().writer().print("Invalid rank: {s}\nExpected one of: root, verified, unverified, shadow, trash\n", .{args[i]});
                std.process.exit(1);
            };
        } else if (std.mem.startsWith(u8, arg, "--rank=")) {
            const raw = arg["--rank=".len..];
            rank = LicenseRank.parse(raw) orelse {
                try std.io.getStdErr().writer().print("Invalid rank: {s}\nExpected one of: root, verified, unverified, shadow, trash\n", .{raw});
                std.process.exit(1);
            };
        } else if (std.mem.startsWith(u8, arg, "--")) {
            try std.io.getStdErr().writer().print("Unknown verify option: {s}\n", .{arg});
            std.process.exit(1);
        } else if (target_path == null) {
            target_path = arg;
        } else {
            try std.io.getStdErr().writer().print("Unexpected extra verify argument: {s}\n", .{arg});
            std.process.exit(1);
        }
    }

    const path = target_path orelse {
        try std.io.getStdErr().writer().print("Usage: ghost verify <path> --rank=[root|verified|unverified|shadow|trash]\n", .{});
        std.process.exit(1);
    };
    const selected_rank = rank orelse {
        try std.io.getStdErr().writer().print("Missing required --rank=[root|verified|unverified|shadow|trash]\n", .{});
        std.process.exit(1);
    };

    const result = updateLicenseRank(allocator, path, selected_rank) catch |err| {
        try std.io.getStdErr().writer().print("Failed to update license rank for {s}: {s}\n", .{ path, @errorName(err) });
        std.process.exit(1);
    };
    defer if (result.original_path) |value| allocator.free(value);
    defer allocator.free(result.root_path);
    defer allocator.free(result.license_path);

    try std.io.getStdOut().writer().print(
        "Corpus License Rank Updated\nPath: {s}\nLicense: {s}\nStatus: {s}\nAuthority Level: {d}\nAudit Action: {s}\n",
        .{ result.root_path, result.license_path, selected_rank.status(), @intFromEnum(selected_rank), selected_rank.action() },
    );
    if (result.original_path) |original| {
        try std.io.getStdOut().writer().print("Original Path: {s}\nMoved To: {s}\n", .{ original, result.root_path });
    }
}

pub fn executeTrashShortcutFromArgs(allocator: std.mem.Allocator, args: []const []const u8) !void {
    var target_path: ?[]const u8 = null;
    for (args) |arg| {
        if (std.mem.startsWith(u8, arg, "--")) {
            try std.io.getStdErr().writer().print("Unknown trash option: {s}\n", .{arg});
            std.process.exit(1);
        } else if (target_path == null) {
            target_path = arg;
        } else {
            try std.io.getStdErr().writer().print("Unexpected extra trash argument: {s}\n", .{arg});
            std.process.exit(1);
        }
    }
    const path = target_path orelse {
        try std.io.getStdErr().writer().print("Usage: ghost trash <path>\n", .{});
        std.process.exit(1);
    };
    try executeVerifyPromotionFromArgs(allocator, &.{ path, "--rank=trash" });
}

const LicenseUpdateResult = struct {
    original_path: ?[]u8 = null,
    root_path: []u8,
    license_path: []u8,
};

fn updateLicenseRank(allocator: std.mem.Allocator, raw_path: []const u8, rank: LicenseRank) !LicenseUpdateResult {
    const root_path = try resolveExistingCorpusPath(allocator, raw_path);
    errdefer allocator.free(root_path);
    {
        var dir = try std.fs.openDirAbsolute(root_path, .{});
        dir.close();
    }

    const license_path = try std.fs.path.join(allocator, &.{ root_path, "license.json" });
    errdefer allocator.free(license_path);
    const file = try std.fs.openFileAbsolute(license_path, .{});
    defer file.close();
    const stat = try file.stat();
    const bytes = try file.readToEndAlloc(allocator, @intCast(@min(stat.size, 1024 * 1024)));
    defer allocator.free(bytes);

    var parsed = try std.json.parseFromSlice(std.json.Value, allocator, bytes, .{});
    defer parsed.deinit();
    if (parsed.value != .object) return error.InvalidLicenseJson;
    var obj = &parsed.value.object;

    try obj.put("status", .{ .string = rank.status() });
    try obj.put("authority_level", .{ .integer = @intFromEnum(rank) });

    const timestamp = try std.fmt.allocPrint(allocator, "{d}", .{std.time.timestamp()});
    defer allocator.free(timestamp);
    var audit_entry = std.json.Value{ .object = std.json.ObjectMap.init(allocator) };
    defer audit_entry.object.deinit();
    try audit_entry.object.put("action", .{ .string = rank.action() });
    try audit_entry.object.put("by", .{ .string = "human" });
    try audit_entry.object.put("timestamp", .{ .string = timestamp });

    if (obj.getPtr("audit_log")) |audit_value| {
        if (audit_value.* != .array) return error.InvalidLicenseAuditLog;
        try audit_value.array.append(audit_entry);
    } else if (obj.getPtr("auditLog")) |audit_value| {
        if (audit_value.* != .array) return error.InvalidLicenseAuditLog;
        try audit_value.array.append(audit_entry);
    } else {
        var audit = std.json.Array.init(allocator);
        try audit.append(audit_entry);
        try obj.put("audit_log", .{ .array = audit });
    }

    const tmp_path = try std.fmt.allocPrint(allocator, "{s}.tmp.{d}", .{ license_path, std.time.milliTimestamp() });
    defer allocator.free(tmp_path);
    errdefer std.fs.deleteFileAbsolute(tmp_path) catch {};
    {
        var tmp = try std.fs.createFileAbsolute(tmp_path, .{ .truncate = true });
        defer tmp.close();
        try std.json.stringify(parsed.value, .{ .whitespace = .indent_2 }, tmp.writer());
        try tmp.writeAll("\n");
    }
    if (obj.getPtr("audit_log")) |audit_value| {
        if (audit_value.* == .array) audit_value.array.deinit();
    } else if (obj.getPtr("auditLog")) |audit_value| {
        if (audit_value.* == .array) audit_value.array.deinit();
    }
    try std.fs.renameAbsolute(tmp_path, license_path);

    if (rank == .trash) {
        return try moveCorpusRootToTrash(allocator, root_path, license_path);
    }
    return .{ .root_path = root_path, .license_path = license_path };
}

fn moveCorpusRootToTrash(allocator: std.mem.Allocator, root_path: []u8, license_path: []u8) !LicenseUpdateResult {
    const parent = std.fs.path.dirname(root_path) orelse return error.InvalidCorpusPath;
    if (std.mem.eql(u8, std.fs.path.basename(parent), ".trash")) {
        return .{ .root_path = root_path, .license_path = license_path };
    }

    const trash_root = try std.fs.path.join(allocator, &.{ parent, ".trash" });
    defer allocator.free(trash_root);
    try std.fs.cwd().makePath(trash_root);

    const base_name = std.fs.path.basename(root_path);
    var destination = try std.fs.path.join(allocator, &.{ trash_root, base_name });
    errdefer allocator.free(destination);
    if (pathExistsAbsolute(destination)) {
        allocator.free(destination);
        const unique_name = try std.fmt.allocPrint(allocator, "{s}-{d}", .{ base_name, std.time.milliTimestamp() });
        defer allocator.free(unique_name);
        destination = try std.fs.path.join(allocator, &.{ trash_root, unique_name });
    }

    try std.fs.renameAbsolute(root_path, destination);
    const moved_license_path = try std.fs.path.join(allocator, &.{ destination, "license.json" });
    errdefer allocator.free(moved_license_path);
    allocator.free(license_path);
    return .{
        .original_path = root_path,
        .root_path = destination,
        .license_path = moved_license_path,
    };
}

fn pathExistsAbsolute(path: []const u8) bool {
    std.fs.accessAbsolute(path, .{}) catch return false;
    return true;
}

fn resolveExistingCorpusPath(allocator: std.mem.Allocator, raw_path: []const u8) ![]u8 {
    const normalized = try normalizeSecondaryPath(allocator, raw_path);
    defer allocator.free(normalized);
    const resolved = if (std.fs.path.isAbsolute(normalized))
        try allocator.dupe(u8, normalized)
    else
        try std.fs.cwd().realpathAlloc(allocator, normalized);
    errdefer allocator.free(resolved);
    var dir = try std.fs.openDirAbsolute(resolved, .{});
    dir.close();
    const license_path = try std.fs.path.join(allocator, &.{ resolved, "license.json" });
    defer allocator.free(license_path);
    const license_file = try std.fs.openFileAbsolute(license_path, .{});
    license_file.close();
    return resolved;
}

pub fn executeIngest(allocator: std.mem.Allocator, engine_root: ?[]const u8, options: CorpusOptions) !void {
    var effective_options = options;
    var deep_path: ?[]u8 = null;
    defer if (deep_path) |value| allocator.free(value);
    const input_path = options.corpus_path orelse {
        try printIngestHelp(std.io.getStdErr().writer());
        std.process.exit(1);
    };
    if (std.mem.trim(u8, input_path, " \r\n\t").len == 0) {
        try std.io.getStdErr().writer().print("corpus ingest path must be non-empty\n", .{});
        std.process.exit(1);
    }
    const corpus_path = if (options.deep_research) blk: {
        deep_path = try buildDeepResearchShard(allocator, input_path, options.deep_research_root);
        effective_options.trust_class = options.trust_class orelse "exploratory";
        effective_options.source_label = options.source_label orelse "deep-research";
        break :blk deep_path.?;
    } else input_path;
    try runCorpusIngest(allocator, engine_root, .ingest, corpus_path, effective_options);
}

pub fn executeUserVaultIngestShortcutFromArgs(
    allocator: std.mem.Allocator,
    engine_root: ?[]const u8,
    args: []const []const u8,
    base: CorpusOptions,
) !void {
    var options = base;
    options.project_shard = options.project_shard orelse "user_vault";
    options.trust_class = options.trust_class orelse "project";
    options.source_label = options.source_label orelse "user_vault";

    var i: usize = 0;
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
        } else if (std.mem.eql(u8, arg, "--deep-research")) {
            options.deep_research = true;
        } else if (std.mem.eql(u8, arg, "--deep-research-root")) {
            i += 1;
            if (i >= args.len) try failMissingValue("--deep-research-root");
            options.deep_research_root = args[i];
        } else if (std.mem.startsWith(u8, arg, "--deep-research-root=")) {
            options.deep_research_root = arg["--deep-research-root=".len..];
        } else if (std.mem.startsWith(u8, arg, "--")) {
            try std.io.getStdErr().writer().print("Unknown ingest option: {s}\n", .{arg});
            std.process.exit(1);
        } else if (options.corpus_path == null) {
            options.corpus_path = arg;
        } else {
            try std.io.getStdErr().writer().print("Unexpected extra ingest argument: {s}\n", .{arg});
            std.process.exit(1);
        }
    }

    try executeIngest(allocator, engine_root, options);
    try executeApplyStaged(allocator, engine_root, .{
        .project_shard = options.project_shard,
        .json = options.json,
        .debug = options.debug,
    });
}

fn buildDeepResearchShard(allocator: std.mem.Allocator, input_path: []const u8, requested_root: ?[]const u8) ![]u8 {
    const vault_root = try resolveDeepResearchRoot(allocator, input_path, requested_root);
    defer allocator.free(vault_root);
    try std.fs.cwd().makePath(vault_root);
    const shard_root = try std.fs.path.join(allocator, &.{ vault_root, "forever_shard" });
    errdefer allocator.free(shard_root);
    try std.fs.cwd().makePath(shard_root);

    const license_path = try std.fs.path.join(allocator, &.{ shard_root, "license.json" });
    defer allocator.free(license_path);
    var license_file = try std.fs.createFileAbsolute(license_path, .{ .truncate = true });
    try license_file.writeAll(
        "{\n  \"status\": \"unverified-research\",\n  \"source\": \"ghost corpus ingest --deep-research\",\n  \"authority\": \"non-authorizing research synthesis\"\n}\n",
    );
    license_file.close();

    const summary_path = try std.fs.path.join(allocator, &.{ shard_root, "deep_research_summary.md" });
    defer allocator.free(summary_path);
    var summary_file = try std.fs.createFileAbsolute(summary_path, .{ .truncate = true });
    defer summary_file.close();
    const writer = summary_file.writer();
    try writer.writeAll("# Deep Research Ingest\n\n");
    try writer.writeAll("Status: unverified-research\n\n");
    try writer.print("Seed path: {s}\n\n", .{input_path});
    try writer.writeAll("Local search summary:\n");
    try writeLocalResearchSummary(allocator, writer, input_path);
    try writer.writeAll("\nMissing context search:\n");
    try writer.writeAll("- No network or hidden model search was performed by the CLI.\n");
    try writer.writeAll("- Files containing unknown, todo, tbd, missing, or unresolved markers should be reviewed as follow-up evidence candidates.\n");
    return shard_root;
}

fn resolveDeepResearchRoot(allocator: std.mem.Allocator, input_path: []const u8, requested_root: ?[]const u8) ![]u8 {
    if (requested_root) |root| return normalizeSecondaryPath(allocator, root);
    if (std.process.getEnvVarOwned(allocator, "GHOST_DEEP_RESEARCH_ROOT")) |root| return normalizeSecondaryPathOwned(allocator, root) else |_| {}
    if (std.process.getEnvVarOwned(allocator, "GHOST_VAULT_ROOT")) |root| return normalizeSecondaryPathOwned(allocator, root) else |_| {}
    if (std.mem.startsWith(u8, input_path, "/mnt/secondary/")) return try allocator.dupe(u8, "/mnt/secondary/ghost_vault");
    if (std.mem.startsWith(u8, input_path, "/mnt/d/")) return try allocator.dupe(u8, "/mnt/d/ghost_vault");
    if (looksLikeWindowsDrivePath(input_path)) {
        const normalized = try normalizeSecondaryPath(allocator, input_path);
        defer allocator.free(normalized);
        const dirname = std.fs.path.dirname(normalized) orelse normalized;
        return try allocator.dupe(u8, dirname);
    }
    return try allocator.dupe(u8, "/mnt/secondary/ghost_vault");
}

fn normalizeSecondaryPathOwned(allocator: std.mem.Allocator, owned: []u8) ![]u8 {
    defer allocator.free(owned);
    return normalizeSecondaryPath(allocator, owned);
}

fn normalizeSecondaryPath(allocator: std.mem.Allocator, raw: []const u8) ![]u8 {
    if (looksLikeWindowsDrivePath(raw)) {
        const drive = std.ascii.toLower(raw[0]);
        var out = std.ArrayList(u8).init(allocator);
        errdefer out.deinit();
        try out.writer().print("/mnt/{c}", .{drive});
        var idx: usize = 2;
        while (idx < raw.len and (raw[idx] == '\\' or raw[idx] == '/')) : (idx += 1) {}
        if (idx < raw.len) try out.append('/');
        while (idx < raw.len) : (idx += 1) {
            try out.append(if (raw[idx] == '\\') '/' else raw[idx]);
        }
        return out.toOwnedSlice();
    }
    return try allocator.dupe(u8, raw);
}

fn looksLikeWindowsDrivePath(path: []const u8) bool {
    return path.len >= 2 and std.ascii.isAlphabetic(path[0]) and path[1] == ':';
}

fn writeLocalResearchSummary(allocator: std.mem.Allocator, writer: anytype, input_path: []const u8) !void {
    var dir = std.fs.cwd().openDir(input_path, .{ .iterate = true }) catch {
        try writer.print("- Seed file: {s}\n", .{input_path});
        return;
    };
    defer dir.close();
    var walker = try dir.walk(allocator);
    defer walker.deinit();
    var count: usize = 0;
    var marker_count: usize = 0;
    while (try walker.next()) |entry| {
        if (entry.kind != .file) continue;
        count += 1;
        if (count <= 64) try writer.print("- File: {s}\n", .{entry.path});
        if (count <= 16) {
            if (try readSmallFileFromDir(allocator, dir, entry.path)) |text| {
                defer allocator.free(text);
                try writer.print("  Excerpt: {s}\n", .{text});
            }
        }
        const marker = containsMissingContextMarker(entry.basename);
        if (marker) marker_count += 1;
    }
    try writer.print("- Files scanned for local context: {d}\n", .{count});
    try writer.print("- Filename-level missing-context markers: {d}\n", .{marker_count});
}

fn readSmallFileFromDir(allocator: std.mem.Allocator, dir: std.fs.Dir, path: []const u8) !?[]u8 {
    const file = dir.openFile(path, .{}) catch return null;
    defer file.close();
    const bytes = file.readToEndAlloc(allocator, 1024) catch return null;
    errdefer allocator.free(bytes);
    var out = std.ArrayList(u8).init(allocator);
    errdefer out.deinit();
    var last_space = false;
    for (bytes) |c| {
        const normalized: u8 = switch (c) {
            '\n', '\r', '\t' => ' ',
            0 => ' ',
            else => c,
        };
        if (normalized == ' ') {
            if (last_space) continue;
            last_space = true;
        } else {
            last_space = false;
        }
        try out.append(normalized);
    }
    allocator.free(bytes);
    return try out.toOwnedSlice();
}

fn containsMissingContextMarker(text: []const u8) bool {
    return indexOfIgnoreCase(text, "todo") != null or
        indexOfIgnoreCase(text, "tbd") != null or
        indexOfIgnoreCase(text, "unknown") != null or
        indexOfIgnoreCase(text, "missing") != null or
        indexOfIgnoreCase(text, "unresolved") != null;
}

fn indexOfIgnoreCase(haystack: []const u8, needle: []const u8) ?usize {
    if (needle.len == 0 or needle.len > haystack.len) return null;
    var idx: usize = 0;
    while (idx + needle.len <= haystack.len) : (idx += 1) {
        if (std.ascii.eqlIgnoreCase(haystack[idx .. idx + needle.len], needle)) return idx;
    }
    return null;
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

    var active_mounts: []MountedPackRef = &.{};
    defer freeMountedPackRefs(allocator, active_mounts);
    var effective_options = options;
    if (options.mounted_packs.len == 0) {
        active_mounts = try loadActiveMountedPacks(allocator, engine_root, options.project_shard, options.debug);
        effective_options.mounted_packs = active_mounts;
    }

    var request = std.ArrayList(u8).init(allocator);
    defer request.deinit();
    try writeCorpusAskRequest(request.writer(), question, effective_options);

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

fn loadActiveMountedPacks(
    allocator: std.mem.Allocator,
    engine_root: ?[]const u8,
    project_shard: ?[]const u8,
    debug: bool,
) ![]MountedPackRef {
    const shard = project_shard orelse "default";
    const bin_path = locator.findEngineBinary(allocator, engine_root, .ghost_knowledge_pack) catch return &.{};
    defer allocator.free(bin_path);
    const shard_arg = try std.fmt.allocPrint(allocator, "--project-shard={s}", .{shard});
    defer allocator.free(shard_arg);
    const argv = &[_][]const u8{ bin_path, "list", shard_arg, "--json" };
    if (debug) try printDebugArgv(std.io.getStdErr().writer(), argv);
    const res = process.runEngineCommand(allocator, argv) catch return &.{};
    defer {
        allocator.free(res.stdout);
        allocator.free(res.stderr);
    }
    if (res.exit_code != 0) return &.{};

    var parsed = std.json.parseFromSlice(std.json.Value, allocator, res.stdout, .{}) catch {
        return &.{};
    };
    defer parsed.deinit();
    if (parsed.value != .array) return &.{};

    var refs = std.ArrayList(MountedPackRef).init(allocator);
    errdefer {
        freeMountedPackRefs(allocator, refs.items);
        refs.deinit();
    }
    for (parsed.value.array.items) |item| {
        if (item != .object) continue;
        const obj = item.object;
        const mounted = if (obj.get("mounted")) |value| value == .bool and value.bool else false;
        const enabled = if (obj.get("enabled")) |value| value == .bool and value.bool else false;
        if (!mounted or !enabled) continue;
        const pack_id = jsonStringField(obj, "packId") orelse continue;
        const version = jsonStringField(obj, "version") orelse continue;
        try refs.append(.{
            .pack_id = try allocator.dupe(u8, pack_id),
            .pack_version = try allocator.dupe(u8, version),
        });
    }
    return refs.toOwnedSlice();
}

fn freeMountedPackRefs(allocator: std.mem.Allocator, refs: []MountedPackRef) void {
    if (refs.len == 0) return;
    for (refs) |ref| {
        allocator.free(ref.pack_id);
        allocator.free(ref.pack_version);
    }
    allocator.free(refs);
}

fn jsonStringField(obj: std.json.ObjectMap, field: []const u8) ?[]const u8 {
    const value = obj.get(field) orelse return null;
    return if (value == .string) value.string else null;
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
    if (options.mounted_packs.len != 0) {
        try writer.writeAll(",\"mountedPacks\":[");
        for (options.mounted_packs, 0..) |mounted_pack, idx| {
            if (idx != 0) try writer.writeByte(',');
            try writer.writeAll("{\"packId\":");
            try std.json.stringify(mounted_pack.pack_id, .{}, writer);
            try writer.writeAll(",\"packVersion\":");
            try std.json.stringify(mounted_pack.pack_version, .{}, writer);
            try writer.writeByte('}');
        }
        try writer.writeByte(']');
    }
    if (options.require_citations) try writer.writeAll(",\"requireCitations\":true");
    try writer.writeAll("}");
}

fn parseMountedPackArg(raw: []const u8) MountedPackRef {
    const trimmed = std.mem.trim(u8, raw, " \r\n\t");
    if (std.mem.indexOfScalar(u8, trimmed, '@')) |idx| {
        const pack_id = std.mem.trim(u8, trimmed[0..idx], " \r\n\t");
        const pack_version = std.mem.trim(u8, trimmed[(idx + 1)..], " \r\n\t");
        if (pack_id.len != 0 and pack_version.len != 0) return .{ .pack_id = pack_id, .pack_version = pack_version };
    }
    return .{ .pack_id = trimmed, .pack_version = "v1" };
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
    const suppressed_evidence = corpus.get("suppressedEvidence");
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
        influence_telemetry,
    );
    const answer_suppressed_by_nk = !has_answer and hasReviewedNegativeKnowledgeSuppression(
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
        } else if (hasUnknownKind(unknowns, "rejected_falsehood") or isCorpusStatus(corpus, "rejected_falsehood")) {
            try writer.print("A blacklisted Trash-ranked source matched this query, so the falsehood was rejected.\n", .{});
        } else if (hasUnknownKind(unknowns, "insufficient_high_rank_evidence")) {
            try writer.print("Only Shadow-ranked corpus context matched, so no answer draft is rendered.\n", .{});
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

    if (suppressed_evidence) |suppressed_value| {
        if (!isEmptyJsonList(suppressed_value)) {
            try writer.print("\nSuppressed Evidence / NON-AUTHORIZING\n", .{});
            try writer.print("These sources were excluded from answer drafting.\n", .{});
            try printEvidenceUsed(writer, suppressed_value);
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
        try printOptionalTraceField(writer, trace, "mountedPacksConsidered");
    }

    try writer.print("\nNotice: This output is a DRAFT and NON-AUTHORIZING.\n", .{});
    try writer.print("Corpus ask uses bounded local matching over live corpus excerpts plus explicitly supplied mounted pack corpus; similarity hints are not evidence and it is not semantic search.\n", .{});
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

fn hasCorrectionSuppression(telemetry: ?std.json.Value) bool {
    return if (telemetry) |v| hasBoolOrPressureField(v, "answerSuppressed") else false;
}

fn hasReviewedNegativeKnowledgeSuppression(telemetry: ?std.json.Value) bool {
    return if (telemetry) |v| hasBoolOrPressureField(v, "answerSuppressed") else false;
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
    if (hasReviewedNegativeKnowledgeSuppression(telemetry)) {
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
    return hasPressureField(obj, "malformedLines") or
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
    if (isTrashEvidence(obj)) {
        try writer.print("    🚫 [Blacklisted Source Blocked] discarded; not used as evidence\n", .{});
    } else if (isShadowEvidence(obj)) {
        try writer.print("    👤 [Shadow Context] contextual only; not used as truth basis\n", .{});
    }
    try printOptionalEvidenceField(writer, obj, "itemId", "itemId");
    try printOptionalEvidenceField(writer, obj, "path", "path");
    try printOptionalEvidenceField(writer, obj, "sourcePath", "sourcePath");
    try printOptionalEvidenceField(writer, obj, "class", "class");
    try printOptionalEvidenceField(writer, obj, "licenseStatus", "licenseStatus");
    try printOptionalEvidenceField(writer, obj, "authorityLevel", "authorityLevel");
    try printOptionalEvidenceField(writer, obj, "snippet", "snippet");
    try printOptionalEvidenceField(writer, obj, "reason", "reason");
    try printOptionalEvidenceField(writer, obj, "authorityRef", "authorityRef");
    try printOptionalEvidenceField(writer, obj, "provenance", "provenance");
    try printOptionalEvidenceField(writer, obj, "score", "score");
}

fn isShadowEvidence(obj: std.json.ObjectMap) bool {
    if (getString(obj, "licenseStatus")) |status| {
        if (std.ascii.eqlIgnoreCase(status, "shadow")) return true;
    }
    if (obj.get("authorityLevel")) |value| {
        switch (value) {
            .integer => |i| return i == 3,
            .float => |f| return f == 3,
            else => {},
        }
    }
    return false;
}

fn isTrashEvidence(obj: std.json.ObjectMap) bool {
    if (getString(obj, "licenseStatus")) |status| {
        if (std.ascii.eqlIgnoreCase(status, "trash")) return true;
    }
    if (obj.get("authorityLevel")) |value| {
        switch (value) {
            .integer => |i| return i >= 4,
            .float => |f| return f >= 4,
            else => {},
        }
    }
    if (getString(obj, "reason")) |reason| {
        if (std.mem.indexOf(u8, reason, "blacklisted") != null) return true;
    }
    return false;
}

fn isCorpusStatus(obj: std.json.ObjectMap, status: []const u8) bool {
    return if (getString(obj, "status")) |value| std.mem.eql(u8, value, status) else false;
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
