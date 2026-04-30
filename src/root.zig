const std = @import("std");
const testing = std.testing;

const paths = @import("config/paths.zig");
const locator = @import("engine/locator.zig");
const json_contracts = @import("engine/json_contracts.zig");
const terminal = @import("render/terminal.zig");
const tui_input = @import("tui/input.zig");
const stats = @import("tui/stats.zig");
const state = @import("tui/state.zig");
const tui_app = @import("tui/app.zig");
const tui_render = @import("tui/render.zig");
const tui_slash = @import("tui/slash.zig");
const tui_terminal = @import("tui/terminal.zig");

comptime {
    _ = tui_input;
    _ = tui_terminal;
}

fn renderEngineJson(allocator: std.mem.Allocator, json: []const u8) ![]u8 {
    var parsed = try json_contracts.parseEngineJson(allocator, json);
    defer parsed.deinit();

    var out_buf = std.ArrayList(u8).init(allocator);
    errdefer out_buf.deinit();
    try terminal.printEngineOutput(out_buf.writer(), parsed.value);
    return try out_buf.toOwnedSlice();
}

test "engine path resolution order - explicit flag" {
    var engine_paths = try paths.discoverEngineRoot(testing.allocator, "/opt/custom/engine");
    defer if (engine_paths) |*ep| ep.deinit(testing.allocator);

    try testing.expect(engine_paths != null);
    try testing.expectEqualStrings("/opt/custom/engine", engine_paths.?.root);
}

test "JSON parsing with extra fields" {
    const json =
        \\{
        \\  "status": "ok",
        \\  "is_draft": true,
        \\  "unknown_field": 123
        \\}
    ;

    var parsed = try json_contracts.parseEngineJson(testing.allocator, json);
    defer parsed.deinit();
    const val = parsed.value;
    try testing.expectEqualStrings("ok", val.status.?);
    try testing.expect(val.isDraftStatus() == true);
}

test "draft rendering is labeled unverified" {
    const json =
        \\{
        \\  "is_draft": true
        \\}
    ;

    var parsed = try json_contracts.parseEngineJson(testing.allocator, json);
    defer parsed.deinit();
    const val = parsed.value;

    var out_buf = std.ArrayList(u8).init(testing.allocator);
    defer out_buf.deinit();

    try terminal.printEngineOutput(out_buf.writer(), val);
    try testing.expect(std.mem.indexOf(u8, out_buf.items, "Draft / unverified") != null);
}

test "verified rendering is labeled verified" {
    const json =
        \\{
        \\  "verification_state": "verified"
        \\}
    ;

    var parsed = try json_contracts.parseEngineJson(testing.allocator, json);
    defer parsed.deinit();
    const val = parsed.value;

    var out_buf = std.ArrayList(u8).init(testing.allocator);
    defer out_buf.deinit();

    try terminal.printEngineOutput(out_buf.writer(), val);
    try testing.expect(std.mem.indexOf(u8, out_buf.items, "Verified") != null);
}

test "unresolved rendering includes missing obligations" {
    const json =
        \\{
        \\  "verification_state": "unresolved",
        \\  "unresolved_reason": "Missing facts",
        \\  "missing_obligations": ["fact A", "fact B"]
        \\}
    ;

    var parsed = try json_contracts.parseEngineJson(testing.allocator, json);
    defer parsed.deinit();
    const val = parsed.value;

    var out_buf = std.ArrayList(u8).init(testing.allocator);
    defer out_buf.deinit();

    try terminal.printEngineOutput(out_buf.writer(), val);
    try testing.expect(std.mem.indexOf(u8, out_buf.items, "Unresolved") != null);
    try testing.expect(std.mem.indexOf(u8, out_buf.items, "Missing facts") != null);
    try testing.expect(std.mem.indexOf(u8, out_buf.items, "Pending Obligations:") != null);
}

test "budget exhausted rendering" {
    const json =
        \\{
        \\  "stop_reason": "budget_exhausted"
        \\}
    ;

    var parsed = try json_contracts.parseEngineJson(testing.allocator, json);
    defer parsed.deinit();
    const val = parsed.value;

    var out_buf = std.ArrayList(u8).init(testing.allocator);
    defer out_buf.deinit();

    try terminal.printEngineOutput(out_buf.writer(), val);
    try testing.expect(std.mem.indexOf(u8, out_buf.items, "Budget Exhausted") != null);
}

test "summary and suggested action rendering" {
    const json =
        \\{
        \\  "summary": "This is a summary.",
        \\  "suggested_action": "Run with more budget."
        \\}
    ;

    var parsed = try json_contracts.parseEngineJson(testing.allocator, json);
    defer parsed.deinit();
    const val = parsed.value;

    var out_buf = std.ArrayList(u8).init(testing.allocator);
    defer out_buf.deinit();

    try terminal.printEngineOutput(out_buf.writer(), val);
    try testing.expect(std.mem.indexOf(u8, out_buf.items, "Summary:") != null);
    try testing.expect(std.mem.indexOf(u8, out_buf.items, "This is a summary.") != null);
    try testing.expect(std.mem.indexOf(u8, out_buf.items, "Next Action:") != null);
    try testing.expect(std.mem.indexOf(u8, out_buf.items, "Run with more budget.") != null);
}

test "epistemic render shows state label and authority statement" {
    const rendered = try renderEngineJson(testing.allocator,
        \\{
        \\  "epistemic_render": {
        \\    "state_label": "unresolved",
        \\    "authority_statement": "not enough evidence for support"
        \\  }
        \\}
    );
    defer testing.allocator.free(rendered);

    try testing.expect(std.mem.indexOf(u8, rendered, "Epistemic State:") != null);
    try testing.expect(std.mem.indexOf(u8, rendered, "Engine Label: unresolved") != null);
    try testing.expect(std.mem.indexOf(u8, rendered, "Engine Authority: not enough evidence for support") != null);
    try testing.expect(std.mem.indexOf(u8, rendered, "Does not prove support") != null);
}

