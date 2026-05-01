const std = @import("std");
const testing = std.testing;

fn runCmd(allocator: std.mem.Allocator, args: []const []const u8) !std.process.Child.RunResult {
    return std.process.Child.run(.{
        .allocator = allocator,
        .argv = args,
        .max_output_bytes = 10 * 1024 * 1024,
    });
}

fn runCmdWithInput(allocator: std.mem.Allocator, args: []const []const u8, stdin_payload: []const u8) !std.process.Child.RunResult {
    var child = std.process.Child.init(args, allocator);
    child.stdin_behavior = .Pipe;
    child.stdout_behavior = .Pipe;
    child.stderr_behavior = .Pipe;

    try child.spawn();
    try child.stdin.?.writeAll(stdin_payload);
    child.stdin.?.close();
    child.stdin = null;

    const stdout = try child.stdout.?.reader().readAllAlloc(allocator, 10 * 1024 * 1024);
    errdefer allocator.free(stdout);
    const stderr = try child.stderr.?.reader().readAllAlloc(allocator, 10 * 1024 * 1024);
    errdefer allocator.free(stderr);
    const term = try child.wait();
    return .{
        .stdout = stdout,
        .stderr = stderr,
        .term = term,
    };
}

fn writeMockExecutable(path: []const u8, body: []const u8) !void {
    const file = try std.fs.cwd().createFile(path, .{ .mode = 0o755 });
    defer file.close();
    try file.writeAll(body);
}

const real_engine_root = "../ghost_engine";

fn writeRealPackFixture(comptime root: []const u8, guidance_json: []const u8) !void {
    std.fs.cwd().deleteTree(root) catch {};
    try std.fs.cwd().makePath(root ++ "/autopsy");
    try std.fs.cwd().makePath(root ++ "/corpus");
    try std.fs.cwd().makePath(root ++ "/abstractions");

    {
        const file = try std.fs.cwd().createFile(root ++ "/autopsy/guidance.json", .{});
        defer file.close();
        try file.writeAll(guidance_json);
    }
    {
        const file = try std.fs.cwd().createFile(root ++ "/manifest.json", .{});
        defer file.close();
        try file.writeAll(
            \\{"schemaVersion":"ghost_knowledge_pack_v1","packId":"sample_pack","packVersion":"1.0.0","domainFamily":"test","trustClass":"project","compatibility":{"engineVersion":"V32","linuxFirst":true,"deterministicOnly":true,"mountSchema":"ghost_knowledge_pack_mounts_v1"},"storage":{"corpusManifestRelPath":"corpus/manifest.json","corpusFilesRelPath":"corpus","abstractionCatalogRelPath":"abstractions/abstractions.gabs","reuseCatalogRelPath":"abstractions/reuse.gabr","lineageStateRelPath":"abstractions/lineage.gabs","influenceManifestRelPath":"influence.json","autopsyGuidanceRelPath":"autopsy/guidance.json"},"provenance":{"packLineageId":"pack:sample_pack@1.0.0","sourceKind":"fixture","sourceId":"fixture","sourceState":"live","freshnessState":"active","sourceSummary":"fixture","sourceLineageSummary":"fixture"},"content":{"corpusItemCount":0,"conceptCount":0,"corpusHash":0,"abstractionHash":0,"reuseHash":0,"lineageHash":0,"corpusPreview":[],"conceptPreview":[]}}
        );
    }
}

test "help text lists all top-level commands" {
    const res = try runCmd(testing.allocator, &[_][]const u8{ "./zig-out/bin/ghost", "--help" });
    defer {
        testing.allocator.free(res.stdout);
        testing.allocator.free(res.stderr);
    }
    // help text goes to stderr via std.debug.print
    try testing.expect(std.mem.indexOf(u8, res.stderr, "chat") != null);
    try testing.expect(std.mem.indexOf(u8, res.stderr, "ask") != null);
    try testing.expect(std.mem.indexOf(u8, res.stderr, "fix") != null);
    try testing.expect(std.mem.indexOf(u8, res.stderr, "verify") != null);
    try testing.expect(std.mem.indexOf(u8, res.stderr, "packs") != null);
    try testing.expect(std.mem.indexOf(u8, res.stderr, "corpus") != null);
    try testing.expect(std.mem.indexOf(u8, res.stderr, "learn") != null);
    try testing.expect(std.mem.indexOf(u8, res.stderr, "status") != null);
    try testing.expect(std.mem.indexOf(u8, res.stderr, "doctor") != null);
    try testing.expect(std.mem.indexOf(u8, res.stderr, "autopsy") != null);
    try testing.expect(std.mem.indexOf(u8, res.stderr, "context") != null);
    try testing.expect(std.mem.indexOf(u8, res.stderr, "debug") != null);
    try testing.expect(std.mem.indexOf(u8, res.stderr, "tui") != null);
    try testing.expect(std.mem.indexOf(u8, res.stderr, "Core:") != null);
    try testing.expect(std.mem.indexOf(u8, res.stderr, "Inspection:") != null);
    try testing.expect(std.mem.indexOf(u8, res.stderr, "Knowledge:") != null);
    try testing.expect(std.mem.indexOf(u8, res.stderr, "Advanced:") != null);
    try testing.expect(std.mem.indexOf(u8, res.stderr, "Interface:") != null);
    try testing.expect(std.mem.indexOf(u8, res.stderr, "--read-only") != null);
    try testing.expect(std.mem.indexOf(u8, res.stderr, "--max-history-turns=<n>") != null);
}

test "subcommand help works without resolving engine" {
    const tui_res = try runCmd(testing.allocator, &[_][]const u8{ "./zig-out/bin/ghost", "tui", "--help", "--engine-root=/tmp/ghost-help-missing" });
    defer {
        testing.allocator.free(tui_res.stdout);
        testing.allocator.free(tui_res.stderr);
    }
    try testing.expectEqual(@as(u32, 0), tui_res.term.Exited);
    try testing.expect(std.mem.indexOf(u8, tui_res.stderr, "Usage: ghost tui") != null);
    try testing.expect(std.mem.indexOf(u8, tui_res.stderr, "/autopsy <path>") != null);
    try testing.expect(std.mem.indexOf(u8, tui_res.stderr, "--read-only") != null);
    try testing.expect(std.mem.indexOf(u8, tui_res.stderr, "--max-history-turns=<n>") != null);
    try testing.expect(std.mem.indexOf(u8, tui_res.stderr, "prefix-first fuzzy suggestions") != null);
    try testing.expect(std.mem.indexOf(u8, tui_res.stderr, "Explicit slash commands and submitted prompts may invoke engine binaries") != null);

    const autopsy_res = try runCmd(testing.allocator, &[_][]const u8{ "./zig-out/bin/ghost", "autopsy", "--help", "--engine-root=/tmp/ghost-help-missing" });
    defer {
        testing.allocator.free(autopsy_res.stdout);
        testing.allocator.free(autopsy_res.stderr);
    }
    try testing.expectEqual(@as(u32, 0), autopsy_res.term.Exited);
    try testing.expect(std.mem.indexOf(u8, autopsy_res.stderr, "Usage: ghost autopsy") != null);
    try testing.expect(std.mem.indexOf(u8, autopsy_res.stderr, "explicitly invoked") != null);

    const context_res = try runCmd(testing.allocator, &[_][]const u8{ "./zig-out/bin/ghost", "context", "--help", "--engine-root=/tmp/ghost-help-missing" });
    defer {
        testing.allocator.free(context_res.stdout);
        testing.allocator.free(context_res.stderr);
    }
    try testing.expectEqual(@as(u32, 0), context_res.term.Exited);
    try testing.expect(std.mem.indexOf(u8, context_res.stderr, "Usage: ghost context autopsy") != null);
    try testing.expect(std.mem.indexOf(u8, context_res.stderr, "context.autopsy GIP request") != null);
    try testing.expect(std.mem.indexOf(u8, context_res.stderr, "--input-file <path>") != null);
    try testing.expect(std.mem.indexOf(u8, context_res.stderr, "DRAFT / NON-AUTHORIZING") != null);

    const context_autopsy_res = try runCmd(testing.allocator, &[_][]const u8{ "./zig-out/bin/ghost", "context", "autopsy", "--help", "--engine-root=/tmp/ghost-help-missing" });
    defer {
        testing.allocator.free(context_autopsy_res.stdout);
        testing.allocator.free(context_autopsy_res.stderr);
    }
    try testing.expectEqual(@as(u32, 0), context_autopsy_res.term.Exited);
    try testing.expect(std.mem.indexOf(u8, context_autopsy_res.stderr, "Usage: ghost context autopsy") != null);
    try testing.expect(std.mem.indexOf(u8, context_autopsy_res.stderr, "--input-max-bytes <n>") != null);

    const corpus_res = try runCmd(testing.allocator, &[_][]const u8{ "./zig-out/bin/ghost", "corpus", "--help", "--engine-root=/tmp/ghost-help-missing" });
    defer {
        testing.allocator.free(corpus_res.stdout);
        testing.allocator.free(corpus_res.stderr);
    }
    try testing.expectEqual(@as(u32, 0), corpus_res.term.Exited);
    try testing.expect(std.mem.indexOf(u8, corpus_res.stderr, "Usage: ghost corpus ask") != null);
    try testing.expect(std.mem.indexOf(u8, corpus_res.stderr, "corpus.ask GIP request") != null);
    try testing.expect(std.mem.indexOf(u8, corpus_res.stderr, "not semantic search") != null);

    const corpus_ask_res = try runCmd(testing.allocator, &[_][]const u8{ "./zig-out/bin/ghost", "corpus", "ask", "--help", "--engine-root=/tmp/ghost-help-missing" });
    defer {
        testing.allocator.free(corpus_ask_res.stdout);
        testing.allocator.free(corpus_ask_res.stderr);
    }
    try testing.expectEqual(@as(u32, 0), corpus_ask_res.term.Exited);
    try testing.expect(std.mem.indexOf(u8, corpus_ask_res.stderr, "Usage: ghost corpus ask") != null);
    try testing.expect(std.mem.indexOf(u8, corpus_ask_res.stderr, "mounted pack corpus is not included") != null);
}

test "TUI read-only help works with command parser" {
    const res = try runCmd(testing.allocator, &[_][]const u8{ "./zig-out/bin/ghost", "tui", "--read-only", "--help", "--engine-root=/tmp/ghost-help-missing" });
    defer {
        testing.allocator.free(res.stdout);
        testing.allocator.free(res.stderr);
    }
    try testing.expectEqual(@as(u32, 0), res.term.Exited);
    try testing.expect(std.mem.indexOf(u8, res.stderr, "Usage: ghost tui") != null);
    try testing.expect(std.mem.indexOf(u8, res.stderr, "--read-only") != null);
    try testing.expect(std.mem.indexOf(u8, res.stderr, "blocked locally") != null);
}

test "TUI max history turns rejects zero" {
    const res = try runCmd(testing.allocator, &[_][]const u8{ "./zig-out/bin/ghost", "tui", "--max-history-turns=0", "--help" });
    defer {
        testing.allocator.free(res.stdout);
        testing.allocator.free(res.stderr);
    }
    try testing.expect(res.term.Exited != 0);
    try testing.expect(std.mem.indexOf(u8, res.stderr, "Invalid --max-history-turns value") != null);
}

test "advanced renderer options parse consistently" {
    const res = try runCmd(testing.allocator, &[_][]const u8{
        "./zig-out/bin/ghost",
        "tui",
        "--help",
        "--no-color",
        "--color=never",
        "--compact",
        "--read-only",
        "--max-history-turns=25",
        "--reasoning=max",
    });
    defer {
        testing.allocator.free(res.stdout);
        testing.allocator.free(res.stderr);
    }
    try testing.expectEqual(@as(u32, 0), res.term.Exited);
    try testing.expect(std.mem.indexOf(u8, res.stderr, "--compact") != null);
    try testing.expect(std.mem.indexOf(u8, res.stderr, "--read-only") != null);
}

test "invalid reasoning fails clearly" {
    const res = try runCmd(testing.allocator, &[_][]const u8{
        "./zig-out/bin/ghost",
        "ask",
        "--reasoning=fastest",
        "hello",
    });
    defer {
        testing.allocator.free(res.stdout);
        testing.allocator.free(res.stderr);
    }
    try testing.expect(res.term.Exited != 0);
    try testing.expect(std.mem.indexOf(u8, res.stderr, "Invalid --reasoning value") != null);
}

test "version flag works" {
    const res = try runCmd(testing.allocator, &[_][]const u8{ "./zig-out/bin/ghost", "--version" });
    defer {
        testing.allocator.free(res.stdout);
        testing.allocator.free(res.stderr);
    }
    try testing.expect(std.mem.indexOf(u8, res.stderr, "ghost_cli v0.1.0-hardened") != null);
}

