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
    try writer.print("{s}Status:{s} ", .{bold, reset});
    if (response.isDraftStatus()) {
        try writer.print("{s}Draft / unverified{s}\n", .{yellow, reset});
    } else if (response.getVerificationState()) |state| {
        if (std.mem.eql(u8, state, "verified") or std.mem.eql(u8, state, "supported")) {
            try writer.print("{s}Verified{s}\n", .{green, reset});
        } else if (std.mem.eql(u8, state, "unresolved")) {
            try writer.print("{s}Unresolved{s}\n", .{yellow, reset});
        } else if (std.mem.eql(u8, state, "failed")) {
            try writer.print("{s}Failed{s}\n", .{red, reset});
        } else {
            try writer.print("{s}{s}{s}\n", .{blue, state, reset});
        }
    } else {
        try writer.print("{s}Parsed JSON, unrecognized contract{s}\n", .{yellow, reset});
    }

    // 2. Metadata
    if (response.requested_reasoning_level orelse response.requestedReasoningLevel) |level| {
        try writer.print("{s}Reasoning:{s} {s}\n", .{bold, reset, level});
    }
    if (response.selected_response_mode orelse response.selectedResponseMode) |mode| {
        try writer.print("{s}Internal Mode:{s} {s}\n", .{bold, reset, mode});
    }
    if (response.effective_compute_budget_tier orelse response.effectiveComputeBudgetTier) |tier| {
        try writer.print("{s}Budget Tier:{s} {s}\n", .{bold, reset, tier});
    }

    try writer.print("\n", .{});

    // 3. Content
    if (response.getSummary()) |summary| {
        try writer.print("{s}Summary:{s}\n{s}\n\n", .{bold, reset, summary});
    }
    if (response.getDetail()) |detail| {
        try writer.print("{s}Detail:{s}\n{s}\n\n", .{bold, reset, detail});
    }

    // 4. Issues / Blockers
    if (response.getUnresolvedReason()) |reason| {
        try writer.print("{s}Unresolved Reason:{s} {s}\n", .{bold, reset, reason});
    }

    if (response.getStopReason()) |reason| {
        if (std.mem.eql(u8, reason, "budget_exhausted")) {
            try writer.print("{s}Stop Reason:{s} {s}Budget Exhausted{s}\n", .{bold, reset, red, reset});
        } else {
            try writer.print("{s}Stop Reason:{s} {s}\n", .{bold, reset, reason});
        }
    }

    if (response.getObligations()) |obligations| {
        try writer.print("{s}Pending Obligations:{s}\n", .{bold, reset});
        try printObligations(writer, obligations, 2);
        try writer.print("\n", .{});
    }

    if (response.getAmbiguities()) |choices| {
        try writer.print("{s}Ambiguities:{s}\n", .{bold, reset});
        try printJsonValue(writer, choices, 2);
        try writer.print("\n", .{});
    }

    if (response.verifier_summaries) |summaries| {
        try writer.print("{s}Verifier Summaries:{s}\n", .{bold, reset});
        try printJsonValue(writer, summaries, 2);
        try writer.print("\n", .{});
    }

    // 5. Next Steps
    if (response.getSuggestedAction()) |action| {
        try writer.print("{s}Suggested Action:{s} {s}\n", .{bold, reset, action});
    }

    // 6. Escalation hint if draft
    if (response.isDraftStatus()) {
        try writer.print("\n{s}Note:{s} This is an unverified draft. Run with {s}--reasoning=deep{s} or ask to {s}verify{s} to confirm.\n", .{yellow, reset, bold, reset, bold, reset});
    }
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
    try writer.print("  Successes:      {d}\n", .{ cand.success_count orelse 0 });
    try writer.print("  Failures:       {d}\n", .{ cand.failure_count orelse 0 });
    try writer.print("  Contradictions: {d}\n", .{ cand.contradiction_count orelse 0 });
    try writer.print("  Independent:    {d}\n", .{ cand.independent_case_count orelse 0 });
    
    try writer.print("\n{s}Analysis:{s}\n", .{ bold, reset });
    try writer.print("  Trust Rec:      {s}\n", .{ cand.trust_recommendation orelse "-" });
    try writer.print("  Reuse Scope:    {s}\n", .{ cand.reuse_scope orelse "-" });
    
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
        try writer.print("Candidate: {s}\n", .{ res.candidate_id });
        try writer.print("Target Pack: {s} (v{s})\n", .{ res.pack_id, res.version });
        if (res.is_non_authorizing) {
            try writer.print("{s}Status: Non-authorizing (hint mode){s}\n", .{ yellow, reset });
        }
        try writer.print("\nNext: ghost packs inspect {s}\n", .{ res.pack_id });
    } else {
        try writer.print("{s}Export Failed{s}\n", .{ red, reset });
        if (res.message) |msg| {
            try writer.print("Error: {s}\n", .{ msg });
        }
    }
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

fn printIndent(writer: anytype, indent: usize) !void {
    var i: usize = 0;
    while (i < indent) : (i += 1) {
        try writer.print(" ", .{});
    }
}