test "correction item renders as correction not apology" {
    const rendered = try renderEngineJson(testing.allocator,
        \\{
        \\  "corrections": {
        \\    "summary": "Prior answer overstated support",
        \\    "items": [
        \\      { "id": "corr-1", "text": "Replace supported with unresolved" }
        \\    ]
        \\  }
        \\}
    );
    defer testing.allocator.free(rendered);

    try testing.expect(std.mem.indexOf(u8, rendered, "Correction Recorded:") != null);
    try testing.expect(std.mem.indexOf(u8, rendered, "Prior answer overstated support") != null);
    try testing.expect(std.mem.indexOf(u8, rendered, "apology") == null);
    try testing.expect(std.mem.indexOf(u8, rendered, "Does not prove support") != null);
}

test "NK candidate renders as proposed and review needed" {
    const rendered = try renderEngineJson(testing.allocator,
        \\{
        \\  "negative_knowledge": {
        \\    "proposed_candidates": [
        \\      { "id": "nk-cand-1", "reason": "failed pattern" }
        \\    ]
        \\  }
        \\}
    );
    defer testing.allocator.free(rendered);

    try testing.expect(std.mem.indexOf(u8, rendered, "Negative Knowledge Candidate Proposed:") != null);
    try testing.expect(std.mem.indexOf(u8, rendered, "Candidate only") != null);
    try testing.expect(std.mem.indexOf(u8, rendered, "Requires review") != null);
}

test "accepted NK influence renders as prior failure influence" {
    const rendered = try renderEngineJson(testing.allocator,
        \\{
        \\  "negative_knowledge": {
        \\    "influence_summary": "accepted record lowered rank for repeated failed path",
        \\    "applied_records": [
        \\      { "id": "nk-accepted-1", "scope": "local" }
        \\    ]
        \\  }
        \\}
    );
    defer testing.allocator.free(rendered);

    try testing.expect(std.mem.indexOf(u8, rendered, "Negative Knowledge Applied:") != null);
    try testing.expect(std.mem.indexOf(u8, rendered, "prior failure influence") != null);
    try testing.expect(std.mem.indexOf(u8, rendered, "Non-authorizing") != null);
}

test "stronger verifier requirement renders" {
    const rendered = try renderEngineJson(testing.allocator,
        \\{
        \\  "negative_knowledge": {
        \\    "items": [
        \\      { "kind": "stronger_verifier_required", "verifier": "integration" }
        \\    ]
        \\  }
        \\}
    );
    defer testing.allocator.free(rendered);

    try testing.expect(std.mem.indexOf(u8, rendered, "Stronger Verifier Required:") != null);
    try testing.expect(std.mem.indexOf(u8, rendered, "Does not prove support") != null);
}

test "exact repeat suppression renders" {
    const rendered = try renderEngineJson(testing.allocator,
        \\{
        \\  "negative_knowledge": {
        \\    "items": [
        \\      { "kind": "exact_repeat_suppressed", "pattern": "same failed command" }
        \\    ]
        \\  }
        \\}
    );
    defer testing.allocator.free(rendered);

    try testing.expect(std.mem.indexOf(u8, rendered, "Exact Repeat Suppressed:") != null);
    try testing.expect(std.mem.indexOf(u8, rendered, "Non-authorizing prior failure influence") != null);
}

test "routing warning renders" {
    const rendered = try renderEngineJson(testing.allocator,
        \\{
        \\  "negative_knowledge": {
        \\    "items": [
        \\      { "kind": "routing_warning", "message": "route was penalized" }
        \\    ]
        \\  }
        \\}
    );
    defer testing.allocator.free(rendered);

    try testing.expect(std.mem.indexOf(u8, rendered, "Routing Warning:") != null);
    try testing.expect(std.mem.indexOf(u8, rendered, "Non-authorizing routing warning") != null);
}

test "NK prose substrings do not infer structured semantics" {
    const rendered = try renderEngineJson(testing.allocator,
        \\{
        \\  "negative_knowledge": {
        \\    "items": [
        \\      {
        \\        "id": "nk-prose-only",
        \\        "reason": "prose mentions stronger_verifier_required, exact_repeat_suppressed, routing_warning, and trust_decay"
        \\      }
        \\    ]
        \\  }
        \\}
    );
    defer testing.allocator.free(rendered);

    try testing.expect(std.mem.indexOf(u8, rendered, "Negative Knowledge Candidate Proposed:") != null);
    try testing.expect(std.mem.indexOf(u8, rendered, "Stronger Verifier Required:") == null);
    try testing.expect(std.mem.indexOf(u8, rendered, "Exact Repeat Suppressed:") == null);
    try testing.expect(std.mem.indexOf(u8, rendered, "Routing Warning:") == null);
    try testing.expect(std.mem.indexOf(u8, rendered, "Trust Decay Candidate Proposed:") == null);
}

test "render counters use explicit NK kind fields only" {
    var parsed = try json_contracts.parseEngineJson(testing.allocator,
        \\{
        \\  "negative_knowledge": {
        \\    "items": [
        \\      { "kind": "stronger_verifier_required", "id": "explicit" },
        \\      { "reason": "routing_warning and exact_repeat_suppressed in prose only" }
        \\    ]
        \\  }
        \\}
    );
    defer parsed.deinit();

    const counters = json_contracts.renderCounters(parsed.value);
    try testing.expectEqual(@as(usize, 1), counters.verifier_requirements);
    try testing.expectEqual(@as(usize, 0), counters.routing_warnings);
    try testing.expectEqual(@as(usize, 0), counters.suppressions);
}

test "trust decay candidate renders as candidate only" {
    const rendered = try renderEngineJson(testing.allocator,
        \\{
        \\  "negative_knowledge": {
        \\    "trust_decay_candidates": [
        \\      { "id": "decay-1", "trust_decay": "review stale pack" }
        \\    ]
        \\  }
        \\}
    );
    defer testing.allocator.free(rendered);

    try testing.expect(std.mem.indexOf(u8, rendered, "Trust Decay Candidate Proposed:") != null);
    try testing.expect(std.mem.indexOf(u8, rendered, "Candidate only") != null);
    try testing.expect(std.mem.indexOf(u8, rendered, "Requires review") != null);
}

