const std = @import("std");
const state = @import("state.zig");
const render = @import("render.zig");
const input = @import("input.zig");
const slash = @import("slash.zig");
const stats = @import("stats.zig");
const terminal = @import("terminal.zig");
const runner = @import("../engine/runner.zig");
const shell = @import("../engine/shell.zig");
const diff_viewer = @import("diff_viewer.zig");
const json_contracts = @import("../engine/json_contracts.zig");
const doctor = @import("../commands/doctor.zig");
const daemon_cmd = @import("../commands/daemon.zig");
const autopsy = @import("../commands/autopsy.zig");
const corpus = @import("../commands/corpus.zig");
const packs = @import("../commands/packs.zig");
const daemon_client = @import("../engine/daemon_client.zig");
const locator = @import("../engine/locator.zig");
const process = @import("../engine/process.zig");

pub const SlashKind = slash.SlashKind;
pub const SlashCommand = slash.SlashCommand;

pub const ColorMode = enum {
    auto,
    always,
    never,
};

pub const RunOptions = struct {
    reasoning: ?json_contracts.ReasoningLevel = null,
    context_artifact: ?[]const u8 = null,
    debug: bool = false,
    details: bool = false,
    color: ColorMode = .auto,
    compact: bool = false,
    read_only: bool = false,
    yolo_mode: bool = false,
    max_history_turns: usize = state.default_max_history_turns,
    version: []const u8,
    engine_root_label: ?[]const u8 = null,
    project_shard: ?[]const u8 = null,
};

pub fn parseSlashCommand(text: []const u8) SlashCommand {
    return slash.parse(text);
}

pub fn shouldSubmitToEngine(text: []const u8) bool {
    return slash.shouldSubmitToEngine(text);
}

pub fn shouldSubmitToEngineInMode(text: []const u8, read_only: bool) bool {
    return !read_only and slash.shouldSubmitToEngine(text);
}

pub fn isReadOnlyBlockedCommand(command: SlashCommand) bool {
    return switch (command.kind) {
        .daemon, .doctor, .autopsy, .mount => true,
        else => false,
    };
}

