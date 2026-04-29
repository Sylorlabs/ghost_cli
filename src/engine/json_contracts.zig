const std = @import("std");

pub const ReasoningLevel = enum {
    quick,
    balanced,
    deep,
    max,

    pub fn toStr(self: ReasoningLevel) []const u8 {
        return @tagName(self);
    }
};

pub const PackInfo = struct {
    id: []const u8,
    version: ?[]const u8 = null,
    status: ?[]const u8 = null, // e.g., "mounted", "available"
    domain: ?[]const u8 = null,
    family: ?[]const u8 = null,
    trust_class: ?[]const u8 = null,
    freshness: ?[]const u8 = null,
    path: ?[]const u8 = null,
    source: ?[]const u8 = null,
    is_mounted: ?bool = null,
    warnings: ?[]const []const u8 = null,
    content_summary: ?[]const u8 = null,
};

pub const CandidateInfo = struct {
    id: []const u8,
    type: ?[]const u8 = null,
    is_eligible: bool,
    eligibility_reason: ?[]const u8 = null,
    success_count: ?u32 = null,
    failure_count: ?u32 = null,
    contradiction_count: ?u32 = null,
    independent_case_count: ?u32 = null,
    trust_recommendation: ?[]const u8 = null,
    reuse_scope: ?[]const u8 = null,
    provenance_summary: ?[]const u8 = null,
    source_feedback_refs: ?[]const []const u8 = null,
    what_it_influences: ?[]const u8 = null,
};

pub const ExportResult = struct {
    success: bool,
    candidate_id: []const u8,
    pack_id: []const u8,
    version: []const u8,
    message: ?[]const u8 = null,
    is_non_authorizing: bool = true,
};

pub const AutopsyResult = struct {
    project_profile: ?ProjectProfile = null,
    project_gap_report: ?ProjectGapReport = null,
    verifier_plan_candidates: ?[]const VerifierPlanCandidate = null,
    state: ?[]const u8 = null,
    non_authorizing: bool = true,

    pub const ProjectProfile = struct {
        workspace_root: ?[]const u8 = null,
        detected_languages: ?[]const NamedSignal = null,
        build_systems: ?[]const NamedSignal = null,
        safe_command_candidates: ?[]const CommandCandidate = null,
        unknowns: ?[]const std.json.Value = null,
        confidence_summary: ?[]const u8 = null,
    };

    pub const NamedSignal = struct {
        name: []const u8,
        path: ?[]const u8 = null,
        kind: ?[]const u8 = null,
        confidence: ?[]const u8 = null,
        reason: ?[]const u8 = null,
    };

    pub const CommandCandidate = struct {
        id: []const u8,
        argv: []const []const u8,
        reason: ?[]const u8 = null,
        risk_level: ?[]const u8 = null,
    };

    pub const VerifierPlanCandidate = struct {
        id: []const u8,
        argv: []const []const u8,
        purpose: ?[]const u8 = null,
        risk_level: ?[]const u8 = null,
        why_candidate_exists: ?[]const u8 = null,
    };

    pub const ProjectGapReport = struct {
        missing_ci: ?std.json.Value = null,
        missing_test_command: ?std.json.Value = null,
        missing_build_command: ?std.json.Value = null,
        missing_verifier_adapters: ?[]const NamedSignal = null,
    };
};

pub const ContextAutopsyEnvelope = struct {
    gipVersion: ?[]const u8 = null,
    kind: ?[]const u8 = null,
    status: ?[]const u8 = null,
    resultState: ?std.json.Value = null,
    result_state: ?std.json.Value = null,
    result: ?std.json.Value = null,
    @"error": ?std.json.Value = null,
};