test "missing correction NK epistemic fields do not crash" {
    const rendered = try renderEngineJson(testing.allocator,
        \\{
        \\  "verification_state": "unresolved",
        \\  "summary": "No optional fields here"
        \\}
    );
    defer testing.allocator.free(rendered);

    try testing.expect(std.mem.indexOf(u8, rendered, "Unresolved") != null);
    try testing.expect(std.mem.indexOf(u8, rendered, "No optional fields here") != null);
}

test "debug reports correction NK epistemic field detection" {
    var parsed = try json_contracts.parseEngineJson(testing.allocator,
        \\{
        \\  "corrections": { "items": [{ "id": "c1" }] },
        \\  "negative_knowledge": { "proposed_candidates": [{ "id": "n1" }] },
        \\  "epistemic_render": { "state_label": "draft" }
        \\}
    );
    defer parsed.deinit();

    var out_buf = std.ArrayList(u8).init(testing.allocator);
    defer out_buf.deinit();
    try terminal.printDebugFieldDetection(out_buf.writer(), parsed.value);

    try testing.expect(std.mem.indexOf(u8, out_buf.items, "corrections=yes") != null);
    try testing.expect(std.mem.indexOf(u8, out_buf.items, "negative_knowledge=yes") != null);
    try testing.expect(std.mem.indexOf(u8, out_buf.items, "epistemic_render=yes") != null);
    try testing.expect(std.mem.indexOf(u8, out_buf.items, "nk_candidates=1") != null);
}

test "TUI render helper handles correction NK sections" {
    const rendered = try renderEngineJson(testing.allocator,
        \\{
        \\  "corrections": { "summary": "Corrected prior label" },
        \\  "negative_knowledge": {
        \\    "proposed_candidates": [{ "id": "nk-cand-2" }]
        \\  }
        \\}
    );
    defer testing.allocator.free(rendered);

    var out_buf = std.ArrayList(u8).init(testing.allocator);
    defer out_buf.deinit();
    const turn = state.Turn{
        .index = 1,
        .input = "hello",
        .reasoning = .balanced,
        .context_artifact = null,
        .response = null,
        .raw_output = "{}",
        .rendered_output = rendered,
        .elapsed_ms = 1,
        .input_runes = 5,
        .output_runes = stats.countRunes(rendered),
        .json_ok = true,
    };
    try tui_render.renderTurn(out_buf.writer(), turn, .{ .color = false });
    try testing.expect(std.mem.indexOf(u8, out_buf.items, "[YOU]") != null);
    try testing.expect(std.mem.indexOf(u8, out_buf.items, "[GHOST]") != null);
    try testing.expect(std.mem.indexOf(u8, out_buf.items, "+-- TURN 1") != null);
    try testing.expect(std.mem.indexOf(u8, out_buf.items, "Correction Recorded:") != null);
    try testing.expect(std.mem.indexOf(u8, out_buf.items, "Negative Knowledge Candidate Proposed:") != null);
}

test "pack list rendering" {
    const json =
        \\[
        \\    {"id": "test_pack", "version": "1.0.0", "status": "mounted", "domain": "test"},
        \\    {"id": "other_pack", "is_mounted": false}
        \\]
    ;

    var parsed = try json_contracts.parsePackListJson(testing.allocator, json);
    defer parsed.deinit();

    var out_buf = std.ArrayList(u8).init(testing.allocator);
    defer out_buf.deinit();

    try terminal.printPackList(out_buf.writer(), parsed.value);
    try testing.expect(std.mem.indexOf(u8, out_buf.items, "test_pack") != null);
    try testing.expect(std.mem.indexOf(u8, out_buf.items, "mounted") != null);
    try testing.expect(std.mem.indexOf(u8, out_buf.items, "other_pack") != null);
}

test "pack info rendering" {
    const json =
        \\{
        \\  "id": "full_pack",
        \\  "version": "2.1.0",
        \\  "is_mounted": true,
        \\  "warnings": ["stale data"],
        \\  "content_summary": "Provides core types."
        \\}
    ;

    var parsed = try json_contracts.parsePackInfoJson(testing.allocator, json);
    defer parsed.deinit();

    var out_buf = std.ArrayList(u8).init(testing.allocator);
    defer out_buf.deinit();

    try terminal.printPackInfo(out_buf.writer(), parsed.value);
    try testing.expect(std.mem.indexOf(u8, out_buf.items, "Pack ID:") != null);
    try testing.expect(std.mem.indexOf(u8, out_buf.items, "full_pack") != null);
    try testing.expect(std.mem.indexOf(u8, out_buf.items, "stale data") != null);
    try testing.expect(std.mem.indexOf(u8, out_buf.items, "Provides core types.") != null);
}

test "candidate list rendering" {
    const json =
        \\[
        \\    {"id": "cand_1", "type": "fix", "is_eligible": true, "success_count": 5},
        \\    {"id": "cand_2", "type": "feat", "is_eligible": false}
        \\]
    ;

    var parsed = try json_contracts.parseCandidateListJson(testing.allocator, json);
    defer parsed.deinit();

    var out_buf = std.ArrayList(u8).init(testing.allocator);
    defer out_buf.deinit();

    try terminal.printCandidateList(out_buf.writer(), parsed.value);
    try testing.expect(std.mem.indexOf(u8, out_buf.items, "cand_1") != null);
    try testing.expect(std.mem.indexOf(u8, out_buf.items, "Eligible") != null);
    try testing.expect(std.mem.indexOf(u8, out_buf.items, "cand_2") != null);
    try testing.expect(std.mem.indexOf(u8, out_buf.items, "Ineligible") != null);
}

