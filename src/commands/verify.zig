const std = @import("std");
const runner = @import("../engine/runner.zig");
const json_contracts = @import("../engine/json_contracts.zig");
const terminal = @import("../render/terminal.zig");

pub const VerifyOptions = struct {
    reasoning: ?json_contracts.ReasoningLevel = null,
    context_artifact: ?[]const u8 = null,
    json: bool = false,
    debug: bool = false,
};

pub fn execute(allocator: std.mem.Allocator, engine_root: ?[]const u8, options: VerifyOptions) !void {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const aa = arena.allocator();

    var argv = std.ArrayList([]const u8).init(aa);
    
    // We use chat command as the verify endpoint per requirements if no dedicated verify exists
    try argv.append("chat");
    try argv.append("--message");
    try argv.append("verify current workspace/task");
    
    const reasoning = options.reasoning orelse .deep;
    var buf: [64]u8 = undefined;
    const reasoning_arg = try std.fmt.bufPrint(&buf, "--reasoning={s}", .{reasoning.toStr()});
    try argv.append(try aa.dupe(u8, reasoning_arg));

    if (options.context_artifact) |art| {
        try argv.append("--context-artifact");
        try argv.append(art);
    }

    try argv.append("--render=json");

    const res = try runner.run(allocator, .{
        .engine_root = engine_root,
        .binary = .ghost_task_operator,
        .argv = argv.items,
        .json = true,
        .debug = options.debug,
    });
    defer res.deinit();

    if (options.json) {
        std.debug.print("{s}\n", .{res.stdout});
        if (res.stderr.len > 0) std.debug.print("{s}\n", .{res.stderr});
        if (res.exit_code != 0) std.process.exit(res.exit_code);
        return;
    }

    if (res.exit_code != 0) {
        // runner.run already printed failure if not json, but we might want to exit
        std.process.exit(res.exit_code);
    }

    if (res.stdout.len > 0) {
        if (json_contracts.parseEngineJson(allocator, res.stdout)) |parsed| {
            defer parsed.deinit();
            try terminal.printEngineOutput(std.io.getStdOut().writer(), parsed.value);
        } else |err| {
            if (options.debug) std.debug.print("[DEBUG] JSON Parse FAILED: {}\n", .{err});
            std.debug.print("\x1b[31m[!] Error:\x1b[0m Failed to parse engine JSON.\n", .{});
            std.debug.print("\x1b[33mRaw Output:\x1b[0m\n{s}\n", .{res.stdout});
        }
    }
}
