const std = @import("std");
const locator = @import("../engine/locator.zig");
const process = @import("../engine/process.zig");

pub const SweOptions = struct {
    json: bool = false,
    debug: bool = false,
};

const usage =
    \\Usage: ghost swe [options]
    \\
;

pub fn printHelp(writer: anytype) !void {
    try writer.writeAll(
        \\swe
        \\
        \\Usage: ghost swe [options]
        \\
        \\Runs the explicit native SWE provisioning harness.
        \\
        \\Common options passed through to ghost_swe_harness:
        \\  --rows <path>             rows.jsonl path
        \\  --batch-size <n>          number of rows to attempt
        \\  --limit <n>               number of rows to attempt
        \\  --cluster-seed <text>     VSA Hamming seed, default qutebrowser
        \\  --max-environment-attempts <n>
        \\  --max-repair-attempts <n> retry missing dependency repairs, default 3
        \\  --linear                  preserve dataset order
        \\  --no-gpu-lattice          keep LATTICE_QUERY reprioritization on CPU
        \\  --include-unsupported-languages
        \\                            attempt non-Python/JS rows instead of skipping them
        \\  --workspace-root <path>   native clone root, default /tmp/ghost/swe
        \\  --knowledge-dir <path>    grounding output directory
        \\  --corpus-dir <path>       offline mirror root for file:// acquisition
        \\  --keep-workspaces         do not delete workspaces after attempts
        \\  --no-bootstrap            disable deterministic environment repairs
        \\  --no-ephemeral-venv       use configured Python/Pip directly
        \\  --no-preflight-pip        skip requirements.txt install in temp_venv
        \\  --no-preflight-npm        skip npm install/npm ci before JS tests
        \\
        \\Safety:
        \\  Explicit invocation only.
        \\  Native sandbox, no Docker or Podman.
        \\  Results are benchmark telemetry, not answer authority.
        \\
    );
}

pub fn executeFromArgs(
    allocator: std.mem.Allocator,
    engine_root: ?[]const u8,
    args: []const []const u8,
    options: SweOptions,
) !void {
    for (args) |arg| {
        if (std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h")) {
            try printHelp(std.io.getStdErr().writer());
            return;
        }
    }

    const bin_path = locator.findEngineBinary(allocator, engine_root, .ghost_swe_harness) catch |err| {
        try locator.printLocatorError(std.io.getStdErr().writer(), .ghost_swe_harness, engine_root, err);
        std.process.exit(1);
    };
    defer allocator.free(bin_path);

    const harness_root = try resolveHarnessEngineRoot(allocator, engine_root);
    defer if (harness_root) |root| allocator.free(root);

    var run_args = std.ArrayList([]const u8).init(allocator);
    defer run_args.deinit();
    var owned_args = std.ArrayList([]u8).init(allocator);
    defer {
        for (owned_args.items) |arg| allocator.free(arg);
        owned_args.deinit();
    }
    try run_args.append(bin_path);
    try appendNormalizedHarnessArgs(allocator, &run_args, &owned_args, harness_root, args);

    if (options.debug) {
        try std.io.getStdErr().writer().print("[DEBUG] Engine Binary: {s}\n", .{bin_path});
        if (harness_root) |root| try std.io.getStdErr().writer().print("[DEBUG] Engine Root: {s}\n", .{root});
        try std.io.getStdErr().writer().print("[DEBUG] Harness: ghost_swe_harness\n", .{});
    }

    const result = try process.runEngineCommandWithTimeout(allocator, run_args.items, 60 * 60 * 1000);
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);

    if (result.exit_code != 0) {
        if (result.stdout.len != 0) try std.io.getStdErr().writer().print("{s}\n", .{result.stdout});
        try std.io.getStdErr().writer().print("ghost_swe_harness exited {d}\n", .{result.exit_code});
        std.process.exit(result.exit_code);
    }

    if (options.json) {
        try std.io.getStdOut().writer().writeAll(result.stdout);
        if (result.stdout.len == 0 or result.stdout[result.stdout.len - 1] != '\n') try std.io.getStdOut().writer().writeByte('\n');
        return;
    }

    var parsed = std.json.parseFromSlice(std.json.Value, allocator, result.stdout, .{}) catch |err| {
        try std.io.getStdErr().writer().print("Error: ghost_swe_harness returned invalid JSON ({s}).\n", .{@errorName(err)});
        try std.io.getStdErr().writer().print("Raw output:\n{s}\n", .{result.stdout});
        std.process.exit(1);
    };
    defer parsed.deinit();
    try printSweSummary(std.io.getStdOut().writer(), parsed.value);
}

