const std = @import("std");
const builtin = @import("builtin");
const locator = @import("../engine/locator.zig");

// Core binaries: their absence sets ok=false.
// Non-core (index >= 4): tracked but do not affect ok.
const engine_binary_names = [_][]const u8{
    "ghost_task_operator",
    "ghost_code_intel",
    "ghost_patch_candidates",
    "ghost_knowledge_pack",
    "ghost_gip",
    "ghost_project_autopsy",
};
const engine_core_count = 4; // ghost_task_operator .. ghost_knowledge_pack

pub const Options = struct {
    json: bool = false,
    debug: bool = false,
    report: bool = false,
    full: bool = false,
    run_build_check: bool = false,
    version: []const u8,
};

const CommandProbe = struct {
    available: bool,
    output: []u8,

    fn deinit(self: *CommandProbe, allocator: std.mem.Allocator) void {
        allocator.free(self.output);
    }
};

const BinaryReport = struct {
    name: []const u8,
    path: []u8,
    exists: bool,
    executable: bool,
    candidates: [][]u8,

    fn deinit(self: *BinaryReport, allocator: std.mem.Allocator) void {
        allocator.free(self.path);
        for (self.candidates) |candidate| allocator.free(candidate);
        allocator.free(self.candidates);
    }
};

const DoctorReport = struct {
    version: []const u8,
    cli_path: []u8,
    cwd: []u8,
    env_engine_root: []u8,
    resolved_engine_root: []const u8,
    os: []const u8,
    arch: []const u8,
    term: []u8,
    path_ghost: []u8,
    global_ghost_kind: []u8,
    path_resolves_expected: bool,
    zig_version: CommandProbe,
    zig_build_check: CommandProbe,
    task_operator_smoke: CommandProbe,
    gip_status_smoke: CommandProbe,
    /// Smoke: ghost_project_autopsy --version (read-only, bounded, labeled smoke only).
    autopsy_smoke: CommandProbe,
    cpu: []u8,
    ram: []u8,
    gpu: []u8,
    binaries: []BinaryReport,
    ok: bool,

    fn deinit(self: *DoctorReport, allocator: std.mem.Allocator) void {
        allocator.free(self.cli_path);
        allocator.free(self.cwd);
        allocator.free(self.env_engine_root);
        allocator.free(self.term);
        allocator.free(self.path_ghost);
        allocator.free(self.global_ghost_kind);
        self.zig_version.deinit(allocator);
        self.zig_build_check.deinit(allocator);
        self.task_operator_smoke.deinit(allocator);
        self.gip_status_smoke.deinit(allocator);
        self.autopsy_smoke.deinit(allocator);
        allocator.free(self.cpu);
        allocator.free(self.ram);
        allocator.free(self.gpu);
        for (self.binaries) |*binary| binary.deinit(allocator);
        allocator.free(self.binaries);
    }
};

pub fn execute(allocator: std.mem.Allocator, engine_root: ?[]const u8, options: Options) !void {
    var report = try collectReport(allocator, engine_root, options);
    defer report.deinit(allocator);

    if (options.json) {
        try printJson(report, options.debug);
    } else if (options.report) {
        try printTesterReport(report, options.debug);
    } else {
        try printHuman(report, options.debug, options.full, options.run_build_check);
    }
}