pub fn run(allocator: std.mem.Allocator, engine_root: ?[]const u8, options: RunOptions) !void {
    if (!input.isTty()) {
        try render.renderNonTty(std.io.getStdErr().writer());
        return;
    }

    const color_enabled = try colorEnabled(allocator, options.color);
    const style = render.Style{ .color = color_enabled };

    if (options.max_history_turns == 0) return error.InvalidHistoryLimit;

    var s = state.SessionState.initWithLimit(allocator, options.version, options.engine_root_label, options.compact, options.max_history_turns);
    defer s.deinit();

    if (options.reasoning) |r| s.reasoning = r;
    if (options.context_artifact) |c| s.context_artifact = try allocator.dupe(u8, c);
    if (options.project_shard) |project_shard| s.project_shard = try allocator.dupe(u8, project_shard);
    s.debug = options.debug;
    s.details = options.details or options.debug;
    s.read_only = options.read_only;
    s.yolo_mode = options.yolo_mode;

    const stdin = std.io.getStdIn();
    const stdout = std.io.getStdOut();
    const writer = stdout.writer();
    const stderr = std.io.getStdErr();
    const warning_writer = stderr.writer();

    var terminal_guard = try input.TerminalGuard.enable();
    defer terminal_guard.restore(writer, warning_writer);

    s.refreshTerminalSize(std.time.milliTimestamp(), terminal.getSize);
    s.refreshRam(std.time.milliTimestamp(), stats.getCliRamRss);

    try render.initTerminalWithSize(writer, style, s.terminal_size);
    terminal_guard.markTerminalInitialized();

    if (!s.read_only and daemon_cmd.ensureActiveQuiet(allocator, engine_root, s.debug)) {
        s.last_daemon_refresh_ms = -state.daemon_refresh_interval_ms;
    }

    var frame_dirty = true;
    while (true) {
        const now_ms = std.time.milliTimestamp();
        const previous_size = s.terminal_size;
        const previous_daemon_active = s.daemon_active;
        const previous_daemon_vram = s.daemon_vram_resident_bytes;
        s.refreshTerminalSize(now_ms, terminal.getSize);
        s.refreshRam(now_ms, stats.getCliRamRss);
        try refreshDaemonTelemetry(allocator, &s, now_ms);
        if (previous_size.rows != s.terminal_size.rows or
            previous_size.cols != s.terminal_size.cols or
            previous_daemon_active != s.daemon_active or
            previous_daemon_vram != s.daemon_vram_resident_bytes)
        {
            frame_dirty = true;
        }
        if (frame_dirty) {
            try render.renderFrameWithSize(writer, &s, style, s.terminal_size);
            frame_dirty = false;
        }

        const key = try input.readKey(stdin.reader());
        var key_changed = true;
        switch (key) {
            .ctrl => |c| {
                switch (c) {
                    'C' => break,
                    'R' => s.cycleReasoning(),
                    'D' => {
                        s.debug = !s.debug;
                        s.details = s.debug;
                        s.last_command_status = if (s.debug) "debug on" else "debug off";
                    },
                    'L' => {
                        s.clearHistory();
                        try render.clearHistoryAreaWithSize(writer, s.terminal_size);
                    },
                    'Y' => {
                        s.yolo_mode = !s.yolo_mode;
                        s.last_command_status = if (s.yolo_mode) "yolo on" else "yolo off";
                    },
                    else => {},
                }
            },
            .esc => {
                if (s.pending_patch != null) {
                    s.clearPendingPatch();
                    s.last_command_status = "patch rejected";
                } else if (s.pending_command != null) {
                    s.clearPendingCommand();
                    s.last_command_status = "command rejected";
                } else break;
            },
            .up => {
                const count = slash.matchingCount(s.current_input.items);
                if (count > 0) {
                    if (s.suggestion_index == 0) {
                        s.suggestion_index = count - 1;
                    } else {
                        s.suggestion_index -= 1;
                    }
                }
            },
            .down => {
                const count = slash.matchingCount(s.current_input.items);
                if (count > 0) {
                    s.suggestion_index = (s.suggestion_index + 1) % count;
                }
            },
            .right => {
                if (std.mem.indexOfAny(u8, s.current_input.items, " \t") == null) {
                    if (slash.findNthMatch(s.current_input.items, s.suggestion_index)) |matched| {
                        if (slash.isPrefixMatch(s.current_input.items, matched) and matched.len > s.current_input.items.len) {
                            try s.current_input.appendSlice(matched[s.current_input.items.len..]);
                            s.suggestion_index = 0;
                        } else if (!slash.isPrefixMatch(s.current_input.items, matched)) {
                            s.current_input.clearRetainingCapacity();
                            try s.current_input.appendSlice(matched);
                            s.suggestion_index = 0;
                        }
                    }
                }
            },
            .left => {
                // Return slash-command input to the root suggestion menu.
                if (s.current_input.items.len > 1 and s.current_input.items[0] == '/') {
                    s.current_input.shrinkAndFree(1);
                    s.suggestion_index = 0;
                }
            },
            .tab => {
                if (std.mem.indexOfAny(u8, s.current_input.items, " \t") == null) {
                    if (slash.findNthMatch(s.current_input.items, s.suggestion_index)) |matched| {
                        if (slash.isPrefixMatch(s.current_input.items, matched) and matched.len > s.current_input.items.len) {
                            try s.current_input.appendSlice(matched[s.current_input.items.len..]);
                            s.suggestion_index = 0;
                        } else if (!slash.isPrefixMatch(s.current_input.items, matched)) {
                            s.current_input.clearRetainingCapacity();
                            try s.current_input.appendSlice(matched);
                            s.suggestion_index = 0;
                        }
                    }
                }
            },
            .shift_tab => {
                if (s.pending_patch != null) {
                    try applyPendingPatch(allocator, &s, writer, style);
                }
            },
            .enter => {
                if (s.current_input.items.len == 0) continue;

                const cmd_text = try allocator.dupe(u8, s.current_input.items);
                defer allocator.free(cmd_text);
                s.current_input.clearRetainingCapacity();
                s.suggestion_index = 0;

                if (try handleSlash(allocator, engine_root, &s, cmd_text, writer, style)) |should_quit| {
                    if (should_quit) break;
                    frame_dirty = true;
                    continue;
                }

                try handleSubmit(allocator, engine_root, &s, cmd_text, writer, style);
            },
            .backspace => {
                if (s.current_input.items.len > 0) {
                    _ = s.current_input.pop();
                    s.suggestion_index = 0;
                }
            },
            .char => |c| {
                if (s.pending_command != null) {
                    if (c == 'y' or c == 'Y') {
                        try executePendingCommand(allocator, &s, writer, style);
                    } else if (c == 'n' or c == 'N') {
                        s.clearPendingCommand();
                        s.last_command_status = "command rejected";
                    }
                    frame_dirty = true;
                    continue;
                }
                if (s.current_input.items.len == 0 and c == 'q') break;
                try s.current_input.append(c);
                s.suggestion_index = 0;
            },
            .unsupported => key_changed = false,
        }
        if (key_changed) frame_dirty = true;
    }
}

fn colorEnabled(allocator: std.mem.Allocator, mode: ColorMode) !bool {
    return switch (mode) {
        .always => true,
        .never => false,
        .auto => blk: {
            const no_color = std.process.getEnvVarOwned(allocator, "NO_COLOR") catch |err| switch (err) {
                error.EnvironmentVariableNotFound => break :blk true,
                else => return err,
            };
            allocator.free(no_color);
            break :blk false;
        },
    };
}

const DaemonStatusPayload = struct {
    status: []const u8 = "",
    vramResidentBytes: ?usize = null,
    l1ConceptIndexBytes: ?usize = null,
    hotPageBytes: ?usize = null,
    rawShardVramBytes: ?usize = null,
    sessionHotBytes: ?usize = null,
    sessionContextTarget: ?[]const u8 = null,
    vaultIngestActive: ?bool = null,
    vaultIngestRecent: ?bool = null,
    vaultIngestedFiles: ?usize = null,
    vaultIngestErrors: ?usize = null,
    lastVaultIngestMs: ?i64 = null,
};