test "engine root resolution - repo root case" {
    const mock_root = "/tmp/ghost-mock-repo";
    try std.fs.cwd().makePath(mock_root ++ "/zig-out/bin");
    const mock_bin = mock_root ++ "/zig-out/bin/ghost_task_operator";
    try writeMockExecutable(mock_bin, "#!/bin/sh\nprintf 'task help\\n'\n");

    const res = try runCmd(testing.allocator, &[_][]const u8{ "./zig-out/bin/ghost", "status", "--engine-root=" ++ mock_root, "--debug" });
    defer {
        testing.allocator.free(res.stdout);
        testing.allocator.free(res.stderr);
        std.fs.cwd().deleteTree(mock_root) catch {};
    }

    try testing.expect(std.mem.indexOf(u8, res.stdout, mock_bin ++ " [engine-root-zig-out; executable]") != null);
}

test "status debug mode shows candidate paths" {
    const res = try runCmd(testing.allocator, &[_][]const u8{ "./zig-out/bin/ghost", "status", "--engine-root=/tmp/nonexistent", "--debug" });
    defer {
        testing.allocator.free(res.stdout);
        testing.allocator.free(res.stderr);
    }

    try testing.expect(std.mem.indexOf(u8, res.stdout, "/tmp/nonexistent/ghost_task_operator") != null);
    try testing.expect(std.mem.indexOf(u8, res.stdout, "/tmp/nonexistent/zig-out/bin/ghost_task_operator") != null);
    try testing.expect(std.mem.indexOf(u8, res.stdout, "ghost_task_operator") != null);
}

test "doctor renders missing engine root clearly" {
    const res = try runCmd(testing.allocator, &[_][]const u8{ "./zig-out/bin/ghost", "doctor", "--engine-root=/tmp/ghost-doctor-missing" });
    defer {
        testing.allocator.free(res.stdout);
        testing.allocator.free(res.stderr);
    }

    try testing.expect(std.mem.indexOf(u8, res.stdout, "Result: ISSUES FOUND") != null);
    try testing.expect(std.mem.indexOf(u8, res.stdout, "Resolved Engine Root: /tmp/ghost-doctor-missing") != null);
    try testing.expect(std.mem.indexOf(u8, res.stdout, "ghost_task_operator: MISSING") != null);
}

test "doctor finds mock engine repo root zig-out bin binaries" {
    const mock_root = "/tmp/ghost-doctor-mock-repo";
    try std.fs.cwd().makePath(mock_root ++ "/zig-out/bin");
    defer std.fs.cwd().deleteTree(mock_root) catch {};

    try writeMockExecutable(mock_root ++ "/zig-out/bin/ghost_task_operator", "#!/bin/sh\nprintf 'task help\\n'\n");
    try writeMockExecutable(mock_root ++ "/zig-out/bin/ghost_code_intel", "#!/bin/sh\nprintf 'code intel\\n'\n");
    try writeMockExecutable(mock_root ++ "/zig-out/bin/ghost_patch_candidates", "#!/bin/sh\nprintf 'patch candidates\\n'\n");
    try writeMockExecutable(mock_root ++ "/zig-out/bin/ghost_knowledge_pack", "#!/bin/sh\nprintf 'knowledge pack\\n'\n");
    try writeMockExecutable(mock_root ++ "/zig-out/bin/ghost_gip", "#!/bin/sh\nprintf 'gip status\\n'\n");

    const res = try runCmd(testing.allocator, &[_][]const u8{ "./zig-out/bin/ghost", "doctor", "--engine-root=" ++ mock_root });
    defer {
        testing.allocator.free(res.stdout);
        testing.allocator.free(res.stderr);
    }

    try testing.expect(std.mem.indexOf(u8, res.stdout, "Result: OK") != null);
    try testing.expect(std.mem.indexOf(u8, res.stdout, mock_root ++ "/zig-out/bin/ghost_task_operator") != null);
    try testing.expect(std.mem.indexOf(u8, res.stdout, "ghost_knowledge_pack: EXECUTABLE") != null);
}

test "doctor json emits valid JSON" {
    const res = try runCmd(testing.allocator, &[_][]const u8{ "./zig-out/bin/ghost", "doctor", "--engine-root=/tmp/ghost-doctor-json-missing", "--json" });
    defer {
        testing.allocator.free(res.stdout);
        testing.allocator.free(res.stderr);
    }

    var parsed = try std.json.parseFromSlice(std.json.Value, testing.allocator, res.stdout, .{});
    defer parsed.deinit();
    try testing.expect(parsed.value.object.contains("version"));
    try testing.expect(parsed.value.object.contains("binaries"));
    try testing.expect(parsed.value.object.contains("doctor_result"));
    try testing.expect(parsed.value.object.contains("knowledge_pack_capabilities"));
}

test "doctor reports knowledge pack validation capabilities when available" {
    const mock_root = "/tmp/ghost-doctor-capabilities";
    try std.fs.cwd().makePath(mock_root ++ "/zig-out/bin");
    defer std.fs.cwd().deleteTree(mock_root) catch {};

    try writeMockExecutable(mock_root ++ "/zig-out/bin/ghost_task_operator", "#!/bin/sh\nprintf 'task help\\n'\n");
    try writeMockExecutable(mock_root ++ "/zig-out/bin/ghost_code_intel", "#!/bin/sh\nprintf 'code intel\\n'\n");
    try writeMockExecutable(mock_root ++ "/zig-out/bin/ghost_patch_candidates", "#!/bin/sh\nprintf 'patch candidates\\n'\n");
    try writeMockExecutable(mock_root ++ "/zig-out/bin/ghost_gip", "#!/bin/sh\nprintf 'gip status\\n'\n");
    try writeMockExecutable(
        mock_root ++ "/zig-out/bin/ghost_knowledge_pack",
        "#!/bin/sh\n" ++
            "case \"$*\" in capabilities*) printf '{\"commands\":[{\"name\":\"validate-autopsy-guidance\"}],\"validateAutopsyGuidance\":{\"flags\":[\"--pack-id\",\"--version\",\"--manifest\",\"--all-mounted\",\"--project-shard\",\"--json\",\"--max-guidance-bytes\",\"--max-array-items\",\"--max-string-bytes\"],\"supportedSchemaVersions\":[\"ghost.autopsy_guidance.v1\"]}}' ;; *) printf 'knowledge pack\\n' ;; esac\n",
    );

    const res = try runCmd(testing.allocator, &[_][]const u8{ "./zig-out/bin/ghost", "doctor", "--engine-root=" ++ mock_root });
    defer {
        testing.allocator.free(res.stdout);
        testing.allocator.free(res.stderr);
    }

    try testing.expect(std.mem.indexOf(u8, res.stdout, "ghost_knowledge_pack capabilities --json [diagnostic/read-only]: available") != null);
    try testing.expect(std.mem.indexOf(u8, res.stdout, "validate-autopsy-guidance supported: yes") != null);
    try testing.expect(std.mem.indexOf(u8, res.stdout, "ghost.autopsy_guidance.v1") != null);
    try testing.expect(std.mem.indexOf(u8, res.stdout, "--max-guidance-bytes") != null);
}

test "doctor reports compatibility warning for old knowledge pack capabilities" {
    const mock_root = "/tmp/ghost-doctor-old-capabilities";
    const marker = mock_root ++ "/validation-marker";
    try std.fs.cwd().makePath(mock_root ++ "/zig-out/bin");
    defer std.fs.cwd().deleteTree(mock_root) catch {};

    try writeMockExecutable(mock_root ++ "/zig-out/bin/ghost_task_operator", "#!/bin/sh\nprintf 'task help\\n'\n");
    try writeMockExecutable(mock_root ++ "/zig-out/bin/ghost_code_intel", "#!/bin/sh\nprintf 'code intel\\n'\n");
    try writeMockExecutable(mock_root ++ "/zig-out/bin/ghost_patch_candidates", "#!/bin/sh\nprintf 'patch candidates\\n'\n");
    try writeMockExecutable(
        mock_root ++ "/zig-out/bin/ghost_knowledge_pack",
        "#!/bin/sh\n" ++
            "case \"$*\" in *validate-autopsy-guidance*) touch '" ++ marker ++ "';; esac\n" ++
            "printf 'old engine\\n'\n",
    );

    const res = try runCmd(testing.allocator, &[_][]const u8{ "./zig-out/bin/ghost", "doctor", "--engine-root=" ++ mock_root });
    defer {
        testing.allocator.free(res.stdout);
        testing.allocator.free(res.stderr);
    }

    try testing.expect(std.mem.indexOf(u8, res.stdout, "capabilities --json [diagnostic/read-only]: unavailable") != null);
    try testing.expect(std.mem.indexOf(u8, res.stdout, "compatibility warning") != null);
    try testing.expect(std.mem.indexOf(u8, res.stdout, "Upgrade/rebuild ghost_engine") != null);
    try testing.expectError(error.FileNotFound, std.fs.cwd().access(marker, .{}));
}

test "doctor debug lists candidate paths" {
    const res = try runCmd(testing.allocator, &[_][]const u8{ "./zig-out/bin/ghost", "doctor", "--engine-root=/tmp/ghost-doctor-debug", "--debug" });
    defer {
        testing.allocator.free(res.stdout);
        testing.allocator.free(res.stderr);
    }

    try testing.expect(std.mem.indexOf(u8, res.stdout, "candidates:") != null);
    try testing.expect(std.mem.indexOf(u8, res.stdout, "/tmp/ghost-doctor-debug/ghost_task_operator") != null);
    try testing.expect(std.mem.indexOf(u8, res.stdout, "/tmp/ghost-doctor-debug/zig-out/bin/ghost_task_operator") != null);
}

test "doctor report includes version path and engine root fields" {
    const res = try runCmd(testing.allocator, &[_][]const u8{ "./zig-out/bin/ghost", "doctor", "--engine-root=/tmp/ghost-doctor-report", "--report" });
    defer {
        testing.allocator.free(res.stdout);
        testing.allocator.free(res.stderr);
    }

    try testing.expect(std.mem.indexOf(u8, res.stdout, "Ghost Tester Report") != null);
    try testing.expect(std.mem.indexOf(u8, res.stdout, "Ghost version: v0.1.0-hardened") != null);
    try testing.expect(std.mem.indexOf(u8, res.stdout, "CLI path:") != null);
    try testing.expect(std.mem.indexOf(u8, res.stdout, "Engine root: /tmp/ghost-doctor-report") != null);
}

test "doctor does not run mutating commands" {
    const mock_root = "/tmp/ghost-doctor-no-mutation";
    const marker = mock_root ++ "/mutation-marker";
    try std.fs.cwd().makePath(mock_root ++ "/zig-out/bin");
    defer std.fs.cwd().deleteTree(mock_root) catch {};

    try writeMockExecutable(mock_root ++ "/zig-out/bin/ghost_task_operator", "#!/bin/sh\nprintf 'task help\\n'\n");
    try writeMockExecutable(mock_root ++ "/zig-out/bin/ghost_code_intel", "#!/bin/sh\nprintf 'code intel\\n'\n");
    try writeMockExecutable(mock_root ++ "/zig-out/bin/ghost_patch_candidates", "#!/bin/sh\nprintf 'patch candidates\\n'\n");
    try writeMockExecutable(
        mock_root ++ "/zig-out/bin/ghost_knowledge_pack",
        "#!/bin/sh\n" ++
            "case \"$*\" in *validate-autopsy-guidance*|*mount*|*unmount*) touch '" ++ marker ++ "';; esac\n" ++
            "case \"$*\" in capabilities*) printf '{\"commands\":[{\"name\":\"validate-autopsy-guidance\"}],\"validateAutopsyGuidance\":{\"flags\":[\"--pack-id\",\"--version\",\"--manifest\",\"--all-mounted\",\"--project-shard\",\"--json\",\"--max-guidance-bytes\",\"--max-array-items\",\"--max-string-bytes\"],\"supportedSchemaVersions\":[\"ghost.autopsy_guidance.v1\"]}}' ;; *) printf 'knowledge pack\\n' ;; esac\n",
    );

    const res = try runCmd(testing.allocator, &[_][]const u8{ "./zig-out/bin/ghost", "doctor", "--engine-root=" ++ mock_root });
    defer {
        testing.allocator.free(res.stdout);
        testing.allocator.free(res.stderr);
    }

    try testing.expect(std.mem.indexOf(u8, res.stdout, "ghost_knowledge_pack: EXECUTABLE") != null);
    try testing.expect(std.mem.indexOf(u8, res.stdout, "validate-autopsy-guidance supported: yes") != null);
    try testing.expectError(error.FileNotFound, std.fs.cwd().access(marker, .{}));
}