test "candidate detail rendering" {
    const json =
        \\{
        \\    "id": "cand_detail",
        \\    "type": "refactor",
        \\    "is_eligible": false,
        \\    "eligibility_reason": "Too many contradictions",
        \\    "provenance_summary": "Derived from 3 sessions",
        \\    "success_count": 2,
        \\    "failure_count": 4
        \\}
    ;

    var parsed = try json_contracts.parseCandidateInfoJson(testing.allocator, json);
    defer parsed.deinit();

    var out_buf = std.ArrayList(u8).init(testing.allocator);
    defer out_buf.deinit();

    try terminal.printCandidateDetail(out_buf.writer(), parsed.value);
    try testing.expect(std.mem.indexOf(u8, out_buf.items, "Candidate ID:") != null);
    try testing.expect(std.mem.indexOf(u8, out_buf.items, "cand_detail") != null);
    try testing.expect(std.mem.indexOf(u8, out_buf.items, "Too many contradictions") != null);
    try testing.expect(std.mem.indexOf(u8, out_buf.items, "Derived from 3 sessions") != null);
    try testing.expect(std.mem.indexOf(u8, out_buf.items, "Successes:      2") != null);
}

test "export result rendering" {
    const json =
        \\{
        \\    "success": true,
        \\    "candidate_id": "cand_x",
        \\    "pack_id": "pack_y",
        \\    "version": "1.0.1"
        \\}
    ;

    var parsed = try json_contracts.parseExportResultJson(testing.allocator, json);
    defer parsed.deinit();

    var out_buf = std.ArrayList(u8).init(testing.allocator);
    defer out_buf.deinit();

    try terminal.printExportResult(out_buf.writer(), parsed.value);
    try testing.expect(std.mem.indexOf(u8, out_buf.items, "Export Successful") != null);
    try testing.expect(std.mem.indexOf(u8, out_buf.items, "Target Pack: pack_y (v1.0.1)") != null);
}

test "actual engine chat JSON rendering" {
    const json =
        \\{
        \\  "formatVersion": "ghost_conversation_session_v1",
        \\  "sessionId": "conv-test",
        \\  "lastResult": {
        \\    "kind": "unresolved",
        \\    "selected_mode": "unresolved",
        \\    "stop_reason": "unresolved",
        \\    "summary": "blocked because ambiguity",
        \\    "artifact_path": null
        \\  },
        \\  "pendingObligations": [
        \\    { "id": "test_obl", "label": "test obligation", "required_for": "any_action" }
        \\  ]
        \\}
    ;

    var parsed = try json_contracts.parseEngineJson(testing.allocator, json);
    defer parsed.deinit();
    const val = parsed.value;

    var out_buf = std.ArrayList(u8).init(testing.allocator);
    defer out_buf.deinit();

    try terminal.printEngineOutput(out_buf.writer(), val);
    try testing.expect(std.mem.indexOf(u8, out_buf.items, "Status:") != null);
    try testing.expect(std.mem.indexOf(u8, out_buf.items, "Unresolved") != null);
    try testing.expect(std.mem.indexOf(u8, out_buf.items, "blocked because ambiguity") != null);
    try testing.expect(std.mem.indexOf(u8, out_buf.items, "Pending Obligations:") != null);
    try testing.expect(std.mem.indexOf(u8, out_buf.items, "test obligation") != null);
}

test "unrecognized contract rendering" {
    const json =
        \\{
        \\  "something_weird": true
        \\}
    ;

    var parsed = try json_contracts.parseEngineJson(testing.allocator, json);
    defer parsed.deinit();
    const val = parsed.value;

    var out_buf = std.ArrayList(u8).init(testing.allocator);
    defer out_buf.deinit();

    try terminal.printEngineOutput(out_buf.writer(), val);
    try testing.expect(std.mem.indexOf(u8, out_buf.items, "unrecognized contract") != null);
}

test "install scripts exist" {
    try std.fs.cwd().access("scripts/install.sh", .{});
    try std.fs.cwd().access("scripts/uninstall.sh", .{});
}

test "help text does not contain old name" {
    const readme = try std.fs.cwd().readFileAlloc(testing.allocator, "README.md", 1024 * 1024);
    defer testing.allocator.free(readme);
    try testing.expect(std.mem.indexOf(u8, readme, "ghost_cli binary path") == null);
}

test "docs avoid global side-effect safety claims" {
    const commands = try std.fs.cwd().readFileAlloc(testing.allocator, "docs/COMMANDS.md", 1024 * 1024);
    defer testing.allocator.free(commands);
    const readme = try std.fs.cwd().readFileAlloc(testing.allocator, "README.md", 1024 * 1024);
    defer testing.allocator.free(readme);
    const contract = try std.fs.cwd().readFileAlloc(testing.allocator, "docs/ENGINE_CONTRACT.md", 1024 * 1024);
    defer testing.allocator.free(contract);
    const architecture = try std.fs.cwd().readFileAlloc(testing.allocator, "docs/ARCHITECTURE.md", 1024 * 1024);
    defer testing.allocator.free(architecture);

    try testing.expect(std.mem.indexOf(u8, commands, "No engine logic, Project Autopsy scanning, verifier execution, or pack mutation occurs on launch") == null);
    try testing.expect(std.mem.indexOf(u8, commands, "No scan is ever run automatically") == null);
    try testing.expect(std.mem.indexOf(u8, readme, "Launching it does not run doctor,\nautopsy, verifiers, scans, or pack mutation") == null);
    try testing.expect(std.mem.indexOf(u8, contract, "The CLI does not execute verifiers, corrections, negative-knowledge review/mutation APIs, pack mutation, or MCP calls.") == null);
    try testing.expect(std.mem.indexOf(u8, architecture, "The CLI must never calculate paths") == null);
}

test "reasoning level string conversion" {
    try testing.expectEqualStrings("quick", json_contracts.ReasoningLevel.quick.toStr());
    try testing.expectEqualStrings("deep", json_contracts.ReasoningLevel.deep.toStr());
}

test "rune counting handles ASCII and Unicode" {
    try testing.expectEqual(@as(usize, 5), stats.countRunes("hello"));
    try testing.expectEqual(@as(usize, 1), stats.countRunes("👻"));
    try testing.expectEqual(@as(usize, 13), stats.countRunes("hello 👻 world"));
}

test "reasoning cycling" {
    var s = state.SessionState.init(testing.allocator, "test", null, false);
    defer s.deinit();

    try testing.expect(s.reasoning == .balanced);
    s.cycleReasoning();
    try testing.expect(s.reasoning == .deep);
    s.cycleReasoning();
    try testing.expect(s.reasoning == .max);
    s.cycleReasoning();
    try testing.expect(s.reasoning == .quick);
}