const DaemonStatusEnvelope = struct {
    status: []const u8 = "",
    daemon: ?DaemonStatusPayload = null,
};

fn refreshDaemonTelemetry(allocator: std.mem.Allocator, s: *state.SessionState, now_ms: i64) !void {
    if (s.daemon_refresh_count != 0 and now_ms - s.last_daemon_refresh_ms < state.daemon_refresh_interval_ms) return;
    s.last_daemon_refresh_ms = now_ms;
    s.daemon_refresh_count += 1;

    const response = daemon_client.request(allocator, "{\"kind\":\"daemon.status\"}") catch {
        s.daemon_active = false;
        s.daemon_vault_ingest_active = false;
        s.daemon_vault_ingest_recent = false;
        try s.setDaemonContextTarget(null);
        return;
    };
    defer allocator.free(response);

    var parsed = std.json.parseFromSlice(DaemonStatusEnvelope, allocator, response, .{ .ignore_unknown_fields = true }) catch {
        s.daemon_active = false;
        try s.setDaemonContextTarget(null);
        return;
    };
    defer parsed.deinit();

    const payload = parsed.value.daemon orelse {
        s.daemon_active = false;
        try s.setDaemonContextTarget(null);
        return;
    };
    s.daemon_active = std.mem.eql(u8, payload.status, "running");
    s.daemon_vram_resident_bytes = payload.vramResidentBytes orelse 0;
    s.daemon_l1_concept_index_bytes = payload.l1ConceptIndexBytes orelse 0;
    s.daemon_hot_page_bytes = payload.hotPageBytes orelse 0;
    s.daemon_raw_shard_vram_bytes = payload.rawShardVramBytes orelse 0;
    s.daemon_session_hot_bytes = payload.sessionHotBytes orelse 0;
    s.daemon_vault_ingest_active = payload.vaultIngestActive orelse false;
    s.daemon_vault_ingest_recent = payload.vaultIngestRecent orelse false;
    s.daemon_vault_ingested_files = payload.vaultIngestedFiles orelse 0;
    s.daemon_vault_ingest_errors = payload.vaultIngestErrors orelse 0;
    s.daemon_last_vault_ingest_ms = payload.lastVaultIngestMs orelse 0;
    try s.setDaemonContextTarget(payload.sessionContextTarget);
}