test "status still works" {
    const res = try runCmd(testing.allocator, &[_][]const u8{ "./zig-out/bin/ghost", "status", "--engine-root=/tmp/ghost-status-still-works" });
    defer {
        testing.allocator.free(res.stdout);
        testing.allocator.free(res.stderr);
    }

    try testing.expect(std.mem.indexOf(u8, res.stdout, "--- Ghost CLI Status ---") != null);
    try testing.expect(std.mem.indexOf(u8, res.stdout, "Engine Root: /tmp/ghost-status-still-works") != null);
    try testing.expect(std.mem.indexOf(u8, res.stdout, "Knowledge Pack Validation Capabilities") != null);
}

test "status reports capabilities without running validation" {
    const mock_root = "/tmp/ghost-status-capabilities";
    const marker = mock_root ++ "/validation-marker";
    try std.fs.cwd().makePath(mock_root);
    defer std.fs.cwd().deleteTree(mock_root) catch {};

    try writeMockExecutable(mock_root ++ "/ghost_task_operator", "#!/bin/sh\nprintf 'task help\\n'\n");
    try writeMockExecutable(mock_root ++ "/ghost_code_intel", "#!/bin/sh\nprintf 'code intel\\n'\n");
    try writeMockExecutable(mock_root ++ "/ghost_patch_candidates", "#!/bin/sh\nprintf 'patch candidates\\n'\n");
    try writeMockExecutable(
        mock_root ++ "/ghost_knowledge_pack",
        "#!/bin/sh\n" ++
            "case \"$*\" in *validate-autopsy-guidance*) touch '" ++ marker ++ "';; esac\n" ++
            "case \"$*\" in capabilities*) printf '{\"commands\":[{\"name\":\"validate-autopsy-guidance\"}],\"validateAutopsyGuidance\":{\"flags\":[\"--pack-id\",\"--version\",\"--manifest\",\"--all-mounted\",\"--project-shard\",\"--json\",\"--max-guidance-bytes\"],\"supportedSchemaVersions\":[\"ghost.autopsy_guidance.v1\"]}}' ;; *) printf 'knowledge pack\\n' ;; esac\n",
    );

    const res = try runCmd(testing.allocator, &[_][]const u8{ "./zig-out/bin/ghost", "status", "--engine-root=" ++ mock_root });
    defer {
        testing.allocator.free(res.stdout);
        testing.allocator.free(res.stderr);
    }

    try testing.expect(std.mem.indexOf(u8, res.stdout, "capabilities available: yes") != null);
    try testing.expect(std.mem.indexOf(u8, res.stdout, "validate-autopsy-guidance supported: yes") != null);
    try testing.expect(std.mem.indexOf(u8, res.stdout, "--max-guidance-bytes") != null);
    try testing.expectError(error.FileNotFound, std.fs.cwd().access(marker, .{}));
}

test "missing required learn flags fail clearly" {
    const res = try runCmd(testing.allocator, &[_][]const u8{ "./zig-out/bin/ghost", "learn", "candidates" });
    defer {
        testing.allocator.free(res.stdout);
        testing.allocator.free(res.stderr);
    }
    try testing.expect(res.term.Exited != 0);
    try testing.expect(std.mem.indexOf(u8, res.stderr, "--project-shard is required") != null);
}

test "missing required pack args fail clearly" {
    const res = try runCmd(testing.allocator, &[_][]const u8{ "./zig-out/bin/ghost", "packs", "inspect" });
    defer {
        testing.allocator.free(res.stdout);
        testing.allocator.free(res.stderr);
    }
    try testing.expect(res.term.Exited != 0);
    try testing.expect(std.mem.indexOf(u8, res.stderr, "Usage: ghost packs inspect <pack-id>") != null);
}

test "packs help lists validate autopsy guidance" {
    const res = try runCmd(testing.allocator, &[_][]const u8{ "./zig-out/bin/ghost", "packs", "--help", "--engine-root=/tmp/ghost-help-missing" });
    defer {
        testing.allocator.free(res.stdout);
        testing.allocator.free(res.stderr);
    }
    try testing.expectEqual(@as(u32, 0), res.term.Exited);
    try testing.expect(std.mem.indexOf(u8, res.stderr, "validate-autopsy-guidance --manifest=<path>") != null);
    try testing.expect(std.mem.indexOf(u8, res.stderr, "review-only") != null);
    try testing.expect(std.mem.indexOf(u8, res.stderr, "does not mutate packs") != null);

    const nested = try runCmd(testing.allocator, &[_][]const u8{ "./zig-out/bin/ghost", "packs", "validate-autopsy-guidance", "--help", "--engine-root=/tmp/ghost-help-missing" });
    defer {
        testing.allocator.free(nested.stdout);
        testing.allocator.free(nested.stderr);
    }
    try testing.expectEqual(@as(u32, 0), nested.term.Exited);
    try testing.expect(std.mem.indexOf(u8, nested.stderr, "validate-autopsy-guidance --manifest=<path>") != null);
    try testing.expect(std.mem.indexOf(u8, nested.stderr, "review-only") != null);
}

test "packs validate autopsy guidance uses real engine capabilities and renders clean success" {
    const fixture_root = "/tmp/ghost-cli-real-pack-valid";
    try writeRealPackFixture(
        fixture_root,
        "{\"schema\":\"ghost.autopsy_guidance.v1\",\"packGuidance\":[{\"pack_id\":\"sample_pack\",\"signals\":[{\"name\":\"sig\",\"kind\":\"generic_signal\",\"confidence\":\"medium\",\"reason\":\"matched\"}]}]}",
    );
    const manifest = fixture_root ++ "/manifest.json";
    defer std.fs.cwd().deleteTree(fixture_root) catch {};

    const res = try runCmd(testing.allocator, &[_][]const u8{
        "./zig-out/bin/ghost",
        "packs",
        "validate-autopsy-guidance",
        "--engine-root=" ++ real_engine_root,
        "--manifest=" ++ manifest,
    });
    defer {
        testing.allocator.free(res.stdout);
        testing.allocator.free(res.stderr);
    }

    try testing.expectEqual(@as(u32, 0), res.term.Exited);
    try testing.expect(std.mem.indexOf(u8, res.stdout, "Autopsy guidance validation passed.") != null);
    try testing.expect(std.mem.indexOf(u8, res.stdout, "Supported schema versions: ghost.autopsy_guidance.v1") != null);
    try testing.expect(std.mem.indexOf(u8, res.stdout, "result: pass") != null);
    try testing.expect(std.mem.indexOf(u8, res.stderr, "thread ") == null);
}

test "packs validate autopsy guidance renders real engine warnings cleanly" {
    const fixture_root = "/tmp/ghost-cli-real-pack-warning";
    try writeRealPackFixture(
        fixture_root,
        "[{\"pack_id\":\"sample_pack\",\"signals\":[{\"name\":\"sig\",\"kind\":\"generic_signal\",\"confidence\":\"medium\",\"reason\":\"matched\"}]}]",
    );
    const manifest = fixture_root ++ "/manifest.json";
    defer std.fs.cwd().deleteTree(fixture_root) catch {};

    const res = try runCmd(testing.allocator, &[_][]const u8{
        "./zig-out/bin/ghost",
        "packs",
        "validate-autopsy-guidance",
        "--engine-root=" ++ real_engine_root,
        "--manifest=" ++ manifest,
    });
    defer {
        testing.allocator.free(res.stdout);
        testing.allocator.free(res.stderr);
    }

    try testing.expectEqual(@as(u32, 0), res.term.Exited);
    try testing.expect(std.mem.indexOf(u8, res.stdout, "passed with 1 warning") != null);
    try testing.expect(std.mem.indexOf(u8, res.stdout, "warning: legacy_unversioned_guidance") != null);
    try testing.expect(std.mem.indexOf(u8, res.stdout, "thread ") == null);
}

test "packs validate autopsy guidance failure renders clean error and stays nonzero" {
    const fixture_root = "/tmp/ghost-cli-real-pack-error";
    try writeRealPackFixture(
        fixture_root,
        "{\"schema\":\"ghost.autopsy_guidance.v99\",\"packGuidance\":[]}",
    );
    const manifest = fixture_root ++ "/manifest.json";
    defer std.fs.cwd().deleteTree(fixture_root) catch {};

    const res = try runCmd(testing.allocator, &[_][]const u8{
        "./zig-out/bin/ghost",
        "packs",
        "validate-autopsy-guidance",
        "--engine-root=" ++ real_engine_root,
        "--manifest=" ++ manifest,
    });
    defer {
        testing.allocator.free(res.stdout);
        testing.allocator.free(res.stderr);
    }

    try testing.expect(res.term.Exited != 0);
    try testing.expect(std.mem.indexOf(u8, res.stdout, "Autopsy guidance validation failed: 1 error(s), 0 warning(s).") != null);
    try testing.expect(std.mem.indexOf(u8, res.stdout, "error: unsupported_schema") != null);
    try testing.expect(std.mem.indexOf(u8, res.stdout, "thread ") == null);
    try testing.expect(std.mem.indexOf(u8, res.stderr, "std/debug.zig") == null);
}

test "packs validate autopsy guidance json byte matches real engine stdout" {
    const fixture_root = "/tmp/ghost-cli-real-pack-json";
    try writeRealPackFixture(
        fixture_root,
        "{\"schema\":\"ghost.autopsy_guidance.v1\",\"packGuidance\":[{\"pack_id\":\"sample_pack\",\"signals\":[{\"name\":\"sig\",\"kind\":\"generic_signal\",\"confidence\":\"medium\",\"reason\":\"matched\"}]}]}",
    );
    const manifest = fixture_root ++ "/manifest.json";
    defer std.fs.cwd().deleteTree(fixture_root) catch {};

    const res = try runCmd(testing.allocator, &[_][]const u8{
        "./zig-out/bin/ghost",
        "packs",
        "validate-autopsy-guidance",
        "--engine-root=" ++ real_engine_root,
        "--json",
        "--manifest=" ++ manifest,
    });
    defer {
        testing.allocator.free(res.stdout);
        testing.allocator.free(res.stderr);
    }
    const direct = try runCmd(testing.allocator, &[_][]const u8{
        "../ghost_engine/zig-out/bin/ghost_knowledge_pack",
        "validate-autopsy-guidance",
        "--json",
        "--manifest=" ++ manifest,
    });
    defer {
        testing.allocator.free(direct.stdout);
        testing.allocator.free(direct.stderr);
    }

    try testing.expectEqual(@as(u32, 0), res.term.Exited);
    try testing.expectEqualStrings(direct.stdout, res.stdout);
}

test "packs validate autopsy guidance debug diagnostics stay on stderr" {
    const fixture_root = "/tmp/ghost-cli-real-pack-debug";
    try writeRealPackFixture(
        fixture_root,
        "{\"schema\":\"ghost.autopsy_guidance.v99\",\"packGuidance\":[]}",
    );
    const manifest = fixture_root ++ "/manifest.json";
    defer std.fs.cwd().deleteTree(fixture_root) catch {};

    const res = try runCmd(testing.allocator, &[_][]const u8{
        "./zig-out/bin/ghost",
        "packs",
        "validate-autopsy-guidance",
        "--engine-root=" ++ real_engine_root,
        "--debug",
        "--manifest=" ++ manifest,
    });
    defer {
        testing.allocator.free(res.stdout);
        testing.allocator.free(res.stderr);
    }

    try testing.expect(res.term.Exited != 0);
    try testing.expect(std.mem.indexOf(u8, res.stdout, "[DEBUG]") == null);
    try testing.expect(std.mem.indexOf(u8, res.stderr, "[DEBUG] capability engine_path=") != null);
    try testing.expect(std.mem.indexOf(u8, res.stderr, "[DEBUG] capability parse_status=ok") != null);
    try testing.expect(std.mem.indexOf(u8, res.stderr, "[DEBUG] validation argv=") != null);
    try testing.expect(std.mem.indexOf(u8, res.stderr, "[DEBUG] validation exit_code=") != null);
    try testing.expect(std.mem.indexOf(u8, res.stderr, "[DEBUG] validation parse_status=ok") != null);
}

test "packs validate autopsy guidance limit flags use real advertised support" {
    const fixture_root = "/tmp/ghost-cli-real-pack-limits";
    try writeRealPackFixture(
        fixture_root,
        "{\"schema\":\"ghost.autopsy_guidance.v1\",\"packGuidance\":[{\"pack_id\":\"sample_pack\",\"signals\":[{\"name\":\"sig\",\"kind\":\"generic_signal\",\"confidence\":\"medium\",\"reason\":\"matched\"}]}]}",
    );
    const manifest = fixture_root ++ "/manifest.json";
    defer std.fs.cwd().deleteTree(fixture_root) catch {};

    const res = try runCmd(testing.allocator, &[_][]const u8{
        "./zig-out/bin/ghost",
        "packs",
        "validate-autopsy-guidance",
        "--engine-root=" ++ real_engine_root,
        "--manifest=" ++ manifest,
        "--max-guidance-bytes=524288",
        "--max-array-items=128",
        "--max-string-bytes=2048",
    });
    defer {
        testing.allocator.free(res.stdout);
        testing.allocator.free(res.stderr);
    }

    try testing.expectEqual(@as(u32, 0), res.term.Exited);
    try testing.expect(std.mem.indexOf(u8, res.stdout, "Autopsy guidance validation passed.") != null);
}

