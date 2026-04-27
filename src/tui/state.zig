const std = @import("std");
const json_contracts = @import("../engine/json_contracts.zig");

pub const Turn = struct {
    index: usize,
    input: []const u8,
    reasoning: json_contracts.ReasoningLevel,
    context_artifact: ?[]const u8,
    response: ?json_contracts.EngineResponse,
    raw_output: []const u8,
    rendered_output: []const u8,
    elapsed_ms: u64,
    input_runes: usize,
    output_runes: usize,
    json_ok: bool,
};

pub const SessionState = struct {
    allocator: std.mem.Allocator,
    history: std.ArrayList(Turn),
    current_input: std.ArrayList(u8),
    reasoning: json_contracts.ReasoningLevel,
    context_artifact: ?[]const u8,
    debug: bool,
    engine_found: bool,
    last_ram_bytes: ?usize,

    pub fn init(allocator: std.mem.Allocator) SessionState {
        return .{
            .allocator = allocator,
            .history = std.ArrayList(Turn).init(allocator),
            .current_input = std.ArrayList(u8).init(allocator),
            .reasoning = .balanced,
            .context_artifact = null,
            .debug = false,
            .engine_found = false,
            .last_ram_bytes = null,
        };
    }

    pub fn deinit(self: *SessionState) void {
        for (self.history.items) |turn| {
            self.allocator.free(turn.input);
            self.allocator.free(turn.raw_output);
            self.allocator.free(turn.rendered_output);
            if (turn.context_artifact) |ca| self.allocator.free(ca);
            // EngineResponse handles its own memory if we use arena (TODO)
        }
        self.history.deinit();
        self.current_input.deinit();
        if (self.context_artifact) |ca| self.allocator.free(ca);
    }

    pub fn cycleReasoning(self: *SessionState) void {
        self.reasoning = switch (self.reasoning) {
            .quick => .balanced,
            .balanced => .deep,
            .deep => .max,
            .max => .quick,
        };
    }

    pub fn clearHistory(self: *SessionState) void {
        for (self.history.items) |turn| {
            self.allocator.free(turn.input);
            self.allocator.free(turn.raw_output);
            self.allocator.free(turn.rendered_output);
            if (turn.context_artifact) |ca| self.allocator.free(ca);
        }
        self.history.clearRetainingCapacity();
    }
};