test "stats RAM formatting" {
    const s1 = try stats.formatBytes(testing.allocator, 512);
    defer testing.allocator.free(s1);
    try testing.expectEqualStrings("512B", s1);

    const s2 = try stats.formatBytes(testing.allocator, 1024 * 10);
    defer testing.allocator.free(s2);
    try testing.expectEqualStrings("10KB", s2);

    const s3 = try stats.formatBytes(testing.allocator, 1024 * 1024 * 5);
    defer testing.allocator.free(s3);
    try testing.expectEqualStrings("5MB", s3);
}

test "TUI session state clear history" {
    var s = state.SessionState.init(testing.allocator, "test", null, false);
    defer s.deinit();

    const turn = state.Turn{
        .index = 1,
        .input = try testing.allocator.dupe(u8, "hello"),
        .reasoning = .balanced,
        .context_artifact = null,
        .response = null,
        .raw_output = try testing.allocator.dupe(u8, "raw"),
        .rendered_output = try testing.allocator.dupe(u8, "rendered"),
        .elapsed_ms = 10,
        .input_runes = 5,
        .output_runes = 8,
        .json_ok = true,
    };
    try s.history.append(turn);

    try testing.expectEqual(@as(usize, 1), s.history.items.len);
    s.clearHistory();
    try testing.expectEqual(@as(usize, 0), s.history.items.len);
}

fn testTurn(allocator: std.mem.Allocator, index: usize, input_text: []const u8) !state.Turn {
    return .{
        .index = index,
        .input = try allocator.dupe(u8, input_text),
        .reasoning = .balanced,
        .context_artifact = null,
        .response = null,
        .raw_output = try allocator.dupe(u8, "raw"),
        .rendered_output = try allocator.dupe(u8, "rendered"),
        .elapsed_ms = 10,
        .input_runes = stats.countRunes(input_text),
        .output_runes = 8,
        .json_ok = true,
    };
}

test "TUI history pruning retains bounded turns and frees owned buffers structurally" {
    var s = state.SessionState.initWithLimit(testing.allocator, "test", null, false, 2);
    defer s.deinit();

    try s.appendTurn(try testTurn(testing.allocator, s.nextTurnIndex(), "one"));
    try s.appendTurn(try testTurn(testing.allocator, s.nextTurnIndex(), "two"));
    try s.appendTurn(try testTurn(testing.allocator, s.nextTurnIndex(), "three"));

    try testing.expectEqual(@as(usize, 2), s.history.items.len);
    try testing.expectEqual(@as(usize, 3), s.total_turns);
    try testing.expectEqual(@as(usize, 1), s.pruned_turns);
    try testing.expectEqual(@as(usize, 1), s.freed_turns);
    try testing.expectEqualStrings("two", s.history.items[0].input);
    try testing.expectEqualStrings("three", s.history.items[1].input);
}

test "TUI resize repaint works after history pruning" {
    var s = state.SessionState.initWithLimit(testing.allocator, "test", null, false, 1);
    defer s.deinit();
    s.previous_render_rows = 24;
    s.previous_render_cols = 80;
    s.previous_fixed_rows = 3;
    s.previous_panel_bottom = 21;
    s.previous_suggestion_height = 4;

    try s.appendTurn(try testTurn(testing.allocator, s.nextTurnIndex(), "old"));
    try s.appendTurn(try testTurn(testing.allocator, s.nextTurnIndex(), "new"));

    var out_buf = std.ArrayList(u8).init(testing.allocator);
    defer out_buf.deinit();
    try tui_render.renderFrameWithSize(out_buf.writer(), &s, .{ .color = false }, .{ .rows = 36, .cols = 100 });

    try testing.expect(std.mem.indexOf(u8, out_buf.items, "+-- TURN 2") != null);
    try testing.expect(std.mem.indexOf(u8, out_buf.items, "[YOU]  new") != null);
    try testing.expect(std.mem.indexOf(u8, out_buf.items, "[YOU]  old") == null);
}

var fake_terminal_refreshes: usize = 0;
fn fakeTerminalSize() tui_terminal.TerminalSize {
    fake_terminal_refreshes += 1;
    return .{ .rows = 40, .cols = 120 };
}

var fake_ram_refreshes: usize = 0;
fn fakeRam() ?usize {
    fake_ram_refreshes += 1;
    return 4096;
}

test "TUI size and RAM refresh caches avoid per-key polling" {
    fake_terminal_refreshes = 0;
    fake_ram_refreshes = 0;
    var s = state.SessionState.init(testing.allocator, "test", null, false);
    defer s.deinit();

    s.refreshTerminalSize(0, fakeTerminalSize);
    s.refreshTerminalSize(10, fakeTerminalSize);
    s.refreshTerminalSize(state.terminal_refresh_interval_ms, fakeTerminalSize);
    try testing.expectEqual(@as(usize, 2), fake_terminal_refreshes);

    s.refreshRam(0, fakeRam);
    s.refreshRam(10, fakeRam);
    s.refreshRam(state.ram_refresh_interval_ms, fakeRam);
    try testing.expectEqual(@as(usize, 2), fake_ram_refreshes);
}

test "TUI terminal size default behavior is isolated and portable" {
    try testing.expectEqual(tui_terminal.TerminalSize{ .rows = 24, .cols = 80 }, tui_terminal.fallbackSize());
    try testing.expectEqual(tui_terminal.TerminalSize{ .rows = 24, .cols = 80 }, tui_terminal.validOrDefault(0, 0));
    try testing.expectEqual(tui_terminal.TerminalSize{ .rows = 12, .cols = 40 }, tui_terminal.validOrDefault(12, 40));
}