fn collectReport(allocator: std.mem.Allocator, engine_root: ?[]const u8, options: Options) !DoctorReport {
    const cli_path = try getSelfExePath(allocator);
    const cwd = try getCwd(allocator);
    const env_engine_root = try getEnvOwned(allocator, "GHOST_ENGINE_ROOT");
    const term = try getEnvOwned(allocator, "TERM");
    const path_ghost = try commandOutput(allocator, &[_][]const u8{ "sh", "-c", "command -v ghost 2>/dev/null || true" });
    const trimmed_path_ghost = try allocator.dupe(u8, std.mem.trim(u8, path_ghost, " \r\n\t"));
    allocator.free(path_ghost);
    const global_kind = try detectGlobalGhostKind(allocator, trimmed_path_ghost);
    const path_expected = trimmed_path_ghost.len > 0 and std.mem.eql(u8, trimmed_path_ghost, cli_path);

    var binaries = std.ArrayList(BinaryReport).init(allocator);
    errdefer {
        for (binaries.items) |*binary| binary.deinit(allocator);
        binaries.deinit();
    }
    var all_core_ok = true;
    for (engine_binary_names, 0..) |name, index| {
        const binary = try collectBinaryReport(allocator, engine_root, name);
        // Only the first engine_core_count binaries determine ok.
        if (index < engine_core_count and !binary.executable) all_core_ok = false;
        try binaries.append(binary);
    }

    const zig_version = try probeCommand(allocator, &[_][]const u8{ "zig", "version" });
    const zig_build_check = if (options.run_build_check)
        try probeCommand(allocator, &[_][]const u8{ "zig", "build", "--help" })
    else
        CommandProbe{ .available = zig_version.available, .output = try allocator.dupe(u8, if (zig_version.available) "available; not run" else "zig not found") };

    const task_operator_path = findBinaryPath(binaries.items, "ghost_task_operator");
    const task_operator_smoke = if (task_operator_path) |path|
        try probeCommand(allocator, &[_][]const u8{ path, "--help" })
    else
        CommandProbe{ .available = false, .output = try allocator.dupe(u8, "ghost_task_operator not executable") };

    const gip_path = findBinaryPath(binaries.items, "ghost_gip");
    const gip_status_smoke = if (gip_path) |path|
        try probeCommand(allocator, &[_][]const u8{ path, "engine.status" })
    else
        CommandProbe{ .available = false, .output = try allocator.dupe(u8, "ghost_gip not available") };

    // Smoke only: ghost_project_autopsy --version
    // Read-only, bounded, labeled.  Does NOT run a scan; does NOT treat output as proof.
    const autopsy_path = findBinaryPath(binaries.items, "ghost_project_autopsy");
    const autopsy_smoke = if (autopsy_path) |path|
        try probeCommand(allocator, &[_][]const u8{ path, "--version" })
    else
        CommandProbe{ .available = false, .output = try allocator.dupe(u8, "ghost_project_autopsy not available") };

    const cpu = try detectCpu(allocator);
    const ram = try detectRam(allocator);
    const gpu = try detectGpu(allocator);

    return DoctorReport{
        .version = options.version,
        .cli_path = cli_path,
        .cwd = cwd,
        .env_engine_root = env_engine_root,
        .resolved_engine_root = engine_root orelse "Not Found",
        .os = @tagName(builtin.os.tag),
        .arch = @tagName(builtin.cpu.arch),
        .term = term,
        .path_ghost = trimmed_path_ghost,
        .global_ghost_kind = global_kind,
        .path_resolves_expected = path_expected,
        .zig_version = zig_version,
        .zig_build_check = zig_build_check,
        .task_operator_smoke = task_operator_smoke,
        .gip_status_smoke = gip_status_smoke,
        .autopsy_smoke = autopsy_smoke,
        .cpu = cpu,
        .ram = ram,
        .gpu = gpu,
        .binaries = try binaries.toOwnedSlice(),
        .ok = all_core_ok,
    };
}

fn collectBinaryReport(allocator: std.mem.Allocator, engine_root: ?[]const u8, name: []const u8) !BinaryReport {
    const candidates = try getCandidatePathsForName(allocator, engine_root, name);
    errdefer {
        for (candidates) |candidate| allocator.free(candidate);
        allocator.free(candidates);
    }

    var chosen: ?[]const u8 = null;
    var chosen_exists = false;
    var chosen_executable = false;
    const preferred_count: usize = if (engine_root != null) @min(candidates.len, 2) else candidates.len;
    for (candidates[0..preferred_count]) |candidate| {
        const exists = checkExists(candidate);
        const executable = checkExecutable(candidate);
        if (executable or (exists and chosen == null)) {
            chosen = candidate;
            chosen_exists = exists;
            chosen_executable = executable;
            if (executable) break;
        }
    }
    if (chosen == null and candidates.len > 0) {
        chosen = candidates[0];
        chosen_exists = checkExists(chosen.?);
        chosen_executable = checkExecutable(chosen.?);
    }

    return BinaryReport{
        .name = name,
        .path = try allocator.dupe(u8, chosen orelse name),
        .exists = chosen_exists,
        .executable = chosen_executable,
        .candidates = candidates,
    };
}

