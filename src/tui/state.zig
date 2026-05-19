const std = @import("std");
const json_contracts = @import("../engine/json_contracts.zig");
const shell = @import("../engine/shell.zig");
const diff_viewer = @import("diff_viewer.zig");
const terminal = @import("terminal.zig");
const sovereign_interface = @import("sovereign_interface");

pub const default_max_history_turns: usize = 500;
pub const terminal_refresh_interval_ms: i64 = 250;
pub const ram_refresh_interval_ms: i64 = 1000;
pub const daemon_refresh_interval_ms: i64 = 500;

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

pub const ActiveSessionMount = struct {
    pack_id: []const u8,
    pack_version: []const u8,
};

pub const EngineTrace = struct {
    authority: ?[]const u8 = null,
    engine_state: ?[]const u8 = null,
    stop_reason: ?[]const u8 = null,
    source: ?[]const u8 = null,
    trace_flags: ?[]const u8 = null,
};

pub const MAX_PROOF_CONSTRAINTS: usize = 16;
pub const MAX_FILE_TARGETS: usize = 64;
pub const MAX_FILE_TARGET_PATH_BYTES: usize = 256;

pub const ProofSlotStatus = enum {
    empty,
    pending,
    verified,
    failed,
};

pub const ConstraintAutocomplete = struct {
    active: bool = false,
    trigger_start: usize = 0,
    token_start: usize = 0,
    selected_index: usize = 0,
};

pub const FileTarget = struct {
    path: [MAX_FILE_TARGET_PATH_BYTES]u8 = [_]u8{0} ** MAX_FILE_TARGET_PATH_BYTES,
    len: usize = 0,

    pub fn text(self: *const FileTarget) []const u8 {
        return self.path[0..self.len];
    }
};

pub const FileTargetFinder = struct {
    active: bool = false,
    targets: [MAX_FILE_TARGETS]FileTarget = [_]FileTarget{.{}} ** MAX_FILE_TARGETS,
    count: usize = 0,
    selected_index: usize = 0,

    pub fn clear(self: *FileTargetFinder) void {
        self.active = false;
        self.count = 0;
        self.selected_index = 0;
    }
};

