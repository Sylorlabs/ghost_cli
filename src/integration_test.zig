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
    try testing.expect(std.mem.indexOf(u8, res.stderr, "autopsy") != null);
    try testing.expect(std.mem.indexOf(u8, res.stderr, "context") != null);
    try testing.expect(std.mem.indexOf(u8, res.stderr, "debug") != null);
    try testing.expect(std.mem.indexOf(u8, res.stderr, "tui") != null);
    try testing.expect(std.mem.indexOf(u8, res.stderr, "Core:") != null);
    try testing.expect(std.mem.indexOf(u8, res.stderr, "Inspection:") != null);
    try testing.expect(std.mem.indexOf(u8, res.stderr, "Knowledge:") != null);
    try testing.expect(std.mem.indexOf(u8, res.stderr, "Advanced:") != null);
    try testing.expect(std.mem.indexOf(u8, res.stderr, "Interface:") != null);
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
}

test "advanced renderer options parse consistently" {
    const res = try runCmd(testing.allocator, &[_][]const u8{
        "./zig-out/bin/ghost",
        "tui",
        "--help",
        "--no-color",
        "--color=never",
        "--compact",
        "--reasoning=max",
    });
    defer {
        testing.allocator.free(res.stdout);
        testing.allocator.free(res.stderr);
    }
    try testing.expectEqual(@as(u32, 0), res.term.Exited);
    try testing.expect(std.mem.indexOf(u8, res.stderr, "--compact") != null);
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
}

test "packs validate autopsy guidance manifest routes to knowledge pack binary" {
    const mock_root = "/tmp/ghost-cli-packs-validate-manifest";
    const args_path = mock_root ++ "/args.txt";
    try std.fs.cwd().makePath(mock_root);
    defer std.fs.cwd().deleteTree(mock_root) catch {};

    try writeMockExecutable(
        mock_root ++ "/ghost_knowledge_pack",
        "#!/bin/sh\n" ++
            "printf '%s\\n' \"$@\" > '" ++ args_path ++ "'\n" ++
            "printf 'autopsy guidance valid\\n'\n",
    );

    const res = try runCmd(testing.allocator, &[_][]const u8{
        "./zig-out/bin/ghost",
        "packs",
        "validate-autopsy-guidance",
        "--engine-root=" ++ mock_root,
        "--manifest=fixtures/pack/manifest.json",
    });
    defer {
        testing.allocator.free(res.stdout);
        testing.allocator.free(res.stderr);
    }
    const args = try std.fs.cwd().readFileAlloc(testing.allocator, args_path, 1024);
    defer testing.allocator.free(args);

    try testing.expectEqual(@as(u32, 0), res.term.Exited);
    try testing.expectEqualStrings("autopsy guidance valid\n", res.stdout);
    try testing.expect(std.mem.indexOf(u8, args, "validate-autopsy-guidance\n--manifest=fixtures/pack/manifest.json\n") != null);
}

test "packs validate autopsy guidance pack id and version route" {
    const mock_root = "/tmp/ghost-cli-packs-validate-pack-version";
    const args_path = mock_root ++ "/args.txt";
    try std.fs.cwd().makePath(mock_root);
    defer std.fs.cwd().deleteTree(mock_root) catch {};

    try writeMockExecutable(
        mock_root ++ "/ghost_knowledge_pack",
        "#!/bin/sh\n" ++
            "printf '%s\\n' \"$@\" > '" ++ args_path ++ "'\n" ++
            "printf 'warnings: none\\n'\n",
    );

    const res = try runCmd(testing.allocator, &[_][]const u8{
        "./zig-out/bin/ghost",
        "packs",
        "validate-autopsy-guidance",
        "--engine-root=" ++ mock_root,
        "--pack-id=pack-a",
        "--version=1.2.3",
    });
    defer {
        testing.allocator.free(res.stdout);
        testing.allocator.free(res.stderr);
    }
    const args = try std.fs.cwd().readFileAlloc(testing.allocator, args_path, 1024);
    defer testing.allocator.free(args);

    try testing.expectEqual(@as(u32, 0), res.term.Exited);
    try testing.expect(std.mem.indexOf(u8, args, "--pack-id=pack-a\n") != null);
    try testing.expect(std.mem.indexOf(u8, args, "--version=1.2.3\n") != null);
}