fn getCandidatePathsForName(allocator: std.mem.Allocator, engine_root: ?[]const u8, name: []const u8) ![][]u8 {
    if (std.mem.eql(u8, name, "ghost_task_operator")) return locator.getCandidatePaths(allocator, engine_root, .ghost_task_operator);
    if (std.mem.eql(u8, name, "ghost_code_intel")) return locator.getCandidatePaths(allocator, engine_root, .ghost_code_intel);
    if (std.mem.eql(u8, name, "ghost_patch_candidates")) return locator.getCandidatePaths(allocator, engine_root, .ghost_patch_candidates);
    if (std.mem.eql(u8, name, "ghost_knowledge_pack")) return locator.getCandidatePaths(allocator, engine_root, .ghost_knowledge_pack);
    if (std.mem.eql(u8, name, "ghost_project_autopsy")) return locator.getCandidatePaths(allocator, engine_root, .ghost_project_autopsy);

    var list = std.ArrayList([]u8).init(allocator);
    errdefer {
        for (list.items) |item| allocator.free(item);
        list.deinit();
    }
    if (engine_root) |root| {
        try list.append(try std.fs.path.join(allocator, &[_][]const u8{ root, name }));
        try list.append(try std.fs.path.join(allocator, &[_][]const u8{ root, "zig-out", "bin", name }));
    }
    try list.append(try std.fs.path.join(allocator, &[_][]const u8{ "../ghost_engine/zig-out/bin", name }));
    try list.append(try allocator.dupe(u8, name));
    return list.toOwnedSlice();
}

fn printHuman(report: DoctorReport, debug: bool, full: bool, run_build_check: bool) !void {
    const out = std.io.getStdOut().writer();
    try out.print("--- Ghost Doctor ---\n", .{});
    try out.print("Result: {s}\n", .{if (report.ok) "OK" else "ISSUES FOUND"});
    try out.print("Ghost Version: {s}\n", .{report.version});
    try out.print("CLI Binary: {s}\n", .{report.cli_path});
    try out.print("Current Directory: {s}\n", .{report.cwd});
    try out.print("GHOST_ENGINE_ROOT: {s}\n", .{if (report.env_engine_root.len > 0) report.env_engine_root else "Not Set"});
    try out.print("Resolved Engine Root: {s}\n", .{report.resolved_engine_root});
    try out.print("OS / Arch: {s} / {s}\n", .{ report.os, report.arch });
    try out.print("Terminal: {s}\n", .{if (report.term.len > 0) report.term else "Unknown"});
    try out.print("PATH ghost: {s}\n", .{if (report.path_ghost.len > 0) report.path_ghost else "Not Found"});
    try out.print("Global ghost kind: {s}\n", .{report.global_ghost_kind});
    try out.print("PATH resolves this binary: {s}\n", .{yesNo(report.path_resolves_expected)});
    try out.print("Zig: {s}\n", .{if (report.zig_version.available) std.mem.trim(u8, report.zig_version.output, " \r\n\t") else "Not Found"});
    if (full or run_build_check) {
        try out.print("zig build check: {s}\n", .{std.mem.trim(u8, report.zig_build_check.output, " \r\n\t")});
    }

    try out.print("\nEngine Binaries:\n", .{});
    for (report.binaries) |binary| {
        try out.print("  - {s}: {s} ({s})\n", .{ binary.name, if (binary.executable) "EXECUTABLE" else if (binary.exists) "FOUND_NOT_EXECUTABLE" else "MISSING", binary.path });
        if (debug) {
            try out.print("    candidates:\n", .{});
            for (binary.candidates) |candidate| {
                try out.print("      - {s} [{s}]\n", .{ candidate, if (checkExecutable(candidate)) "executable" else if (checkExists(candidate)) "found" else "missing" });
            }
        }
    }

    try out.print("\nSmoke Checks (read-only, no scanning performed):\n", .{});
    try out.print("  - ghost_task_operator --help: {s}\n", .{if (report.task_operator_smoke.available) "ok" else "unavailable/failed"});
    try out.print("  - ghost_gip engine.status: {s}\n", .{if (report.gip_status_smoke.available) "ok" else "unavailable/failed"});
    try out.print("  - ghost_project_autopsy --version [smoke only]: {s}\n", .{if (report.autopsy_smoke.available) "ok" else "unavailable/not-installed"});
    try out.print("\nNo mutation performed. No scan was run. {s}\n", .{if (run_build_check) "`zig build --help` was run; no build artifacts were requested." else "No build was run."});
    if (!report.ok) {
        try out.print("\nSuggested next steps:\n", .{});
        try out.print("  1. Build ghost_engine: cd <ghost_engine> && zig build\n", .{});
        try out.print("  2. Set GHOST_ENGINE_ROOT to the ghost_engine repo root or zig-out/bin\n", .{});
        try out.print("  3. Run ghost status\n", .{});
    }
}