test "packs validate autopsy guidance missing real capabilities fails before routing" {
    const fixture_root = "/tmp/ghost-cli-real-pack-missing-caps";
    try writeRealPackFixture(
        fixture_root,
        "{\"schema\":\"ghost.autopsy_guidance.v1\",\"packGuidance\":[]}",
    );
    const manifest = fixture_root ++ "/manifest.json";
    defer std.fs.cwd().deleteTree(fixture_root) catch {};

    const res = try runCmd(testing.allocator, &[_][]const u8{
        "./zig-out/bin/ghost",
        "packs",
        "validate-autopsy-guidance",
        "--engine-root=/tmp/ghost-cli-missing-real-engine",
        "--manifest=" ++ manifest,
    });
    defer {
        testing.allocator.free(res.stdout);
        testing.allocator.free(res.stderr);
    }

    try testing.expect(res.term.Exited != 0);
    try testing.expect(std.mem.indexOf(u8, res.stderr, "Engine binary 'ghost_knowledge_pack' is missing") != null);
}

test "existing packs list command still works" {
    const mock_root = "/tmp/ghost-cli-packs-list-existing";
    try std.fs.cwd().makePath(mock_root);
    defer std.fs.cwd().deleteTree(mock_root) catch {};

    try writeMockExecutable(
        mock_root ++ "/ghost_knowledge_pack",
        "#!/bin/sh\n" ++
            "case \"$*\" in list*) printf '[]' ;; *) printf 'unexpected args: %s\\n' \"$*\"; exit 9 ;; esac\n",
    );

    const res = try runCmd(testing.allocator, &[_][]const u8{
        "./zig-out/bin/ghost",
        "packs",
        "list",
        "--engine-root=" ++ mock_root,
    });
    defer {
        testing.allocator.free(res.stdout);
        testing.allocator.free(res.stderr);
    }

    try testing.expectEqual(@as(u32, 0), res.term.Exited);
}

test "packs validate autopsy guidance spaced flags parse in command module" {
    const mock_root = "/tmp/ghost-cli-packs-parse-spaced";
    const argv_path = mock_root ++ "/argv.txt";
    try std.fs.cwd().makePath(mock_root);
    defer std.fs.cwd().deleteTree(mock_root) catch {};

    try writeMockExecutable(
        mock_root ++ "/ghost_knowledge_pack",
        "#!/bin/sh\n" ++
            "case \"$*\" in capabilities*) printf '{\"commands\":[{\"name\":\"validate-autopsy-guidance\"}],\"validateAutopsyGuidance\":{\"flags\":[\"--pack-id\",\"--version\",\"--manifest\",\"--all-mounted\",\"--project-shard\",\"--json\",\"--max-guidance-bytes\",\"--max-array-items\",\"--max-string-bytes\"],\"supportedSchemaVersions\":[\"ghost.autopsy_guidance.v1\"]}}'; exit 0 ;; esac\n" ++
            "printf '%s\\n' \"$*\" > '" ++ argv_path ++ "'\n" ++
            "printf '{\"ok\":true,\"supportedSchemaVersions\":[\"ghost.autopsy_guidance.v1\"],\"errorCount\":0,\"warningCount\":0,\"reports\":[]}'\n",
    );

    const res = try runCmd(testing.allocator, &[_][]const u8{
        "./zig-out/bin/ghost",
        "packs",
        "validate-autopsy-guidance",
        "--engine-root=" ++ mock_root,
        "--manifest",
        "relative/manifest.json",
        "--max-guidance-bytes",
        "64",
        "--max-array-items",
        "8",
        "--max-string-bytes",
        "16",
    });
    defer {
        testing.allocator.free(res.stdout);
        testing.allocator.free(res.stderr);
    }

    const argv = try std.fs.cwd().readFileAlloc(testing.allocator, argv_path, 1024 * 1024);
    defer testing.allocator.free(argv);
    try testing.expectEqual(@as(u32, 0), res.term.Exited);
    try testing.expect(std.mem.indexOf(u8, argv, "--manifest=relative/manifest.json") != null);
    try testing.expect(std.mem.indexOf(u8, argv, "--max-guidance-bytes=64") != null);
    try testing.expect(std.mem.indexOf(u8, argv, "--max-array-items=8") != null);
    try testing.expect(std.mem.indexOf(u8, argv, "--max-string-bytes=16") != null);
}

test "packs validate autopsy guidance pack and all-mounted forms still parse" {
    const mock_root = "/tmp/ghost-cli-packs-parse-targets";
    const argv_path = mock_root ++ "/argv.txt";
    try std.fs.cwd().makePath(mock_root);
    defer std.fs.cwd().deleteTree(mock_root) catch {};

    try writeMockExecutable(
        mock_root ++ "/ghost_knowledge_pack",
        "#!/bin/sh\n" ++
            "case \"$*\" in capabilities*) printf '{\"commands\":[{\"name\":\"validate-autopsy-guidance\"}],\"validateAutopsyGuidance\":{\"flags\":[\"--pack-id\",\"--version\",\"--manifest\",\"--all-mounted\",\"--project-shard\",\"--json\"],\"supportedSchemaVersions\":[\"ghost.autopsy_guidance.v1\"]}}'; exit 0 ;; esac\n" ++
            "printf '%s\\n' \"$*\" >> '" ++ argv_path ++ "'\n" ++
            "printf '{\"ok\":true,\"supportedSchemaVersions\":[\"ghost.autopsy_guidance.v1\"],\"errorCount\":0,\"warningCount\":0,\"reports\":[]}'\n",
    );

    const pack_res = try runCmd(testing.allocator, &[_][]const u8{
        "./zig-out/bin/ghost",
        "packs",
        "validate-autopsy-guidance",
        "--engine-root=" ++ mock_root,
        "--pack-id=pack-a",
        "--version=1.0.0",
    });
    defer {
        testing.allocator.free(pack_res.stdout);
        testing.allocator.free(pack_res.stderr);
    }
    const mounted_res = try runCmd(testing.allocator, &[_][]const u8{
        "./zig-out/bin/ghost",
        "packs",
        "validate-autopsy-guidance",
        "--engine-root=" ++ mock_root,
        "--all-mounted",
        "--project-shard",
        "project-a",
    });
    defer {
        testing.allocator.free(mounted_res.stdout);
        testing.allocator.free(mounted_res.stderr);
    }

    const argv = try std.fs.cwd().readFileAlloc(testing.allocator, argv_path, 1024 * 1024);
    defer testing.allocator.free(argv);
    try testing.expectEqual(@as(u32, 0), pack_res.term.Exited);
    try testing.expectEqual(@as(u32, 0), mounted_res.term.Exited);
    try testing.expect(std.mem.indexOf(u8, argv, "--pack-id=pack-a") != null);
    try testing.expect(std.mem.indexOf(u8, argv, "--version=1.0.0") != null);
    try testing.expect(std.mem.indexOf(u8, argv, "--all-mounted") != null);
    try testing.expect(std.mem.indexOf(u8, argv, "--project-shard=project-a") != null);
}

test "doctor status and no-arg TUI do not run autopsy guidance validation" {
    const mock_root = "/tmp/ghost-cli-packs-no-hidden-validation";
    const marker = mock_root ++ "/validation-marker";
    const corpus_marker = mock_root ++ "/corpus-ask-marker";
    try std.fs.cwd().makePath(mock_root);
    defer std.fs.cwd().deleteTree(mock_root) catch {};

    try writeMockExecutable(mock_root ++ "/ghost_task_operator", "#!/bin/sh\nprintf 'task help\\n'\n");
    try writeMockExecutable(mock_root ++ "/ghost_code_intel", "#!/bin/sh\nprintf 'code intel\\n'\n");
    try writeMockExecutable(mock_root ++ "/ghost_patch_candidates", "#!/bin/sh\nprintf 'patch candidates\\n'\n");
    try writeMockExecutable(
        mock_root ++ "/ghost_knowledge_pack",
        "#!/bin/sh\n" ++
            "case \"$*\" in *validate-autopsy-guidance*) touch '" ++ marker ++ "';; esac\n" ++
            "printf 'knowledge pack\\n'\n",
    );
    try writeMockExecutable(
        mock_root ++ "/ghost_gip",
        "#!/bin/sh\n" ++
            "payload=$(cat 2>/dev/null || true)\n" ++
            "case \"$payload $*\" in *corpus.ask*) touch '" ++ corpus_marker ++ "';; esac\n" ++
            "printf '{\"status\":\"ok\"}'\n",
    );
    try writeMockExecutable(mock_root ++ "/ghost_project_autopsy", "#!/bin/sh\nprintf 'project autopsy\\n'\n");

    const doctor_res = try runCmd(testing.allocator, &[_][]const u8{ "./zig-out/bin/ghost", "doctor", "--engine-root=" ++ mock_root });
    defer {
        testing.allocator.free(doctor_res.stdout);
        testing.allocator.free(doctor_res.stderr);
    }
    const status_res = try runCmd(testing.allocator, &[_][]const u8{ "./zig-out/bin/ghost", "status", "--engine-root=" ++ mock_root });
    defer {
        testing.allocator.free(status_res.stdout);
        testing.allocator.free(status_res.stderr);
    }
    const tui_res = try runCmd(testing.allocator, &[_][]const u8{ "./zig-out/bin/ghost", "--engine-root=" ++ mock_root });
    defer {
        testing.allocator.free(tui_res.stdout);
        testing.allocator.free(tui_res.stderr);
    }

    try testing.expectError(error.FileNotFound, std.fs.cwd().access(marker, .{}));
    try testing.expectError(error.FileNotFound, std.fs.cwd().access(corpus_marker, .{}));
}

test "corpus ask creates correct GIP payload with options" {
    const mock_root = "/tmp/ghost-cli-corpus-payload";
    const payload_path = mock_root ++ "/payload.json";
    try std.fs.cwd().makePath(mock_root);
    defer std.fs.cwd().deleteTree(mock_root) catch {};

    try writeMockExecutable(
        mock_root ++ "/ghost_gip",
        "#!/bin/sh\n" ++
            "cat > '" ++ payload_path ++ "'\n" ++
            "printf '%s' '{\"corpusAsk\":{\"status\":\"unknown\",\"state\":\"unresolved\",\"permission\":\"unresolved\",\"unknowns\":[{\"kind\":\"no_corpus_available\",\"reason\":\"none\"}],\"evidenceUsed\":[],\"candidateFollowups\":[],\"learningCandidates\":[],\"trace\":{\"corpusMutation\":false,\"packMutation\":false,\"negativeKnowledgeMutation\":false,\"commandsExecuted\":false,\"verifiersExecuted\":false}}}'\n",
    );

    const res = try runCmd(testing.allocator, &[_][]const u8{
        "./zig-out/bin/ghost",
        "corpus",
        "ask",
        "--engine-root=" ++ mock_root,
        "--project-shard",
        "project-a",
        "--max-results",
        "3",
        "--max-snippet-bytes=512",
        "--require-citations",
        "What does the corpus say?",
    });
    defer {
        testing.allocator.free(res.stdout);
        testing.allocator.free(res.stderr);
    }

    const payload = try std.fs.cwd().readFileAlloc(testing.allocator, payload_path, 1024 * 1024);
    defer testing.allocator.free(payload);
    var parsed = try std.json.parseFromSlice(std.json.Value, testing.allocator, payload, .{});
    defer parsed.deinit();
    const obj = parsed.value.object;

    try testing.expectEqual(@as(u32, 0), res.term.Exited);
    try testing.expectEqualStrings("gip.v0.1", obj.get("gipVersion").?.string);
    try testing.expectEqualStrings("corpus.ask", obj.get("kind").?.string);
    try testing.expectEqualStrings("What does the corpus say?", obj.get("question").?.string);
    try testing.expectEqualStrings("project-a", obj.get("projectShard").?.string);
    try testing.expectEqual(@as(i64, 3), obj.get("maxResults").?.integer);
    try testing.expectEqual(@as(i64, 512), obj.get("maxSnippetBytes").?.integer);
    try testing.expect(obj.get("requireCitations").?.bool);
}

