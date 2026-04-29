const std = @import("std");
const json_contracts = @import("../engine/json_contracts.zig");

const bold = "\x1b[1m";
const reset = "\x1b[0m";
const green = "\x1b[32m";
const yellow = "\x1b[33m";
const red = "\x1b[31m";
const blue = "\x1b[34m";

pub fn printEngineOutput(writer: anytype, response: json_contracts.EngineResponse) !void {
    // 1. Status Line
    try writer.print("{s}Status:{s} ", .{ bold, reset });
    if (response.isDraftStatus()) {
        try writer.print("{s}Draft / unverified{s}\n", .{ yellow, reset });
    } else if (response.getVerificationState()) |state| {
        if (std.mem.eql(u8, state, "verified") or std.mem.eql(u8, state, "supported")) {
            try writer.print("{s}Verified{s}\n", .{ green, reset });
        } else if (std.mem.eql(u8, state, "unresolved")) {
            try writer.print("{s}Unresolved{s}\n", .{ yellow, reset });
        } else if (std.mem.eql(u8, state, "failed")) {
            try writer.print("{s}Failed{s}\n", .{ red, reset });
        } else {
            try writer.print("{s}{s}{s}\n", .{ blue, state, reset });
        }
    } else {
        try writer.print("{s}Parsed JSON, unrecognized contract{s}\n", .{ yellow, reset });
    }

    // 2. Metadata
    if (response.requested_reasoning_level orelse response.requestedReasoningLevel) |level| {
        try writer.print("{s}Reasoning:{s} {s}\n", .{ bold, reset, level });
    }
    if (response.selected_response_mode orelse response.selectedResponseMode) |mode| {
        try writer.print("{s}Internal Mode:{s} {s}\n", .{ bold, reset, mode });
    }
    if (response.effective_compute_budget_tier orelse response.effectiveComputeBudgetTier) |tier| {
        try writer.print("{s}Budget Tier:{s} {s}\n", .{ bold, reset, tier });
    }

    try writer.print("\n", .{});

    // 3. Content
    if (response.getSummary()) |summary| {
        try writer.print("{s}Summary:{s}\n{s}\n\n", .{ bold, reset, summary });
    }
    if (response.getDetail()) |detail| {
        try writer.print("{s}Detail:{s}\n{s}\n\n", .{ bold, reset, detail });
    }

    try printEpistemicRender(writer, response);
    try printCorrections(writer, response);
    try printNegativeKnowledge(writer, response);

    // 4. Issues / Blockers
    if (response.getUnresolvedReason()) |reason| {
        try writer.print("{s}Unresolved Reason:{s} {s}\n", .{ bold, reset, reason });
    }

    if (response.getStopReason()) |reason| {
        if (std.mem.eql(u8, reason, "budget_exhausted")) {
            try writer.print("{s}Stop Reason:{s} {s}Budget Exhausted{s}\n", .{ bold, reset, red, reset });
        } else {
            try writer.print("{s}Stop Reason:{s} {s}\n", .{ bold, reset, reason });
        }
    }

    if (response.getObligations()) |obligations| {
        try writer.print("{s}Pending Obligations:{s}\n", .{ bold, reset });
        try printObligations(writer, obligations, 2);
        try writer.print("\n", .{});
    }

    if (response.getAmbiguities()) |choices| {
        try writer.print("{s}Ambiguities:{s}\n", .{ bold, reset });
        try printJsonValue(writer, choices, 2);
        try writer.print("\n", .{});
    }

    if (response.verifier_summaries) |summaries| {
        try writer.print("{s}Verifier Summaries:{s}\n", .{ bold, reset });
        try printJsonValue(writer, summaries, 2);
        try writer.print("\n", .{});
    }

    // 5. Next Steps
    if (response.getSuggestedAction()) |action| {
        try writer.print("{s}Next Action:{s} {s}\n", .{ bold, reset, action });
    }

    // 6. Escalation hint if draft
    if (response.isDraftStatus()) {
        try writer.print("\n{s}Note:{s} This is an unverified draft. Run with {s}--reasoning=deep{s} or ask to {s}verify{s} to confirm.\n", .{ yellow, reset, bold, reset, bold, reset });
    }
}