fn printSweSummary(writer: anytype, value: std.json.Value) !void {
    if (value != .object) return error.InvalidSweSummary;
    const obj = value.object;
    try writer.writeAll("Ghost SWE Harness\nState: EXPLICIT / NATIVE SANDBOX / NON-AUTHORIZING\n\n");
    try writer.print("Rows: attempted {d} / total {d}\n", .{ intField(obj, "attempted"), intField(obj, "totalRows") });
    try writer.print("Verified: {d}\n", .{intField(obj, "verified")});
    try writer.print("Invalid Environment: {d}\n", .{intField(obj, "invalidEnvironment")});
    try writer.print("Failed: {d}\n", .{intField(obj, "failed")});
    try writer.print("False Positive: {d}\n", .{intField(obj, "falsePositive")});
    try writer.print("Skipped By Language: {d}\n", .{intField(obj, "skippedByLanguage")});
    try writer.print("Truth Density: {d}/1000\n", .{intField(obj, "truthDensityPerMille")});
    try writer.print("Lattice Query: backend={s} opcode={s} rows={d}\n", .{
        stringField(obj, "latticeBackend"),
        stringField(obj, "latticeQueryGipOpCode"),
        intField(obj, "latticeQueryCount"),
    });

    const results = obj.get("results") orelse return;
    if (results != .array or results.array.items.len == 0) return;
    try writer.writeAll("\nResults:\n");
    for (results.array.items) |item| {
        if (item != .object) continue;
        const row = item.object;
        try writer.print("  - {s}: {s}", .{ stringField(row, "instanceId"), stringField(row, "status") });
        const build_root = stringField(row, "buildRootRelative");
        if (build_root.len != 0) try writer.print(" buildRoot={s}", .{build_root});
        const landlock_opcode = stringField(row, "landlockGipOpCode");
        if (landlock_opcode.len != 0) try writer.print(" leash={s}", .{landlock_opcode});
        if (boolField(row, "oracleTimeout")) {
            const timeout_opcode = stringField(row, "oracleTimeoutGipOpCode");
            if (timeout_opcode.len != 0) {
                try writer.print(" oracleTimeout=true opcode={s}", .{timeout_opcode});
            } else {
                try writer.writeAll(" oracleTimeout=true");
            }
        }
        if (row.get("reprioritizationDistance")) |distance| {
            if (distance == .integer) try writer.print(" hamming={d}", .{distance.integer});
        }
        const patch_mode = stringField(row, "goldPatchMode");
        if (patch_mode.len != 0) try writer.print(" goldPatch={s}", .{patch_mode});
        try writer.writeByte('\n');
        if (row.get("landlockAllowedPaths")) |paths| {
            try printAllowedPaths(writer, paths);
        }
        const retry_path = stringField(row, "landlockRetryPath");
        if (retry_path.len != 0) try writer.print("    Retry Scratchpad: {s}\n", .{retry_path});
    }
}

fn printAllowedPaths(writer: anytype, value: std.json.Value) !void {
    if (value != .object) return;
    const obj = value.object;
    try writer.writeAll("    Leash Allowed Paths:\n");
    if (obj.get("readWriteExecute")) |rw| {
        if (rw == .array and rw.array.items.len != 0) {
            try writer.writeAll("      RWX: ");
            try printStringArrayInline(writer, rw);
            try writer.writeByte('\n');
        }
    }
    if (obj.get("readOnlyExecute")) |ro| {
        if (ro == .array and ro.array.items.len != 0) {
            try writer.writeAll("      ROX: ");
            try printStringArrayInline(writer, ro);
            try writer.writeByte('\n');
        }
    }
}