// Unified response struct that handles multiple engine JSON shapes
pub const EngineResponse = struct {
    // Top-level status/permission
    status: ?[]const u8 = null,
    permission: ?[]const u8 = null,
    claim_status: ?[]const u8 = null,

    // Draft/Verification state
    isDraft: ?bool = null,
    is_draft: ?bool = null,
    verificationState: ?[]const u8 = null,
    verification_state: ?[]const u8 = null,

    // Execution metadata
    selected_response_mode: ?[]const u8 = null,
    selectedResponseMode: ?[]const u8 = null,
    requested_reasoning_level: ?[]const u8 = null,
    requestedReasoningLevel: ?[]const u8 = null,
    effective_compute_budget_tier: ?[]const u8 = null,
    effectiveComputeBudgetTier: ?[]const u8 = null,

    // Stop reasons
    stopReason: ?[]const u8 = null,
    stop_reason: ?[]const u8 = null,
    unresolvedReason: ?[]const u8 = null,
    unresolved_reason: ?[]const u8 = null,

    // Content
    summary: ?[]const u8 = null,
    detail: ?[]const u8 = null,
    response: ?[]const u8 = null,
    message: ?[]const u8 = null,
    suggested_action: ?[]const u8 = null,
    suggestedAction: ?[]const u8 = null,

    // Nested results (ghost_task_operator chat style)
    lastResult: ?LastResult = null,
    last_result: ?LastResult = null,
    currentIntent: ?CurrentIntent = null,
    current_intent: ?CurrentIntent = null,

    // Blockers / Obligations
    pendingObligations: ?std.json.Value = null,
    pending_obligations: ?std.json.Value = null,
    missingObligations: ?std.json.Value = null,
    missing_obligations: ?std.json.Value = null,
    pendingAmbiguities: ?std.json.Value = null,
    pending_ambiguities: ?std.json.Value = null,
    ambiguity_sets: ?std.json.Value = null,
    ambiguity_choices: ?std.json.Value = null,

    // Draft contract specific
    assumptions: ?std.json.Value = null,
    missingInformation: ?std.json.Value = null,
    missing_information: ?std.json.Value = null,
    possibleAlternatives: ?std.json.Value = null,
    possible_alternatives: ?std.json.Value = null,
    escalationHint: ?[]const u8 = null,
    escalation_hint: ?[]const u8 = null,

    // Findings
    partial_findings: ?std.json.Value = null,
    verifier_summaries: ?std.json.Value = null,

    // Correction / negative-knowledge / epistemic renderer fields.
    // Keep these as raw JSON values: the CLI renders labels only and does not
    // reinterpret engine proof, support, verifier, or mutation semantics.
    corrections: ?std.json.Value = null,
    negative_knowledge: ?std.json.Value = null,
    epistemic_render: ?std.json.Value = null,

    pub const LastResult = struct {
        kind: ?[]const u8 = null,
        status: ?[]const u8 = null,
        selected_mode: ?[]const u8 = null,
        selectedMode: ?[]const u8 = null,
        stop_reason: ?[]const u8 = null,
        stopReason: ?[]const u8 = null,
        summary: ?[]const u8 = null,
        detail: ?[]const u8 = null,
        corrections: ?std.json.Value = null,
        negative_knowledge: ?std.json.Value = null,
        epistemic_render: ?std.json.Value = null,
    };

    pub const CurrentIntent = struct {
        status: ?[]const u8 = null,
        selected_mode: ?[]const u8 = null,
        selectedMode: ?[]const u8 = null,
    };

    pub fn getStatus(self: EngineResponse) ?[]const u8 {
        if (self.status) |val| return val;
        if (self.claim_status) |val| return val;
        if (self.last_result) |lr| if (lr.status) |val| return val;
        if (self.lastResult) |lr| if (lr.status) |val| return val;
        if (self.current_intent) |ci| if (ci.status) |val| return val;
        if (self.currentIntent) |ci| if (ci.status) |val| return val;
        if (self.last_result) |lr| if (lr.kind) |val| return val;
        if (self.lastResult) |lr| if (lr.kind) |val| return val;
        return null;
    }

    pub fn isDraftStatus(self: EngineResponse) bool {
        if (self.isDraft) |val| return val;
        if (self.is_draft) |val| return val;
        if (std.mem.eql(u8, self.getVerificationState() orelse "", "draft")) return true;
        if (std.mem.eql(u8, self.getStatus() orelse "", "draft")) return true;
        return false;
    }

    pub fn getVerificationState(self: EngineResponse) ?[]const u8 {
        if (self.verificationState) |val| return val;
        if (self.verification_state) |val| return val;
        if (self.last_result) |lr| if (lr.selected_mode) |val| return val;
        if (self.lastResult) |lr| if (lr.selectedMode) |val| return val;
        if (self.current_intent) |ci| if (ci.selected_mode) |val| return val;
        if (self.currentIntent) |ci| if (ci.selectedMode) |val| return val;
        return self.getStatus();
    }

    pub fn getStopReason(self: EngineResponse) ?[]const u8 {
        if (self.stopReason) |val| return val;
        if (self.stop_reason) |val| return val;
        if (self.last_result) |lr| if (lr.stop_reason) |val| return val;
        if (self.lastResult) |lr| if (lr.stopReason) |val| return val;
        return null;
    }

    pub fn getUnresolvedReason(self: EngineResponse) ?[]const u8 {
        if (self.unresolvedReason) |val| return val;
        if (self.unresolved_reason) |val| return val;
        return null;
    }

    pub fn getSummary(self: EngineResponse) ?[]const u8 {
        if (self.summary) |val| return val;
        if (self.last_result) |lr| if (lr.summary) |val| return val;
        if (self.lastResult) |lr| if (lr.summary) |val| return val;
        return null;
    }

    pub fn getDetail(self: EngineResponse) ?[]const u8 {
        if (self.detail) |val| return val;
        if (self.message) |val| return val;
        if (self.response) |val| return val;
        if (self.last_result) |lr| if (lr.detail) |val| return val;
        if (self.lastResult) |lr| if (lr.detail) |val| return val;
        return null;
    }

    pub fn getSuggestedAction(self: EngineResponse) ?[]const u8 {
        if (self.suggested_action) |val| return val;
        if (self.suggestedAction) |val| return val;
        if (self.escalation_hint) |val| return val;
        if (self.escalationHint) |val| return val;
        return null;
    }

    pub fn getObligations(self: EngineResponse) ?std.json.Value {
        if (self.pending_obligations) |val| return val;
        if (self.pendingObligations) |val| return val;
        if (self.missing_obligations) |val| return val;
        if (self.missingObligations) |val| return val;
        return null;
    }

    pub fn getAmbiguities(self: EngineResponse) ?std.json.Value {
        if (self.pending_ambiguities) |val| return val;
        if (self.pendingAmbiguities) |val| return val;
        if (self.ambiguity_sets) |val| return val;
        if (self.ambiguity_choices) |val| return val;
        return null;
    }

    pub fn getCorrections(self: EngineResponse) ?std.json.Value {
        if (self.corrections) |val| return val;
        if (self.last_result) |lr| if (lr.corrections) |val| return val;
        if (self.lastResult) |lr| if (lr.corrections) |val| return val;
        return null;
    }

    pub fn getNegativeKnowledge(self: EngineResponse) ?std.json.Value {
        if (self.negative_knowledge) |val| return val;
        if (self.last_result) |lr| if (lr.negative_knowledge) |val| return val;
        if (self.lastResult) |lr| if (lr.negative_knowledge) |val| return val;
        return null;
    }

    pub fn getEpistemicRender(self: EngineResponse) ?std.json.Value {
        if (self.epistemic_render) |val| return val;
        if (self.last_result) |lr| if (lr.epistemic_render) |val| return val;
        if (self.lastResult) |lr| if (lr.epistemic_render) |val| return val;
        return null;
    }
};