test "corpus ask human no-corpus output clearly says no answer" {
    const mock_root = "/tmp/ghost-cli-corpus-no-corpus";
    try std.fs.cwd().makePath(mock_root);
    defer std.fs.cwd().deleteTree(mock_root) catch {};

    try writeMockExecutable(
        mock_root ++ "/ghost_gip",
        "#!/bin/sh\n" ++
            "cat >/dev/null\n" ++
            "printf '%s' '{\"corpusAsk\":{\"status\":\"unknown\",\"state\":\"unresolved\",\"permission\":\"unresolved\",\"unknowns\":[{\"kind\":\"no_corpus_available\",\"reason\":\"no live shard corpus is available for this ask request\"}],\"evidenceUsed\":[],\"candidateFollowups\":[{\"kind\":\"evidence_to_collect\",\"detail\":\"ingest corpus\",\"executes\":false}],\"learningCandidates\":[],\"trace\":{\"corpusMutation\":false,\"packMutation\":false,\"negativeKnowledgeMutation\":false,\"commandsExecuted\":false,\"verifiersExecuted\":false}}}'\n",
    );

    const res = try runCmd(testing.allocator, &[_][]const u8{
        "./zig-out/bin/ghost",
        "corpus",
        "ask",
        "--engine-root=" ++ mock_root,
        "What does the corpus say?",
    });
    defer {
        testing.allocator.free(res.stdout);
        testing.allocator.free(res.stderr);
    }

    try testing.expectEqual(@as(u32, 0), res.term.Exited);
    try testing.expect(std.mem.indexOf(u8, res.stdout, "DRAFT") != null);
    try testing.expect(std.mem.indexOf(u8, res.stdout, "NON-AUTHORIZING") != null);
    try testing.expect(std.mem.indexOf(u8, res.stdout, "No answer was produced.") != null);
    try testing.expect(std.mem.indexOf(u8, res.stdout, "No live shard corpus is available") != null);
    try testing.expect(std.mem.indexOf(u8, res.stdout, "no_corpus_available") != null);
    try testing.expect(std.mem.indexOf(u8, res.stdout, "Candidate Followups:") != null);
    try testing.expect(std.mem.indexOf(u8, res.stdout, "answer draft") == null);
}

test "corpus ask human matching evidence renders draft answer and evidence" {
    const mock_root = "/tmp/ghost-cli-corpus-answer";
    try std.fs.cwd().makePath(mock_root);
    defer std.fs.cwd().deleteTree(mock_root) catch {};

    try writeMockExecutable(
        mock_root ++ "/ghost_gip",
        "#!/bin/sh\n" ++
            "cat >/dev/null\n" ++
            "printf '%s' '{\"corpusAsk\":{\"status\":\"answered\",\"state\":\"draft\",\"permission\":\"none\",\"answerDraft\":\"Verifier execution is not run by corpus ask.\",\"evidenceUsed\":[{\"itemId\":\"item-1\",\"path\":\"corpus/live.jsonl\",\"sourcePath\":\"docs/GIP.md\",\"class\":\"doc\",\"snippet\":\"commandsExecuted false and verifiersExecuted false\",\"reason\":\"matched verifier terms\",\"provenance\":\"fixture\",\"score\":7}],\"unknowns\":[],\"candidateFollowups\":[],\"learningCandidates\":[{\"candidateKind\":\"followup\",\"proposedAction\":\"collect more evidence\",\"reason\":\"candidate only\",\"candidateOnly\":true,\"nonAuthorizing\":true,\"persisted\":false}],\"trace\":{\"corpusEntriesConsidered\":2,\"maxResults\":3,\"maxSnippetBytes\":512,\"requireCitations\":true,\"corpusMutation\":false,\"packMutation\":false,\"negativeKnowledgeMutation\":false,\"commandsExecuted\":false,\"verifiersExecuted\":false}}}'\n",
    );

    const res = try runCmd(testing.allocator, &[_][]const u8{
        "./zig-out/bin/ghost",
        "corpus",
        "ask",
        "--engine-root=" ++ mock_root,
        "What does the corpus say about verifier execution?",
    });
    defer {
        testing.allocator.free(res.stdout);
        testing.allocator.free(res.stderr);
    }

    try testing.expectEqual(@as(u32, 0), res.term.Exited);
    try testing.expect(std.mem.indexOf(u8, res.stdout, "DRAFT") != null);
    try testing.expect(std.mem.indexOf(u8, res.stdout, "NON-AUTHORIZING") != null);
    try testing.expect(std.mem.indexOf(u8, res.stdout, "Answer Draft:") != null);
    try testing.expect(std.mem.indexOf(u8, res.stdout, "Verifier execution is not run") != null);
    try testing.expect(std.mem.indexOf(u8, res.stdout, "Evidence Used:") != null);
    try testing.expect(std.mem.indexOf(u8, res.stdout, "corpus/live.jsonl") != null);
    try testing.expect(std.mem.indexOf(u8, res.stdout, "docs/GIP.md") != null);
    try testing.expect(std.mem.indexOf(u8, res.stdout, "matched verifier terms") != null);
    try testing.expect(std.mem.indexOf(u8, res.stdout, "Learning Candidates: CANDIDATE ONLY / NOT PERSISTED") != null);
    try testing.expect(std.mem.indexOf(u8, res.stdout, "persisted: false") != null);
    try testing.expect(std.mem.indexOf(u8, res.stdout, "corpusMutation: false") != null);
    try testing.expect(std.mem.indexOf(u8, res.stdout, "packMutation: false") != null);
    try testing.expect(std.mem.indexOf(u8, res.stdout, "negativeKnowledgeMutation: false") != null);
    try testing.expect(std.mem.indexOf(u8, res.stdout, "commandsExecuted: false") != null);
    try testing.expect(std.mem.indexOf(u8, res.stdout, "verifiersExecuted: false") != null);
}

test "corpus ask human weak evidence renders unknown and no answer" {
    const mock_root = "/tmp/ghost-cli-corpus-weak";
    try std.fs.cwd().makePath(mock_root);
    defer std.fs.cwd().deleteTree(mock_root) catch {};

    try writeMockExecutable(
        mock_root ++ "/ghost_gip",
        "#!/bin/sh\n" ++
            "cat >/dev/null\n" ++
            "printf '%s' '{\"corpusAsk\":{\"status\":\"unknown\",\"state\":\"unresolved\",\"permission\":\"unresolved\",\"evidenceUsed\":[],\"unknowns\":[{\"kind\":\"insufficient_evidence\",\"reason\":\"matched corpus evidence was too weak\"}],\"candidateFollowups\":[],\"learningCandidates\":[],\"trace\":{\"corpusMutation\":false,\"packMutation\":false,\"negativeKnowledgeMutation\":false,\"commandsExecuted\":false,\"verifiersExecuted\":false}}}'\n",
    );

    const res = try runCmd(testing.allocator, &[_][]const u8{ "./zig-out/bin/ghost", "corpus", "ask", "--engine-root=" ++ mock_root, "weak question" });
    defer {
        testing.allocator.free(res.stdout);
        testing.allocator.free(res.stderr);
    }

    try testing.expectEqual(@as(u32, 0), res.term.Exited);
    try testing.expect(std.mem.indexOf(u8, res.stdout, "No answer was produced.") != null);
    try testing.expect(std.mem.indexOf(u8, res.stdout, "insufficient_evidence") != null);
    try testing.expect(std.mem.indexOf(u8, res.stdout, "Answer Draft:") == null);
}

test "corpus ask human conflict renders conflicting evidence and no answer" {
    const mock_root = "/tmp/ghost-cli-corpus-conflict";
    try std.fs.cwd().makePath(mock_root);
    defer std.fs.cwd().deleteTree(mock_root) catch {};

    try writeMockExecutable(
        mock_root ++ "/ghost_gip",
        "#!/bin/sh\n" ++
            "cat >/dev/null\n" ++
            "printf '%s' '{\"corpusAsk\":{\"status\":\"unknown\",\"state\":\"unresolved\",\"permission\":\"unresolved\",\"evidenceUsed\":[],\"unknowns\":[{\"kind\":\"conflicting_evidence\",\"reason\":\"affirmative and negative signals conflict\"}],\"candidateFollowups\":[{\"kind\":\"evidence_to_collect\",\"detail\":\"resolve conflict\",\"executes\":false}],\"learningCandidates\":[],\"trace\":{\"corpusMutation\":false,\"packMutation\":false,\"negativeKnowledgeMutation\":false,\"commandsExecuted\":false,\"verifiersExecuted\":false}}}'\n",
    );

    const res = try runCmd(testing.allocator, &[_][]const u8{ "./zig-out/bin/ghost", "corpus", "ask", "--engine-root=" ++ mock_root, "conflict question" });
    defer {
        testing.allocator.free(res.stdout);
        testing.allocator.free(res.stderr);
    }

    try testing.expectEqual(@as(u32, 0), res.term.Exited);
    try testing.expect(std.mem.indexOf(u8, res.stdout, "No answer was produced.") != null);
    try testing.expect(std.mem.indexOf(u8, res.stdout, "conflicting_evidence") != null);
    try testing.expect(std.mem.indexOf(u8, res.stdout, "Conflicting corpus evidence") != null);
    try testing.expect(std.mem.indexOf(u8, res.stdout, "Answer Draft:") == null);
}

test "corpus ask json byte matches direct ghost gip output" {
    const mock_root = "/tmp/ghost-cli-corpus-json";
    const raw_json = "{\"corpusAsk\":{\"status\":\"unknown\",\"state\":\"unresolved\",\"permission\":\"unresolved\",\"unknowns\":[{\"kind\":\"no_corpus_available\",\"reason\":\"none\"}],\"evidenceUsed\":[],\"candidateFollowups\":[],\"learningCandidates\":[],\"trace\":{\"corpusMutation\":false,\"packMutation\":false,\"negativeKnowledgeMutation\":false,\"commandsExecuted\":false,\"verifiersExecuted\":false}}}";
    try std.fs.cwd().makePath(mock_root);
    defer std.fs.cwd().deleteTree(mock_root) catch {};

    const file = try std.fs.cwd().createFile(mock_root ++ "/ghost_gip", .{ .mode = 0o755 });
    try file.writeAll("#!/bin/sh\ncat >/dev/null\nprintf '%s' '");
    try file.writeAll(raw_json);
    try file.writeAll("'\n");
    file.close();

    const equivalent_payload = "{\"gipVersion\":\"gip.v0.1\",\"kind\":\"corpus.ask\",\"question\":\"What does the corpus say?\"}";
    const direct = try runCmdWithInput(testing.allocator, &[_][]const u8{ mock_root ++ "/ghost_gip", "--stdin" }, equivalent_payload);
    defer {
        testing.allocator.free(direct.stdout);
        testing.allocator.free(direct.stderr);
    }
    const cli = try runCmd(testing.allocator, &[_][]const u8{
        "./zig-out/bin/ghost",
        "corpus",
        "ask",
        "--engine-root=" ++ mock_root,
        "--json",
        "What does the corpus say?",
    });
    defer {
        testing.allocator.free(cli.stdout);
        testing.allocator.free(cli.stderr);
    }

    try testing.expectEqual(@as(u32, 0), cli.term.Exited);
    try testing.expectEqualStrings(direct.stdout, cli.stdout);
}

test "corpus ask debug diagnostics stay on stderr" {
    const mock_root = "/tmp/ghost-cli-corpus-debug";
    try std.fs.cwd().makePath(mock_root);
    defer std.fs.cwd().deleteTree(mock_root) catch {};

    try writeMockExecutable(
        mock_root ++ "/ghost_gip",
        "#!/bin/sh\n" ++
            "cat >/dev/null\n" ++
            "printf '%s' '{\"corpusAsk\":{\"status\":\"unknown\",\"state\":\"unresolved\",\"permission\":\"unresolved\",\"unknowns\":[{\"kind\":\"no_corpus_available\",\"reason\":\"none\"}],\"evidenceUsed\":[],\"candidateFollowups\":[],\"learningCandidates\":[],\"trace\":{\"corpusMutation\":false,\"packMutation\":false,\"negativeKnowledgeMutation\":false,\"commandsExecuted\":false,\"verifiersExecuted\":false}}}'\n",
    );

    const res = try runCmd(testing.allocator, &[_][]const u8{
        "./zig-out/bin/ghost",
        "corpus",
        "ask",
        "--engine-root=" ++ mock_root,
        "--debug",
        "What does the corpus say?",
    });
    defer {
        testing.allocator.free(res.stdout);
        testing.allocator.free(res.stderr);
    }

    try testing.expectEqual(@as(u32, 0), res.term.Exited);
    try testing.expect(std.mem.indexOf(u8, res.stdout, "[DEBUG]") == null);
    try testing.expect(std.mem.indexOf(u8, res.stderr, "[DEBUG] Engine Binary:") != null);
    try testing.expect(std.mem.indexOf(u8, res.stderr, "[DEBUG] GIP Kind: corpus.ask") != null);
    try testing.expect(std.mem.indexOf(u8, res.stderr, "[DEBUG] Arguments:") != null);
    try testing.expect(std.mem.indexOf(u8, res.stderr, "[DEBUG] Stdin Payload Summary:") != null);
    try testing.expect(std.mem.indexOf(u8, res.stderr, "[DEBUG] Exit Code:") != null);
    try testing.expect(std.mem.indexOf(u8, res.stderr, "[DEBUG] JSON Parse: SUCCESS") != null);
}