pub fn printDebugFieldDetection(writer: anytype, response: json_contracts.EngineResponse) !void {
    const counters = json_contracts.renderCounters(response);
    try writer.print("[DEBUG] Field Detection: corrections={s} negative_knowledge={s} epistemic_render={s}\n", .{
        if (response.getCorrections() != null) "yes" else "no",
        if (response.getNegativeKnowledge() != null) "yes" else "no",
        if (response.getEpistemicRender() != null) "yes" else "no",
    });
    try writer.print("[DEBUG] Render Counts: corrections={d} nk_applied={d} nk_candidates={d} verifier_requirements={d} suppressions={d} routing_warnings={d} trust_decay_candidates={d}\n", .{
        counters.corrections,
        counters.nk_applied,
        counters.nk_candidates,
        counters.verifier_requirements,
        counters.suppressions,
        counters.routing_warnings,
        counters.trust_decay_candidates,
    });
}

fn printEpistemicRender(writer: anytype, response: json_contracts.EngineResponse) !void {
    const epistemic = response.getEpistemicRender() orelse return;

    try writer.print("{s}Epistemic State:{s}\n", .{ bold, reset });
    try writer.print("  Renderer: {s}Non-authorizing display only{s}\n", .{ yellow, reset });
    try writer.print("  Authority: Does not prove support.\n", .{});

    switch (epistemic) {
        .object => |obj| {
            if (getStringField(obj, "state_label") orelse getStringField(obj, "label") orelse getStringField(obj, "state")) |label| {
                try writer.print("  Engine Label: {s}\n", .{label});
            }
            if (getStringField(obj, "authority_statement") orelse getStringField(obj, "authority") orelse getStringField(obj, "support_statement")) |statement| {
                try writer.print("  Engine Authority: {s}\n", .{statement});
            }
            try printOptionalJsonField(writer, obj, "next_action", "  Next Action");
            try printOptionalJsonField(writer, obj, "reason", "  Reason");
        },
        else => {
            try writer.print("  Engine Render: ", .{});
            try printJsonValue(writer, epistemic, 2);
            try writer.print("\n", .{});
        },
    }
    try writer.print("\n", .{});
}

fn printCorrections(writer: anytype, response: json_contracts.EngineResponse) !void {
    const corrections = response.getCorrections() orelse return;

    try writer.print("{s}Correction Recorded:{s} {s}Non-authorizing{s}\n", .{ bold, reset, yellow, reset });
    switch (corrections) {
        .object => |obj| {
            if (obj.get("summary")) |summary| {
                try writer.print("  Summary: ", .{});
                try printJsonValue(writer, summary, 2);
                try writer.print("\n", .{});
            }
            if (obj.get("items")) |items| {
                try printLabeledItems(writer, items, "  - ");
            }
        },
        else => try printLabeledItems(writer, corrections, "  - "),
    }
    try writer.print("  Note: Correction record only. Does not prove support.\n\n", .{});
}

fn printNegativeKnowledge(writer: anytype, response: json_contracts.EngineResponse) !void {
    const nk = response.getNegativeKnowledge() orelse return;

    switch (nk) {
        .object => |obj| {
            if (obj.get("influence_summary")) |summary| {
                try writer.print("{s}Negative Knowledge Applied:{s} prior failure influence; {s}Non-authorizing{s}\n", .{ bold, reset, yellow, reset });
                try writer.print("  Influence Summary: ", .{});
                try printJsonValue(writer, summary, 2);
                try writer.print("\n  Note: Does not prove support.\n\n", .{});
            }
            if (obj.get("applied_records")) |records| {
                try writer.print("{s}Negative Knowledge Applied:{s} prior failure influence; {s}Non-authorizing{s}\n", .{ bold, reset, yellow, reset });
                try printLabeledItems(writer, records, "  - ");
                try writer.print("  Note: Does not prove support.\n\n", .{});
            }
            if (obj.get("proposed_candidates")) |candidates| {
                try writer.print("{s}Negative Knowledge Candidate Proposed:{s} {s}Candidate only; Requires review; Non-authorizing{s}\n", .{ bold, reset, yellow, reset });
                try printLabeledItems(writer, candidates, "  - ");
                try writer.print("\n", .{});
            }
            if (obj.get("items")) |items| {
                try printNkItems(writer, items);
            }
            if (obj.get("trust_decay_candidates")) |candidates| {
                try writer.print("{s}Trust Decay Candidate Proposed:{s} {s}Candidate only; Requires review; Non-authorizing{s}\n", .{ bold, reset, yellow, reset });
                try printLabeledItems(writer, candidates, "  - ");
                try writer.print("\n", .{});
            }
        },
        else => {
            try writer.print("{s}Negative Knowledge Applied:{s} {s}Non-authorizing{s}\n", .{ bold, reset, yellow, reset });
            try printLabeledItems(writer, nk, "  - ");
            try writer.print("  Note: Does not prove support.\n\n", .{});
        },
    }
}