fn printTesterReport(report: DoctorReport, debug: bool) !void {
    const out = std.io.getStdOut().writer();
    try out.print("Ghost Tester Report\n", .{});
    try out.print("===================\n", .{});
    try out.print("Doctor result: {s}\n", .{if (report.ok) "OK" else "ISSUES FOUND"});
    try out.print("OS: {s}\n", .{report.os});
    try out.print("Arch: {s}\n", .{report.arch});
    try out.print("CPU: {s}\n", .{report.cpu});
    try out.print("RAM: {s}\n", .{report.ram});
    try out.print("GPU: {s}\n", .{report.gpu});
    try out.print("Zig version: {s}\n", .{if (report.zig_version.available) std.mem.trim(u8, report.zig_version.output, " \r\n\t") else "unknown"});
    try out.print("Ghost version: {s}\n", .{report.version});
    try out.print("CLI path: {s}\n", .{report.cli_path});
    try out.print("Engine root: {s}\n", .{report.resolved_engine_root});
    try out.print("GHOST_ENGINE_ROOT: {s}\n", .{if (report.env_engine_root.len > 0) report.env_engine_root else "Not Set"});
    try out.print("PATH ghost: {s}\n", .{if (report.path_ghost.len > 0) report.path_ghost else "Not Found"});
    try out.print("\nResolved binaries:\n", .{});
    for (report.binaries) |binary| {
        try out.print("- {s}: {s} ({s})\n", .{ binary.name, if (binary.executable) "executable" else if (binary.exists) "found-not-executable" else "missing", binary.path });
        if (debug) {
            for (binary.candidates) |candidate| try out.print("  candidate: {s}\n", .{candidate});
        }
    }
    try out.print("ghost_project_autopsy: {s}\n", .{if (report.autopsy_smoke.available) "available" else "not-installed"});
    try out.print("\nSuggested next commands:\n", .{});
    try out.print("1. ghost status\n", .{});
    try out.print("2. ghost ask hello --debug\n", .{});
    try out.print("3. ghost tui\n", .{});
}