test "json mode preserves raw engine stdout" {
    const mock_root = "/tmp/ghost-cli-json-preserve";
    try std.fs.cwd().makePath(mock_root);
    const mock_bin = mock_root ++ "/ghost_task_operator";
    const raw_json = "{\"summary\":\"raw engine json\",\"negative_knowledge\":{\"proposed_candidates\":[{\"id\":\"nk1\"}]}}";

    const file = try std.fs.cwd().createFile(mock_bin, .{ .mode = 0o755 });
    defer std.fs.cwd().deleteTree(mock_root) catch {};
    try file.writeAll("#!/bin/sh\nprintf '%s' '");
    try file.writeAll(raw_json);
    try file.writeAll("'\n");
    file.close();

    const res = try runCmd(testing.allocator, &[_][]const u8{
        "./zig-out/bin/ghost",
        "ask",
        "--engine-root=" ++ mock_root,
        "--json",
        "hello",
    });
    defer {
        testing.allocator.free(res.stdout);
        testing.allocator.free(res.stderr);
    }

    try testing.expectEqualStrings(raw_json, res.stdout);
}

test "json debug mode keeps stdout raw and debug on stderr" {
    const mock_root = "/tmp/ghost-cli-json-debug-preserve";
    try std.fs.cwd().makePath(mock_root);
    const mock_bin = mock_root ++ "/ghost_task_operator";
    const raw_json = "{\"summary\":\"raw debug json\"}";

    const file = try std.fs.cwd().createFile(mock_bin, .{ .mode = 0o755 });
    defer std.fs.cwd().deleteTree(mock_root) catch {};
    try file.writeAll("#!/bin/sh\nprintf '%s' '");
    try file.writeAll(raw_json);
    try file.writeAll("'\n");
    file.close();

    const res = try runCmd(testing.allocator, &[_][]const u8{
        "./zig-out/bin/ghost",
        "ask",
        "--engine-root=" ++ mock_root,
        "--json",
        "--debug",
        "hello",
    });
    defer {
        testing.allocator.free(res.stdout);
        testing.allocator.free(res.stderr);
    }

    try testing.expectEqualStrings(raw_json, res.stdout);
    try testing.expect(std.mem.indexOf(u8, res.stderr, "[DEBUG] Engine Binary:") != null);
}

test "context autopsy renders draft non-authorizing human output" {
    const mock_root = "/tmp/ghost-cli-context-human";
    try std.fs.cwd().makePath(mock_root);
    defer std.fs.cwd().deleteTree(mock_root) catch {};

    try writeMockExecutable(
        mock_root ++ "/ghost_gip",
        "#!/bin/sh\n" ++
            "cat >/dev/null\n" ++
            "printf '%s' '{\"gipVersion\":\"gip.v0.1\",\"kind\":\"context.autopsy\",\"status\":\"ok\",\"resultState\":{\"state\":\"draft\"},\"result\":{\"contextAutopsy\":{\"contextCase\":{\"description\":\"launch\"},\"detectedSignals\":[{\"name\":\"signal\"}],\"suggestedUnknowns\":[{\"name\":\"unknown\"}],\"riskSurfaces\":[{\"riskKind\":\"risk\"}],\"candidateActions\":[{\"id\":\"action\"}],\"checkCandidates\":[{\"id\":\"check\"}],\"pendingEvidenceObligations\":[{\"id\":\"pending\"}],\"packInfluences\":[{\"packName\":\"pack\"}],\"state\":\"draft\",\"nonAuthorizing\":true},\"readOnly\":true,\"commandsExecuted\":false,\"verifiersExecuted\":false,\"packMutation\":false,\"negativeKnowledgeMutation\":false,\"non_authorizing\":true}}'\n",
    );

    const res = try runCmd(testing.allocator, &[_][]const u8{
        "./zig-out/bin/ghost",
        "context",
        "autopsy",
        "--engine-root=" ++ mock_root,
        "I need marketing advice for a launch",
    });
    defer {
        testing.allocator.free(res.stdout);
        testing.allocator.free(res.stderr);
    }

    try testing.expectEqual(@as(u32, 0), res.term.Exited);
    try testing.expect(std.mem.indexOf(u8, res.stdout, "Context Autopsy Result") != null);
    try testing.expect(std.mem.indexOf(u8, res.stdout, "DRAFT") != null);
    try testing.expect(std.mem.indexOf(u8, res.stdout, "NON-AUTHORIZING") != null);
    try testing.expect(std.mem.indexOf(u8, res.stdout, "Signals:") != null);
    try testing.expect(std.mem.indexOf(u8, res.stdout, "Unknowns:") != null);
    try testing.expect(std.mem.indexOf(u8, res.stdout, "Risks:") != null);
    try testing.expect(std.mem.indexOf(u8, res.stdout, "Candidate Actions:") != null);
    try testing.expect(std.mem.indexOf(u8, res.stdout, "Check Candidates:") != null);
    try testing.expect(std.mem.indexOf(u8, res.stdout, "Pending Obligations:") != null);
    try testing.expect(std.mem.indexOf(u8, res.stdout, "Pack Influence:") != null);
}

test "context autopsy single input file creates context input refs payload" {
    const mock_root = "/tmp/ghost-cli-context-input-single";
    const payload_path = mock_root ++ "/payload.json";
    try std.fs.cwd().makePath(mock_root);
    defer std.fs.cwd().deleteTree(mock_root) catch {};

    try writeMockExecutable(
        mock_root ++ "/ghost_gip",
        "#!/bin/sh\n" ++
            "cat > '" ++ payload_path ++ "'\n" ++
            "printf '%s' '{\"gipVersion\":\"gip.v0.1\",\"kind\":\"context.autopsy\",\"status\":\"ok\",\"result\":{\"contextAutopsy\":{\"state\":\"draft\",\"nonAuthorizing\":true}}}'\n",
    );

    const res = try runCmd(testing.allocator, &[_][]const u8{
        "./zig-out/bin/ghost",
        "context",
        "autopsy",
        "--engine-root=" ++ mock_root,
        "Summarize this context",
        "--input-file",
        "logs/failure.log",
    });
    defer {
        testing.allocator.free(res.stdout);
        testing.allocator.free(res.stderr);
    }

    const payload = try std.fs.cwd().readFileAlloc(testing.allocator, payload_path, 1024 * 1024);
    defer testing.allocator.free(payload);
    var parsed = try std.json.parseFromSlice(std.json.Value, testing.allocator, payload, .{});
    defer parsed.deinit();

    const context = parsed.value.object.get("context").?.object;
    const refs = context.get("input_refs").?.array;
    try testing.expectEqual(@as(usize, 1), refs.items.len);
    try testing.expectEqualStrings("file", refs.items[0].object.get("kind").?.string);
    try testing.expectEqualStrings("logs/failure.log", refs.items[0].object.get("path").?.string);
    try testing.expect(std.mem.indexOf(u8, payload, "failure log contents") == null);
}

test "context autopsy repeated input files and max bytes map to refs" {
    const mock_root = "/tmp/ghost-cli-context-input-repeat";
    const payload_path = mock_root ++ "/payload.json";
    try std.fs.cwd().makePath(mock_root);
    defer std.fs.cwd().deleteTree(mock_root) catch {};

    try writeMockExecutable(
        mock_root ++ "/ghost_gip",
        "#!/bin/sh\n" ++
            "cat > '" ++ payload_path ++ "'\n" ++
            "printf '%s' '{\"gipVersion\":\"gip.v0.1\",\"kind\":\"context.autopsy\",\"status\":\"ok\",\"result\":{\"contextAutopsy\":{\"state\":\"draft\",\"nonAuthorizing\":true}}}'\n",
    );

    const res = try runCmd(testing.allocator, &[_][]const u8{
        "./zig-out/bin/ghost",
        "context",
        "autopsy",
        "--engine-root=" ++ mock_root,
        "--input-file",
        "logs/one.log",
        "--input-file=logs/two.log",
        "--input-max-bytes",
        "65536",
        "--input-purpose",
        "bounded transcript/log context",
        "--input-reason=operator supplied",
        "Summarize this context",
    });
    defer {
        testing.allocator.free(res.stdout);
        testing.allocator.free(res.stderr);
    }

    const payload = try std.fs.cwd().readFileAlloc(testing.allocator, payload_path, 1024 * 1024);
    defer testing.allocator.free(payload);
    var parsed = try std.json.parseFromSlice(std.json.Value, testing.allocator, payload, .{});
    defer parsed.deinit();

    const refs = parsed.value.object.get("context").?.object.get("input_refs").?.array;
    try testing.expectEqual(@as(usize, 2), refs.items.len);
    try testing.expectEqualStrings("logs/one.log", refs.items[0].object.get("path").?.string);
    try testing.expectEqualStrings("logs/two.log", refs.items[1].object.get("path").?.string);
    try testing.expectEqual(@as(i64, 65536), refs.items[0].object.get("maxBytes").?.integer);
    try testing.expectEqual(@as(i64, 65536), refs.items[1].object.get("maxBytes").?.integer);
    try testing.expectEqualStrings("bounded transcript/log context", refs.items[0].object.get("purpose").?.string);
    try testing.expectEqualStrings("operator supplied", refs.items[1].object.get("reason").?.string);
}

test "context autopsy json preserves raw GIP stdout" {
    const mock_root = "/tmp/ghost-cli-context-json";
    try std.fs.cwd().makePath(mock_root);
    defer std.fs.cwd().deleteTree(mock_root) catch {};
    const raw_json = "{\"gipVersion\":\"gip.v0.1\",\"kind\":\"context.autopsy\",\"status\":\"ok\",\"result\":{\"contextAutopsy\":{\"state\":\"draft\",\"nonAuthorizing\":true}}}";

    const file = try std.fs.cwd().createFile(mock_root ++ "/ghost_gip", .{ .mode = 0o755 });
    try file.writeAll("#!/bin/sh\ncat >/dev/null\nprintf '%s' '");
    try file.writeAll(raw_json);
    try file.writeAll("'\n");
    file.close();

    const res = try runCmd(testing.allocator, &[_][]const u8{
        "./zig-out/bin/ghost",
        "context",
        "autopsy",
        "--engine-root=" ++ mock_root,
        "--json",
        "I need marketing advice for a launch",
        "--input-file",
        "README.md",
    });
    defer {
        testing.allocator.free(res.stdout);
        testing.allocator.free(res.stderr);
    }

    try testing.expectEqualStrings(raw_json, res.stdout);
}

test "context autopsy json byte matches direct ghost gip for equivalent payload" {
    const mock_root = "/tmp/ghost-cli-context-json-direct";
    try std.fs.cwd().makePath(mock_root);
    defer std.fs.cwd().deleteTree(mock_root) catch {};
    const raw_json = "{\"gipVersion\":\"gip.v0.1\",\"kind\":\"context.autopsy\",\"status\":\"ok\",\"result\":{\"contextAutopsy\":{\"state\":\"draft\",\"nonAuthorizing\":true},\"inputCoverage\":{\"inputsRequested\":1,\"inputsRead\":1,\"bytesRead\":42}}}";

    const file = try std.fs.cwd().createFile(mock_root ++ "/ghost_gip", .{ .mode = 0o755 });
    try file.writeAll("#!/bin/sh\ncat >/dev/null\nprintf '%s' '");
    try file.writeAll(raw_json);
    try file.writeAll("'\n");
    file.close();

    const equivalent_payload =
        \\{"gipVersion":"gip.v0.1","kind":"context.autopsy","context":{"summary":"Summarize this context","intakeType":"context","input_refs":[{"kind":"file","path":"README.md","maxBytes":65536}]}}
    ;
    const direct = try runCmdWithInput(testing.allocator, &[_][]const u8{ mock_root ++ "/ghost_gip", "--stdin" }, equivalent_payload);
    defer {
        testing.allocator.free(direct.stdout);
        testing.allocator.free(direct.stderr);
    }

    const cli = try runCmd(testing.allocator, &[_][]const u8{
        "./zig-out/bin/ghost",
        "context",
        "autopsy",
        "--engine-root=" ++ mock_root,
        "--json",
        "--input-file",
        "README.md",
        "--input-max-bytes=65536",
        "Summarize this context",
    });
    defer {
        testing.allocator.free(cli.stdout);
        testing.allocator.free(cli.stderr);
    }

    try testing.expectEqualStrings(direct.stdout, cli.stdout);
}

