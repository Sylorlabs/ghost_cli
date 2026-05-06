const std = @import("std");
const locator = @import("../engine/locator.zig");
const process = @import("../engine/process.zig");
const packs = @import("packs.zig");

pub fn execute(allocator: std.mem.Allocator, engine_root: ?[]const u8, debug: bool, build_version: []const u8) !void {
    const stdout = std.io.getStdOut().writer();

    try stdout.print("--- Ghost CLI Status ---\n", .{});
    try stdout.print("Scope: engine availability/status. Use `ghost doctor` for full tester diagnostics.\n", .{});
    try stdout.print("Build Version: {s}\n", .{build_version});
    var self_exe_path_buf: [1024]u8 = undefined;
    const self_exe_path = std.fs.selfExePath(&self_exe_path_buf) catch "Unknown";
    try stdout.print("CLI Binary: {s}\n", .{self_exe_path});
    try stdout.print("Engine Root: {s}\n", .{engine_root orelse "Not Found"});
    try printReleaseSeal(allocator, stdout, engine_root);

    try stdout.print("\nEngine Binaries:\n", .{});

    var all_core_ok = true;
    for (locator.allBinaries()) |binary| {
        var resolution = try locator.resolveEngineBinary(allocator, engine_root, binary);
        defer resolution.deinit(allocator);

        if (binary.isCore() and resolution.resolved_status != .executable) all_core_ok = false;

        try stdout.print("  - {s}: {s}", .{ binary.toStr(), resolution.resolved_status.label() });
        if (resolution.resolved_kind) |kind| try stdout.print(" [{s}]", .{kind.label()});
        try stdout.print("\n", .{});
        if (resolution.resolved_path) |path| {
            try stdout.print("    Path: {s}\n", .{path});
        } else {
            try stdout.print("    Path: unresolved\n", .{});
        }

        if (debug) {
            try stdout.print("    candidates:\n", .{});
            for (resolution.candidates) |candidate| {
                try stdout.print("      - {s} [{s}; {s}", .{ candidate.path, candidate.kind.label(), candidate.status.label() });
                if (candidate.resolved_path) |resolved| try stdout.print("; resolved={s}", .{resolved});
                try stdout.print("]\n", .{});
            }
        }
    }

    if (!all_core_ok) {
        try stdout.print("\n\x1b[31m[!] Some core engine binaries are missing or not executable.\x1b[0m\n", .{});
        if (engine_root) |root| {
            try stdout.print("\x1b[33mHint:\x1b[0m If GHOST_ENGINE_ROOT points to the repo root ({s}), run `zig build` in ghost_engine.\n", .{root});
        }
        try stdout.print("\x1b[33mFix:\x1b[0m Set GHOST_ENGINE_ROOT, use --engine-root=<path>, or put binaries on PATH.\n", .{});
    } else {
        try stdout.print("\n\x1b[32m[+] Core engine binaries located successfully.\x1b[0m\n", .{});
    }

    var capability_diagnostic = try packs.collectCapabilityDiagnostic(allocator, engine_root, debug);
    defer capability_diagnostic.deinit();
    try stdout.print("\nKnowledge Pack Validation Capabilities (diagnostic/read-only):\n", .{});
    try stdout.print("  capabilities available: {s}\n", .{yesNo(capability_diagnostic.capabilities_available)});
    try stdout.print("  validate-autopsy-guidance supported: {s}\n", .{yesNo(capability_diagnostic.validate_autopsy_guidance_supported)});
    try stdout.print("  supported schema versions: ", .{});
    if (capability_diagnostic.supported_schema_versions.len == 0) {
        try stdout.print("unknown\n", .{});
    } else {
        for (capability_diagnostic.supported_schema_versions, 0..) |schema, i| {
            if (i > 0) try stdout.print(", ", .{});
            try stdout.print("{s}", .{schema});
        }
        try stdout.print("\n", .{});
    }
    try stdout.print("  supported validation limit flags: ", .{});
    var wrote_flag = false;
    if (capability_diagnostic.supported_validation_limit_flags.max_guidance_bytes) {
        try stdout.print("--max-guidance-bytes", .{});
        wrote_flag = true;
    }
    if (capability_diagnostic.supported_validation_limit_flags.max_array_items) {
        try stdout.print("{s}--max-array-items", .{if (wrote_flag) ", " else ""});
        wrote_flag = true;
    }
    if (capability_diagnostic.supported_validation_limit_flags.max_string_bytes) {
        try stdout.print("{s}--max-string-bytes", .{if (wrote_flag) ", " else ""});
        wrote_flag = true;
    }
    if (!wrote_flag) try stdout.print("unknown", .{});
    try stdout.print("\n", .{});
    if (capability_diagnostic.warning) |warning| {
        try stdout.print("  compatibility warning: {s}. Upgrade/rebuild ghost_engine if this command is needed.\n", .{warning});
    }

    try printGlobalPackRegistrySummary(allocator, stdout, engine_root, debug);

    var cwd_buf: [1024]u8 = undefined;
    const cwd = std.fs.cwd().realpath(".", &cwd_buf) catch "Unknown";
    try stdout.print("\nWorking Directory: {s}\n", .{cwd});
}