pub fn handleSlash(allocator: std.mem.Allocator, engine_root: ?[]const u8, s: *state.SessionState, text: []const u8, writer: anytype, style: render.Style) !?bool {
    const command = parseSlashCommand(text);
    if (s.read_only and isReadOnlyBlockedCommand(command)) {
        const token = slash.suggestionToken(text);
        s.last_command_status = "read-only blocked";
        try render.renderErrorMessage(writer, style, "Read-only mode: command blocked: {s}", .{token});
        return false;
    }
    switch (command.kind) {
        .none => return null,
        .quit => return true,
        .help => {
            try render.renderHelpWithSize(writer, style, s.terminal_size);
            s.last_command_status = "help";
        },
        .status => {
            try render.renderStatus(writer, s, style);
            s.last_command_status = "status";
        },
        .clear => {
            s.clearHistory();
            try render.clearHistoryAreaWithSize(writer, s.terminal_size);
        },
        .reasoning => {
            const level_str = command.arg orelse "";
            if (std.meta.stringToEnum(json_contracts.ReasoningLevel, level_str)) |level| {
                s.reasoning = level;
                s.last_command_status = "reasoning changed";
                try render.renderCommandMessage(writer, style, "reasoning={s}", .{level.toStr()});
            } else {
                s.last_command_status = "invalid reasoning";
                try render.renderErrorMessage(writer, style, "Invalid reasoning level: {s}. Use quick|balanced|deep|max", .{level_str});
            }
        },
        .debug => {
            const setting = command.arg orelse "";
            if (std.mem.eql(u8, setting, "on")) s.debug = true else if (std.mem.eql(u8, setting, "off")) s.debug = false else s.debug = !s.debug;
            s.details = s.debug;
            s.last_command_status = if (s.debug) "debug on" else "debug off";
            try render.renderCommandMessage(writer, style, "debug={s}", .{if (s.debug) "on" else "off"});
        },
        .details => {
            const setting = command.arg orelse "";
            if (std.mem.eql(u8, setting, "on")) s.details = true else if (std.mem.eql(u8, setting, "off")) s.details = false else s.details = !s.details;
            s.last_command_status = if (s.details) "details on" else "details off";
            try render.renderCommandMessage(writer, style, "details={s}", .{if (s.details) "on" else "off"});
        },
        .json => {
            const setting = command.arg orelse "";
            if (std.mem.eql(u8, setting, "on")) s.json_mode = true else if (std.mem.eql(u8, setting, "off")) s.json_mode = false else s.json_mode = !s.json_mode;
            s.last_command_status = if (s.json_mode) "json on" else "json off";
            try render.renderCommandMessage(writer, style, "json={s}", .{if (s.json_mode) "on" else "off"});
        },
        .doctor => {
            s.last_command_status = "doctor requested";
            try render.renderCommandMessage(writer, style, "doctor: explicit read-only diagnostics", .{});
            try doctor.execute(allocator, engine_root, .{
                .json = false,
                .debug = s.debug,
                .report = false,
                .full = false,
                .run_build_check = false,
                .version = s.version,
            });
        },
        .daemon => {
            const sub = command.arg orelse "";
            const action = if (sub.len == 0) "start" else sub;
            s.last_command_status = "daemon requested";
            try render.renderCommandMessage(writer, style, "daemon: {s}", .{action});
            if (std.mem.eql(u8, action, "start")) {
                try daemon_cmd.startWithWriter(allocator, engine_root, s.debug, writer);
                s.last_command_status = "daemon start requested";
                s.last_daemon_refresh_ms = -state.daemon_refresh_interval_ms;
                try refreshDaemonTelemetry(allocator, s, std.time.milliTimestamp());
            } else if (std.mem.eql(u8, action, "status")) {
                try daemon_cmd.statusWithWriter(allocator, writer);
                s.last_command_status = "daemon status";
                s.last_daemon_refresh_ms = -state.daemon_refresh_interval_ms;
                try refreshDaemonTelemetry(allocator, s, std.time.milliTimestamp());
            } else if (std.mem.eql(u8, action, "stop")) {
                try daemon_cmd.stopWithWriter(allocator, writer);
                s.last_command_status = "daemon stop requested";
                s.daemon_active = false;
            } else {
                s.last_command_status = "invalid daemon command";
                try render.renderErrorMessage(writer, style, "Invalid daemon command: {s}. Use /daemon, /daemon status, or /daemon stop", .{action});
            }
        },
        .autopsy => {
            const path = command.arg orelse "";
            if (path.len == 0) {
                s.last_command_status = "autopsy path required";
                try render.renderErrorMessage(writer, style, "/autopsy requires an explicit path", .{});
            } else {
                s.last_command_status = "autopsy requested";
                try render.renderCommandMessage(writer, style, "autopsy: explicit scan: {s}", .{path});
                try autopsy.execute(allocator, engine_root, .{ .path = path, .json = false, .debug = s.debug });
            }
        },
        .context => {
            const path = command.arg orelse "";
            if (path.len == 0) {
                s.last_command_status = "context path required";
                try render.renderErrorMessage(writer, style, "/context requires a path", .{});
            } else {
                if (s.context_artifact) |ca| allocator.free(ca);
                s.context_artifact = try allocator.dupe(u8, path);
                s.last_command_status = "context changed";
                try render.renderCommandMessage(writer, style, "context={s}", .{path});
            }
        },
        .mount => {
            const pack = command.arg orelse "";
            if (pack.len == 0) {
                s.last_command_status = "mount pack required";
                try render.renderErrorMessage(writer, style, "/mount requires a pack id", .{});
            } else {
                const parsed_mount = parseMountArg(pack);
                s.last_command_status = "mount requested";
                try render.renderCommandMessage(writer, style, "mount: {s}@{s}", .{ parsed_mount.pack_id, parsed_mount.pack_version });
                // We use standard executeMount which handles runner.run
                packs.execute(allocator, engine_root, .{
                    .subcommand = "mount",
                    .pack_id = parsed_mount.pack_id,
                    .version = parsed_mount.pack_version,
                    .debug = s.debug,
                }) catch |err| {
                    try render.renderErrorMessage(writer, style, "Mount failed: {}", .{err});
                    return false;
                };
                try s.addActiveSessionMount(parsed_mount.pack_id, parsed_mount.pack_version);
                s.last_counters.mounted_packs = s.active_session_mounts.items.len;
                s.last_command_status = "mount active";
            }
        },
        .unknown => {
            s.last_command_status = "unknown slash command";
            try render.renderInvalidSlashCommand(writer, style, command.arg orelse text);
        },
    }
    return false;
}

const ParsedMountArg = struct {
    pack_id: []const u8,
    pack_version: []const u8,
};

fn parseMountArg(raw: []const u8) ParsedMountArg {
    const trimmed = std.mem.trim(u8, raw, " \r\n\t");
    if (std.mem.indexOfScalar(u8, trimmed, '@')) |idx| {
        const pack_id = std.mem.trim(u8, trimmed[0..idx], " \r\n\t");
        const pack_version = std.mem.trim(u8, trimmed[(idx + 1)..], " \r\n\t");
        if (pack_id.len != 0 and pack_version.len != 0) return .{ .pack_id = pack_id, .pack_version = pack_version };
    }
    return .{ .pack_id = trimmed, .pack_version = "v1" };
}