fn printStringArrayInline(writer: anytype, value: std.json.Value) !void {
    if (value != .array) return;
    for (value.array.items, 0..) |item, idx| {
        if (item != .string) continue;
        if (idx != 0) try writer.writeAll(", ");
        try writer.writeAll(item.string);
    }
}

fn intField(obj: std.json.ObjectMap, key: []const u8) i128 {
    const value = obj.get(key) orelse return 0;
    return switch (value) {
        .integer => |n| n,
        .float => |n| @intFromFloat(n),
        else => 0,
    };
}

fn stringField(obj: std.json.ObjectMap, key: []const u8) []const u8 {
    const value = obj.get(key) orelse return "";
    return if (value == .string) value.string else "";
}

fn boolField(obj: std.json.ObjectMap, key: []const u8) bool {
    const value = obj.get(key) orelse return false;
    return switch (value) {
        .bool => |b| b,
        else => false,
    };
}

fn appendNormalizedHarnessArgs(
    allocator: std.mem.Allocator,
    run_args: *std.ArrayList([]const u8),
    owned_args: *std.ArrayList([]u8),
    engine_root: ?[]const u8,
    args: []const []const u8,
) !void {
    var saw_rows = false;
    var saw_knowledge_dir = false;
    var saw_corpus_dir = false;
    var idx: usize = 0;
    while (idx < args.len) : (idx += 1) {
        const arg = args[idx];
        if (std.mem.eql(u8, arg, "--rows")) {
            try appendResolvedPair(allocator, run_args, owned_args, "--rows", args, &idx, engine_root, true);
            saw_rows = true;
        } else if (std.mem.startsWith(u8, arg, "--rows=")) {
            try appendResolvedInline(allocator, run_args, owned_args, "--rows", arg["--rows=".len..], engine_root, true);
            saw_rows = true;
        } else if (std.mem.eql(u8, arg, "--workspace-root")) {
            try appendResolvedPair(allocator, run_args, owned_args, "--workspace-root", args, &idx, engine_root, false);
        } else if (std.mem.startsWith(u8, arg, "--workspace-root=")) {
            try appendResolvedInline(allocator, run_args, owned_args, "--workspace-root", arg["--workspace-root=".len..], engine_root, false);
        } else if (std.mem.eql(u8, arg, "--knowledge-dir")) {
            try appendResolvedPair(allocator, run_args, owned_args, "--knowledge-dir", args, &idx, engine_root, false);
            saw_knowledge_dir = true;
        } else if (std.mem.startsWith(u8, arg, "--knowledge-dir=")) {
            try appendResolvedInline(allocator, run_args, owned_args, "--knowledge-dir", arg["--knowledge-dir=".len..], engine_root, false);
            saw_knowledge_dir = true;
        } else if (std.mem.eql(u8, arg, "--corpus-dir")) {
            try appendResolvedPair(allocator, run_args, owned_args, "--corpus-dir", args, &idx, engine_root, false);
            saw_corpus_dir = true;
        } else if (std.mem.startsWith(u8, arg, "--corpus-dir=")) {
            try appendResolvedInline(allocator, run_args, owned_args, "--corpus-dir", arg["--corpus-dir=".len..], engine_root, false);
            saw_corpus_dir = true;
        } else {
            try run_args.append(arg);
        }
    }

    if (engine_root) |root| {
        if (!saw_rows) {
            try run_args.append("--rows");
            const path = try std.fs.path.join(allocator, &.{ root, ".ghost", "knowledge", "swe_bench_pro", "rows.jsonl" });
            try owned_args.append(path);
            try run_args.append(path);
        }
        if (!saw_knowledge_dir) {
            try run_args.append("--knowledge-dir");
            const path = try std.fs.path.join(allocator, &.{ root, ".ghost", "knowledge", "swe_bench_pro" });
            try owned_args.append(path);
            try run_args.append(path);
        }
        if (!saw_corpus_dir) {
            if (try defaultCorpusDir(allocator, root)) |path| {
                try run_args.append("--corpus-dir");
                try owned_args.append(path);
                try run_args.append(path);
            }
        }
    }
}

