const std = @import("std");
const locator = @import("../engine/locator.zig");
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

    var cwd_buf: [1024]u8 = undefined;
    const cwd = std.fs.cwd().realpath(".", &cwd_buf) catch "Unknown";
    try stdout.print("\nWorking Directory: {s}\n", .{cwd});
}

fn yesNo(value: bool) []const u8 {
    return if (value) "yes" else "no";
}