pub const RenderCounters = struct {
    corrections: usize = 0,
    nk_applied: usize = 0,
    nk_candidates: usize = 0,
    verifier_requirements: usize = 0,
    suppressions: usize = 0,
    routing_warnings: usize = 0,
    trust_decay_candidates: usize = 0,
};

pub fn renderCounters(response: EngineResponse) RenderCounters {
    var counters = RenderCounters{};
    if (response.getCorrections()) |corrections| {
        counters.corrections = countItems(corrections);
    }
    if (response.getNegativeKnowledge()) |nk| {
        counters.nk_applied += countObjectFieldItems(nk, "applied_records");
        counters.nk_candidates += countObjectFieldItems(nk, "proposed_candidates");
        counters.nk_candidates += countObjectFieldItems(nk, "items");
        counters.trust_decay_candidates += countObjectFieldItems(nk, "trust_decay_candidates");
        counters.verifier_requirements += countItemsByKind(nk, &.{
            "stronger_verifier_required",
            "stronger_verifier_requirement",
            "stronger_verifier",
        });
        counters.suppressions += countItemsByKind(nk, &.{
            "exact_repeat_suppressed",
            "repeat_suppression",
        });
        counters.routing_warnings += countItemsByKind(nk, &.{
            "routing_warning",
        });
    }
    return counters;
}

