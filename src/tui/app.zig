const std = @import("std");
const state = @import("state.zig");
const render = @import("render.zig");
const input = @import("input.zig");
const input_controller = @import("input_controller.zig");
const slash = @import("slash.zig");
const stats = @import("stats.zig");
const terminal = @import("terminal.zig");
const history = @import("history.zig");
const shell = @import("../engine/shell.zig");
const diff_viewer = @import("diff_viewer.zig");
const json_contracts = @import("../engine/json_contracts.zig");
const sovereign_interface = @import("sovereign_interface");

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

    const sovereign_state_path = try resolveSovereignStatePath(allocator, engine_root);
    defer allocator.free(sovereign_state_path);
    var sovereign_core = try sovereign_interface.SovereignCore.init(.{
        .state_path = sovereign_state_path,
        .size_bytes = sovereign_interface.default_manifold_bytes,
    });
    defer sovereign_core.deinit();
    s.sovereign_mirror = sovereign_core.snapshot();
    s.last_command_status = "sovereign ready";

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

    var frame_dirty = true;
    while (true) {
        const now_ms = std.time.milliTimestamp();
        const previous_size = s.terminal_size;
        s.refreshTerminalSize(now_ms, terminal.getSize);
        s.refreshRam(now_ms, stats.getCliRamRss);
        if (previous_size.rows != s.terminal_size.rows or
            previous_size.cols != s.terminal_size.cols)
        {
            frame_dirty = true;
        }
        if (frame_dirty) {
            try render.renderFrameWithSize(writer, &s, style, s.terminal_size);
            frame_dirty = false;
        }

        const key = try input.readKey(stdin.reader());
        if (keyResonanceByte(key)) |byte| {
            s.sovereign_mirror = sovereign_core.ingestByte(byte);
            frame_dirty = true;
        }
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
                    'T' => {
                        try input_controller.activateFileTargetFinder(&s);
                        s.constraint_autocomplete = .{};
                        s.last_command_status = "file target finder";
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
                if (s.file_target_finder.active or s.constraint_autocomplete.active) {
                    input_controller.moveSelection(&s, -1);
                } else {
                    const count = slash.matchingCount(s.current_input.items);
                    if (count > 0) {
                        if (s.suggestion_index == 0) {
                            s.suggestion_index = count - 1;
                        } else {
                            s.suggestion_index -= 1;
                        }
                    }
                }
            },
            .down => {
                if (s.file_target_finder.active or s.constraint_autocomplete.active) {
                    input_controller.moveSelection(&s, 1);
                } else {
                    const count = slash.matchingCount(s.current_input.items);
                    if (count > 0) {
                        s.suggestion_index = (s.suggestion_index + 1) % count;
                    }
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
                if (try input_controller.completeCurrentToken(&s)) {
                    s.suggestion_index = 0;
                } else if (std.mem.indexOfAny(u8, s.current_input.items, " \t") == null) {
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

                try handleSovereignSubmit(allocator, &sovereign_core, &s, cmd_text, writer, style);
            },
            .backspace => {
                if (s.current_input.items.len > 0) {
                    _ = s.current_input.pop();
                    s.suggestion_index = 0;
                    s.file_target_finder.clear();
                    input_controller.refreshConstraintAutocomplete(&s);
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
                s.file_target_finder.clear();
                input_controller.refreshConstraintAutocomplete(&s);
            },
            .unsupported => key_changed = false,
        }
        if (key_changed) frame_dirty = true;
    }

    if (s.history.items.len > 0) {
        history.saveConversation(allocator, "last_session", s.history.items) catch {};
    }
}

fn keyResonanceByte(key: input.Key) ?u8 {
    return switch (key) {
        .char => |c| c,
        .ctrl => |c| c,
        .enter => '\n',
        .backspace => 8,
        .esc => 27,
        .up => 0x11,
        .down => 0x12,
        .left => 0x13,
        .right => 0x14,
        .tab => '\t',
        .shift_tab => 0x0B,
        .unsupported => null,
    };
}

fn resolveSovereignStatePath(allocator: std.mem.Allocator, engine_root: ?[]const u8) ![]u8 {
    if (std.posix.getenv("GHOST_SOVEREIGN_STATE")) |env_path| {
        return try allocator.dupe(u8, env_path);
    }

    if (engine_root) |root| {
        const engine_repo = try normalizeEngineRoot(allocator, root);
        defer allocator.free(engine_repo);
        const sovereign_root = try std.fs.path.join(allocator, &.{ engine_repo, "ghost_sovereign" });
        defer allocator.free(sovereign_root);
        var dir = std.fs.cwd().openDir(sovereign_root, .{}) catch null;
        if (dir) |*d| {
            d.close();
            return try std.fs.path.join(allocator, &.{ sovereign_root, "state", "ghost_absolute.bin" });
        }
    }

    const cwd_abs = std.fs.cwd().realpathAlloc(allocator, ".") catch {
        return try allocator.dupe(u8, "state/ghost_absolute.bin");
    };
    defer allocator.free(cwd_abs);

    if (std.fs.path.dirname(cwd_abs)) |workspace| {
        const candidate = try std.fs.path.join(allocator, &.{ workspace, "ghost_engine", "ghost_sovereign", "state", "ghost_absolute.bin" });
        const candidate_dir = std.fs.path.dirname(candidate) orelse return candidate;
        var dir = std.fs.cwd().openDir(candidate_dir, .{}) catch null;
        if (dir) |*d| {
            d.close();
            return candidate;
        }
        allocator.free(candidate);
    }

    return try allocator.dupe(u8, "state/ghost_absolute.bin");
}

fn normalizeEngineRoot(allocator: std.mem.Allocator, root: []const u8) ![]u8 {
    const trimmed = std.mem.trimRight(u8, root, "/");
    if (std.mem.endsWith(u8, trimmed, "zig-out/bin")) {
        const zig_out = std.fs.path.dirname(trimmed) orelse trimmed;
        const repo = std.fs.path.dirname(zig_out) orelse zig_out;
        return try allocator.dupe(u8, repo);
    }
    return try allocator.dupe(u8, trimmed);
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
        .conversations => {
            s.last_command_status = "list conversations";
            const list = history.listConversations(allocator) catch |err| {
                try render.renderErrorMessage(writer, style, "Failed to list conversations: {}", .{err});
                return false;
            };
            defer {
                for (list) |name| allocator.free(name);
                allocator.free(list);
            }
            if (list.len == 0) {
                try render.renderCommandMessage(writer, style, "No saved conversations found.", .{});
            } else {
                try render.renderCommandMessage(writer, style, "Saved Conversations:", .{});
                for (list) |name| {
                    try writer.print("  {s}\n", .{name});
                }
            }
        },
        .save => {
            const name = command.arg orelse "";
            if (name.len == 0) {
                s.last_command_status = "save name required";
                try render.renderErrorMessage(writer, style, "/save requires a name", .{});
            } else {
                s.last_command_status = "saving...";
                history.saveConversation(allocator, name, s.history.items) catch |err| {
                    try render.renderErrorMessage(writer, style, "Failed to save conversation: {}", .{err});
                    return false;
                };
                s.last_command_status = "saved";
                try render.renderCommandMessage(writer, style, "Conversation saved as: {s}", .{name});
            }
        },
        .resume_session => {
            const name = command.arg orelse "";
            if (name.len == 0) {
                s.last_command_status = "resume name required";
                try render.renderErrorMessage(writer, style, "/resume requires a name", .{});
            } else {
                s.last_command_status = "resuming...";
                const loaded = history.loadConversation(allocator, name) catch |err| {
                    try render.renderErrorMessage(writer, style, "Failed to load conversation: {}", .{err});
                    return false;
                };
                // Note: loaded.turns memory is managed by its own allocator/parsed value
                // In a real app we might want to deep copy or be careful.
                // For now, let's just clear and append.
                s.clearHistory();
                for (loaded.turns) |turn| {
                    // We need to dupe the strings because s.freeTurn will free them.
                    const turn_dupe = state.Turn{
                        .index = turn.index,
                        .input = try allocator.dupe(u8, turn.input),
                        .reasoning = turn.reasoning,
                        .context_artifact = if (turn.context_artifact) |ca| try allocator.dupe(u8, ca) else null,
                        .response = null, // TODO: deep copy response if needed
                        .raw_output = try allocator.dupe(u8, turn.raw_output),
                        .rendered_output = try allocator.dupe(u8, turn.rendered_output),
                        .elapsed_ms = turn.elapsed_ms,
                        .input_runes = turn.input_runes,
                        .output_runes = turn.output_runes,
                        .json_ok = turn.json_ok,
                    };
                    try s.appendTurn(turn_dupe);
                }
                s.last_command_status = "resumed";
                try render.clearHistoryAreaWithSize(writer, s.terminal_size);
                try render.renderCommandMessage(writer, style, "Resumed conversation: {s}", .{name});
            }
        },
        .unknown => {
            s.last_command_status = "unknown slash command";
            try render.renderInvalidSlashCommand(writer, style, command.arg orelse text);
        },
    }
    return false;
}

