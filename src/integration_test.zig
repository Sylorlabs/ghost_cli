const std = @import("std");
const testing = std.testing;

fn runCmd(allocator: std.mem.Allocator, args: []const []const u8) !std.process.Child.RunResult {
    return std.process.Child.run(.{
        .allocator = allocator,
        .argv = args,
        .max_output_bytes = 10 * 1024 * 1024,
    });
}

test "help text lists all top-level commands" {
    const res = try runCmd(testing.allocator, &[_][]const u8{ "./zig-out/bin/ghost", "--help" });
    defer {
        testing.allocator.free(res.stdout);
        testing.allocator.free(res.stderr);
    }
    // help text goes to stderr via std.debug.print
    try testing.expect(std.mem.indexOf(u8, res.stderr, "chat") != null);
    try testing.expect(std.mem.indexOf(u8, res.stderr, "ask") != null);
    try testing.expect(std.mem.indexOf(u8, res.stderr, "fix") != null);
    try testing.expect(std.mem.indexOf(u8, res.stderr, "verify") != null);
    try testing.expect(std.mem.indexOf(u8, res.stderr, "packs") != null);
    try testing.expect(std.mem.indexOf(u8, res.stderr, "learn") != null);
    try testing.expect(std.mem.indexOf(u8, res.stderr, "status") != null);
    try testing.expect(std.mem.indexOf(u8, res.stderr, "debug") != null);
}

test "version flag works" {
    const res = try runCmd(testing.allocator, &[_][]const u8{ "./zig-out/bin/ghost", "--version" });
    defer {
        testing.allocator.free(res.stdout);
        testing.allocator.free(res.stderr);
    }
    try testing.expect(std.mem.indexOf(u8, res.stderr, "ghost_cli v0.1.0-hardened") != null);
}

test "engine root resolution - repo root case" {
    const mock_root = "/tmp/ghost-mock-repo";
    try std.fs.cwd().makePath(mock_root ++ "/zig-out/bin");
    const mock_bin = mock_root ++ "/zig-out/bin/ghost_task_operator";
    const file = try std.fs.cwd().createFile(mock_bin, .{});
    file.close();
    
    const res = try runCmd(testing.allocator, &[_][]const u8{ 
        "./zig-out/bin/ghost", 
        "status", 
        "--engine-root=" ++ mock_root, 
        "--debug" 
    });
    defer {
        testing.allocator.free(res.stdout);
        testing.allocator.free(res.stderr);
        std.fs.cwd().deleteTree(mock_root) catch {};
    }
    
    try testing.expect(std.mem.indexOf(u8, res.stdout, "[FOUND]    " ++ mock_bin) != null);
}

test "status debug mode shows candidate paths" {
    const res = try runCmd(testing.allocator, &[_][]const u8{ 
        "./zig-out/bin/ghost", 
        "status", 
        "--engine-root=/tmp/nonexistent", 
        "--debug" 
    });
    defer {
        testing.allocator.free(res.stdout);
        testing.allocator.free(res.stderr);
    }
    
    try testing.expect(std.mem.indexOf(u8, res.stdout, "/tmp/nonexistent/ghost_task_operator") != null);
    try testing.expect(std.mem.indexOf(u8, res.stdout, "/tmp/nonexistent/zig-out/bin/ghost_task_operator") != null);
    try testing.expect(std.mem.indexOf(u8, res.stdout, "ghost_task_operator") != null);
}

test "missing required learn flags fail clearly" {
    const res = try runCmd(testing.allocator, &[_][]const u8{ "./zig-out/bin/ghost", "learn", "candidates" });
    defer {
        testing.allocator.free(res.stdout);
        testing.allocator.free(res.stderr);
    }
    try testing.expect(res.term.Exited != 0);
    try testing.expect(std.mem.indexOf(u8, res.stderr, "--project-shard is required") != null);
}

test "missing required pack args fail clearly" {
    const res = try runCmd(testing.allocator, &[_][]const u8{ "./zig-out/bin/ghost", "packs", "inspect" });
    defer {
        testing.allocator.free(res.stdout);
        testing.allocator.free(res.stderr);
    }
    try testing.expect(res.term.Exited != 0);
    try testing.expect(std.mem.indexOf(u8, res.stderr, "Usage: ghost packs inspect <pack-id>") != null);
}
