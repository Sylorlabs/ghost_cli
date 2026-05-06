const std = @import("std");

pub const EnginePaths = struct {
    root: []const u8,

    pub fn deinit(self: *EnginePaths, allocator: std.mem.Allocator) void {
        allocator.free(self.root);
    }
};

pub fn discoverEngineRoot(allocator: std.mem.Allocator, explicit_flag: ?[]const u8) !?EnginePaths {
    // 1. Explicit CLI flag: --engine-root=<path>
    if (explicit_flag) |path| {
        return EnginePaths{ .root = try allocator.dupe(u8, path) };
    }

    // 2. Environment variable: GHOST_ENGINE_ROOT
    if (std.posix.getenv("GHOST_ENGINE_ROOT")) |env_path| {
        return EnginePaths{ .root = try allocator.dupe(u8, env_path) };
    }

    // 3. Config file path: ~/.config/ghost/config.toml or ghost_config.toml
    if (try discoverConfiguredEngineRoot(allocator)) |path| {
        return EnginePaths{ .root = path };
    }

    // 4. Relative to the CLI executable (Canonical Path Auto-Detection)
    if (std.fs.selfExeDirPathAlloc(allocator) catch null) |exe_dir| {
        defer allocator.free(exe_dir);
        const p1 = std.fs.path.dirname(exe_dir) orelse exe_dir; // up to zig-out/
        const project_root = std.fs.path.dirname(p1) orelse p1; // up to ghost_cli/
        const workspace_root = std.fs.path.dirname(project_root) orelse project_root; // up to sylorlabs projects/

        // Construct path to adjacent ghost_engine
        const adjacent_engine = try std.fs.path.join(allocator, &.{ workspace_root, "ghost_engine" });
        var dir = std.fs.cwd().openDir(adjacent_engine, .{}) catch null;
        if (dir) |*d| {
            d.close();
            return EnginePaths{ .root = adjacent_engine };
        }
        allocator.free(adjacent_engine);
    }

    // 5. Relative development path: ../ghost_engine/zig-out/bin/
    const dev_path = "../ghost_engine/zig-out/bin";
    var dir = std.fs.cwd().openDir(dev_path, .{}) catch null;
    if (dir) |*d| {
        d.close();
        return EnginePaths{ .root = try allocator.dupe(u8, dev_path) };
    }

    return null;
}

fn discoverConfiguredEngineRoot(allocator: std.mem.Allocator) !?[]u8 {
    const home = std.posix.getenv("HOME") orelse return null;
    const candidates = [_][]const u8{
        ".config/ghost/config.toml",
        ".config/ghost/ghost_config.toml",
    };
    for (candidates) |candidate| {
        const path = try std.fs.path.join(allocator, &.{ home, candidate });
        defer allocator.free(path);
        if (try readEngineRootFromConfig(allocator, path)) |root| return root;
    }
    return null;
}

fn readEngineRootFromConfig(allocator: std.mem.Allocator, path: []const u8) !?[]u8 {
    const file = std.fs.openFileAbsolute(path, .{}) catch |err| switch (err) {
        error.FileNotFound => return null,
        else => return err,
    };
    defer file.close();
    const stat = try file.stat();
    const bytes = try file.readToEndAlloc(allocator, @intCast(@min(stat.size, 64 * 1024)));
    defer allocator.free(bytes);

    var it = std.mem.splitScalar(u8, bytes, '\n');
    while (it.next()) |line_raw| {
        const line = std.mem.trim(u8, line_raw, " \r\t");
        if (line.len == 0 or line[0] == '#') continue;
        if (!std.mem.startsWith(u8, line, "engine_root") and !std.mem.startsWith(u8, line, "engine_path")) continue;
        const eq = std.mem.indexOfScalar(u8, line, '=') orelse continue;
        var value = std.mem.trim(u8, line[eq + 1 ..], " \r\t");
        if (std.mem.indexOfScalar(u8, value, '#')) |comment| {
            value = std.mem.trim(u8, value[0..comment], " \r\t");
        }
        value = std.mem.trim(u8, value, "\"'");
        if (value.len == 0) return null;
        return try allocator.dupe(u8, value);
    }
    return null;
}
