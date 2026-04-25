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
