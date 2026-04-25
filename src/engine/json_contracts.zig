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
    
    pub const LastResult = struct {
        kind: ?[]const u8 = null,
        status: ?[]const u8 = null,
        selected_mode: ?[]const u8 = null,
        selectedMode: ?[]const u8 = null,
        stop_reason: ?[]const u8 = null,
        stopReason: ?[]const u8 = null,
        summary: ?[]const u8 = null,
        detail: ?[]const u8 = null,
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
};

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
