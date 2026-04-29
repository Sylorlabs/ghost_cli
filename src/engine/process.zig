const std = @import("std");

pub const ProcessResult = struct {
    stdout: []u8,
    stderr: []u8,
    exit_code: u8,
};

pub fn runEngineCommand(allocator: std.mem.Allocator, args: []const []const u8) !ProcessResult {
    const result = try std.process.Child.run(.{
        .allocator = allocator,
        .argv = args,
        .max_output_bytes = 10 * 1024 * 1024, // 10MB
    });

    const exit_code = switch (result.term) {
        .Exited => |code| code,
        else => 1,
    };

    return ProcessResult{
        .stdout = result.stdout,
        .stderr = result.stderr,
        .exit_code = exit_code,
    };
}

pub fn runEngineCommandWithInput(allocator: std.mem.Allocator, args: []const []const u8, stdin_payload: []const u8) !ProcessResult {
    var child = std.process.Child.init(args, allocator);
    child.stdin_behavior = .Pipe;
    child.stdout_behavior = .Pipe;
    child.stderr_behavior = .Pipe;

    try child.spawn();
    try child.stdin.?.writeAll(stdin_payload);
    child.stdin.?.close();
    child.stdin = null;

    const stdout = try child.stdout.?.reader().readAllAlloc(allocator, 10 * 1024 * 1024);
    errdefer allocator.free(stdout);
    const stderr = try child.stderr.?.reader().readAllAlloc(allocator, 10 * 1024 * 1024);
    errdefer allocator.free(stderr);

    const term = try child.wait();
    const exit_code = switch (term) {
        .Exited => |code| code,
        else => 1,
    };

    return .{
        .stdout = stdout,
        .stderr = stderr,
        .exit_code = exit_code,
    };
}