fn printGlobalPackRegistrySummary(allocator: std.mem.Allocator, writer: anytype, engine_root: ?[]const u8, debug: bool) !void {
    try writer.print("\nGlobal Pack Registry:\n", .{});
    const bin_path = locator.findEngineBinary(allocator, engine_root, .ghost_knowledge_pack) catch {
        try writer.print("  unavailable: ghost_knowledge_pack binary not found\n", .{});
        return;
    };
    defer allocator.free(bin_path);
    const argv = &[_][]const u8{ bin_path, "list", "--project-shard=default", "--json" };
    if (debug) {
        try writer.print("  registry argv:", .{});
        for (argv) |arg| try writer.print(" {s}", .{arg});
        try writer.print("\n", .{});
    }
    const res = process.runEngineCommand(allocator, argv) catch {
        try writer.print("  unavailable: ghost_knowledge_pack list failed\n", .{});
        return;
    };
    defer {
        allocator.free(res.stdout);
        allocator.free(res.stderr);
    }
    if (res.exit_code != 0) {
        try writer.print("  unavailable: ghost_knowledge_pack list exited {d}\n", .{res.exit_code});
        return;
    }
    var parsed = std.json.parseFromSlice(std.json.Value, allocator, res.stdout, .{}) catch {
        try writer.print("  unavailable: pack registry JSON could not be parsed\n", .{});
        return;
    };
    defer parsed.deinit();
    if (parsed.value != .array) {
        try writer.print("  unavailable: pack registry JSON was not an array\n", .{});
        return;
    }
    const items = parsed.value.array.items;
    var mounted_count: usize = 0;
    for (items) |item| {
        if (item != .object) continue;
        if (jsonBoolField(item.object, "mounted")) mounted_count += 1;
    }
    try writer.print("  installed packs: {d}\n", .{items.len});
    try writer.print("  mounted in default status view: {d}\n", .{mounted_count});
    const limit = @min(items.len, 8);
    for (items[0..limit]) |item| {
        if (item != .object) continue;
        const obj = item.object;
        const pack_id = jsonStringField(obj, "packId") orelse "<unknown>";
        const version = jsonStringField(obj, "version") orelse "<unknown>";
        const mounted = jsonBoolField(obj, "mounted");
        const enabled = jsonBoolField(obj, "enabled");
        try writer.print("  - {s}@{s} mounted={s} enabled={s}\n", .{ pack_id, version, yesNo(mounted), yesNo(enabled) });
    }
    if (items.len > limit) try writer.print("  - ... {d} more\n", .{items.len - limit});
}

fn printReleaseSeal(allocator: std.mem.Allocator, writer: anytype, engine_root: ?[]const u8) !void {
    try writer.print("\nRelease Seal:\n", .{});
    try printGitSeal(allocator, writer, "ghost_cli", ".", "cli-v");

    if (engine_root) |root| {
        if (try printGitSealIfAvailable(allocator, writer, "ghost_engine", root, "engine-v")) return;
        if (try inferEngineSourceRoot(allocator, root)) |source_root| {
            defer allocator.free(source_root);
            if (try printGitSealIfAvailable(allocator, writer, "ghost_engine", source_root, "engine-v")) return;
        }
    }
    try writer.print("  - ghost_engine: unavailable (git root not found)\n", .{});
}