fn printNkItems(writer: anytype, value: std.json.Value) !void {
    switch (value) {
        .array => |arr| {
            for (arr.items) |item| try printNkItem(writer, item);
        },
        else => try printNkItem(writer, value),
    }
}

fn printNkItem(writer: anytype, item: std.json.Value) !void {
    const label = nkItemLabel(item);
    try writer.print("{s}{s}:{s} ", .{ bold, label, reset });
    if (std.mem.eql(u8, label, "Stronger Verifier Required")) {
        try writer.print("{s}Requires review; Does not prove support{s}\n", .{ yellow, reset });
    } else if (std.mem.eql(u8, label, "Exact Repeat Suppressed")) {
        try writer.print("{s}Non-authorizing prior failure influence{s}\n", .{ yellow, reset });
    } else if (std.mem.eql(u8, label, "Routing Warning")) {
        try writer.print("{s}Non-authorizing routing warning{s}\n", .{ yellow, reset });
    } else {
        try writer.print("{s}Candidate only; Requires review; Non-authorizing{s}\n", .{ yellow, reset });
    }
    try writer.print("  - ", .{});
    try printJsonValue(writer, item, 4);
    try writer.print("\n\n", .{});
}

fn nkItemLabel(item: std.json.Value) []const u8 {
    const obj = switch (item) {
        .object => |obj| obj,
        else => return "Negative Knowledge Candidate Proposed",
    };
    const kind = explicitKind(obj) orelse return "Negative Knowledge Candidate Proposed";
    if (matchesAny(kind, &.{ "stronger_verifier_required", "stronger_verifier_requirement", "stronger_verifier" })) return "Stronger Verifier Required";
    if (matchesAny(kind, &.{ "exact_repeat_suppressed", "repeat_suppression" })) return "Exact Repeat Suppressed";
    if (matchesAny(kind, &.{"routing_warning"})) return "Routing Warning";
    if (matchesAny(kind, &.{ "trust_decay_candidate", "trust_decay" })) return "Trust Decay Candidate Proposed";
    return "Negative Knowledge Candidate Proposed";
}

pub fn printPackList(writer: anytype, packs: []json_contracts.PackInfo) !void {
    try writer.print("{s}{s:<20} {s:<10} {s:<10} {s:<15} {s}{s}\n", .{ bold, "ID", "Version", "Status", "Trust", "Domain", reset });
    try writer.print("-------------------------------------------------------------------------------\n", .{});

    for (packs) |pack| {
        const status_color = if (pack.is_mounted == true or (pack.status != null and std.mem.eql(u8, pack.status.?, "mounted"))) green else reset;
        try writer.print("{s:<20} {s:<10} {s}{s:<10}{s} {s:<15} {s:<15}\n", .{
            pack.id,
            pack.version orelse "-",
            status_color,
            pack.status orelse (if (pack.is_mounted == true) "mounted" else "available"),
            reset,
            pack.trust_class orelse "-",
            pack.domain orelse "-",
        });
    }
}