test "context autopsy debug stays on stderr" {
    const mock_root = "/tmp/ghost-cli-context-debug";
    try std.fs.cwd().makePath(mock_root);
    defer std.fs.cwd().deleteTree(mock_root) catch {};

    try writeMockExecutable(
        mock_root ++ "/ghost_gip",
        "#!/bin/sh\n" ++
            "cat >/dev/null\n" ++
            "printf '%s' '{\"gipVersion\":\"gip.v0.1\",\"kind\":\"context.autopsy\",\"status\":\"ok\",\"result\":{\"contextAutopsy\":{\"state\":\"draft\",\"nonAuthorizing\":true}}}'\n",
    );

    const res = try runCmd(testing.allocator, &[_][]const u8{
        "./zig-out/bin/ghost",
        "context",
        "autopsy",
        "--engine-root=" ++ mock_root,
        "--debug",
        "--input-file",
        "README.md",
        "I need marketing advice for a launch",
    });
    defer {
        testing.allocator.free(res.stdout);
        testing.allocator.free(res.stderr);
    }

    try testing.expect(std.mem.indexOf(u8, res.stdout, "Context Autopsy Result") != null);
    try testing.expect(std.mem.indexOf(u8, res.stderr, "[DEBUG] Engine Binary:") != null);
    try testing.expect(std.mem.indexOf(u8, res.stderr, "[DEBUG] GIP Kind: context.autopsy") != null);
    try testing.expect(std.mem.indexOf(u8, res.stderr, "[DEBUG] Stdin Payload Summary:") != null);
    try testing.expect(std.mem.indexOf(u8, res.stderr, "input_file_refs=1") != null);
    try testing.expect(std.mem.indexOf(u8, res.stderr, "[DEBUG] Input File Refs: 1") != null);
    try testing.expect(std.mem.indexOf(u8, res.stderr, "[DEBUG] Exit Code: 0") != null);
    try testing.expect(std.mem.indexOf(u8, res.stderr, "[DEBUG] JSON Parse: SUCCESS") != null);
}

test "context autopsy human output renders input coverage" {
    const mock_root = "/tmp/ghost-cli-context-input-coverage";
    try std.fs.cwd().makePath(mock_root);
    defer std.fs.cwd().deleteTree(mock_root) catch {};

    try writeMockExecutable(
        mock_root ++ "/ghost_gip",
        "#!/bin/sh\n" ++
            "cat >/dev/null\n" ++
            "printf '%s' '{\"gipVersion\":\"gip.v0.1\",\"kind\":\"context.autopsy\",\"status\":\"ok\",\"result\":{\"contextAutopsy\":{\"state\":\"draft\",\"nonAuthorizing\":true},\"inputCoverage\":{\"inputsRequested\":2,\"inputsRead\":1,\"bytesRead\":65536,\"skippedInputs\":[{\"path\":\"missing.log\"}],\"truncatedInputs\":[{\"path\":\"README.md\"}],\"unknowns\":[\"unread region after byte budget\"]}}}'\n",
    );

    const res = try runCmd(testing.allocator, &[_][]const u8{
        "./zig-out/bin/ghost",
        "context",
        "autopsy",
        "--engine-root=" ++ mock_root,
        "--input-file",
        "README.md",
        "Summarize this context",
    });
    defer {
        testing.allocator.free(res.stdout);
        testing.allocator.free(res.stderr);
    }

    try testing.expect(std.mem.indexOf(u8, res.stdout, "Input Coverage:") != null);
    try testing.expect(std.mem.indexOf(u8, res.stdout, "inputsRequested: 2") != null);
    try testing.expect(std.mem.indexOf(u8, res.stdout, "inputsRead: 1") != null);
    try testing.expect(std.mem.indexOf(u8, res.stdout, "bytesRead: 65536") != null);
    try testing.expect(std.mem.indexOf(u8, res.stdout, "skippedInputs:") != null);
    try testing.expect(std.mem.indexOf(u8, res.stdout, "truncatedInputs:") != null);
    try testing.expect(std.mem.indexOf(u8, res.stdout, "unread region after byte budget") != null);
    try testing.expect(std.mem.indexOf(u8, res.stdout, "COVERAGE WARNING") != null);
    try testing.expect(std.mem.indexOf(u8, res.stdout, "Ghost did not inspect all provided material") != null);
}

test "context autopsy human output omits coverage warning when coverage is complete" {
    const mock_root = "/tmp/ghost-cli-context-complete-coverage";
    try std.fs.cwd().makePath(mock_root);
    defer std.fs.cwd().deleteTree(mock_root) catch {};

    try writeMockExecutable(
        mock_root ++ "/ghost_gip",
        "#!/bin/sh\n" ++
            "cat >/dev/null\n" ++
            "printf '%s' '{\"gipVersion\":\"gip.v0.1\",\"kind\":\"context.autopsy\",\"status\":\"ok\",\"result\":{\"contextAutopsy\":{\"state\":\"draft\",\"nonAuthorizing\":true},\"inputCoverage\":{\"inputsRequested\":1,\"inputsRead\":1,\"bytesRead\":128,\"skippedInputs\":[],\"truncatedInputs\":[],\"unknowns\":[]},\"artifactCoverage\":{\"filesRequested\":1,\"filesRead\":1,\"filesSkipped\":[],\"filesTruncated\":[],\"budgetHits\":[]}}}'\n",
    );

    const res = try runCmd(testing.allocator, &[_][]const u8{
        "./zig-out/bin/ghost",
        "context",
        "autopsy",
        "--engine-root=" ++ mock_root,
        "--input-file",
        "README.md",
        "Summarize this context",
    });
    defer {
        testing.allocator.free(res.stdout);
        testing.allocator.free(res.stderr);
    }

    try testing.expect(std.mem.indexOf(u8, res.stdout, "Input Coverage:") != null);
    try testing.expect(std.mem.indexOf(u8, res.stdout, "Artifact Coverage:") != null);
    try testing.expect(std.mem.indexOf(u8, res.stdout, "COVERAGE WARNING") == null);
}

test "context autopsy human output warns for artifact coverage budget hits" {
    const mock_root = "/tmp/ghost-cli-context-artifact-coverage-warning";
    try std.fs.cwd().makePath(mock_root);
    defer std.fs.cwd().deleteTree(mock_root) catch {};

    try writeMockExecutable(
        mock_root ++ "/ghost_gip",
        "#!/bin/sh\n" ++
            "cat >/dev/null\n" ++
            "printf '%s' '{\"gipVersion\":\"gip.v0.1\",\"kind\":\"context.autopsy\",\"status\":\"ok\",\"result\":{\"contextAutopsy\":{\"state\":\"draft\",\"nonAuthorizing\":true},\"artifactCoverage\":{\"filesRead\":1,\"filesSkipped\":[{\"path\":\"large.bin\"}],\"budgetHits\":[\"maxBytes\"]}}}'\n",
    );

    const res = try runCmd(testing.allocator, &[_][]const u8{
        "./zig-out/bin/ghost",
        "context",
        "autopsy",
        "--engine-root=" ++ mock_root,
        "Summarize this context",
    });
    defer {
        testing.allocator.free(res.stdout);
        testing.allocator.free(res.stderr);
    }

    try testing.expect(std.mem.indexOf(u8, res.stdout, "COVERAGE WARNING") != null);
    try testing.expect(std.mem.indexOf(u8, res.stdout, "Artifact Coverage:") != null);
}

test "doctor status and no-arg TUI do not invoke context autopsy" {
    const mock_root = "/tmp/ghost-cli-context-no-hidden";
    const marker = mock_root ++ "/context-marker";
    const corpus_marker = mock_root ++ "/corpus-ask-marker";
    try std.fs.cwd().makePath(mock_root);
    defer std.fs.cwd().deleteTree(mock_root) catch {};

    try writeMockExecutable(mock_root ++ "/ghost_task_operator", "#!/bin/sh\nprintf 'task help\\n'\n");
    try writeMockExecutable(mock_root ++ "/ghost_code_intel", "#!/bin/sh\nprintf 'code intel\\n'\n");
    try writeMockExecutable(mock_root ++ "/ghost_patch_candidates", "#!/bin/sh\nprintf 'patch candidates\\n'\n");
    try writeMockExecutable(mock_root ++ "/ghost_knowledge_pack", "#!/bin/sh\nprintf 'knowledge pack\\n'\n");
    try writeMockExecutable(mock_root ++ "/ghost_project_autopsy", "#!/bin/sh\nprintf 'project autopsy\\n'\n");
    try writeMockExecutable(
        mock_root ++ "/ghost_gip",
        "#!/bin/sh\n" ++
            "payload=$(cat)\n" ++
            "case \"$payload\" in *context.autopsy*) touch '" ++ marker ++ "';; esac\n" ++
            "case \"$payload\" in *corpus.ask*) touch '" ++ corpus_marker ++ "';; esac\n" ++
            "printf '{\"status\":\"ok\"}'\n",
    );

    const doctor_res = try runCmd(testing.allocator, &[_][]const u8{ "./zig-out/bin/ghost", "doctor", "--engine-root=" ++ mock_root });
    defer {
        testing.allocator.free(doctor_res.stdout);
        testing.allocator.free(doctor_res.stderr);
    }
    const status_res = try runCmd(testing.allocator, &[_][]const u8{ "./zig-out/bin/ghost", "status", "--engine-root=" ++ mock_root });
    defer {
        testing.allocator.free(status_res.stdout);
        testing.allocator.free(status_res.stderr);
    }
    const tui_res = try runCmd(testing.allocator, &[_][]const u8{ "./zig-out/bin/ghost", "--engine-root=" ++ mock_root });
    defer {
        testing.allocator.free(tui_res.stdout);
        testing.allocator.free(tui_res.stderr);
    }

    try testing.expectError(error.FileNotFound, std.fs.cwd().access(marker, .{}));
    try testing.expectError(error.FileNotFound, std.fs.cwd().access(corpus_marker, .{}));
}

test "missing engine binary fails early with locator error" {
    const mock_root = "/tmp/ghost-cli-missing-engine";
    try std.fs.cwd().makePath(mock_root);
    defer std.fs.cwd().deleteTree(mock_root) catch {};

    const res = try runCmd(testing.allocator, &[_][]const u8{
        "./zig-out/bin/ghost",
        "ask",
        "--engine-root=" ++ mock_root,
        "hello",
    });
    defer {
        testing.allocator.free(res.stdout);
        testing.allocator.free(res.stderr);
    }

    try testing.expect(res.term.Exited != 0);
    try testing.expectEqualStrings("", res.stdout);
    try testing.expect(std.mem.indexOf(u8, res.stderr, "Engine binary 'ghost_task_operator' is missing") != null);
}

test "doctor and status share locator semantics for non executable binary" {
    const mock_root = "/tmp/ghost-cli-non-exec-engine";
    try std.fs.cwd().makePath(mock_root);
    const mock_bin = mock_root ++ "/ghost_task_operator";
    const file = try std.fs.cwd().createFile(mock_bin, .{ .mode = 0o644 });
    file.close();
    defer std.fs.cwd().deleteTree(mock_root) catch {};

    const status_res = try runCmd(testing.allocator, &[_][]const u8{
        "./zig-out/bin/ghost",
        "status",
        "--engine-root=" ++ mock_root,
    });
    defer {
        testing.allocator.free(status_res.stdout);
        testing.allocator.free(status_res.stderr);
    }
    try testing.expect(std.mem.indexOf(u8, status_res.stdout, "ghost_task_operator: found-not-executable [engine-root]") != null);

    const doctor_res = try runCmd(testing.allocator, &[_][]const u8{
        "./zig-out/bin/ghost",
        "doctor",
        "--engine-root=" ++ mock_root,
        "--json",
    });
    defer {
        testing.allocator.free(doctor_res.stdout);
        testing.allocator.free(doctor_res.stderr);
    }
    var parsed = try std.json.parseFromSlice(std.json.Value, testing.allocator, doctor_res.stdout, .{});
    defer parsed.deinit();
    const binaries = parsed.value.object.get("binaries") orelse return error.MissingField;
    var found_matching_status = false;
    for (binaries.array.items) |item| {
        if (std.mem.eql(u8, item.object.get("name").?.string, "ghost_task_operator")) {
            found_matching_status = std.mem.eql(u8, item.object.get("status").?.string, "found-not-executable") and
                std.mem.eql(u8, item.object.get("source").?.string, "engine-root");
            break;
        }
    }
    try testing.expect(found_matching_status);
}

// ---------------------------------------------------------------------------
// Default TUI routing and flag regression tests
// ---------------------------------------------------------------------------

