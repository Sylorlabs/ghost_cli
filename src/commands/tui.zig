const std = @import("std");
const app = @import("../tui/app.zig");
const state = @import("../tui/state.zig");
const json_contracts = @import("../engine/json_contracts.zig");

pub const ColorMode = enum {
    auto,
    always,
    never,
};

pub const TuiOptions = struct {
    reasoning: ?json_contracts.ReasoningLevel = null,
    context_artifact: ?[]const u8 = null,
    debug: bool = false,
    color: ColorMode = .auto,
    compact: bool = false,
    read_only: bool = false,
    max_history_turns: usize = state.default_max_history_turns,
    version: []const u8,
    engine_root_label: ?[]const u8 = null,
};

pub fn execute(allocator: std.mem.Allocator, engine_root: ?[]const u8, options: TuiOptions) !void {
    try app.run(allocator, engine_root, .{
        .reasoning = options.reasoning,
        .context_artifact = options.context_artifact,
        .debug = options.debug,
        .color = switch (options.color) {
            .auto => .auto,
            .always => .always,
            .never => .never,
        },
        .compact = options.compact,
        .read_only = options.read_only,
        .max_history_turns = options.max_history_turns,
        .version = options.version,
        .engine_root_label = options.engine_root_label,
    });
}