pub fn printPackInfo(writer: anytype, pack: json_contracts.PackInfo) !void {
    try writer.print("{s}Pack ID:{s}   {s}\n", .{ bold, reset, pack.id });
    try writer.print("{s}Version:{s}   {s}\n", .{ bold, reset, pack.version orelse "-" });
    try writer.print("{s}Status:{s}    {s}{s}{s}\n", .{ bold, reset, if (pack.is_mounted == true) green else reset, pack.status orelse (if (pack.is_mounted == true) "mounted" else "available"), reset });
    try writer.print("{s}Trust:{s}     {s}\n", .{ bold, reset, pack.trust_class orelse "-" });
    try writer.print("{s}Domain:{s}    {s}\n", .{ bold, reset, pack.domain orelse "-" });
    try writer.print("{s}Family:{s}    {s}\n", .{ bold, reset, pack.family orelse "-" });
    try writer.print("{s}Freshness:{s} {s}\n", .{ bold, reset, pack.freshness orelse "-" });
    try writer.print("{s}Source:{s}    {s}\n", .{ bold, reset, pack.source orelse "-" });
    try writer.print("{s}Path:{s}      {s}\n", .{ bold, reset, pack.path orelse "-" });

    if (pack.warnings) |warnings| {
        if (warnings.len > 0) {
            try writer.print("\n{s}Warnings:{s}\n", .{ red, reset });
            for (warnings) |warning| {
                try writer.print("  [!] {s}\n", .{warning});
            }
        }
    }

    if (pack.content_summary) |summary| {
        try writer.print("\n{s}Content Summary:{s}\n{s}\n", .{ bold, reset, summary });
    }
}

pub fn printCandidateList(writer: anytype, candidates: []json_contracts.CandidateInfo) !void {
    try writer.print("{s}{s:<30} {s:<15} {s:<12} {s:<10}{s}\n", .{ bold, "ID", "Type", "Eligibility", "Success", reset });
    try writer.print("-------------------------------------------------------------------------------------\n", .{});

    for (candidates) |cand| {
        const eligibility_color = if (cand.is_eligible) green else red;
        const status_label = if (cand.is_eligible) "Eligible" else "Ineligible";

        try writer.print("{s:<30} {s:<15} {s}{s:<12}{s} {s:<10}\n", .{
            cand.id,
            cand.type orelse "-",
            eligibility_color,
            status_label,
            reset,
            if (cand.success_count) |s| try std.fmt.allocPrint(std.heap.page_allocator, "{d}", .{s}) else "-",
        });
    }
}

pub fn printCandidateDetail(writer: anytype, cand: json_contracts.CandidateInfo) !void {
    try writer.print("{s}Candidate ID:{s} {s}\n", .{ bold, reset, cand.id });
    try writer.print("{s}Type:{s}         {s}\n", .{ bold, reset, cand.type orelse "-" });

    const eligibility_color = if (cand.is_eligible) green else red;
    try writer.print("{s}Eligibility:{s}  {s}{s}{s}\n", .{ bold, reset, eligibility_color, if (cand.is_eligible) "Eligible" else "Ineligible", reset });

    if (cand.eligibility_reason) |reason| {
        try writer.print("{s}Reason:{s}       {s}\n", .{ bold, reset, reason });
    }

    try writer.print("\n{s}Metrics:{s}\n", .{ bold, reset });
    try writer.print("  Successes:      {d}\n", .{cand.success_count orelse 0});
    try writer.print("  Failures:       {d}\n", .{cand.failure_count orelse 0});
    try writer.print("  Contradictions: {d}\n", .{cand.contradiction_count orelse 0});
    try writer.print("  Independent:    {d}\n", .{cand.independent_case_count orelse 0});

    try writer.print("\n{s}Analysis:{s}\n", .{ bold, reset });
    try writer.print("  Trust Rec:      {s}\n", .{cand.trust_recommendation orelse "-"});
    try writer.print("  Reuse Scope:    {s}\n", .{cand.reuse_scope orelse "-"});

    if (cand.provenance_summary) |prov| {
        try writer.print("\n{s}Provenance:{s} {s}\n", .{ bold, reset, prov });
    }

    if (cand.source_feedback_refs) |refs| {
        if (refs.len > 0) {
            try writer.print("\n{s}Source Feedback:{s}\n", .{ bold, reset });
            for (refs) |ref| {
                try writer.print("  - {s}\n", .{ref});
            }
        }
    }

    if (cand.what_it_influences) |inf| {
        try writer.print("\n{s}Impact:{s} {s}\n", .{ bold, reset, inf });
    }

    if (!cand.is_eligible) {
        try writer.print("\n{s}Note:{s} Review required. This candidate cannot be exported yet.\n", .{ yellow, reset });
    } else {
        try writer.print("\n{s}Note:{s} Approval required. This candidate is ready for export.\n", .{ yellow, reset });
    }
}