pub fn handleSubmit(allocator: std.mem.Allocator, engine_root: ?[]const u8, s: *state.SessionState, cmd_text: []const u8, writer: anytype, style: render.Style) !void {
    if (s.read_only) {
        s.last_command_status = "read-only blocked";
        try render.renderErrorMessage(writer, style, "Read-only mode: engine prompt blocked", .{});
        return;
    }

    const start_time = std.time.milliTimestamp();
    s.last_command_status = "thinking";
    try render.renderFrameWithSize(writer, s, style, s.terminal_size);

    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const aa = arena.allocator();

    const use_daemon = s.daemon_refresh_count != 0 and s.daemon_active;
    const res = if (s.active_session_mounts.items.len != 0) blk: {
        const bin_path = locator.findEngineBinary(allocator, engine_root, .ghost_gip) catch |err| {
            try render.renderErrorMessage(writer, style, "Failed to resolve ghost_gip: {}", .{err});
            return;
        };
        defer allocator.free(bin_path);

        var request = std.ArrayList(u8).init(aa);
        try writeMountedCorpusAskRequest(request.writer(), cmd_text, s);

        const gip_argv = &[_][]const u8{ bin_path, "--stdin" };
        const result = process.runEngineCommandWithInput(allocator, gip_argv, request.items) catch |err| {
            try render.renderErrorMessage(writer, style, "Failed to run mounted corpus.ask: {}", .{err});
            return;
        };
        break :blk runner.RunResult{
            .stdout = result.stdout,
            .stderr = result.stderr,
            .exit_code = result.exit_code,
            .allocator = allocator,
        };
    } else if (use_daemon) blk: {
        var request = std.ArrayList(u8).init(aa);
        try writeDaemonCorpusAskRequest(request.writer(), cmd_text, s);
        const response = daemon_client.request(allocator, request.items) catch {
            s.daemon_active = false;
            break :blk runner.RunResult{
                .stdout = try allocator.dupe(u8, process.OFFLINE_ROUTING_ERROR),
                .stderr = try allocator.alloc(u8, 0),
                .exit_code = 1,
                .allocator = allocator,
            };
        };
        break :blk runner.RunResult{
            .stdout = response,
            .stderr = try allocator.alloc(u8, 0),
            .exit_code = 0,
            .allocator = allocator,
        };
    } else blk: {
        break :blk try runTaskOperatorFallback(allocator, engine_root, aa, cmd_text, s);
    };
    defer res.deinit();

    const elapsed = @as(u64, @intCast(std.time.milliTimestamp() - start_time));

    var rendered_buf = std.ArrayList(u8).init(allocator);
    defer rendered_buf.deinit();

    var json_ok = false;

    if (s.json_mode) {
        if (!(try renderTuiChatProjection(allocator, res.stdout, rendered_buf.writer(), s))) {
            try rendered_buf.appendSlice("No generated response was present in engine output.\n");
        }
        json_ok = true;
    } else if (try renderTuiChatProjection(allocator, res.stdout, rendered_buf.writer(), s)) {
        json_ok = true;
    } else if (json_contracts.parseEngineJson(allocator, res.stdout)) |parsed| {
        s.last_counters = json_contracts.renderCounters(parsed.value);
        s.recordResponseState(parsed.value);
        try s.setEngineTrace(traceFromEngineResponse(parsed.value));
        try writeEngineResponseChat(rendered_buf.writer(), parsed.value);
        json_ok = true;
        parsed.deinit();
    } else |_| {
        try writeCleanFallbackChat(rendered_buf.writer(), res.stdout, !use_daemon);
    }

    const rendered_output = try rendered_buf.toOwnedSlice();
    const output_runes = stats.countRunes(rendered_output);
    const turn = state.Turn{
        .index = s.nextTurnIndex(),
        .input = try allocator.dupe(u8, cmd_text),
        .reasoning = s.reasoning,
        .context_artifact = if (s.context_artifact) |ca| try allocator.dupe(u8, ca) else null,
        .response = null, // TODO: store response if needed
        .raw_output = try allocator.dupe(u8, res.stdout),
        .rendered_output = rendered_output,
        .elapsed_ms = elapsed,
        .input_runes = stats.countRunes(cmd_text),
        .output_runes = output_runes,
        .json_ok = json_ok,
    };

    try s.appendTurn(turn);

    if (try diff_viewer.findPatchProposal(allocator, res.stdout)) |proposal| {
        s.setPendingPatch(proposal);
        s.last_command_status = "patch approval pending";
    } else if (try shell.findCommandProposal(allocator, res.stdout)) |proposal| {
        s.setPendingCommand(proposal);
        s.last_command_status = "command approval pending";
    }

    const post_ms = std.time.milliTimestamp();
    s.refreshRam(post_ms, stats.getCliRamRss);
    if (s.daemon_refresh_count != 0) try refreshDaemonTelemetry(allocator, s, post_ms);
    s.last_command_status = if (res.exit_code == 0) "engine response" else "engine error";
    if (s.pending_patch != null) {
        s.last_command_status = "patch approval pending";
    } else if (s.pending_command != null) {
        s.last_command_status = "command approval pending";
    }
    try renderTypewriterTurn(writer, s, turn.index, rendered_output.len, style);
    if (s.yolo_mode and s.pending_command != null) {
        try executePendingCommand(allocator, s, writer, style);
    }
}