fn countObjectFieldItems(value: std.json.Value, field: []const u8) usize {
    return switch (value) {
        .object => |obj| if (obj.get(field)) |child| countItems(child) else 0,
        else => 0,
    };
}

fn countItems(value: std.json.Value) usize {
    return switch (value) {
        .array => |arr| arr.items.len,
        .object => |obj| if (obj.get("items")) |items| countItems(items) else 1,
        .null => 0,
        else => 1,
    };
}

fn countItemsByKind(value: std.json.Value, accepted: []const []const u8) usize {
    return switch (value) {
        .array => |arr| blk: {
            var count: usize = 0;
            for (arr.items) |item| count += countItemsByKind(item, accepted);
            break :blk count;
        },
        .object => |obj| blk: {
            var nested_count: usize = 0;
            if (obj.get("items")) |items| nested_count += countItemsByKind(items, accepted);
            const self_matches = if (explicitKind(obj)) |kind| matchesAny(kind, accepted) else false;
            break :blk nested_count + @as(usize, if (self_matches) 1 else 0);
        },
        else => 0,
    };
}

fn explicitKind(obj: std.json.ObjectMap) ?[]const u8 {
    const fields = [_][]const u8{ "kind", "type", "event", "category" };
    for (fields) |field| {
        if (obj.get(field)) |value| {
            if (value == .string) return value.string;
        }
    }
    return null;
}

fn matchesAny(value: []const u8, accepted: []const []const u8) bool {
    for (accepted) |candidate| {
        if (std.mem.eql(u8, value, candidate)) return true;
    }
    return false;
}
pub fn parseEngineJson(allocator: std.mem.Allocator, json_str: []const u8) !std.json.Parsed(EngineResponse) {
    return try std.json.parseFromSlice(EngineResponse, allocator, json_str, .{ .ignore_unknown_fields = true });
}

pub fn parsePackListJson(allocator: std.mem.Allocator, json_str: []const u8) !std.json.Parsed([]PackInfo) {
    return try std.json.parseFromSlice([]PackInfo, allocator, json_str, .{ .ignore_unknown_fields = true });
}

pub fn parsePackInfoJson(allocator: std.mem.Allocator, json_str: []const u8) !std.json.Parsed(PackInfo) {
    return try std.json.parseFromSlice(PackInfo, allocator, json_str, .{ .ignore_unknown_fields = true });
}

pub fn parseCandidateListJson(allocator: std.mem.Allocator, json_str: []const u8) !std.json.Parsed([]CandidateInfo) {
    return try std.json.parseFromSlice([]CandidateInfo, allocator, json_str, .{ .ignore_unknown_fields = true });
}

pub fn parseCandidateInfoJson(allocator: std.mem.Allocator, json_str: []const u8) !std.json.Parsed(CandidateInfo) {
    return try std.json.parseFromSlice(CandidateInfo, allocator, json_str, .{ .ignore_unknown_fields = true });
}

pub fn parseExportResultJson(allocator: std.mem.Allocator, json_str: []const u8) !std.json.Parsed(ExportResult) {
    return try std.json.parseFromSlice(ExportResult, allocator, json_str, .{ .ignore_unknown_fields = true });
}

pub fn parseAutopsyJson(allocator: std.mem.Allocator, json_str: []const u8) !std.json.Parsed(AutopsyResult) {
    return try std.json.parseFromSlice(AutopsyResult, allocator, json_str, .{ .ignore_unknown_fields = true });
}

pub fn parseContextAutopsyJson(allocator: std.mem.Allocator, json_str: []const u8) !std.json.Parsed(ContextAutopsyEnvelope) {
    return try std.json.parseFromSlice(ContextAutopsyEnvelope, allocator, json_str, .{ .ignore_unknown_fields = true });
}