pub fn printExportResult(writer: anytype, res: json_contracts.ExportResult) !void {
    if (res.success) {
        try writer.print("{s}Export Successful{s}\n", .{ green, reset });
        try writer.print("Candidate: {s}\n", .{res.candidate_id});
        try writer.print("Target Pack: {s} (v{s})\n", .{ res.pack_id, res.version });
        if (res.is_non_authorizing) {
            try writer.print("{s}Status: Non-authorizing (hint mode){s}\n", .{ yellow, reset });
        }
        try writer.print("\nNext: ghost packs inspect {s}\n", .{res.pack_id});
    } else {
        try writer.print("{s}Export Failed{s}\n", .{ red, reset });
        if (res.message) |msg| {
            try writer.print("Error: {s}\n", .{msg});
        }
    }
}

pub fn printAutopsyResult(writer: anytype, res: json_contracts.AutopsyResult) !void {
    try writer.print("{s}Project Autopsy Result{s}\n", .{ bold, reset });

    if (res.project_profile) |profile| {
        if (profile.workspace_root) |root| {
            try writer.print("Workspace: {s}\n", .{root});
        }
        try writer.print("\n", .{});

        // 1. Detected Languages
        if (profile.detected_languages) |langs| {
            if (langs.len > 0) {
                try writer.print("{s}Detected Languages:{s}\n", .{ bold, reset });
                for (langs) |lang| {
                    try writer.print("  - {s}\n", .{lang.name});
                }
                try writer.print("\n", .{});
            }
        }

        // 2. Build Systems
        if (profile.build_systems) |builds| {
            if (builds.len > 0) {
                try writer.print("{s}Build Systems:{s}\n", .{ bold, reset });
                for (builds) |b| {
                    try writer.print("  - {s}\n", .{b.name});
                }
                try writer.print("\n", .{});
            }
        }

        // 3. Safe Command Candidates
        if (profile.safe_command_candidates) |cmds| {
            if (cmds.len > 0) {
                try writer.print("{s}Safe Command Candidates:{s}\n", .{ bold, reset });
                for (cmds) |c| {
                    try writer.print("  - {s}: ", .{c.id});
                    for (c.argv, 0..) |arg, i| {
                        try writer.print("{s}{s}", .{ arg, if (i < c.argv.len - 1) " " else "" });
                    }
                    try writer.print("\n", .{});
                }
                try writer.print("\n", .{});
            }
        }
    }

    // 4. Verifier Plan Candidates
    if (res.verifier_plan_candidates) |plans| {
        if (plans.len > 0) {
            try writer.print("{s}Verifier Plan Candidates:{s}\n", .{ bold, reset });
            for (plans) |p| {
                try writer.print("  - {s}: ", .{p.id});
                for (p.argv, 0..) |arg, i| {
                    try writer.print("{s}{s}", .{ arg, if (i < p.argv.len - 1) " " else "" });
                }
                if (p.purpose) |purpose| {
                    try writer.print(" ({s})", .{purpose});
                }
                try writer.print("\n", .{});
            }
            try writer.print("\n", .{});
        }
    }

    // 5. Gaps / Unknowns
    var has_gaps = false;
    if (res.project_gap_report) |report| {
        if (report.missing_ci != null or report.missing_test_command != null or report.missing_build_command != null or (report.missing_verifier_adapters != null and report.missing_verifier_adapters.?.len > 0)) {
            has_gaps = true;
            try writer.print("{s}Gaps Detected:{s}\n", .{ bold, reset });
            if (report.missing_ci != null) try writer.print("  - CI configuration missing\n", .{});
            if (report.missing_test_command != null) try writer.print("  - Test command missing\n", .{});
            if (report.missing_build_command != null) try writer.print("  - Build command missing\n", .{});
            if (report.missing_verifier_adapters) |adapters| {
                for (adapters) |a| {
                    try writer.print("  - Missing Verifier Adapter: {s}\n", .{a.name});
                }
            }
        }
    }

    if (res.project_profile) |profile| {
        if (profile.unknowns) |unknowns| {
            if (unknowns.len > 0) {
                if (!has_gaps) {
                    try writer.print("{s}Unknowns:{s}\n", .{ bold, reset });
                }
                for (unknowns) |u| {
                    try writer.print("  - ", .{});
                    try printJsonValue(writer, u, 4);
                    try writer.print("\n", .{});
                }
                has_gaps = true;
            }
        }
    }
    if (has_gaps) try writer.print("\n", .{});

    // 6. Non-authorizing notice
    try writer.print("{s}Notice: This output is a DRAFT and NON-AUTHORIZING.{s}\n", .{ yellow, reset });
    try writer.print("Project Autopsy candidates are proposals only and do not constitute evidence of correctness or support.\n", .{});
}