fn appendResolvedPair(
    allocator: std.mem.Allocator,
    run_args: *std.ArrayList([]const u8),
    owned_args: *std.ArrayList([]u8),
    flag: []const u8,
    args: []const []const u8,
    idx: *usize,
    engine_root: ?[]const u8,
    prefer_engine_root: bool,
) !void {
    idx.* += 1;
    if (idx.* >= args.len) return error.MissingSwePathArgument;
    try appendResolvedInline(allocator, run_args, owned_args, flag, args[idx.*], engine_root, prefer_engine_root);
}

fn appendResolvedInline(
    allocator: std.mem.Allocator,
    run_args: *std.ArrayList([]const u8),
    owned_args: *std.ArrayList([]u8),
    flag: []const u8,
    path: []const u8,
    engine_root: ?[]const u8,
    prefer_engine_root: bool,
) !void {
    try run_args.append(flag);
    const resolved = try resolveHarnessPath(allocator, engine_root, path, prefer_engine_root);
    try owned_args.append(resolved);
    try run_args.append(resolved);
}

fn resolveHarnessEngineRoot(allocator: std.mem.Allocator, engine_root: ?[]const u8) !?[]u8 {
    const root = engine_root orelse return null;
    const abs = try resolveHarnessPath(allocator, null, root, false);
    errdefer allocator.free(abs);
    if (hasRowsUnder(allocator, abs)) return abs;

    if (std.mem.endsWith(u8, abs, "/zig-out/bin")) {
        const zig_out = std.fs.path.dirname(abs) orelse return abs;
        const project_root = std.fs.path.dirname(zig_out) orelse return abs;
        const dupe = try allocator.dupe(u8, project_root);
        allocator.free(abs);
        return dupe;
    }
    return abs;
}

fn hasRowsUnder(allocator: std.mem.Allocator, root: []const u8) bool {
    const path = std.fs.path.join(allocator, &.{ root, ".ghost", "knowledge", "swe_bench_pro", "rows.jsonl" }) catch return false;
    defer allocator.free(path);
    var file = std.fs.openFileAbsolute(path, .{}) catch return false;
    file.close();
    return true;
}

fn defaultCorpusDir(allocator: std.mem.Allocator, engine_root: []const u8) !?[]u8 {
    const path = try std.fs.path.join(allocator, &.{ engine_root, "corpus_local_backup", "code" });
    errdefer allocator.free(path);
    var dir = std.fs.openDirAbsolute(path, .{}) catch |err| switch (err) {
        error.FileNotFound => {
            allocator.free(path);
            return null;
        },
        else => {
            allocator.free(path);
            return null;
        },
    };
    dir.close();
    const real = std.fs.realpathAlloc(allocator, path) catch return path;
    allocator.free(path);
    return real;
}

fn resolveHarnessPath(
    allocator: std.mem.Allocator,
    engine_root: ?[]const u8,
    path: []const u8,
    prefer_engine_root: bool,
) ![]u8 {
    if (std.fs.path.isAbsolute(path)) {
        return std.fs.realpathAlloc(allocator, path) catch allocator.dupe(u8, path);
    }
    if (prefer_engine_root) {
        if (try resolveRelativeToRoot(allocator, engine_root, path)) |resolved| return resolved;
    }
    if (std.fs.cwd().realpathAlloc(allocator, path)) |resolved| return resolved else |_| {}
    if (!prefer_engine_root) {
        if (try resolveRelativeToRoot(allocator, engine_root, path)) |resolved| return resolved;
    }
    return std.fs.path.resolve(allocator, &.{path});
}

fn resolveRelativeToRoot(allocator: std.mem.Allocator, engine_root: ?[]const u8, path: []const u8) !?[]u8 {
    const root = engine_root orelse return null;
    const candidate = try std.fs.path.join(allocator, &.{ root, path });
    defer allocator.free(candidate);
    if (std.fs.cwd().realpathAlloc(allocator, candidate)) |resolved| return resolved else |_| {}
    return try std.fs.path.resolve(allocator, &.{candidate});
}