fn executePendingCommand(allocator: std.mem.Allocator, s: *state.SessionState, writer: anytype, style: render.Style) !void {
    const proposal = s.takePendingCommand() orelse return;
    defer proposal.deinit();
    s.last_command_status = "command executing";
    try render.renderFrameWithSize(writer, s, style, s.terminal_size);

    const start_time = std.time.milliTimestamp();
    const result = shell.execute(allocator, proposal) catch |err| {
        s.last_command_status = "command failed";
        try render.renderErrorMessage(writer, style, "Command failed before execution completed: {}", .{err});
        return;
    };
    defer result.deinit();
    const elapsed = @as(u64, @intCast(std.time.milliTimestamp() - start_time));

    var raw = std.ArrayList(u8).init(allocator);
    defer raw.deinit();
    try shell.renderCommandResultJson(raw.writer(), proposal, result);

    var rendered = std.ArrayList(u8).init(allocator);
    defer rendered.deinit();
    try rendered.writer().print("[COMMAND] {s}\nexit={d}\n", .{ proposal.command_display, result.exit_code });
    if (result.stdout.len > 0) {
        try rendered.appendSlice("\nStdout:\n");
        try rendered.appendSlice(result.stdout);
    }
    if (result.stderr.len > 0) {
        try rendered.appendSlice("\nStderr:\n");
        try rendered.appendSlice(result.stderr);
    }

    const rendered_output = try rendered.toOwnedSlice();
    const raw_output = try raw.toOwnedSlice();
    const turn = state.Turn{
        .index = s.nextTurnIndex(),
        .input = try allocator.dupe(u8, proposal.command_display),
        .reasoning = s.reasoning,
        .context_artifact = if (s.context_artifact) |ca| try allocator.dupe(u8, ca) else null,
        .response = null,
        .raw_output = raw_output,
        .rendered_output = rendered_output,
        .elapsed_ms = elapsed,
        .input_runes = stats.countRunes(proposal.command_display),
        .output_runes = stats.countRunes(rendered_output),
        .json_ok = true,
    };
    try s.appendTurn(turn);
    s.last_command_status = if (result.exit_code == 0) "command executed" else "command error";
    try renderTypewriterTurn(writer, s, turn.index, rendered_output.len, style);
}

fn applyPendingPatch(allocator: std.mem.Allocator, s: *state.SessionState, writer: anytype, style: render.Style) !void {
    const proposal = s.takePendingPatch() orelse return;
    defer proposal.deinit();
    const result = diff_viewer.applyUnifiedDiff(allocator, proposal.diff) catch |err| {
        s.last_command_status = "patch apply failed";
        try render.renderErrorMessage(writer, style, "Patch apply failed: {}", .{err});
        return;
    };
    defer result.deinit();
    s.last_command_status = "patch applied";
    try render.renderCommandMessage(writer, style, "applied patch to {s}", .{result.path});
}

fn renderTypewriterTurn(writer: anytype, s: *state.SessionState, turn_index: usize, output_len: usize, style: render.Style) !void {
    s.typing_turn_index = turn_index;
    s.typing_output_bytes = 0;
    const step = @max(@as(usize, 8), output_len / 80 + 1);
    while (s.typing_output_bytes < output_len) {
        s.typing_output_bytes = @min(output_len, s.typing_output_bytes + step);
        try render.renderFrameWithSize(writer, s, style, s.terminal_size);
        std.time.sleep(6 * std.time.ns_per_ms);
    }
    s.typing_turn_index = null;
    s.typing_output_bytes = 0;
    try render.renderFrameWithSize(writer, s, style, s.terminal_size);
}

fn runTaskOperatorFallback(
    allocator: std.mem.Allocator,
    engine_root: ?[]const u8,
    aa: std.mem.Allocator,
    cmd_text: []const u8,
    s: *state.SessionState,
) !runner.RunResult {
    var argv = std.ArrayList([]const u8).init(aa);
    try argv.append("chat");
    try argv.append(try std.fmt.allocPrint(aa, "--message={s}", .{cmd_text}));

    var buf: [64]u8 = undefined;
    const reasoning_arg = try std.fmt.bufPrint(&buf, "--reasoning={s}", .{s.reasoning.toStr()});
    try argv.append(try aa.dupe(u8, reasoning_arg));

    if (s.context_artifact) |art| {
        try argv.append("--context-artifact");
        try argv.append(art);
    }

    try argv.append("--render=json");
    return try runner.run(allocator, .{
        .engine_root = engine_root,
        .binary = .ghost_task_operator,
        .argv = argv.items,
        .json = true,
        .debug = s.debug,
    });
}

fn renderTuiChatProjection(allocator: std.mem.Allocator, bytes: []const u8, writer: anytype, s: *state.SessionState) !bool {
    var parsed = std.json.parseFromSlice(std.json.Value, allocator, bytes, .{}) catch return false;
    defer parsed.deinit();
    if (findCorpusAskValue(parsed.value)) |corpus_value| {
        const trace = try traceFromCorpusAskJson(allocator, parsed.value, corpus_value);
        defer if (trace.trace_flags) |flags| allocator.free(flags);
        try s.setEngineTrace(trace);
        try writeCorpusAskChat(writer, corpus_value);
        return true;
    }
    if (try writeGenericJsonChat(allocator, writer, parsed.value, s)) return true;
    try writer.writeAll(process.SEMANTIC_VOID_MESSAGE);
    try writer.writeByte('\n');
    return true;
}

