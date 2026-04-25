const std = @import("std");
const runner = @import("../engine/runner.zig");
const json_contracts = @import("../engine/json_contracts.zig");
const terminal = @import("../render/terminal.zig");

pub const ContextOptions = struct {
    message: ?[]const u8 = null,
    reasoning: ?json_contracts.ReasoningLevel = null,
    context_artifact: ?[]const u8 = null,
    json: bool = false,
    debug: bool = false,
};

pub fn execute(allocator: std.mem.Allocator, engine_root: ?[]const u8, options: ContextOptions) !void {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const aa = arena.allocator();

    var argv = std.ArrayList([]const u8).init(aa);
    
    try argv.append("chat");
    
    if (options.message) |msg| {
        try argv.append("--message");
        try argv.append(msg);
    }

    if (options.reasoning) |level| {
        var buf: [64]u8 = undefined;
        const level_arg = try std.fmt.bufPrint(&buf, "--reasoning={s}", .{level.toStr()});
        try argv.append(try aa.dupe(u8, level_arg));
    }

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
        std.process.exit(res.exit_code);
    }

    if (res.stdout.len > 0) {
        if (json_contracts.parseEngineJson(allocator, res.stdout)) |parsed| {
            defer parsed.deinit();
            if (options.debug) std.debug.print("[DEBUG] JSON Parse: SUCCESS\n", .{});
            try terminal.printEngineOutput(std.io.getStdOut().writer(), parsed.value);
        } else |err| {
            if (options.debug) std.debug.print("[DEBUG] JSON Parse: FAILED ({})\n", .{err});
            std.debug.print("\x1b[31m[!] Error:\x1b[0m Failed to parse engine JSON.\n", .{});
            std.debug.print("\x1b[33mRaw Output:\x1b[0m\n{s}\n", .{res.stdout});
        }
    }

    if (res.stderr.len > 0) {
        std.debug.print("{s}\n", .{res.stderr});
    }
}