fn handleSovereignSubmit(
    allocator: std.mem.Allocator,
    core: *sovereign_interface.SovereignCore,
    s: *state.SessionState,
    cmd_text: []const u8,
    writer: anytype,
    style: render.Style,
) !void {
    if (s.read_only) {
        s.last_command_status = "read-only blocked";
        try render.renderErrorMessage(writer, style, "Read-only mode: local sovereign prompt blocked", .{});
        return;
    }

    const start_time = std.time.milliTimestamp();
    s.last_command_status = "resonating";
    s.sovereign_mirror = core.ingestSlice(cmd_text);
    try s.setEngineTrace(.{
        .authority = "non-authorizing",
        .engine_state = "local_absolute_core",
        .stop_reason = "none",
        .source = "ghost_sovereign.absolute_final",
        .trace_flags = "no_llm,no_api,no_daemon",
    });

    const raw_output = blk: {
        var raw = std.ArrayList(u8).init(allocator);
        errdefer raw.deinit();
        try sovereign_interface.emitJson(raw.writer(), s.sovereign_mirror);
        break :blk try raw.toOwnedSlice();
    };
    var turn_owns_output = false;
    errdefer if (!turn_owns_output) allocator.free(raw_output);

    const rendered_output = try core.explain(allocator, cmd_text);
    errdefer if (!turn_owns_output) allocator.free(rendered_output);

    const elapsed = @as(u64, @intCast(std.time.milliTimestamp() - start_time));
    const turn = state.Turn{
        .index = s.nextTurnIndex(),
        .input = try allocator.dupe(u8, cmd_text),
        .reasoning = s.reasoning,
        .context_artifact = if (s.context_artifact) |ca| try allocator.dupe(u8, ca) else null,
        .response = null,
        .raw_output = raw_output,
        .rendered_output = rendered_output,
        .elapsed_ms = elapsed,
        .input_runes = stats.countRunes(cmd_text),
        .output_runes = stats.countRunes(rendered_output),
        .json_ok = true,
    };

    try s.appendTurn(turn);
    turn_owns_output = true;
    s.last_command_status = "sovereign response";
    try renderTypewriterTurn(writer, s, turn.index, rendered_output.len, style);
}