fn printJson(report: DoctorReport, debug: bool) !void {
    const out = std.io.getStdOut().writer();
    try out.writeAll("{");
    try jsonField(out, "version", report.version, true);
    try jsonField(out, "cli_path", report.cli_path, false);
    try jsonField(out, "cwd", report.cwd, false);
    try jsonField(out, "ghost_engine_root_env", if (report.env_engine_root.len > 0) report.env_engine_root else null, false);
    try jsonField(out, "resolved_engine_root", report.resolved_engine_root, false);
    try jsonField(out, "os", report.os, false);
    try jsonField(out, "arch", report.arch, false);
    try jsonField(out, "terminal", report.term, false);
    try jsonField(out, "path_ghost", report.path_ghost, false);
    try jsonField(out, "global_ghost_kind", report.global_ghost_kind, false);
    try out.print(",\"path_resolves_expected\":{}", .{report.path_resolves_expected});
    try jsonField(out, "zig_version", if (report.zig_version.available) std.mem.trim(u8, report.zig_version.output, " \r\n\t") else null, false);
    try out.print(",\"doctor_result\":\"{s}\"", .{if (report.ok) "ok" else "issues_found"});
    try out.writeAll(",\"binaries\":[");
    for (report.binaries, 0..) |binary, i| {
        if (i > 0) try out.writeAll(",");
        try out.writeAll("{");
        try jsonField(out, "name", binary.name, true);
        try jsonField(out, "path", binary.path, false);
        try out.print(",\"exists\":{},\"executable\":{}", .{ binary.exists, binary.executable });
        if (debug) {
            try out.writeAll(",\"candidates\":[");
            for (binary.candidates, 0..) |candidate, j| {
                if (j > 0) try out.writeAll(",");
                try writeJsonString(out, candidate);
            }
            try out.writeAll("]");
        }
        try out.writeAll("}");
    }
    try out.writeAll("]");
    try out.print(",\"smoke\":{{\"ghost_task_operator_help\":{},\"ghost_gip_engine_status\":{},\"ghost_project_autopsy_version_smoke\":{}}}", .{ report.task_operator_smoke.available, report.gip_status_smoke.available, report.autopsy_smoke.available });
    try out.writeAll("}\n");
}

fn jsonField(writer: anytype, name: []const u8, value: ?[]const u8, first: bool) !void {
    if (!first) try writer.writeAll(",");
    try writeJsonString(writer, name);
    try writer.writeAll(":");
    if (value) |v| {
        try writeJsonString(writer, v);
    } else {
        try writer.writeAll("null");
    }
}

fn writeJsonString(writer: anytype, value: []const u8) !void {
    try writer.writeByte('"');
    for (value) |c| {
        switch (c) {
            '\\' => try writer.writeAll("\\\\"),
            '"' => try writer.writeAll("\\\""),
            '\n' => try writer.writeAll("\\n"),
            '\r' => try writer.writeAll("\\r"),
            '\t' => try writer.writeAll("\\t"),
            else => try writer.writeByte(c),
        }
    }
    try writer.writeByte('"');
}

fn findBinaryPath(binaries: []BinaryReport, name: []const u8) ?[]const u8 {
    for (binaries) |binary| {
        if (std.mem.eql(u8, binary.name, name) and binary.executable) return binary.path;
    }
    return null;
}

fn getSelfExePath(allocator: std.mem.Allocator) ![]u8 {
    var buf: [std.fs.max_path_bytes]u8 = undefined;
    const path = std.fs.selfExePath(&buf) catch return allocator.dupe(u8, "Unknown");
    return allocator.dupe(u8, path);
}

fn getCwd(allocator: std.mem.Allocator) ![]u8 {
    var buf: [std.fs.max_path_bytes]u8 = undefined;
    const cwd = std.fs.cwd().realpath(".", &buf) catch return allocator.dupe(u8, "Unknown");
    return allocator.dupe(u8, cwd);
}

fn getEnvOwned(allocator: std.mem.Allocator, name: []const u8) ![]u8 {
    return std.process.getEnvVarOwned(allocator, name) catch |err| switch (err) {
        error.EnvironmentVariableNotFound => allocator.dupe(u8, ""),
        else => allocator.dupe(u8, "Unknown"),
    };
}

fn probeCommand(allocator: std.mem.Allocator, argv: []const []const u8) !CommandProbe {
    const result = std.process.Child.run(.{
        .allocator = allocator,
        .argv = argv,
        .max_output_bytes = 128 * 1024,
    }) catch |err| {
        return CommandProbe{ .available = false, .output = try std.fmt.allocPrint(allocator, "failed: {}", .{err}) };
    };
    defer allocator.free(result.stderr);
    const exit_ok = switch (result.term) {
        .Exited => |code| code == 0,
        else => false,
    };
    if (result.stdout.len > 0) {
        return CommandProbe{ .available = exit_ok, .output = result.stdout };
    }
    allocator.free(result.stdout);
    return CommandProbe{ .available = exit_ok, .output = try allocator.dupe(u8, result.stderr) };
}