pub fn printContextAutopsyResult(writer: anytype, envelope: json_contracts.ContextAutopsyEnvelope) !void {
    try writer.print("{s}Context Autopsy Result{s}\n", .{ bold, reset });
    try writer.print("{s}State:{s} DRAFT\n", .{ bold, reset });
    try writer.print("{s}Authority:{s} NON-AUTHORIZING\n\n", .{ bold, reset });

    if (envelope.@"error") |err| {
        try writer.print("{s}Engine Error:{s}\n", .{ bold, reset });
        try printJsonValue(writer, err, 2);
        try writer.print("\n", .{});
        return;
    }

    const result = envelope.result orelse {
        try writer.print("No context autopsy result payload was present.\n", .{});
        return;
    };
    const result_obj = switch (result) {
        .object => |obj| obj,
        else => {
            try printJsonValue(writer, result, 2);
            try writer.print("\n", .{});
            return;
        },
    };
    const autopsy = result_obj.get("contextAutopsy") orelse result_obj.get("context_autopsy") orelse result;
    const autopsy_obj = switch (autopsy) {
        .object => |obj| obj,
        else => {
            try printJsonValue(writer, autopsy, 2);
            try writer.print("\n", .{});
            return;
        },
    };

    if (autopsy_obj.get("contextCase") orelse autopsy_obj.get("context_case")) |case_value| {
        try writer.print("{s}Context Case:{s}\n", .{ bold, reset });
        try printJsonValue(writer, case_value, 2);
        try writer.print("\n", .{});
    }

    try printContextSection(writer, autopsy_obj, "detectedSignals", "detected_signals", "Signals");
    try printContextSection(writer, autopsy_obj, "suggestedUnknowns", "suggested_unknowns", "Unknowns");
    try printContextSection(writer, autopsy_obj, "riskSurfaces", "risk_surfaces", "Risks");
    try printContextSection(writer, autopsy_obj, "candidateActions", "candidate_actions", "Candidate Actions");
    try printContextSection(writer, autopsy_obj, "checkCandidates", "check_candidates", "Check Candidates");
    try printContextSection(writer, autopsy_obj, "pendingEvidenceObligations", "pending_evidence_obligations", "Pending Obligations");
    try printContextSection(writer, autopsy_obj, "evidenceExpectations", "evidence_expectations", "Evidence Expectations");
    try printContextSection(writer, autopsy_obj, "packInfluences", "pack_influences", "Pack Influence");

    if (result_obj.get("inputCoverage") orelse result_obj.get("input_coverage") orelse autopsy_obj.get("inputCoverage") orelse autopsy_obj.get("input_coverage")) |coverage| {
        try writer.print("{s}Input Coverage:{s}\n", .{ bold, reset });
        try printJsonValue(writer, coverage, 2);
        try writer.print("\n", .{});
    }

    if (result_obj.get("packGuidanceTrace") orelse result_obj.get("pack_guidance_trace")) |trace| {
        try writer.print("{s}Pack Guidance Trace:{s}\n", .{ bold, reset });
        try printJsonValue(writer, trace, 2);
        try writer.print("\n", .{});
    }

    if (result_obj.get("artifactCoverage") orelse result_obj.get("artifact_coverage")) |coverage| {
        try writer.print("{s}Artifact Coverage:{s}\n", .{ bold, reset });
        try printJsonValue(writer, coverage, 2);
        try writer.print("\n", .{});
    }

    try writer.print("{s}Notice: This output is a DRAFT and NON-AUTHORIZING.{s}\n", .{ yellow, reset });
    try writer.print("Context Autopsy signals, unknowns, risks, actions, checks, obligations, and pack influence are candidates only and do not constitute proof or supported output.\n", .{});
}

