const std = @import("std");
const runner = @import("../engine/runner.zig");
const locator = @import("../engine/locator.zig");
const process = @import("../engine/process.zig");
const json_contracts = @import("../engine/json_contracts.zig");
const terminal = @import("../render/terminal.zig");

pub const PacksOptions = struct {
    subcommand: []const u8,
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

const ValidationLimitFlags = struct {
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
        const resolved_manifest = try std.fs.path.resolve(allocator, &.{manifest});
        defer allocator.free(resolved_manifest);
        const arg = try std.fmt.allocPrint(allocator, "--manifest={s}", .{resolved_manifest});
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

fn printDebugArgv(writer: anytype, label: []const u8, argv: []const []const u8) !void {
    try writer.print("[DEBUG] {s}=", .{label});
    for (argv, 0..) |arg, idx| {
        if (idx != 0) try writer.print(" ", .{});
        try writer.print("'{s}'", .{arg});
    }
    try writer.print("\n", .{});
}
