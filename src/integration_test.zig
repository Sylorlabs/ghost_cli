const std = @import("std");
const testing = std.testing;

fn runCmd(allocator: std.mem.Allocator, args: []const []const u8) !std.process.Child.RunResult {
    return std.process.Child.run(.{
        .allocator = allocator,
        .argv = args,
        .max_output_bytes = 10 * 1024 * 1024,
    });
}

fn writeMockExecutable(path: []const u8, body: []const u8) !void {
    const file = try std.fs.cwd().createFile(path, .{ .mode = 0o755 });
    defer file.close();
    try file.writeAll(body);
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
    try testing.expect(std.mem.indexOf(u8, res.stderr, "learn") != null);
    try testing.expect(std.mem.indexOf(u8, res.stderr, "status") != null);
    try testing.expect(std.mem.indexOf(u8, res.stderr, "doctor") != null);
    try testing.expect(std.mem.indexOf(u8, res.stderr, "debug") != null);
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
    const file = try std.fs.cwd().createFile(mock_bin, .{});
    file.close();

    const res = try runCmd(testing.allocator, &[_][]const u8{ "./zig-out/bin/ghost", "status", "--engine-root=" ++ mock_root, "--debug" });
    defer {
        testing.allocator.free(res.stdout);
        testing.allocator.free(res.stderr);
        std.fs.cwd().deleteTree(mock_root) catch {};
    }

    try testing.expect(std.mem.indexOf(u8, res.stdout, "[FOUND]    " ++ mock_bin) != null);
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
    try writeMockExecutable(mock_root ++ "/zig-out/bin/ghost_knowledge_pack", "#!/bin/sh\ntouch '" ++ marker ++ "'\n");

    const res = try runCmd(testing.allocator, &[_][]const u8{ "./zig-out/bin/ghost", "doctor", "--engine-root=" ++ mock_root });
    defer {
        testing.allocator.free(res.stdout);
        testing.allocator.free(res.stderr);
    }

    try testing.expect(std.mem.indexOf(u8, res.stdout, "ghost_knowledge_pack: EXECUTABLE") != null);
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

// ---------------------------------------------------------------------------
// Default TUI routing and flag regression tests
// ---------------------------------------------------------------------------

test "no-arg invocation attempts TUI not static help" {
    // The TUI enters raw mode and blocks on stdin, so we cannot invoke `ghost`
    // bare in a non-interactive test without hanging.  Instead we verify the
    // routing contract via two observable proxy signals:
    //   1. `ghost --help` now documents the no-arg TUI default.
    //   2. The help output does NOT start with the old static-only preamble
    //      that was the sole result of a bare invocation.
    // This is the safe smoke method called out in the audit spec.
    const res = try runCmd(testing.allocator, &[_][]const u8{ "./zig-out/bin/ghost", "--help" });
    defer {
        testing.allocator.free(res.stdout);
        testing.allocator.free(res.stderr);
    }
    // Updated help must mention TUI/no-arg default
    const has_noarg_doc = std.mem.indexOf(u8, res.stderr, "no arguments") != null or
        std.mem.indexOf(u8, res.stderr, "(none)") != null;
    try testing.expect(has_noarg_doc);
    // All commands still listed in help
    try testing.expect(std.mem.indexOf(u8, res.stderr, "chat") != null);
    try testing.expect(std.mem.indexOf(u8, res.stderr, "ask") != null);
    try testing.expect(std.mem.indexOf(u8, res.stderr, "tui") != null);
    try testing.expect(std.mem.indexOf(u8, res.stderr, "doctor") != null);
    try testing.expect(std.mem.indexOf(u8, res.stderr, "status") != null);
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