test "TUI slash command parser covers operator commands" {
    try testing.expectEqual(tui_app.SlashKind.help, tui_app.parseSlashCommand("/help").kind);
    try testing.expectEqual(tui_app.SlashKind.quit, tui_app.parseSlashCommand("/quit").kind);
    try testing.expectEqual(tui_app.SlashKind.status, tui_app.parseSlashCommand("/status").kind);
    try testing.expectEqual(tui_app.SlashKind.clear, tui_app.parseSlashCommand("/clear").kind);
    try testing.expectEqual(tui_app.SlashKind.doctor, tui_app.parseSlashCommand("/doctor").kind);
    try testing.expectEqual(tui_app.SlashKind.debug, tui_app.parseSlashCommand("/debug").kind);
    try testing.expectEqual(tui_app.SlashKind.json, tui_app.parseSlashCommand("/json").kind);

    const reasoning = tui_app.parseSlashCommand("/reasoning deep");
    try testing.expectEqual(tui_app.SlashKind.reasoning, reasoning.kind);
    try testing.expectEqualStrings("deep", reasoning.arg.?);

    const autopsy_cmd = tui_app.parseSlashCommand("/autopsy .");
    try testing.expectEqual(tui_app.SlashKind.autopsy, autopsy_cmd.kind);
    try testing.expectEqualStrings(".", autopsy_cmd.arg.?);

    const context = tui_app.parseSlashCommand("/context src/main.zig");
    try testing.expectEqual(tui_app.SlashKind.context, context.kind);
    try testing.expectEqualStrings("src/main.zig", context.arg.?);
}

test "TUI read-only mode blocks engine-invoking slash commands and prompts" {
    try testing.expect(tui_app.isReadOnlyBlockedCommand(tui_app.parseSlashCommand("/autopsy .")));
    try testing.expect(tui_app.isReadOnlyBlockedCommand(tui_app.parseSlashCommand("/doctor")));
    try testing.expect(!tui_app.isReadOnlyBlockedCommand(tui_app.parseSlashCommand("/help")));
    try testing.expect(!tui_app.isReadOnlyBlockedCommand(tui_app.parseSlashCommand("/status")));
    try testing.expect(!tui_app.isReadOnlyBlockedCommand(tui_app.parseSlashCommand("/context README.md")));
    try testing.expect(!tui_app.shouldSubmitToEngineInMode("normal prompt", true));
    try testing.expect(tui_app.shouldSubmitToEngineInMode("normal prompt", false));

    var s = state.SessionState.init(testing.allocator, "test", null, false);
    defer s.deinit();
    s.read_only = true;
    s.terminal_size = .{ .rows = 24, .cols = 80 };

    var out_buf = std.ArrayList(u8).init(testing.allocator);
    defer out_buf.deinit();

    const mock_root = "/tmp/ghost-read-only-blocked";
    const marker = mock_root ++ "/autopsy-marker";
    const prompt_marker = mock_root ++ "/prompt-marker";
    try std.fs.cwd().makePath(mock_root);
    defer std.fs.cwd().deleteTree(mock_root) catch {};
    {
        const file = try std.fs.cwd().createFile(mock_root ++ "/ghost_project_autopsy", .{ .mode = 0o755 });
        defer file.close();
        try file.writeAll("#!/bin/sh\ntouch '" ++ marker ++ "'\nprintf '{}'\n");
    }
    {
        const file = try std.fs.cwd().createFile(mock_root ++ "/ghost_task_operator", .{ .mode = 0o755 });
        defer file.close();
        try file.writeAll("#!/bin/sh\ntouch '" ++ prompt_marker ++ "'\nprintf '{}'\n");
    }

    _ = try tui_app.handleSlash(testing.allocator, mock_root, &s, "/autopsy .", out_buf.writer(), .{ .color = false });
    try testing.expect(std.mem.indexOf(u8, out_buf.items, "Read-only mode: command blocked: /autopsy") != null);
    try testing.expectError(error.FileNotFound, std.fs.cwd().access(marker, .{}));

    out_buf.clearRetainingCapacity();
    try tui_app.handleSubmit(testing.allocator, mock_root, &s, "hello", out_buf.writer(), .{ .color = false });
    try testing.expect(std.mem.indexOf(u8, out_buf.items, "Read-only mode: engine prompt blocked") != null);
    try testing.expectError(error.FileNotFound, std.fs.cwd().access(prompt_marker, .{}));
}

test "TUI read-only mode allows local session commands" {
    var s = state.SessionState.init(testing.allocator, "test", null, false);
    defer s.deinit();
    s.read_only = true;
    s.terminal_size = .{ .rows = 24, .cols = 80 };

    var out_buf = std.ArrayList(u8).init(testing.allocator);
    defer out_buf.deinit();
    _ = try tui_app.handleSlash(testing.allocator, null, &s, "/context README.md", out_buf.writer(), .{ .color = false });

    try testing.expectEqualStrings("README.md", s.context_artifact.?);
    try testing.expect(std.mem.indexOf(u8, out_buf.items, "context=README.md") != null);
}