pub const SessionState = struct {
    allocator: std.mem.Allocator,
    history: std.ArrayList(Turn),
    current_input: std.ArrayList(u8),
    reasoning: json_contracts.ReasoningLevel,
    context_artifact: ?[]const u8,
    project_shard: ?[]const u8,
    debug: bool,
    details: bool,
    json_mode: bool,
    compact: bool,
    version: []const u8,
    engine_root_label: ?[]const u8,
    last_command_status: []const u8,
    warnings: std.ArrayList([]const u8),
    engine_found: bool,
    last_ram_bytes: ?usize,
    terminal_size: terminal.TerminalSize,
    last_terminal_refresh_ms: i64,
    last_ram_refresh_ms: i64,
    terminal_refresh_count: usize,
    ram_refresh_count: usize,
    last_counters: json_contracts.RenderCounters,
    draft_count: usize,
    verified_count: usize,
    unresolved_count: usize,
    read_only: bool,
    max_history_turns: usize,
    total_turns: usize,
    pruned_turns: usize,
    freed_turns: usize,
    previous_suggestion_height: u16,
    previous_panel_bottom: u16,
    previous_fixed_rows: u16,
    previous_render_rows: u16,
    previous_render_cols: u16,
    suggestion_index: usize,
    active_session_mounts: std.ArrayList(ActiveSessionMount),
    daemon_active: bool,
    daemon_vram_resident_bytes: usize,
    daemon_l1_concept_index_bytes: usize,
    daemon_hot_page_bytes: usize,
    daemon_raw_shard_vram_bytes: usize,
    daemon_session_hot_bytes: usize,
    daemon_vault_ingest_active: bool,
    daemon_vault_ingest_recent: bool,
    daemon_vault_ingested_files: usize,
    daemon_vault_ingest_errors: usize,
    daemon_last_vault_ingest_ms: i64,
    daemon_context_target: ?[]u8,
    daemon_pipeline_domain: ?[]u8,
    daemon_pipeline_z3_status: ?[]u8,
    daemon_pipeline_confidence_band: ?[]u8,
    last_daemon_refresh_ms: i64,
    daemon_refresh_count: usize,
    typing_turn_index: ?usize,
    typing_output_bytes: usize,
    yolo_mode: bool,
    neural_layer_active: bool,
    pending_command: ?shell.CommandProposal,
    pending_patch: ?diff_viewer.PatchProposal,
    engine_trace: EngineTrace,
    constraint_autocomplete: ConstraintAutocomplete,
    file_target_finder: FileTargetFinder,
    proof_slots: [MAX_PROOF_CONSTRAINTS]ProofSlotStatus,
    sovereign_mirror: sovereign_interface.Snapshot,

    pub fn init(allocator: std.mem.Allocator, version: []const u8, engine_root_label: ?[]const u8, compact: bool) SessionState {
        return initWithLimit(allocator, version, engine_root_label, compact, default_max_history_turns);
    }

    pub fn initWithLimit(allocator: std.mem.Allocator, version: []const u8, engine_root_label: ?[]const u8, compact: bool, max_history_turns: usize) SessionState {
        return .{
            .allocator = allocator,
            .history = std.ArrayList(Turn).init(allocator),
            .current_input = std.ArrayList(u8).init(allocator),
            .reasoning = .balanced,
            .context_artifact = null,
            .project_shard = null,
            .debug = false,
            .details = false,
            .json_mode = false,
            .compact = compact,
            .version = version,
            .engine_root_label = engine_root_label,
            .last_command_status = "ready",
            .warnings = std.ArrayList([]const u8).init(allocator),
            .engine_found = false,
            .last_ram_bytes = null,
            .terminal_size = terminal.default_size,
            .last_terminal_refresh_ms = -terminal_refresh_interval_ms,
            .last_ram_refresh_ms = -ram_refresh_interval_ms,
            .terminal_refresh_count = 0,
            .ram_refresh_count = 0,
            .last_counters = .{},
            .draft_count = 0,
            .verified_count = 0,
            .unresolved_count = 0,
            .read_only = false,
            .max_history_turns = max_history_turns,
            .total_turns = 0,
            .pruned_turns = 0,
            .freed_turns = 0,
            .previous_suggestion_height = 0,
            .previous_panel_bottom = 0,
            .previous_fixed_rows = 0,
            .previous_render_rows = 0,
            .previous_render_cols = 0,
            .suggestion_index = 0,
            .active_session_mounts = std.ArrayList(ActiveSessionMount).init(allocator),
            .daemon_active = false,
            .daemon_vram_resident_bytes = 0,
            .daemon_l1_concept_index_bytes = 0,
            .daemon_hot_page_bytes = 0,
            .daemon_raw_shard_vram_bytes = 0,
            .daemon_session_hot_bytes = 0,
            .daemon_vault_ingest_active = false,
            .daemon_vault_ingest_recent = false,
            .daemon_vault_ingested_files = 0,
            .daemon_vault_ingest_errors = 0,
            .daemon_last_vault_ingest_ms = 0,
            .daemon_context_target = null,
            .daemon_pipeline_domain = null,
            .daemon_pipeline_z3_status = null,
            .daemon_pipeline_confidence_band = null,
            .last_daemon_refresh_ms = -daemon_refresh_interval_ms,
            .daemon_refresh_count = 0,
            .typing_turn_index = null,
            .typing_output_bytes = 0,
            .yolo_mode = false,
            .neural_layer_active = false,
            .pending_command = null,
            .pending_patch = null,
            .engine_trace = .{},
            .constraint_autocomplete = .{},
            .file_target_finder = .{},
            .proof_slots = [_]ProofSlotStatus{.empty} ** MAX_PROOF_CONSTRAINTS,
            .sovereign_mirror = sovereign_interface.emptySnapshot(),
        };
    }

    pub fn deinit(self: *SessionState) void {
        for (self.history.items) |turn| {
            self.freeTurn(turn);
        }
        self.history.deinit();
        self.current_input.deinit();
        self.warnings.deinit();
        for (self.active_session_mounts.items) |mount| {
            self.allocator.free(mount.pack_id);
            self.allocator.free(mount.pack_version);
        }
        self.active_session_mounts.deinit();
        if (self.context_artifact) |ca| self.allocator.free(ca);
        if (self.project_shard) |project_shard| self.allocator.free(project_shard);
        if (self.daemon_context_target) |target| self.allocator.free(target);
        if (self.daemon_pipeline_domain) |domain| self.allocator.free(domain);
        if (self.daemon_pipeline_z3_status) |status| self.allocator.free(status);
        if (self.daemon_pipeline_confidence_band) |band| self.allocator.free(band);
        self.clearPendingCommand();
        self.clearPendingPatch();
        self.clearEngineTrace();
    }

    pub fn setPendingCommand(self: *SessionState, proposal: shell.CommandProposal) void {
        self.clearPendingCommand();
        self.pending_command = proposal;
    }

    pub fn clearPendingCommand(self: *SessionState) void {
        if (self.pending_command) |proposal| proposal.deinit();
        self.pending_command = null;
    }

    pub fn takePendingCommand(self: *SessionState) ?shell.CommandProposal {
        const proposal = self.pending_command;
        self.pending_command = null;
        return proposal;
    }

    pub fn setPendingPatch(self: *SessionState, proposal: diff_viewer.PatchProposal) void {
        self.clearPendingPatch();
        self.pending_patch = proposal;
    }

    pub fn clearPendingPatch(self: *SessionState) void {
        if (self.pending_patch) |proposal| proposal.deinit();
        self.pending_patch = null;
    }

    pub fn takePendingPatch(self: *SessionState) ?diff_viewer.PatchProposal {
        const proposal = self.pending_patch;
        self.pending_patch = null;
        return proposal;
    }

    pub fn setEngineTrace(self: *SessionState, trace: EngineTrace) !void {
        self.clearEngineTrace();
        self.engine_trace = .{
            .authority = if (trace.authority) |v| try self.allocator.dupe(u8, v) else null,
            .engine_state = if (trace.engine_state) |v| try self.allocator.dupe(u8, v) else null,
            .stop_reason = if (trace.stop_reason) |v| try self.allocator.dupe(u8, v) else null,
            .source = if (trace.source) |v| try self.allocator.dupe(u8, v) else null,
            .trace_flags = if (trace.trace_flags) |v| try self.allocator.dupe(u8, v) else null,
        };
    }

    pub fn clearEngineTrace(self: *SessionState) void {
        if (self.engine_trace.authority) |v| self.allocator.free(v);
        if (self.engine_trace.engine_state) |v| self.allocator.free(v);
        if (self.engine_trace.stop_reason) |v| self.allocator.free(v);
        if (self.engine_trace.source) |v| self.allocator.free(v);
        if (self.engine_trace.trace_flags) |v| self.allocator.free(v);
        self.engine_trace = .{};
    }

    pub fn setDaemonContextTarget(self: *SessionState, target: ?[]const u8) !void {
        if (self.daemon_context_target) |existing| self.allocator.free(existing);
        self.daemon_context_target = null;
        if (target) |value| {
            if (value.len != 0) self.daemon_context_target = try self.allocator.dupe(u8, value);
        }
    }

    pub fn setDaemonPipelineTelemetry(self: *SessionState, domain: ?[]const u8, z3_status: ?[]const u8, confidence_band: ?[]const u8) !void {
        if (self.daemon_pipeline_domain) |existing| self.allocator.free(existing);
        if (self.daemon_pipeline_z3_status) |existing| self.allocator.free(existing);
        if (self.daemon_pipeline_confidence_band) |existing| self.allocator.free(existing);
        self.daemon_pipeline_domain = null;
        self.daemon_pipeline_z3_status = null;
        self.daemon_pipeline_confidence_band = null;
        if (domain) |value| {
            if (value.len != 0) self.daemon_pipeline_domain = try self.allocator.dupe(u8, value);
        }
        if (z3_status) |value| {
            if (value.len != 0) self.daemon_pipeline_z3_status = try self.allocator.dupe(u8, value);
        }
        if (confidence_band) |value| {
            if (value.len != 0) self.daemon_pipeline_confidence_band = try self.allocator.dupe(u8, value);
        }
        self.refreshProofSlots();
    }

    pub fn refreshProofSlots(self: *SessionState) void {
        const z3 = self.daemon_pipeline_z3_status orelse "";
        const active = self.daemon_active or z3.len > 0;
        if (!active) {
            self.proof_slots = [_]ProofSlotStatus{.empty} ** MAX_PROOF_CONSTRAINTS;
            return;
        }

        const slot_status: ProofSlotStatus = if (std.mem.indexOf(u8, z3, "fail") != null or std.mem.indexOf(u8, z3, "unsat") != null)
            .failed
        else if (std.mem.indexOf(u8, z3, "verified") != null or std.mem.indexOf(u8, z3, "proved") != null or std.mem.eql(u8, z3, "sat"))
            .verified
        else
            .pending;

        self.proof_slots[0] = slot_status;
        var i: usize = 1;
        while (i < self.proof_slots.len) : (i += 1) {
            self.proof_slots[i] = .empty;
        }
    }

    pub fn addActiveSessionMount(self: *SessionState, pack_id: []const u8, pack_version: []const u8) !void {
        for (self.active_session_mounts.items) |mount| {
            if (std.mem.eql(u8, mount.pack_id, pack_id) and std.mem.eql(u8, mount.pack_version, pack_version)) return;
        }
        try self.active_session_mounts.append(.{
            .pack_id = try self.allocator.dupe(u8, pack_id),
            .pack_version = try self.allocator.dupe(u8, pack_version),
        });
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
            self.freeTurn(turn);
        }
        self.history.clearRetainingCapacity();
        self.last_counters = .{};
        self.draft_count = 0;
        self.verified_count = 0;
        self.unresolved_count = 0;
        self.last_command_status = "history cleared";
    }

    pub fn nextTurnIndex(self: *const SessionState) usize {
        return self.total_turns + 1;
    }

    pub fn appendTurn(self: *SessionState, turn: Turn) !void {
        try self.history.append(turn);
        self.total_turns += 1;
        try self.pruneHistory();
    }

    pub fn pruneHistory(self: *SessionState) !void {
        if (self.max_history_turns == 0) return error.InvalidHistoryLimit;
        while (self.history.items.len > self.max_history_turns) {
            const turn = self.history.orderedRemove(0);
            self.freeTurn(turn);
            self.pruned_turns += 1;
        }
    }

    pub fn refreshTerminalSize(self: *SessionState, now_ms: i64, provider: *const fn () terminal.TerminalSize) void {
        if (self.terminal_refresh_count == 0 or now_ms - self.last_terminal_refresh_ms >= terminal_refresh_interval_ms) {
            self.terminal_size = provider();
            self.last_terminal_refresh_ms = now_ms;
            self.terminal_refresh_count += 1;
        }
    }

    pub fn refreshRam(self: *SessionState, now_ms: i64, provider: *const fn () ?usize) void {
        if (self.ram_refresh_count == 0 or now_ms - self.last_ram_refresh_ms >= ram_refresh_interval_ms) {
            self.last_ram_bytes = provider();
            self.last_ram_refresh_ms = now_ms;
            self.ram_refresh_count += 1;
        }
    }

    pub fn recordResponseState(self: *SessionState, response: json_contracts.EngineResponse) void {
        switch (response.getVisualAuthorityState()) {
            .draft => self.draft_count += 1,
            .verified => self.verified_count += 1,
            .unresolved => self.unresolved_count += 1,
            .failed, .other, .unrecognized => {},
        }
    }

    pub fn getContextWindowText(self: *SessionState, turns: usize) ![]u8 {
        var out = std.ArrayList(u8).init(self.allocator);
        errdefer out.deinit();
        const start = if (self.history.items.len > turns) self.history.items.len - turns else 0;
        for (self.history.items[start..]) |turn| {
            try out.writer().print("user: {s}\n", .{turn.input});
            if (turn.response) |res| {
                try out.writer().print("engine: {s}\n", .{res.answer_draft orelse ""});
            }
        }
        return out.toOwnedSlice();
    }

    pub fn freeTurn(self: *SessionState, turn: Turn) void {
        self.allocator.free(turn.input);
        self.allocator.free(turn.raw_output);
        self.allocator.free(turn.rendered_output);
        if (turn.context_artifact) |ca| self.allocator.free(ca);
        self.freed_turns += 1;
        // EngineResponse handles its own memory if we use arena (TODO)
    }
};