fn printGitSealIfAvailable(
    allocator: std.mem.Allocator,
    writer: anytype,
    label: []const u8,
    root: []const u8,
    tag_prefix: []const u8,
) !bool {
    const top = gitOutput(allocator, root, &[_][]const u8{ "rev-parse", "--show-toplevel" }) catch return false;
    defer allocator.free(top);
    if (top.len == 0) return false;
    try printGitSealAtRoot(allocator, writer, label, top, tag_prefix);
    return true;
}

fn printGitSeal(
    allocator: std.mem.Allocator,
    writer: anytype,
    label: []const u8,
    root: []const u8,
    tag_prefix: []const u8,
) !void {
    if (try printGitSealIfAvailable(allocator, writer, label, root, tag_prefix)) return;
    try writer.print("  - {s}: unavailable (git root not found)\n", .{label});
}

fn printGitSealAtRoot(
    allocator: std.mem.Allocator,
    writer: anytype,
    label: []const u8,
    root: []const u8,
    tag_prefix: []const u8,
) !void {
    const status = gitOutput(allocator, root, &[_][]const u8{ "status", "--short", "--untracked-files=all" }) catch |err| {
        try writer.print("  - {s}: unavailable ({s})\n", .{ label, @errorName(err) });
        return;
    };
    defer allocator.free(status);
    const head = gitOutput(allocator, root, &[_][]const u8{ "rev-parse", "--short", "HEAD" }) catch |err| {
        try writer.print("  - {s}: unavailable ({s})\n", .{ label, @errorName(err) });
        return;
    };
    defer allocator.free(head);
    const tags = gitOutput(allocator, root, &[_][]const u8{ "tag", "--points-at", "HEAD" }) catch |err| {
        try writer.print("  - {s}: unavailable ({s})\n", .{ label, @errorName(err) });
        return;
    };
    defer allocator.free(tags);

    const tag = firstTagWithPrefix(tags, tag_prefix) orelse "untagged";
    try writer.print("  - {s}: worktree={s} version={s} head={s}\n", .{
        label,
        if (status.len == 0) "clean" else "dirty",
        tag,
        head,
    });
}

fn gitOutput(allocator: std.mem.Allocator, root: []const u8, args: []const []const u8) ![]u8 {
    var argv = try std.ArrayList([]const u8).initCapacity(allocator, args.len + 3);
    defer argv.deinit();
    try argv.append("git");
    try argv.append("-C");
    try argv.append(root);
    try argv.appendSlice(args);

    const res = try process.runEngineCommand(allocator, argv.items);
    defer {
        allocator.free(res.stderr);
        allocator.free(res.stdout);
    }
    if (res.exit_code != 0) return error.GitCommandFailed;
    return allocator.dupe(u8, std.mem.trim(u8, res.stdout, " \t\r\n"));
}

fn firstTagWithPrefix(tags: []const u8, prefix: []const u8) ?[]const u8 {
    var lines = std.mem.splitScalar(u8, tags, '\n');
    while (lines.next()) |line| {
        if (std.mem.startsWith(u8, line, prefix)) return line;
    }
    return null;
}

fn inferEngineSourceRoot(allocator: std.mem.Allocator, engine_root: []const u8) !?[]u8 {
    const normalized = std.mem.trimRight(u8, engine_root, "/");
    const bin_parent = std.fs.path.dirname(normalized) orelse return null;
    const source_root = std.fs.path.dirname(bin_parent) orelse return null;
    return try allocator.dupe(u8, source_root);
}

fn jsonStringField(obj: std.json.ObjectMap, field: []const u8) ?[]const u8 {
    const value = obj.get(field) orelse return null;
    return if (value == .string) value.string else null;
}

fn jsonBoolField(obj: std.json.ObjectMap, field: []const u8) bool {
    const value = obj.get(field) orelse return false;
    return value == .bool and value.bool;
}

fn yesNo(value: bool) []const u8 {
    return if (value) "yes" else "no";
}
