const std = @import("std");
const testing = std.testing;

const paths = @import("config/paths.zig");
const locator = @import("engine/locator.zig");
const json_contracts = @import("engine/json_contracts.zig");
const terminal = @import("render/terminal.zig");

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
    try testing.expect(std.mem.indexOf(u8, out_buf.items, "Suggested Action:") != null);
    try testing.expect(std.mem.indexOf(u8, out_buf.items, "Run with more budget.") != null);
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

test "reasoning level string conversion" {
    try testing.expectEqualStrings("quick", json_contracts.ReasoningLevel.quick.toStr());
    try testing.expectEqualStrings("deep", json_contracts.ReasoningLevel.deep.toStr());
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

comptime {
    _ = @import("integration_test.zig");
}