pub fn handleSubmit(allocator: std.mem.Allocator, engine_root: ?[]const u8, s: *state.SessionState, cmd_text: []const u8, writer: anytype, style: render.Style) !void {
    if (s.read_only) {
        s.last_command_status = "read-only blocked";
        try render.renderErrorMessage(writer, style, "Read-only mode: local sovereign prompt blocked", .{});
        return;
    }

    const sovereign_state_path = try resolveSovereignStatePath(allocator, engine_root);
    defer allocator.free(sovereign_state_path);
    var core = try sovereign_interface.SovereignCore.init(.{
        .state_path = sovereign_state_path,
        .size_bytes = sovereign_interface.default_manifold_bytes,
    });
    defer core.deinit();
    s.sovereign_mirror = core.snapshot();
    try handleSovereignSubmit(allocator, &core, s, cmd_text, writer, style);
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
    if (firstUnknownReason(obj)) |reason| {
        try writer.writeAll(reason);
        try writer.writeByte('\n');
        return;
    }
    try writer.writeAll("No answer was produced.\n");
}

fn firstUnknownReason(obj: std.json.ObjectMap) ?[]const u8 {
    const unknowns = obj.get("unknowns") orelse return null;
    if (unknowns != .array or unknowns.array.items.len == 0) return null;
    const first = unknowns.array.items[0];
    if (first != .object) return null;
    return getStringField(first.object, "reason");
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
        try writer.print("{s} [Source: Neuro-Symbolic Engine]\n", .{answer});
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
        .source = if (response.answer_draft != null) "Neuro-Symbolic Engine" else null,
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
    if (getBoolField(obj, "residentDaemon") orelse getBoolFromObjectField(obj, "trace", "residentDaemon") orelse false) return "Neuro-Symbolic Engine";
    if (getBoolField(obj, "voiceSynthesis") orelse getBoolField(obj, "voice_synthesis") orelse false) return "Neuro-Symbolic Engine";
    if (obj.get("answerDraft") != null or obj.get("answer_draft") != null) return "Neuro-Symbolic Engine";
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
