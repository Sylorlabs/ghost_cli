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
        \\  --linear                  preserve dataset order
        \\  --no-gpu-lattice          keep LATTICE_QUERY reprioritization on CPU
        \\  --include-unsupported-languages
        \\                            attempt non-Python/JS rows instead of skipping them
        \\  --workspace-root <path>   native clone root, default /tmp/ghost/swe
        \\  --knowledge-dir <path>    grounding output directory
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

    var run_args = std.ArrayList([]const u8).init(allocator);
    defer run_args.deinit();
    try run_args.append(bin_path);
    for (args) |arg| try run_args.append(arg);

    if (options.debug) {
        try std.io.getStdErr().writer().print("[DEBUG] Engine Binary: {s}\n", .{bin_path});
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

test "SWE summary renderer shows build root and hamming telemetry" {
    const json =
        \\{"totalRows":731,"attempted":1,"verified":1,"invalidEnvironment":0,"failed":0,"falsePositive":0,"skippedByLanguage":4,"truthDensityPerMille":1,"latticeBackend":"vulkan","latticeQueryCount":731,"latticeQueryGipOpCode":"GIP_OP_LATTICE_QUERY","results":[{"instanceId":"instance_qutebrowser","status":"verified","buildRootRelative":".","landlockGipOpCode":"GIP_OP_LANDLOCK_STRICT","landlockAllowedPaths":{"readWriteExecute":["/tmp/ghost/swe/instance_qutebrowser"],"readOnlyExecute":["/usr","/lib","/lib64","/etc"]},"reprioritizationDistance":0,"goldPatchMode":"clean"}]}
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
    try std.testing.expect(std.mem.indexOf(u8, out.items, "RWX: /tmp/ghost/swe/instance_qutebrowser") != null);
    try std.testing.expect(std.mem.indexOf(u8, out.items, "ROX: /usr, /lib, /lib64, /etc") != null);
    try std.testing.expect(std.mem.indexOf(u8, out.items, "hamming=0") != null);
}
