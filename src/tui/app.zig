const std = @import("std");
const state = @import("state.zig");
const render = @import("render.zig");
const input = @import("input.zig");
const slash = @import("slash.zig");
const stats = @import("stats.zig");
const terminal = @import("terminal.zig");
const history = @import("history.zig");
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
    _ = command;
    return false;
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

    if (options.context_artifact) |c| s.context_artifact = try allocator.dupe(u8, c);
    if (options.project_shard) |project_shard| s.project_shard = try allocator.dupe(u8, project_shard);
    s.debug = options.debug;
    s.details = options.details or options.debug;
    s.read_only = options.read_only;

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
                    'R' => {},
                    'D' => {
                        s.debug = !s.debug;
                        s.details = s.debug;
                        s.last_command_status = if (s.debug) "debug on" else "debug off";
                    },
                    'L' => {
                        s.clearHistory();
                        try render.clearHistoryAreaWithSize(writer, s.terminal_size);
                    },
                    'Y' => {},
                    'T' => {},
                    else => {},
                }
            },
            .esc => {
                break;
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
            .shift_tab => {},
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
                }
            },
            .char => |c| {
                if (s.current_input.items.len == 0 and c == 'q') break;
                try s.current_input.append(c);
                s.suggestion_index = 0;
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
    _ = engine_root;
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

    const rendered_output = try core.pathfinder(allocator, s.sovereign_mirror.peak_voxel);
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
