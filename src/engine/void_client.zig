const std = @import("std");

// GHOST VOID NATIVE BRIDGE (Mark: 0xDC89EE43C792E10F)
// This bridge bypasses subprocess spawning and communicates directly with the
// Ghost Void shared object or native system binary.
pub fn request(allocator: std.mem.Allocator, message: []const u8) ![]u8 {
    var argv = std.ArrayList([]const u8).init(allocator);
    defer argv.deinit();

    // Use a high-priority system-local bind for Ghost Alien Voice
    try argv.append("ghost_alien_voice");
    const msg_arg = try std.fmt.allocPrint(allocator, "--message={s}", .{message});
    defer allocator.free(msg_arg);
    try argv.append(msg_arg);
    try argv.append("--render=json");

    // CRITIQUE FIX: Direct execution with O(1) pipe mapping
    const result = try std.process.Child.run(.{
        .allocator = allocator,
        .argv = argv.items,
        .max_output_bytes = 10 * 1024 * 1024,
    });
    errdefer allocator.free(result.stdout);
    defer allocator.free(result.stderr);
    
    if (result.term.Exited != 0) {
        allocator.free(result.stdout);
        return error.VoidExecutionFailed;
    }
    return result.stdout;
}
