const std = @import("std");
const paths = @import("../config/paths.zig");
const locator = @import("../engine/locator.zig");

pub fn execute(allocator: std.mem.Allocator, engine_root: ?[]const u8, debug: bool, build_version: []const u8) !void {
    const stdout = std.io.getStdOut().writer();

    try stdout.print("--- Ghost CLI Status ---\n", .{});
    try stdout.print("Scope: engine availability/status. Use `ghost doctor` for full tester diagnostics.\n", .{});
    try stdout.print("Build Version: {s}\n", .{build_version});
    var self_exe_path_buf: [1024]u8 = undefined;
    const self_exe_path = std.fs.selfExePath(&self_exe_path_buf) catch "Unknown";
    try stdout.print("CLI Binary: {s}\n", .{self_exe_path});

    // 2. Engine Root Resolution
    try stdout.print("Engine Root: {s}\n", .{engine_root orelse "Not Found"});

    // 3. Engine Binaries
    try stdout.print("\nEngine Binaries:\n", .{});

    var all_found = true;
    inline for (@typeInfo(locator.EngineBinaries).@"enum".fields) |field| {
        const enum_val = @field(locator.EngineBinaries, field.name);

        if (debug) {
            try stdout.print("  - {s}:\n", .{field.name});
            const candidates = try locator.getCandidatePaths(allocator, engine_root, enum_val);
            defer {
                for (candidates) |c| allocator.free(c);
                allocator.free(candidates);
            }

            var found_this = false;
            for (candidates) |cand| {
                const exists = locator.checkBinaryExists(cand);
                const mark = if (exists) "[FOUND]" else "[MISSING]";
                try stdout.print("    {s:<10} {s}\n", .{ mark, cand });
                if (exists) found_this = true;
            }
            if (!found_this) all_found = false;
        } else {
            const bin_path = try locator.findEngineBinary(allocator, engine_root, enum_val);
            defer allocator.free(bin_path);

            const exists = locator.checkBinaryExists(bin_path);
            const status_str = if (exists) "FOUND" else "MISSING";

            try stdout.print("  - {s}: {s}\n", .{ field.name, status_str });
            try stdout.print("    Path: {s}\n", .{bin_path});

            if (!exists) all_found = false;
        }
    }

    if (!all_found) {
        try stdout.print("\n\x1b[31m[!] Some engine binaries are missing.\x1b[0m\n", .{});
        if (engine_root) |root| {
            try stdout.print("\x1b[33mHint:\x1b[0m If GHOST_ENGINE_ROOT points to the repo root ({s}), run `zig build` in ghost_engine.\n", .{root});
        }
        try stdout.print("\x1b[33mFix:\x1b[0m Set GHOST_ENGINE_ROOT environment variable or use --engine-root=<path>.\n", .{});
    } else {
        try stdout.print("\n\x1b[32m[+] All engine binaries located successfully.\x1b[0m\n", .{});
    }

    // 4. Working Directory
    var cwd_buf: [1024]u8 = undefined;
    const cwd = std.fs.cwd().realpath(".", &cwd_buf) catch "Unknown";
    try stdout.print("\nWorking Directory: {s}\n", .{cwd});
}