fn printContextSection(writer: anytype, obj: std.json.ObjectMap, camel: []const u8, snake: []const u8, label: []const u8) !void {
    const value = obj.get(camel) orelse obj.get(snake) orelse return;
    if (isEmptyJsonList(value)) return;
    try writer.print("{s}{s}:{s}\n", .{ bold, label, reset });
    try printJsonValue(writer, value, 2);
    try writer.print("\n", .{});
}

fn isEmptyJsonList(value: std.json.Value) bool {
    return switch (value) {
        .array => |arr| arr.items.len == 0,
        else => false,
    };
}

fn printObligations(writer: anytype, value: std.json.Value, indent: usize) !void {
    switch (value) {
        .array => |arr| {
            for (arr.items) |item| {
                switch (item) {
                    .object => |obj| {
                        try printIndent(writer, indent);
                        try writer.print("- ", .{});
                        if (obj.get("id")) |id| {
                            try writer.print("{s}{s}{s}\n", .{ bold, id.string, reset });
                        } else {
                            try writer.print("\n", .{});
                        }

                        var it = obj.iterator();
                        while (it.next()) |entry| {
                            if (std.mem.eql(u8, entry.key_ptr.*, "id")) continue;
                            try printIndent(writer, indent + 2);
                            try writer.print("{s}: ", .{entry.key_ptr.*});
                            try printJsonValue(writer, entry.value_ptr.*, indent + 4);
                            try writer.print("\n", .{});
                        }
                    },
                    else => {
                        try printIndent(writer, indent);
                        try writer.print("- ", .{});
                        try printJsonValue(writer, item, indent + 2);
                        try writer.print("\n", .{});
                    },
                }
            }
        },
        else => try printJsonValue(writer, value, indent),
    }
}

fn printJsonValue(writer: anytype, value: std.json.Value, indent: usize) !void {
    switch (value) {
        .string => |s| try writer.print("{s}", .{s}),
        .integer => |i| try writer.print("{d}", .{i}),
        .float => |f| try writer.print("{d}", .{f}),
        .bool => |b| try writer.print("{s}", .{if (b) "true" else "false"}),
        .null => try writer.print("null", .{}),
        .array => |arr| {
            for (arr.items) |item| {
                try printIndent(writer, indent);
                try writer.print("- ", .{});
                try printJsonValue(writer, item, indent + 2);
                try writer.print("\n", .{});
            }
        },
        .object => |obj| {
            var it = obj.iterator();
            while (it.next()) |entry| {
                try printIndent(writer, indent);
                try writer.print("{s}: ", .{entry.key_ptr.*});
                try printJsonValue(writer, entry.value_ptr.*, indent + 2);
                try writer.print("\n", .{});
            }
        },
        else => try writer.print("{}", .{value}),
    }
}

fn printLabeledItems(writer: anytype, value: std.json.Value, prefix: []const u8) !void {
    switch (value) {
        .array => |arr| {
            for (arr.items) |item| {
                try writer.print("{s}", .{prefix});
                try printJsonValue(writer, item, prefix.len + 2);
                try writer.print("\n", .{});
            }
        },
        .object => |obj| {
            if (obj.get("items")) |items| {
                try printLabeledItems(writer, items, prefix);
            } else {
                try writer.print("{s}", .{prefix});
                try printJsonValue(writer, value, prefix.len + 2);
                try writer.print("\n", .{});
            }
        },
        .null => {},
        else => {
            try writer.print("{s}", .{prefix});
            try printJsonValue(writer, value, prefix.len + 2);
            try writer.print("\n", .{});
        },
    }
}

fn getStringField(obj: std.json.ObjectMap, field: []const u8) ?[]const u8 {
    const value = obj.get(field) orelse return null;
    return switch (value) {
        .string => |s| s,
        else => null,
    };
}

fn printOptionalJsonField(writer: anytype, obj: std.json.ObjectMap, field: []const u8, label: []const u8) !void {
    if (obj.get(field)) |value| {
        try writer.print("{s}: ", .{label});
        try printJsonValue(writer, value, 2);
        try writer.print("\n", .{});
    }
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

fn printIndent(writer: anytype, indent: usize) !void {
    var i: usize = 0;
    while (i < indent) : (i += 1) {
        try writer.print(" ", .{});
    }
}
