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
    json_mode: bool,
    compact: bool,
    version: []const u8,
    engine_root_label: ?[]const u8,
    last_command_status: []const u8,
    warnings: std.ArrayList([]const u8),
    engine_found: bool,
    last_ram_bytes: ?usize,
    last_counters: json_contracts.RenderCounters,
    draft_count: usize,
    verified_count: usize,
    unresolved_count: usize,
    previous_suggestion_height: u16,
    suggestion_index: usize,

    pub fn init(allocator: std.mem.Allocator, version: []const u8, engine_root_label: ?[]const u8, compact: bool) SessionState {
        return .{
            .allocator = allocator,
            .history = std.ArrayList(Turn).init(allocator),
            .current_input = std.ArrayList(u8).init(allocator),
            .reasoning = .balanced,
            .context_artifact = null,
            .debug = false,
            .json_mode = false,
            .compact = compact,
            .version = version,
            .engine_root_label = engine_root_label,
            .last_command_status = "ready",
            .warnings = std.ArrayList([]const u8).init(allocator),
            .engine_found = false,
            .last_ram_bytes = null,
            .last_counters = .{},
            .draft_count = 0,
            .verified_count = 0,
            .unresolved_count = 0,
            .previous_suggestion_height = 0,
            .suggestion_index = 0,
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
        self.warnings.deinit();
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
        self.last_counters = .{};
        self.draft_count = 0;
        self.verified_count = 0;
        self.unresolved_count = 0;
        self.last_command_status = "history cleared";
    }

    pub fn recordResponseState(self: *SessionState, response: json_contracts.EngineResponse) void {
        if (response.isDraftStatus()) {
            self.draft_count += 1;
            return;
        }
        if (response.getVerificationState()) |verification| {
            if (std.mem.eql(u8, verification, "verified") or std.mem.eql(u8, verification, "supported")) {
                self.verified_count += 1;
            } else if (std.mem.eql(u8, verification, "unresolved")) {
                self.unresolved_count += 1;
            }
        }
    }
};