test "TUI slash command suggestions use prefix and fuzzy matching" {
    try testing.expectEqual(@as(usize, tui_slash.commands.len), tui_slash.matchingCount("/"));
    try testing.expectEqual(@as(usize, 1), tui_slash.matchingCount("/r"));
    try testing.expectEqual(@as(usize, 2), tui_slash.matchingCount("/d"));
    try testing.expectEqualStrings("/reasoning", tui_slash.findFirstMatch("/r").?);
    try testing.expectEqualStrings("/reasoning", tui_slash.findFirstMatch("/rsn").?);
    try testing.expectEqualStrings("/debug", tui_slash.findFirstMatch("/dbg").?);
    try testing.expectEqualStrings("/autopsy", tui_slash.findFirstMatch("/ast").?);
    try testing.expectEqualStrings("/context", tui_slash.findFirstMatch("/ctx").?);
    try testing.expectEqualStrings("/status", tui_slash.findNthMatch("/st", 0).?);
    try testing.expectEqualStrings("/autopsy", tui_slash.findNthMatch("/st", 1).?);
    try testing.expectEqual(@as(usize, 0), tui_slash.matchingCount("/notreal"));

    var out_buf = std.ArrayList(u8).init(testing.allocator);
    defer out_buf.deinit();
    var session = state.SessionState.init(testing.allocator, "test", null, false);
    defer session.deinit();

    try session.current_input.appendSlice("/");
    try tui_render.renderSlashSuggestions(out_buf.writer(), &session, 20, .{ .color = false });
    try testing.expect(std.mem.indexOf(u8, out_buf.items, "+-- slash commands ") != null);
    try testing.expect(std.mem.indexOf(u8, out_buf.items, "/help") != null);
    try testing.expect(std.mem.indexOf(u8, out_buf.items, "/context") != null);
    try testing.expectEqual(@as(u16, 12), session.previous_suggestion_height);
    try testing.expectEqual(@as(u16, 12), tui_render.suggestionHeight("/", .{ .rows = 24, .cols = 80 }, false));
    try testing.expectEqual(@as(u16, 3), tui_render.suggestionHeight("/r", .{ .rows = 24, .cols = 80 }, false));
    try testing.expectEqual(@as(u16, 3), tui_render.suggestionHeight("/notreal", .{ .rows = 24, .cols = 80 }, false));
    try testing.expectEqual(@as(u16, 0), tui_render.suggestionHeight("normal prompt", .{ .rows = 24, .cols = 80 }, false));

    out_buf.clearRetainingCapacity();
    session.current_input.clearRetainingCapacity();
    try session.current_input.appendSlice("/r");
    try tui_render.renderSlashSuggestions(out_buf.writer(), &session, 20, .{ .color = false });
    try testing.expect(std.mem.indexOf(u8, out_buf.items, "/reasoning") != null);
    try testing.expect(std.mem.indexOf(u8, out_buf.items, "/debug") == null);
    try testing.expectEqual(@as(u16, 3), session.previous_suggestion_height);

    out_buf.clearRetainingCapacity();
    session.current_input.clearRetainingCapacity();
    try session.current_input.appendSlice("/d");
    try tui_render.renderSlashSuggestions(out_buf.writer(), &session, 20, .{ .color = false });
    try testing.expect(std.mem.indexOf(u8, out_buf.items, "/debug") != null);
    try testing.expect(std.mem.indexOf(u8, out_buf.items, "/doctor") != null);

    out_buf.clearRetainingCapacity();
    session.current_input.clearRetainingCapacity();
    try session.current_input.appendSlice("/reasoning ");
    try tui_render.renderSlashSuggestions(out_buf.writer(), &session, 20, .{ .color = false });
    try testing.expect(std.mem.indexOf(u8, out_buf.items, "/reasoning") != null);
    try testing.expect(std.mem.indexOf(u8, out_buf.items, "no matching slash commands") == null);

    out_buf.clearRetainingCapacity();
    session.current_input.clearRetainingCapacity();
    try session.current_input.appendSlice("/notreal");
    try tui_render.renderSlashSuggestions(out_buf.writer(), &session, 20, .{ .color = false });
    try testing.expect(std.mem.indexOf(u8, out_buf.items, "[WARN]") != null);
    try testing.expect(std.mem.indexOf(u8, out_buf.items, "no matching slash commands") != null);

    out_buf.clearRetainingCapacity();
    session.current_input.clearRetainingCapacity();
    try tui_render.renderSlashSuggestions(out_buf.writer(), &session, 20, .{ .color = false });
    try testing.expectEqual(@as(u16, 0), session.previous_suggestion_height);
    try testing.expect(std.mem.indexOf(u8, out_buf.items, "\x1b[9;1H\x1b[K") == null);
}

test "TUI tiny terminal layout hides suggestions and avoids reserved rows" {
    const tiny5 = tui_render.layoutFor(.{ .rows = 5, .cols = 80 }, "/", false);
    try testing.expect(tiny5.tiny);
    try testing.expectEqual(@as(u16, 0), tiny5.suggestion_height);
    try testing.expect(tiny5.input_row <= 5);

    const tinyNarrow = tui_render.layoutFor(.{ .rows = 10, .cols = 12 }, "/", false);
    try testing.expect(tinyNarrow.tiny);
    try testing.expectEqual(@as(u16, 0), tinyNarrow.suggestion_height);

    const rows8 = tui_render.layoutFor(.{ .rows = 8, .cols = 80 }, "/", false);
    try testing.expect(!rows8.tiny);
    try testing.expect(rows8.suggestion_height <= rows8.suggestion_panel_bottom);
    try testing.expect(rows8.suggestion_panel_bottom < rows8.status_row);
    try testing.expect(rows8.status_row < rows8.footer_row);
    try testing.expect(rows8.footer_row < rows8.input_row);

    const rows10 = tui_render.layoutFor(.{ .rows = 10, .cols = 80 }, "/", false);
    try testing.expect(!rows10.tiny);
    try testing.expect(rows10.suggestion_height <= rows10.suggestion_panel_bottom);
    try testing.expect(rows10.suggestion_panel_bottom < rows10.status_row);
}

test "TUI tiny terminal render does not draw slash suggestions" {
    var s = state.SessionState.init(testing.allocator, "test", null, false);
    defer s.deinit();
    try s.current_input.appendSlice("/");

    var out_buf = std.ArrayList(u8).init(testing.allocator);
    defer out_buf.deinit();
    try tui_render.renderFrameWithSize(out_buf.writer(), &s, .{ .color = false }, .{ .rows = 5, .cols = 80 });

    try testing.expect(std.mem.indexOf(u8, out_buf.items, "terminal too small") != null);
    try testing.expect(std.mem.indexOf(u8, out_buf.items, "slash commands") == null);
}