fn commandOutput(allocator: std.mem.Allocator, argv: []const []const u8) ![]u8 {
    var probe = try probeCommand(allocator, argv);
    defer probe.deinit(allocator);
    return allocator.dupe(u8, probe.output);
}

fn detectGlobalGhostKind(allocator: std.mem.Allocator, ghost_path: []const u8) ![]u8 {
    if (ghost_path.len == 0) return allocator.dupe(u8, "not-found");
    const out = try commandOutput(allocator, &[_][]const u8{ "sh", "-c", "if [ -L \"$1\" ]; then printf symlink; else printf local-binary; fi", "sh", ghost_path });
    defer allocator.free(out);
    return allocator.dupe(u8, std.mem.trim(u8, out, " \r\n\t"));
}

fn detectCpu(allocator: std.mem.Allocator) ![]u8 {
    if (builtin.os.tag == .linux) {
        const out = try commandOutput(allocator, &[_][]const u8{ "sh", "-c", "grep -m1 'model name' /proc/cpuinfo 2>/dev/null | cut -d: -f2- || true" });
        defer allocator.free(out);
        const trimmed = std.mem.trim(u8, out, " \r\n\t");
        if (trimmed.len > 0) return allocator.dupe(u8, trimmed);
    }
    return allocator.dupe(u8, "unknown");
}

fn detectRam(allocator: std.mem.Allocator) ![]u8 {
    if (builtin.os.tag == .linux) {
        const out = try commandOutput(allocator, &[_][]const u8{ "sh", "-c", "awk '/MemTotal/ { printf \"%.1f GiB\", $2 / 1024 / 1024 }' /proc/meminfo 2>/dev/null || true" });
        defer allocator.free(out);
        const trimmed = std.mem.trim(u8, out, " \r\n\t");
        if (trimmed.len > 0) return allocator.dupe(u8, trimmed);
    }
    return allocator.dupe(u8, "unknown");
}

fn detectGpu(allocator: std.mem.Allocator) ![]u8 {
    if (builtin.os.tag == .linux) {
        var out = try commandOutput(allocator, &[_][]const u8{ "sh", "-c", "command -v nvidia-smi >/dev/null 2>&1 && nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null | head -n1 || true" });
        var trimmed = std.mem.trim(u8, out, " \r\n\t");
        if (trimmed.len > 0 and std.mem.indexOf(u8, trimmed, "failed") == null and std.mem.indexOf(u8, trimmed, "couldn't communicate") == null) return out;
        allocator.free(out);
        out = try commandOutput(allocator, &[_][]const u8{ "sh", "-c", "command -v lspci >/dev/null 2>&1 && lspci 2>/dev/null | grep -Ei 'vga|3d|display' | head -n1 || true" });
        trimmed = std.mem.trim(u8, out, " \r\n\t");
        if (trimmed.len > 0) return out;
        allocator.free(out);
    }
    return allocator.dupe(u8, "unknown");
}

fn checkExists(path: []const u8) bool {
    if (std.mem.indexOfScalar(u8, path, std.fs.path.sep) == null) return pathExecutableOnPath(path);
    var file = std.fs.cwd().openFile(path, .{}) catch return false;
    file.close();
    return true;
}

fn checkExecutable(path: []const u8) bool {
    if (std.mem.indexOfScalar(u8, path, std.fs.path.sep) == null) return pathExecutableOnPath(path);
    var file = std.fs.cwd().openFile(path, .{}) catch return false;
    file.close();
    std.posix.access(path, std.posix.X_OK) catch return false;
    return true;
}

fn pathExecutableOnPath(name: []const u8) bool {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var probe = probeCommand(allocator, &[_][]const u8{ "sh", "-c", "command -v \"$1\" >/dev/null 2>&1", "sh", name }) catch return false;
    defer probe.deinit(allocator);
    return probe.available;
}

fn yesNo(value: bool) []const u8 {
    return if (value) "yes" else "no";
}