fn findCorpusAskValue(value: std.json.Value) ?std.json.Value {
    if (value != .object) return null;
    const obj = value.object;
    if (obj.get("corpusAsk")) |corpus_value| return corpus_value;
    if (obj.get("corpus_ask")) |corpus_value| return corpus_value;
    if (obj.get("result")) |result| {
        if (result == .object) {
            if (result.object.get("corpusAsk")) |corpus_value| return corpus_value;
            if (result.object.get("corpus_ask")) |corpus_value| return corpus_value;
        }
    }
    return null;
}

fn writeCorpusAskChat(writer: anytype, corpus_value: std.json.Value) !void {
    const obj = if (corpus_value == .object) corpus_value.object else return;
    if (getStringField(obj, "answerDraft") orelse getStringField(obj, "answer_draft")) |answer| {
        try writer.writeAll(answer);
        if (sourceLabelFromCorpusAsk(corpus_value)) |source| {
            try writer.print(" [Source: {s}]", .{source});
        }
        try writer.writeByte('\n');
        return;
    }
    try writer.writeAll("No answer was produced.\n");
}

fn writeGenericJsonChat(allocator: std.mem.Allocator, writer: anytype, value: std.json.Value, s: *state.SessionState) !bool {
    var out = std.ArrayList(u8).init(allocator);
    defer out.deinit();
    try std.json.stringify(value, .{}, out.writer());
    var parsed = json_contracts.parseEngineJson(allocator, out.items) catch return false;
    defer parsed.deinit();
    s.last_counters = json_contracts.renderCounters(parsed.value);
    s.recordResponseState(parsed.value);
    try s.setEngineTrace(traceFromEngineResponse(parsed.value));
    try writeEngineResponseChat(writer, parsed.value);
    return true;
}

fn writeEngineResponseChat(writer: anytype, response: json_contracts.EngineResponse) !void {
    if (response.answer_draft) |answer| {
        try writer.print("{s} [Source: Resident Omni-Codex]\n", .{answer});
        return;
    }
    if (response.getSummary()) |summary| {
        try writer.print("{s}\n", .{summary});
        return;
    }
    if (response.getDetail()) |detail| {
        try writer.print("{s}\n", .{detail});
        return;
    }
    try writer.writeAll("No generated response was present in engine output.\n");
}

fn writeCleanFallbackChat(writer: anytype, stdout: []const u8, offline_path: bool) !void {
    const trimmed = std.mem.trim(u8, stdout, " \r\n\t");
    if (trimmed.len == 0) {
        try writer.writeAll(if (offline_path) process.OFFLINE_ROUTING_ERROR else process.SEMANTIC_VOID_MESSAGE);
        try writer.writeByte('\n');
        return;
    }
    if (std.mem.eql(u8, trimmed, process.OFFLINE_ROUTING_ERROR) or process.looksLikeSystemTelemetry(trimmed)) {
        try writer.writeAll(process.OFFLINE_ROUTING_ERROR);
        try writer.writeByte('\n');
        return;
    }
    if (process.looksLikeRawJson(trimmed)) {
        try writer.writeAll(process.SEMANTIC_VOID_MESSAGE);
        try writer.writeByte('\n');
        return;
    }
    if (offline_path) {
        try writer.writeAll(process.OFFLINE_ROUTING_ERROR);
        try writer.writeByte('\n');
        return;
    }
    try writer.writeAll(trimmed);
    try writer.writeByte('\n');
}

fn traceFromEngineResponse(response: json_contracts.EngineResponse) state.EngineTrace {
    return .{
        .authority = authorityLabel(response),
        .engine_state = response.getStatus() orelse response.getVerificationState(),
        .stop_reason = response.getStopReason() orelse response.getUnresolvedReason(),
        .source = if (response.answer_draft != null) "Resident Omni-Codex" else null,
        .trace_flags = null,
    };
}

test "tui clean fallback never renders raw json or daemon telemetry" {
    var json_buf = std.ArrayList(u8).init(std.testing.allocator);
    defer json_buf.deinit();
    try writeCleanFallbackChat(json_buf.writer(), "{\"formatVersion\":\"telemetry.v1\"}", false);
    try std.testing.expectEqualStrings(process.SEMANTIC_VOID_MESSAGE ++ "\n", json_buf.items);

    var offline_buf = std.ArrayList(u8).init(std.testing.allocator);
    defer offline_buf.deinit();
    try writeCleanFallbackChat(offline_buf.writer(), "ghostd inactive socket=/tmp/ghost.sock", true);
    try std.testing.expectEqualStrings(process.OFFLINE_ROUTING_ERROR ++ "\n", offline_buf.items);

    var vulkan_buf = std.ArrayList(u8).init(std.testing.allocator);
    defer vulkan_buf.deinit();
    try writeCleanFallbackChat(vulkan_buf.writer(), "[VULKAN VALIDATION][INFO] noise", true);
    try std.testing.expectEqualStrings(process.OFFLINE_ROUTING_ERROR ++ "\n", vulkan_buf.items);
}