test "TUI fuzzy slash command suggestions render from live table" {
    var out_buf = std.ArrayList(u8).init(testing.allocator);
    defer out_buf.deinit();
    var session = state.SessionState.init(testing.allocator, "test", null, false);
    defer session.deinit();

    try session.current_input.appendSlice("/rsn");
    try tui_render.renderSlashSuggestions(out_buf.writer(), &session, 20, .{ .color = false });
    try testing.expect(std.mem.indexOf(u8, out_buf.items, "/reasoning <level>") != null);
    try testing.expect(std.mem.indexOf(u8, out_buf.items, "Set quick|balanced|deep|max") != null);
    try testing.expect(std.mem.indexOf(u8, out_buf.items, "no matching slash commands") == null);

    out_buf.clearRetainingCapacity();
    session.current_input.clearRetainingCapacity();
    try session.current_input.appendSlice("/dbg");
    try tui_render.renderSlashSuggestions(out_buf.writer(), &session, 20, .{ .color = false });
    try testing.expect(std.mem.indexOf(u8, out_buf.items, "/debug on|off") != null);

    out_buf.clearRetainingCapacity();
    session.current_input.clearRetainingCapacity();
    try session.current_input.appendSlice("/ast");
    try tui_render.renderSlashSuggestions(out_buf.writer(), &session, 20, .{ .color = false });
    try testing.expect(std.mem.indexOf(u8, out_buf.items, "/autopsy <path>") != null);

    out_buf.clearRetainingCapacity();
    session.current_input.clearRetainingCapacity();
    try session.current_input.appendSlice("/ctx");
    try tui_render.renderSlashSuggestions(out_buf.writer(), &session, 20, .{ .color = false });
    try testing.expect(std.mem.indexOf(u8, out_buf.items, "/context <path>") != null);
}

test "TUI invalid slash command is explicit and not engine-submitted" {
    const invalid = tui_app.parseSlashCommand("/notreal");
    try testing.expectEqual(tui_app.SlashKind.unknown, invalid.kind);
    try testing.expect(!tui_app.shouldSubmitToEngine("/notreal"));
    try testing.expect(tui_app.shouldSubmitToEngine("normal prompt"));

    var out_buf = std.ArrayList(u8).init(testing.allocator);
    defer out_buf.deinit();
    try tui_render.renderInvalidSlashCommand(out_buf.writer(), .{ .color = false }, invalid.arg.?);
    try testing.expect(std.mem.indexOf(u8, out_buf.items, "[ERROR]") != null);
    try testing.expect(std.mem.indexOf(u8, out_buf.items, "Not a valid command: /notreal") != null);
    try testing.expect(std.mem.indexOf(u8, out_buf.items, "Type /help for available commands") != null);
}

test "TUI command and system render labels are distinguishable" {
    var out_buf = std.ArrayList(u8).init(testing.allocator);
    defer out_buf.deinit();

    try tui_render.renderCommandMessage(out_buf.writer(), .{ .color = false }, "debug={s}", .{"on"});
    try tui_render.renderSystemMessage(out_buf.writer(), .{ .color = false }, "status={s}", .{"ready"});
    try tui_render.renderWarningMessage(out_buf.writer(), .{ .color = false }, "match={s}", .{"none"});
    try tui_render.renderErrorMessage(out_buf.writer(), .{ .color = false }, "bad={s}", .{"command"});

    try testing.expect(std.mem.indexOf(u8, out_buf.items, "[COMMAND] debug=on") != null);
    try testing.expect(std.mem.indexOf(u8, out_buf.items, "[SYSTEM] status=ready") != null);
    try testing.expect(std.mem.indexOf(u8, out_buf.items, "[WARN]") != null);
    try testing.expect(std.mem.indexOf(u8, out_buf.items, "[ERROR]") != null);
}

test "TUI help renders visible command block" {
    var out_buf = std.ArrayList(u8).init(testing.allocator);
    defer out_buf.deinit();

    try tui_render.renderHelp(out_buf.writer(), .{ .color = false });

    try testing.expect(std.mem.indexOf(u8, out_buf.items, "[COMMAND] Ghost TUI Help") != null);
    try testing.expect(std.mem.indexOf(u8, out_buf.items, "/reasoning <level>") != null);
    try testing.expect(std.mem.indexOf(u8, out_buf.items, "Ctrl+C quit") != null);
}

test "locator candidate paths - with engine_root" {
    const candidates = try locator.getCandidatePaths(testing.allocator, "/opt/ghost", .ghost_task_operator);
    defer {
        for (candidates) |c| testing.allocator.free(c);
        testing.allocator.free(candidates);
    }

    try testing.expect(candidates.len >= 4);
    try testing.expectEqualStrings("/opt/ghost/ghost_task_operator", candidates[0]);
    try testing.expectEqualStrings("/opt/ghost/zig-out/bin/ghost_task_operator", candidates[1]);
    try testing.expectEqualStrings("../ghost_engine/zig-out/bin/ghost_task_operator", candidates[2]);
    try testing.expectEqualStrings("ghost_task_operator", candidates[3]);
}

test "locator candidate paths - no engine_root" {
    const candidates = try locator.getCandidatePaths(testing.allocator, null, .ghost_task_operator);
    defer {
        for (candidates) |c| testing.allocator.free(c);
        testing.allocator.free(candidates);
    }

    try testing.expectEqual(@as(usize, 2), candidates.len);
    try testing.expectEqualStrings("../ghost_engine/zig-out/bin/ghost_task_operator", candidates[0]);
    try testing.expectEqualStrings("ghost_task_operator", candidates[1]);
}

test "locator classifies candidates and does not resolve missing preferred path" {
    var resolution = try locator.resolveEngineBinary(testing.allocator, "/tmp/ghost-cli-missing-root", .ghost_gip);
    defer resolution.deinit(testing.allocator);

    try testing.expect(resolution.candidates.len >= 4);
    try testing.expectEqual(locator.CandidateKind.engine_root_direct, resolution.candidates[0].kind);
    try testing.expectEqual(locator.CandidateStatus.missing, resolution.candidates[0].status);
    try testing.expectEqual(locator.CandidateKind.dev_fallback, resolution.candidates[2].kind);
    if (resolution.resolved_path) |path| {
        try testing.expect(!std.mem.eql(u8, path, "/tmp/ghost-cli-missing-root/ghost_gip"));
    }
}

test "findEngineBinary fails when no executable candidate exists" {
    const result = locator.findEngineBinary(testing.allocator, "/tmp/ghost-cli-missing-root", .ghost_gip);
    if (result) |path| {
        testing.allocator.free(path);
        return error.ExpectedMissingBinary;
    } else |err| {
        try testing.expect(err == locator.LocatorError.EngineBinaryMissing or err == locator.LocatorError.EngineBinaryFoundNotExecutable);
    }
}

comptime {
    _ = @import("integration_test.zig");
}