test "SWE summary renderer shows build root and hamming telemetry" {
    const json =
        \\{"totalRows":731,"attempted":1,"verified":1,"invalidEnvironment":0,"failed":0,"falsePositive":0,"skippedByLanguage":4,"truthDensityPerMille":1,"latticeBackend":"vulkan","latticeQueryCount":731,"latticeQueryGipOpCode":"GIP_OP_LATTICE_QUERY","results":[{"instanceId":"instance_qutebrowser","status":"verified","buildRootRelative":".","landlockGipOpCode":"GIP_OP_LANDLOCK_STRICT","landlockAllowedPaths":{"readWriteExecute":["/tmp/ghost/swe/instance_qutebrowser"],"readOnlyExecute":["/usr","/lib","/lib64","/etc"]},"oracleTimeout":true,"oracleTimeoutGipOpCode":"GIP_OP_ORACLE_TIMEOUT","reprioritizationDistance":0,"goldPatchMode":"clean"}]}
    ;
    var parsed = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, json, .{});
    defer parsed.deinit();
    var out = std.ArrayList(u8).init(std.testing.allocator);
    defer out.deinit();
    try printSweSummary(out.writer(), parsed.value);
    try std.testing.expect(std.mem.indexOf(u8, out.items, "NON-AUTHORIZING") != null);
    try std.testing.expect(std.mem.indexOf(u8, out.items, "backend=vulkan opcode=GIP_OP_LATTICE_QUERY rows=731") != null);
    try std.testing.expect(std.mem.indexOf(u8, out.items, "Skipped By Language: 4") != null);
    try std.testing.expect(std.mem.indexOf(u8, out.items, "goldPatch=clean") != null);
    try std.testing.expect(std.mem.indexOf(u8, out.items, "buildRoot=.") != null);
    try std.testing.expect(std.mem.indexOf(u8, out.items, "leash=GIP_OP_LANDLOCK_STRICT") != null);
    try std.testing.expect(std.mem.indexOf(u8, out.items, "oracleTimeout=true opcode=GIP_OP_ORACLE_TIMEOUT") != null);
    try std.testing.expect(std.mem.indexOf(u8, out.items, "RWX: /tmp/ghost/swe/instance_qutebrowser") != null);
    try std.testing.expect(std.mem.indexOf(u8, out.items, "ROX: /usr, /lib, /lib64, /etc") != null);
    try std.testing.expect(std.mem.indexOf(u8, out.items, "hamming=0") != null);
}

test "SWE args inject default offline corpus dir from engine root" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.makePath(".ghost/knowledge/swe_bench_pro");
    try tmp.dir.writeFile(.{ .sub_path = ".ghost/knowledge/swe_bench_pro/rows.jsonl", .data = "" });
    try tmp.dir.makePath("corpus_local_backup/code");
    const root = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(root);

    var run_args = std.ArrayList([]const u8).init(allocator);
    defer run_args.deinit();
    var owned_args = std.ArrayList([]u8).init(allocator);
    defer {
        for (owned_args.items) |arg| allocator.free(arg);
        owned_args.deinit();
    }

    try appendNormalizedHarnessArgs(allocator, &run_args, &owned_args, root, &.{});
    var saw_rows = false;
    var corpus_idx: ?usize = null;
    for (run_args.items, 0..) |arg, idx| {
        if (std.mem.eql(u8, arg, "--rows")) saw_rows = true;
        if (std.mem.eql(u8, arg, "--corpus-dir")) corpus_idx = idx;
    }
    try std.testing.expect(saw_rows);
    const idx = corpus_idx orelse return error.MissingCorpusDir;
    try std.testing.expect(idx + 1 < run_args.items.len);
    try std.testing.expect(std.mem.endsWith(u8, run_args.items[idx + 1], "/corpus_local_backup/code"));
}