fn authorityLabel(response: json_contracts.EngineResponse) []const u8 {
    return switch (response.getVisualAuthorityState()) {
        .draft => "draft / unverified",
        .verified => "resolved",
        .unresolved => "unresolved",
        .failed => "failed",
        .other => |label| label,
        .unrecognized => "no verified authority",
    };
}

fn traceFromCorpusAskJson(allocator: std.mem.Allocator, root: std.json.Value, corpus_value: std.json.Value) !state.EngineTrace {
    const corpus_obj = if (corpus_value == .object) corpus_value.object else return .{};
    return .{
        .authority = if (getBoolField(corpus_obj, "nonAuthorizing") orelse getBoolField(corpus_obj, "non_authorizing") orelse false) "non-authorizing" else "unknown",
        .engine_state = getStringField(corpus_obj, "state") orelse getStringField(corpus_obj, "status") orelse resultStateString(root, "state"),
        .stop_reason = resultStateString(root, "stopReason") orelse resultStateString(root, "stop_reason"),
        .source = sourceLabelFromCorpusAsk(corpus_value),
        .trace_flags = try traceFlagsSummary(allocator, if (corpus_obj.get("trace")) |trace| trace else null),
    };
}

fn resultStateString(root: std.json.Value, field: []const u8) ?[]const u8 {
    if (root != .object) return null;
    const obj = root.object;
    const rs = obj.get("resultState") orelse obj.get("result_state") orelse return null;
    if (rs != .object) return null;
    return getStringField(rs.object, field);
}

fn traceFlagsSummary(allocator: std.mem.Allocator, value: ?std.json.Value) !?[]const u8 {
    const trace = value orelse return null;
    if (trace != .object) return null;
    var out = std.ArrayList(u8).init(allocator);
    defer out.deinit();
    const fields = [_][]const u8{
        "corpusMutation",
        "packMutation",
        "negativeKnowledgeMutation",
        "commandsExecuted",
        "verifiersExecuted",
        "residentDaemon",
    };
    for (fields) |field| {
        if (getBoolField(trace.object, field)) |flag| {
            if (out.items.len != 0) try out.appendSlice(" ");
            try out.writer().print("{s}={s}", .{ field, if (flag) "true" else "false" });
        }
    }
    if (out.items.len == 0) return null;
    return try out.toOwnedSlice();
}

fn sourceLabelFromCorpusAsk(corpus_value: std.json.Value) ?[]const u8 {
    if (corpus_value != .object) return null;
    const obj = corpus_value.object;
    if (getStringField(obj, "state")) |state_label| {
        if (std.mem.eql(u8, state_label, "concept void fallback")) return "Concept Void";
    }
    if (getBoolField(obj, "residentDaemon") orelse getBoolFromObjectField(obj, "trace", "residentDaemon") orelse false) return "Resident Omni-Codex";
    if (getBoolField(obj, "voiceSynthesis") orelse getBoolField(obj, "voice_synthesis") orelse false) return "Resident Omni-Codex";
    if (obj.get("answerDraft") != null or obj.get("answer_draft") != null) return "Resident Omni-Codex";
    return null;
}

fn getBoolFromObjectField(obj: std.json.ObjectMap, object_field: []const u8, bool_field: []const u8) ?bool {
    const value = obj.get(object_field) orelse return null;
    if (value != .object) return null;
    return getBoolField(value.object, bool_field);
}

fn getStringField(obj: std.json.ObjectMap, field: []const u8) ?[]const u8 {
    const value = obj.get(field) orelse return null;
    if (value != .string) return null;
    return value.string;
}

fn getBoolField(obj: std.json.ObjectMap, field: []const u8) ?bool {
    const value = obj.get(field) orelse return null;
    if (value != .bool) return null;
    return value.bool;
}

fn writeMountedCorpusAskRequest(writer: anytype, question: []const u8, s: *const state.SessionState) !void {
    try writer.writeAll("{\"gipVersion\":\"gip.v0.1\",\"kind\":\"corpus.ask\",\"question\":");
    try std.json.stringify(question, .{}, writer);
    if (s.project_shard) |project_shard| {
        try writer.writeAll(",\"projectShard\":");
        try std.json.stringify(project_shard, .{}, writer);
    }
    try writer.writeAll(",\"mountedPacks\":[");
    for (s.active_session_mounts.items, 0..) |mount, idx| {
        if (idx != 0) try writer.writeByte(',');
        try writer.writeAll("{\"packId\":");
        try std.json.stringify(mount.pack_id, .{}, writer);
        try writer.writeAll(",\"packVersion\":");
        try std.json.stringify(mount.pack_version, .{}, writer);
        try writer.writeByte('}');
    }
    try writer.writeAll("],\"requireCitations\":true}");
}

fn writeDaemonCorpusAskRequest(writer: anytype, question: []const u8, s: *const state.SessionState) !void {
    try writer.writeAll("{\"gipVersion\":\"gip.v0.1\",\"kind\":\"corpus.ask\",\"question\":");
    try std.json.stringify(question, .{}, writer);
    if (s.project_shard) |project_shard| {
        try writer.writeAll(",\"projectShard\":");
        try std.json.stringify(project_shard, .{}, writer);
    }
    try writer.writeAll(",\"requireCitations\":true}");
}