test "no-arg invocation routes to graceful non-tty TUI without scan" {
    const mock_root = "/tmp/ghost-cli-noarg-non-tty";
    try std.fs.cwd().makePath(mock_root);
    defer std.fs.cwd().deleteTree(mock_root) catch {};

    const marker = mock_root ++ "/scan-marker";
    try writeMockExecutable(mock_root ++ "/ghost_project_autopsy", "#!/bin/sh\ntouch '" ++ marker ++ "'\nprintf '{}'\n");

    const res = try runCmd(testing.allocator, &[_][]const u8{ "./zig-out/bin/ghost", "--engine-root=" ++ mock_root });
    defer {
        testing.allocator.free(res.stdout);
        testing.allocator.free(res.stderr);
    }

    try testing.expectEqual(@as(u32, 0), res.term.Exited);
    try testing.expect(std.mem.indexOf(u8, res.stderr, "requires an interactive TTY") != null);
    try testing.expect(std.mem.indexOf(u8, res.stderr, "No CLI-owned TUI command was run") != null);
    try testing.expect(std.mem.indexOf(u8, res.stderr, "context/project autopsy scan") != null);
    try testing.expectError(error.FileNotFound, std.fs.cwd().access(marker, .{}));
}

test "help flag still prints help" {
    const res = try runCmd(testing.allocator, &[_][]const u8{ "./zig-out/bin/ghost", "--help" });
    defer {
        testing.allocator.free(res.stdout);
        testing.allocator.free(res.stderr);
    }
    try testing.expect(std.mem.indexOf(u8, res.stderr, "Usage:") != null);
    try testing.expect(std.mem.indexOf(u8, res.stderr, "ghost") != null);
    try testing.expectEqual(@as(u32, 0), res.term.Exited);
}

test "version flag still prints version after no-arg change" {
    const res = try runCmd(testing.allocator, &[_][]const u8{ "./zig-out/bin/ghost", "--version" });
    defer {
        testing.allocator.free(res.stdout);
        testing.allocator.free(res.stderr);
    }
    try testing.expect(std.mem.indexOf(u8, res.stderr, "ghost_cli v0.1.0-hardened") != null);
    try testing.expectEqual(@as(u32, 0), res.term.Exited);
}

test "doctor routes correctly after no-arg change" {
    const res = try runCmd(testing.allocator, &[_][]const u8{
        "./zig-out/bin/ghost",                         "doctor",
        "--engine-root=/tmp/ghost-noarg-route-doctor",
    });
    defer {
        testing.allocator.free(res.stdout);
        testing.allocator.free(res.stderr);
    }
    try testing.expect(std.mem.indexOf(u8, res.stderr, "Unknown command") == null);
    try testing.expect(std.mem.indexOf(u8, res.stdout, "Result:") != null);
}

test "status routes correctly after no-arg change" {
    const res = try runCmd(testing.allocator, &[_][]const u8{
        "./zig-out/bin/ghost",                         "status",
        "--engine-root=/tmp/ghost-noarg-route-status",
    });
    defer {
        testing.allocator.free(res.stdout);
        testing.allocator.free(res.stderr);
    }
    try testing.expect(std.mem.indexOf(u8, res.stderr, "Unknown command") == null);
    try testing.expect(std.mem.indexOf(u8, res.stdout, "--- Ghost CLI Status ---") != null);
}

test "ask command argument parsing still works" {
    // Runs ask with a missing engine; verifies routing reached ask (engine error, not parse error)
    const res = try runCmd(testing.allocator, &[_][]const u8{
        "./zig-out/bin/ghost",                      "ask",
        "--engine-root=/tmp/ghost-noarg-ask-route", "--message=ping",
    });
    defer {
        testing.allocator.free(res.stdout);
        testing.allocator.free(res.stderr);
    }
    // Should NOT produce "Unknown command: ask"
    try testing.expect(std.mem.indexOf(u8, res.stderr, "Unknown command: ask") == null);
}

test "fix command argument parsing still works" {
    const res = try runCmd(testing.allocator, &[_][]const u8{
        "./zig-out/bin/ghost",                      "fix",
        "--engine-root=/tmp/ghost-noarg-fix-route", "--message=ping",
    });
    defer {
        testing.allocator.free(res.stdout);
        testing.allocator.free(res.stderr);
    }
    try testing.expect(std.mem.indexOf(u8, res.stderr, "Unknown command: fix") == null);
}

test "chat command argument parsing still works" {
    const res = try runCmd(testing.allocator, &[_][]const u8{
        "./zig-out/bin/ghost",                       "chat",
        "--engine-root=/tmp/ghost-noarg-chat-route", "--message=ping",
    });
    defer {
        testing.allocator.free(res.stdout);
        testing.allocator.free(res.stderr);
    }
    try testing.expect(std.mem.indexOf(u8, res.stderr, "Unknown command: chat") == null);
}

test "verify command argument parsing still works" {
    const res = try runCmd(testing.allocator, &[_][]const u8{
        "./zig-out/bin/ghost",                         "verify",
        "--engine-root=/tmp/ghost-noarg-verify-route",
    });
    defer {
        testing.allocator.free(res.stdout);
        testing.allocator.free(res.stderr);
    }
    try testing.expect(std.mem.indexOf(u8, res.stderr, "Unknown command: verify") == null);
}

test "no project autopsy auto-scan in CLI" {
    // ghost_project_autopsy is a legitimately tracked engine binary.
    // The safety boundary being tested here is that ghost_cli does NOT contain
    // code that invokes a Project Autopsy *scan* automatically (e.g. on TUI
    // launch or as a background side-effect of any command).
    //
    // What is ALLOWED:
    //   - The binary name appearing in locator/doctor/status (detection/rendering).
    //   - The explicit --version smoke probe in doctor (bounded, labeled, read-only).
    //
    // What is FORBIDDEN:
    //   - Any auto-dispatch to ghost_project_autopsy with scan-triggering args
    //     (e.g. "run", "scan", "analyse") outside of an explicit user command.
    //
    // We verify doctor still reports the binary without triggering a scan,
    // and that the binary count in doctor output matches expected listing.
    const res = try runCmd(testing.allocator, &[_][]const u8{
        "./zig-out/bin/ghost",                            "doctor",
        "--engine-root=/tmp/ghost-autopsy-boundary-test",
    });
    defer {
        testing.allocator.free(res.stdout);
        testing.allocator.free(res.stderr);
    }

    // Doctor must list ghost_project_autopsy as a binary (detection is OK).
    try testing.expect(std.mem.indexOf(u8, res.stdout, "ghost_project_autopsy") != null);

    // Doctor must NOT have run a scan: confirm the "no scan" label is present.
    try testing.expect(std.mem.indexOf(u8, res.stdout, "No scan was run") != null);

    // The smoke label must be present and explicit.
    try testing.expect(std.mem.indexOf(u8, res.stdout, "[smoke only]") != null);
}

test "doctor json includes ghost_project_autopsy in binaries array" {
    const res = try runCmd(testing.allocator, &[_][]const u8{
        "./zig-out/bin/ghost",                        "doctor",
        "--engine-root=/tmp/ghost-autopsy-json-test", "--json",
    });
    defer {
        testing.allocator.free(res.stdout);
        testing.allocator.free(res.stderr);
    }

    var parsed = try std.json.parseFromSlice(std.json.Value, testing.allocator, res.stdout, .{});
    defer parsed.deinit();

    // Binaries array must include ghost_project_autopsy.
    const binaries = parsed.value.object.get("binaries") orelse return error.MissingField;
    var found_autopsy = false;
    for (binaries.array.items) |item| {
        if (item.object.get("name")) |name_val| {
            if (std.mem.eql(u8, name_val.string, "ghost_project_autopsy")) {
                found_autopsy = true;
                break;
            }
        }
    }
    try testing.expect(found_autopsy);

    // Smoke field must exist and be named correctly (labeled, not unlabeled).
    const smoke = parsed.value.object.get("smoke") orelse return error.MissingField;
    try testing.expect(smoke.object.contains("ghost_project_autopsy_version_smoke"));
}

test "autopsy command is listed in help" {
    const res = try runCmd(testing.allocator, &[_][]const u8{ "./zig-out/bin/ghost", "--help" });
    defer {
        testing.allocator.free(res.stdout);
        testing.allocator.free(res.stderr);
    }
    try testing.expect(std.mem.indexOf(u8, res.stderr, "autopsy") != null);
    try testing.expect(std.mem.indexOf(u8, res.stderr, "Project Autopsy pass") != null);
}

test "autopsy json mode preserves raw engine stdout" {
    const mock_root = "/tmp/ghost-autopsy-json-preserve";
    try std.fs.cwd().makePath(mock_root);
    const mock_bin = mock_root ++ "/ghost_project_autopsy";
    const raw_json = "{\"state\":\"draft\",\"non_authorizing\":true,\"project_profile\":{\"workspace_root\":\".\"}}";

    const file = try std.fs.cwd().createFile(mock_bin, .{ .mode = 0o755 });
    defer std.fs.cwd().deleteTree(mock_root) catch {};
    try file.writeAll("#!/bin/sh\nprintf '%s' '");
    try file.writeAll(raw_json);
    try file.writeAll("'\n");
    file.close();

    const res = try runCmd(testing.allocator, &[_][]const u8{
        "./zig-out/bin/ghost",
        "autopsy",
        "--engine-root=" ++ mock_root,
        "--json",
        ".",
    });
    defer {
        testing.allocator.free(res.stdout);
        testing.allocator.free(res.stderr);
    }

    try testing.expectEqualStrings(raw_json, res.stdout);
}

test "autopsy human mode renders draft notice" {
    const mock_root = "/tmp/ghost-autopsy-human-notice";
    try std.fs.cwd().makePath(mock_root);
    const mock_bin = mock_root ++ "/ghost_project_autopsy";
    const raw_json = "{\"state\":\"draft\",\"non_authorizing\":true,\"project_profile\":{\"workspace_root\":\".\"}}";

    const file = try std.fs.cwd().createFile(mock_bin, .{ .mode = 0o755 });
    defer std.fs.cwd().deleteTree(mock_root) catch {};
    try file.writeAll("#!/bin/sh\nprintf '%s' '");
    try file.writeAll(raw_json);
    try file.writeAll("'\n");
    file.close();

    const res = try runCmd(testing.allocator, &[_][]const u8{
        "./zig-out/bin/ghost",
        "autopsy",
        "--engine-root=" ++ mock_root,
        ".",
    });
    defer {
        testing.allocator.free(res.stdout);
        testing.allocator.free(res.stderr);
    }

    try testing.expect(std.mem.indexOf(u8, res.stdout, "DRAFT and NON-AUTHORIZING") != null);
}

test "doctor and status do not run autopsy scans" {
    const mock_root = "/tmp/ghost-no-auto-scan";
    try std.fs.cwd().makePath(mock_root);
    const mock_bin = mock_root ++ "/ghost_project_autopsy";
    const marker = mock_root ++ "/scan-marker";

    const file = try std.fs.cwd().createFile(mock_bin, .{ .mode = 0o755 });
    defer std.fs.cwd().deleteTree(mock_root) catch {};
    // If it receives any arg other than --version, it touches the marker
    try file.writeAll("#!/bin/sh\nfor arg in \"$@\"; do if [ \"$arg\" != \"--version\" ]; then touch '" ++ marker ++ "'; fi; done\n");
    file.close();

    // Test doctor
    const res_doctor = try runCmd(testing.allocator, &[_][]const u8{
        "./zig-out/bin/ghost",
        "doctor",
        "--engine-root=" ++ mock_root,
    });
    defer {
        testing.allocator.free(res_doctor.stdout);
        testing.allocator.free(res_doctor.stderr);
    }
    try testing.expectError(error.FileNotFound, std.fs.cwd().access(marker, .{}));

    // Test status
    const res_status = try runCmd(testing.allocator, &[_][]const u8{
        "./zig-out/bin/ghost",
        "status",
        "--engine-root=" ++ mock_root,
    });
    defer {
        testing.allocator.free(res_status.stdout);
        testing.allocator.free(res_status.stderr);
    }
    try testing.expectError(error.FileNotFound, std.fs.cwd().access(marker, .{}));
}

test "no-arg ghost routes through TUI preflight and does not run autopsy scan" {
    const mock_root = "/tmp/ghost-noarg-no-auto-scan";
    try std.fs.cwd().makePath(mock_root);
    const mock_bin = mock_root ++ "/ghost_project_autopsy";
    const marker = mock_root ++ "/scan-marker";

    const file = try std.fs.cwd().createFile(mock_bin, .{ .mode = 0o755 });
    defer std.fs.cwd().deleteTree(mock_root) catch {};
    try file.writeAll("#!/bin/sh\ntouch '" ++ marker ++ "'\n");
    file.close();

    const res = try runCmd(testing.allocator, &[_][]const u8{
        "./zig-out/bin/ghost",
        "--engine-root=" ++ mock_root,
    });
    defer {
        testing.allocator.free(res.stdout);
        testing.allocator.free(res.stderr);
    }

    try testing.expect(std.mem.indexOf(u8, res.stderr, "requires an interactive TTY") != null);
    try testing.expect(std.mem.indexOf(u8, res.stderr, "No CLI-owned TUI command was run") != null);
    try testing.expectError(error.FileNotFound, std.fs.cwd().access(marker, .{}));
}