test "packs validate autopsy guidance all mounted project shard routes" {
    const mock_root = "/tmp/ghost-cli-packs-validate-all-mounted";
    const args_path = mock_root ++ "/args.txt";
    try std.fs.cwd().makePath(mock_root);
    defer std.fs.cwd().deleteTree(mock_root) catch {};

    try writeMockExecutable(
        mock_root ++ "/ghost_knowledge_pack",
        "#!/bin/sh\n" ++
            "printf '%s\\n' \"$@\" > '" ++ args_path ++ "'\n" ++
            "printf 'mounted guidance checked\\n'\n",
    );

    const res = try runCmd(testing.allocator, &[_][]const u8{
        "./zig-out/bin/ghost",
        "packs",
        "validate-autopsy-guidance",
        "--engine-root=" ++ mock_root,
        "--all-mounted",
        "--project-shard=shard-a",
    });
    defer {
        testing.allocator.free(res.stdout);
        testing.allocator.free(res.stderr);
    }
    const args = try std.fs.cwd().readFileAlloc(testing.allocator, args_path, 1024);
    defer testing.allocator.free(args);

    try testing.expectEqual(@as(u32, 0), res.term.Exited);
    try testing.expect(std.mem.indexOf(u8, args, "--all-mounted\n--project-shard=shard-a\n") != null);
}

test "packs validate autopsy guidance json preserves raw engine stdout" {
    const mock_root = "/tmp/ghost-cli-packs-validate-json";
    const args_path = mock_root ++ "/args.txt";
    const raw_json = "{\"status\":\"valid\",\"warnings\":[\"review guidance wording\"]}";
    try std.fs.cwd().makePath(mock_root);
    defer std.fs.cwd().deleteTree(mock_root) catch {};

    const file = try std.fs.cwd().createFile(mock_root ++ "/ghost_knowledge_pack", .{ .mode = 0o755 });
    try file.writeAll("#!/bin/sh\nprintf '%s\\n' \"$@\" > '");
    try file.writeAll(args_path);
    try file.writeAll("'\nprintf '%s' '");
    try file.writeAll(raw_json);
    try file.writeAll("'\n");
    file.close();

    const res = try runCmd(testing.allocator, &[_][]const u8{
        "./zig-out/bin/ghost",
        "packs",
        "validate-autopsy-guidance",
        "--engine-root=" ++ mock_root,
        "--json",
        "--manifest=fixtures/pack/manifest.json",
    });
    defer {
        testing.allocator.free(res.stdout);
        testing.allocator.free(res.stderr);
    }
    const args = try std.fs.cwd().readFileAlloc(testing.allocator, args_path, 1024);
    defer testing.allocator.free(args);

    try testing.expectEqual(@as(u32, 0), res.term.Exited);
    try testing.expectEqualStrings(raw_json, res.stdout);
    try testing.expect(std.mem.indexOf(u8, args, "--json\n") != null);
}

test "packs validate autopsy guidance failure propagates nonzero" {
    const mock_root = "/tmp/ghost-cli-packs-validate-failure";
    try std.fs.cwd().makePath(mock_root);
    defer std.fs.cwd().deleteTree(mock_root) catch {};

    try writeMockExecutable(
        mock_root ++ "/ghost_knowledge_pack",
        "#!/bin/sh\n" ++
            "printf 'validation failed: missing guidance id\\n'\n" ++
            "exit 7\n",
    );

    const res = try runCmd(testing.allocator, &[_][]const u8{
        "./zig-out/bin/ghost",
        "packs",
        "validate-autopsy-guidance",
        "--engine-root=" ++ mock_root,
        "--manifest=bad-manifest.json",
    });
    defer {
        testing.allocator.free(res.stdout);
        testing.allocator.free(res.stderr);
    }

    try testing.expectEqual(@as(u32, 7), res.term.Exited);
    try testing.expectEqualStrings("validation failed: missing guidance id\n", res.stdout);
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

test "doctor status and no-arg TUI do not run autopsy guidance validation" {
    const mock_root = "/tmp/ghost-cli-packs-no-hidden-validation";
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
            "printf 'knowledge pack\\n'\n",
    );
    try writeMockExecutable(mock_root ++ "/ghost_gip", "#!/bin/sh\nprintf '{\"status\":\"ok\"}'\n");
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
}

test "doctor status and no-arg TUI do not invoke context autopsy" {
    const mock_root = "/tmp/ghost-cli-context-no-hidden";
    const marker = mock_root ++ "/context-marker";
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
