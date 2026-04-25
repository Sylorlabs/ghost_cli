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

    // 3. Config file path, if implemented: ~/.config/ghost/config.toml (TODO)
    
    // 4. PATH lookup for engine binaries (Will handle in locator if root is null, or just rely on locator)
    
    // 5. Relative development path: ../ghost_engine/zig-out/bin/
    const dev_path = "../ghost_engine/zig-out/bin";
    var dir = std.fs.cwd().openDir(dev_path, .{}) catch null;
    if (dir) |*d| {
        d.close();
        return EnginePaths{ .root = try allocator.dupe(u8, dev_path) };
    }

    return null;
}
