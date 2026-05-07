const std = @import("std");
const state = @import("state.zig");
const slash = @import("slash.zig");
const stats = @import("stats.zig");
const terminal = @import("terminal.zig");

pub const TerminalSize = terminal.TerminalSize;

pub const Style = struct {
    color: bool,

    fn code(self: Style, value: []const u8) []const u8 {
        return if (self.color) value else "";
    }

    pub fn reset(self: Style) []const u8 {
        return self.code("\x1b[0m");
    }

    pub fn header(self: Style) []const u8 {
        return self.code("\x1b[40;37m");
    }

    pub fn status(self: Style) []const u8 {
        return self.code("\x1b[44;37m");
    }

    pub fn dim(self: Style) []const u8 {
        return self.code("\x1b[2m");
    }

    pub fn cyan(self: Style) []const u8 {
        return self.code("\x1b[36m");
    }

    pub fn white(self: Style) []const u8 {
        return self.code("\x1b[37m");
    }

    pub fn userText(self: Style) []const u8 {
        return self.code("\x1b[38;2;255;255;255m");
    }

    pub fn ghostText(self: Style) []const u8 {
        return self.code("\x1b[38;2;93;169;255m");
    }

    pub fn yellow(self: Style) []const u8 {
        return self.code("\x1b[33m");
    }

    pub fn red(self: Style) []const u8 {
        return self.code("\x1b[31m");
    }
};

pub fn getTerminalSize() TerminalSize {
    return terminal.getSize();
}

pub fn initTerminal(writer: anytype, style: Style) !void {
    try initTerminalWithSize(writer, style, getTerminalSize());
}

pub fn initTerminalWithSize(writer: anytype, style: Style, size: TerminalSize) !void {
    try writer.writeAll("\x1b[2J\x1b[H");
    try writer.print("{s} GHOST OPERATOR CONSOLE {s} native terminal | renderer only | no startup scans{s}\n", .{
        style.header(),
        style.yellow(),
        style.reset(),
    });
    try writer.print("\x1b[2;{d}r", .{historyBottomRow(size, 0)});
    try writer.writeAll("\x1b[2;1H");
}

pub fn deinitTerminal(writer: anytype) !void {
    // Reset scroll region
    try writer.writeAll("\x1b[r");
    // Clear screen
    try writer.writeAll("\x1b[2J\x1b[H");
}

pub fn render(writer: anytype, s: *state.SessionState, style: Style) !void {
    try renderWithSize(writer, s, style, getTerminalSize());
}

pub fn renderWithSize(writer: anytype, s: *state.SessionState, style: Style, size: TerminalSize) !void {
    if (isTiny(size)) {
        try renderTiny(writer, s, style, size);
        return;
    }
    try renderDashboardWithSize(writer, s, style, size, false);
}

pub fn renderCompact(writer: anytype, s: *state.SessionState, style: Style) !void {
    try renderCompactWithSize(writer, s, style, getTerminalSize());
}

pub fn renderCompactWithSize(writer: anytype, s: *state.SessionState, style: Style, size: TerminalSize) !void {
    if (isTiny(size)) {
        try renderTiny(writer, s, style, size);
        return;
    }
    try renderDashboardWithSize(writer, s, style, size, true);
}

fn renderDashboardWithSize(writer: anytype, s: *state.SessionState, style: Style, size: TerminalSize, compact: bool) !void {
    const suggestion_height = suggestionHeight(s.current_input.items, size, compact);
    const input_row = size.rows;
    const content_top: u16 = 2;
    const content_bottom: u16 = if (size.rows > 2 + suggestion_height) size.rows - 1 - suggestion_height else 2;
    const desired_left: u16 = @as(u16, @intCast((@as(usize, size.cols) * 60) / 100));
    const max_left: u16 = if (size.cols > 18) size.cols - 18 else size.cols - 2;
    const left_width: u16 = @min(@max(@as(u16, 24), @min(desired_left, max_left)), if (size.cols > 2) size.cols - 2 else 1);
    const divider_col: u16 = @min(left_width + 1, size.cols);
    const right_col: u16 = @min(divider_col + 1, size.cols);
    const right_width: u16 = if (right_col <= size.cols) size.cols - right_col + 1 else 0;
    const content_height: u16 = if (content_bottom >= content_top) content_bottom - content_top + 1 else 0;
    const right_split: u16 = content_top + @max(@as(u16, 4), content_height / 2);

    try writer.writeAll("\x1b[r");
    try clearRows(writer, size.rows);
    try writeFmtAt(writer, 1, 1, size.cols, "{s} Ghost TUI {s} shard={s} | daemon={s} | {s}{s}", .{
        style.header(),
        style.reset(),
        s.project_shard orelse "all",
        if (s.daemon_active) "hot" else "off",
        systemIndicator(s),
        style.reset(),
    });

    if (content_height != 0) {
        var row = content_top;
        while (row <= content_bottom) : (row += 1) {
            try writeAt(writer, row, divider_col, 1, "|");
        }
        try renderConversationPane(writer, s, style, content_top, content_bottom, 1, if (left_width > 1) left_width - 1 else left_width);
        try renderTelemetryPane(writer, s, style, content_top, @min(content_bottom, right_split - 1), right_col + 1, if (right_width > 2) right_width - 2 else right_width);
        if (right_split <= content_bottom) {
            try renderSessionHotPane(writer, s, style, right_split, content_bottom, right_col + 1, if (right_width > 2) right_width - 2 else right_width);
        }
    }

    try renderSlashSuggestionsWithSize(writer, s, size.rows - 1, style, size);
    try renderInputLine(writer, s, input_row, style);

    s.previous_render_rows = size.rows;
    s.previous_render_cols = size.cols;
}

fn renderConversationPane(writer: anytype, s: *state.SessionState, style: Style, top: u16, bottom: u16, col: u16, width: u16) !void {
    try writeFmtAt(writer, top, col, width, "{s}CHAT{s}", .{ style.cyan(), style.reset() });
    var row = top + 1;
    if (row > bottom) return;
    const rows_available = bottom - row + 1;
    const max_turns: usize = @max(@as(usize, 1), rows_available / 4 + 1);
    const start = if (s.history.items.len > max_turns) s.history.items.len - max_turns else 0;
    for (s.history.items[start..]) |turn| {
        if (row > bottom) break;
        try writeFmtAt(writer, row, col, width, "{s}YOU{s} {s}", .{ style.userText(), style.reset(), turn.input });
        row += 1;
        if (row > bottom) break;
        try writeFmtAt(writer, row, col, width, "{s}GHOST{s}", .{ style.ghostText(), style.reset() });
        row += 1;
        const output = visibleTurnOutput(s, turn);
        var it = std.mem.splitScalar(u8, output, '\n');
        while (it.next()) |line| {
            if (row > bottom) break;
            const trimmed = std.mem.trimRight(u8, line, "\r");
            if (trimmed.len == 0) continue;
            try writeAt(writer, row, col + 2, if (width > 2) width - 2 else width, trimmed);
            row += 1;
        }
        if (row <= bottom) row += 1;
    }
}

fn visibleTurnOutput(s: *const state.SessionState, turn: state.Turn) []const u8 {
    if (s.typing_turn_index) |idx| {
        if (idx == turn.index) return turn.rendered_output[0..@min(s.typing_output_bytes, turn.rendered_output.len)];
    }
    return turn.rendered_output;
}

fn renderTelemetryPane(writer: anytype, s: *state.SessionState, style: Style, top: u16, bottom: u16, col: u16, width: u16) !void {
    if (top > bottom or width == 0) return;
    var row = top;
    try writeFmtAt(writer, row, col, width, "{s}DAEMON TELEMETRY{s}", .{ style.cyan(), style.reset() });
    row += 1;
    if (row <= bottom) {
        try writeFmtAt(writer, row, col, width, "heartbeat: {s}", .{if (s.daemon_active) "hot" else "off"});
        row += 1;
    }
    var vram_buf: [32]u8 = undefined;
    if (row <= bottom) {
        try writeFmtAt(writer, row, col, width, "VRAM resident: {s}", .{formatBytes(&vram_buf, s.daemon_vram_resident_bytes)});
        row += 1;
    }
    var l1_buf: [32]u8 = undefined;
    if (row <= bottom) {
        try writeFmtAt(writer, row, col, width, "L1 index: {s}", .{formatBytes(&l1_buf, s.daemon_l1_concept_index_bytes)});
        row += 1;
    }
    var hot_buf: [32]u8 = undefined;
    if (row <= bottom) {
        try writeFmtAt(writer, row, col, width, "hot-page: {s}", .{formatBytes(&hot_buf, s.daemon_hot_page_bytes)});
        row += 1;
    }
    var raw_buf: [32]u8 = undefined;
    if (row <= bottom) {
        try writeFmtAt(writer, row, col, width, "raw shard VRAM: {s}", .{formatBytes(&raw_buf, s.daemon_raw_shard_vram_bytes)});
        row += 1;
    }
    if (row <= bottom) {
        try writeFmtAt(writer, row, col, width, "vault ingest: {s}", .{if (s.daemon_vault_ingest_active) "active" else if (s.daemon_vault_ingest_recent) "recent" else "idle"});
        row += 1;
    }
    if (row <= bottom) {
        try writeFmtAt(writer, row, col, width, "vault files/errors: {d}/{d}", .{ s.daemon_vault_ingested_files, s.daemon_vault_ingest_errors });
        row += 1;
    }
}

fn renderSessionHotPane(writer: anytype, s: *state.SessionState, style: Style, top: u16, bottom: u16, col: u16, width: u16) !void {
    if (top > bottom or width == 0) return;
    var row = top;
    try writeFmtAt(writer, row, col, width, "{s}SESSION HOT{s}", .{ style.cyan(), style.reset() });
    row += 1;
    if (row <= bottom) {
        try writeFmtAt(writer, row, col, width, "target: {s}", .{s.daemon_context_target orelse "none"});
        row += 1;
    }
    var session_buf: [32]u8 = undefined;
    if (row <= bottom) {
        try writeFmtAt(writer, row, col, width, "working bytes: {s}", .{formatBytes(&session_buf, s.daemon_session_hot_bytes)});
        row += 1;
    }
    if (row <= bottom) {
        try writeFmtAt(writer, row, col, width, "reasoning: {s}", .{s.reasoning.toStr()});
        row += 1;
    }
    if (row <= bottom) {
        try writeFmtAt(writer, row, col, width, "mounts: {d}", .{s.active_session_mounts.items.len});
        row += 1;
    }
    if (row <= bottom) {
        try writeFmtAt(writer, row, col, width, "last: {s}", .{s.last_command_status});
        row += 1;
    }
}

fn clearRows(writer: anytype, rows: u16) !void {
    var row: u16 = 1;
    while (row <= rows) : (row += 1) {
        try writer.print("\x1b[{d};1H\x1b[K", .{row});
    }
}

fn writeFmtAt(writer: anytype, row: u16, col: u16, width: u16, comptime fmt: []const u8, args: anytype) !void {
    var buf: [512]u8 = undefined;
    const text = std.fmt.bufPrint(&buf, fmt, args) catch |err| switch (err) {
        error.NoSpaceLeft => buf[0..],
        else => return err,
    };
    try writeAt(writer, row, col, width, text);
}

fn writeAt(writer: anytype, row: u16, col: u16, width: u16, text: []const u8) !void {
    try writer.print("\x1b[{d};{d}H", .{ row, col });
    try writeTruncated(writer, text, width);
}

fn formatBytes(buf: *[32]u8, bytes: usize) []const u8 {
    if (bytes >= 1024 * 1024) {
        return std.fmt.bufPrint(buf, "{d}.{d} MiB", .{ bytes / (1024 * 1024), (bytes % (1024 * 1024)) / (1024 * 102) }) catch "n/a";
    }
    if (bytes >= 1024) {
        return std.fmt.bufPrint(buf, "{d}.{d} KiB", .{ bytes / 1024, (bytes % 1024) / 102 }) catch "n/a";
    }
    return std.fmt.bufPrint(buf, "{d} B", .{bytes}) catch "n/a";
}

fn renderInputLine(writer: anytype, s: *state.SessionState, row: u16, style: Style) !void {
    try writer.print("\x1b[{d};1H\x1b[K{s}ghost>{s} {s}", .{
        row,
        style.cyan(),
        style.reset(),
        s.current_input.items,
    });

    if (std.mem.indexOfAny(u8, s.current_input.items, " \t") == null) {
        if (slash.findNthMatch(s.current_input.items, s.suggestion_index)) |matched| {
            if (slash.isPrefixMatch(s.current_input.items, matched) and matched.len > s.current_input.items.len) {
                try writer.print("{s}{s}{s}", .{
                    style.dim(),
                    matched[s.current_input.items.len..],
                    style.reset(),
                });
                // Move cursor back to the end of actual input
                try writer.print("\x1b[{d};{d}H", .{ row, @as(u16, @intCast(8 + s.current_input.items.len)) });
            }
        }
    }
}

pub fn renderFrame(writer: anytype, s: *state.SessionState, style: Style) !void {
    try renderFrameWithSize(writer, s, style, getTerminalSize());
}

pub fn renderFrameWithSize(writer: anytype, s: *state.SessionState, style: Style, size: TerminalSize) !void {
    if (s.compact) {
        try renderCompactWithSize(writer, s, style, size);
    } else {
        try renderWithSize(writer, s, style, size);
    }
}

pub fn renderHelp(writer: anytype, style: Style) !void {
    try renderHelpWithSize(writer, style, getTerminalSize());
}

pub fn renderHelpWithSize(writer: anytype, style: Style, size: TerminalSize) !void {
    try writer.print("\x1b[{d};1H", .{historyBottomRow(size, 0)});
    try writer.print("\n{s}[COMMAND]{s} Ghost TUI Help\n", .{ style.cyan(), style.reset() });
    for (slash.commands) |command| {
        try writer.print("  {s:<21} {s}\n", .{ commandDisplay(command), command.help });
    }
    try writer.print(
        \\  keys                 Ctrl+C quit | Ctrl+L clear | Ctrl+R reasoning | Ctrl+D debug | Esc quit
        \\
    , .{});
}

pub fn renderStatus(writer: anytype, s: *state.SessionState, style: Style) !void {
    try writer.print(
        \\
        \\{s}SYSTEM{s} TUI Session Status
        \\  turns={d}
        \\  total_turns={d}
        \\  pruned_turns={d}
        \\  reasoning={s}
        \\  mounted_packs={d}
        \\  debug={s}
        \\  json={s}
        \\  read_only={s}
        \\  context={s}
        \\  engine_root={s}
        \\  last={s}
        \\
    , .{
        style.cyan(),
        style.reset(),
        s.history.items.len,
        s.total_turns,
        s.pruned_turns,
        s.reasoning.toStr(),
        s.last_counters.mounted_packs,
        if (s.debug) "on" else "off",
        if (s.json_mode) "on" else "off",
        if (s.read_only) "on" else "off",
        s.context_artifact orelse "none",
        s.engine_root_label orelse "auto",
        s.last_command_status,
    });
}

pub fn renderNonTty(writer: anytype) !void {
    try writer.writeAll(
        \\Ghost TUI requires an interactive TTY.
        \\No CLI-owned TUI command was run. No doctor check, context/project autopsy scan, correction proposal/review/reviewed inspection, reviewed NK review/list/get, verifier, pack mutation, or negative-knowledge mutation was started from this non-TTY fallback.
        \\Use `ghost --help`, `ghost ask ...`, or run `ghost tui` from a terminal.
        \\
    );
}

pub fn renderInputStats(writer: anytype, s: *state.SessionState, style: Style) !void {
    const size = s.terminal_size;
    try writer.print("\x1b[{d};1H{s}\x1b[K input={d} runes | context={s}{s}", .{
        size.rows - 1,
        style.dim(),
        stats.countRunes(s.current_input.items),
        s.context_artifact orelse "none",
        style.reset(),
    });
}

pub fn renderTurn(writer: anytype, turn: state.Turn, style: Style) !void {
    try renderTurnWithSize(writer, turn, style, getTerminalSize());
}

pub fn renderTurnWithSize(writer: anytype, turn: state.Turn, style: Style, size: TerminalSize) !void {
    try writer.print("\x1b[{d};1H", .{historyBottomRow(size, 0)});
    try writeTurn(writer, turn, style);
}

fn writeTurn(writer: anytype, turn: state.Turn, style: Style) !void {
    try writer.print("{s}YOU{s}\n{s}{s}{s}\n", .{ style.userText(), style.reset(), style.userText(), turn.input, style.reset() });
    try writer.print("\n{s}GHOST\n", .{style.ghostText()});
    try writer.writeAll(turn.rendered_output);
    try writer.print("{s}\n", .{style.reset()});
}

pub fn renderCommandMessage(writer: anytype, style: Style, comptime fmt: []const u8, args: anytype) !void {
    try writer.print("\n{s}[COMMAND]{s} ", .{ style.cyan(), style.reset() });
    try writer.print(fmt, args);
    try writer.writeAll("\n");
}

pub fn renderSystemMessage(writer: anytype, style: Style, comptime fmt: []const u8, args: anytype) !void {
    try writer.print("\n{s}[SYSTEM]{s} ", .{ style.cyan(), style.reset() });
    try writer.print(fmt, args);
    try writer.writeAll("\n");
}

pub fn renderErrorMessage(writer: anytype, style: Style, comptime fmt: []const u8, args: anytype) !void {
    try writer.print("\n{s}[ERROR] {s}", .{ style.red(), style.reset() });
    try writer.print(fmt, args);
    try writer.writeAll("\n");
}

pub fn renderWarningMessage(writer: anytype, style: Style, comptime fmt: []const u8, args: anytype) !void {
    try writer.print("\n{s}[WARN]  {s}", .{ style.yellow(), style.reset() });
    try writer.print(fmt, args);
    try writer.writeAll("\n");
}

pub fn renderInvalidSlashCommand(writer: anytype, style: Style, command: []const u8) !void {
    try renderErrorMessage(writer, style, "Not a valid command: {s}\nType /help for available commands", .{command});
}

pub fn clearHistoryArea(writer: anytype) !void {
    try clearHistoryAreaWithSize(writer, getTerminalSize());
}

pub fn clearHistoryAreaWithSize(writer: anytype, size: TerminalSize) !void {
    // Move to 1,1
    try writer.writeAll("\x1b[1;1H");
    // Clear lines from 1 to height-2
    var i: usize = 1;
    while (i <= historyBottomRow(size, 0)) : (i += 1) {
        try writer.print("\x1b[{d};1H\x1b[K", .{i});
    }
    try writer.writeAll("\x1b[1;1H");
}

pub fn renderSlashSuggestions(writer: anytype, s: *state.SessionState, panel_bottom: u16, style: Style) !void {
    try renderSlashSuggestionsWithSize(writer, s, panel_bottom, style, getTerminalSize());
}

pub fn renderSlashSuggestionsWithSize(writer: anytype, s: *state.SessionState, panel_bottom: u16, style: Style, size: TerminalSize) !void {
    const input_text = s.current_input.items;
    const height = suggestionHeightForPanel(input_text, panel_bottom);
    try clearSuggestionPanel(writer, panel_bottom, @max(height, s.previous_suggestion_height));
    s.previous_suggestion_height = height;
    s.previous_panel_bottom = panel_bottom;

    if (height == 0) return;

    const top = panel_bottom - height + 1;

    const token = slash.suggestionToken(input_text);
    const count = slash.matchingCount(token);
    const width = panelWidth(size);
    if (count == 0) {
        try printPanelBorder(writer, top, width, " slash commands ");
        try writer.print("\x1b[{d};1H| {s}[WARN]{s} ", .{ top + 1, style.yellow(), style.reset() });
        try writeTruncated(writer, "no matching slash commands | Type /help for available commands", panelContentWidth(width, 9));
        try printPanelBorder(writer, top + 2, width, "");
        return;
    }

    // Ensure suggestion_index is within bounds
    if (s.suggestion_index >= count) s.suggestion_index = 0;

    try printPanelBorder(writer, top, width, " slash commands ");
    var row = top + 1;
    const row_limit = panel_bottom - 1;
    var matching_idx: usize = 0;
    while (matching_idx < count) : (matching_idx += 1) {
        const command = slash.findNthMatchingCommand(token, matching_idx) orelse break;
        if (row > row_limit) break;

        const is_selected = (matching_idx == s.suggestion_index);
        const item_style = if (is_selected) style.white() else style.cyan();

        try writer.print("\x1b[{d};1H| {s}", .{ row, item_style });
        try writePadded(writer, commandDisplay(command), @min(@as(usize, 21), panelContentWidth(width, 3)));
        try writer.print("{s} ", .{style.reset()});
        try writeTruncated(writer, command.help, panelHelpWidth(width));

        row += 1;
    }
    if (matching_idx < count and row <= row_limit) {
        try writer.print("\x1b[{d};1H| {s}[WARN]{s} ", .{ row, style.yellow(), style.reset() });
        var hidden_buf: [64]u8 = undefined;
        const hidden = try std.fmt.bufPrint(&hidden_buf, "{d} more command(s) hidden by terminal height", .{count - matching_idx});
        try writeTruncated(writer, hidden, panelContentWidth(width, 9));
    }
    try printPanelBorder(writer, panel_bottom, width, "");
}

pub fn suggestionHeight(input_text: []const u8, size: TerminalSize, compact: bool) u16 {
    _ = compact;
    const fixed_rows: u16 = 2;
    if (size.rows <= fixed_rows + 2) return 0;
    const panel_bottom = size.rows - fixed_rows;
    return suggestionHeightForPanel(input_text, panel_bottom);
}

fn suggestionHeightForPanel(input_text: []const u8, panel_bottom: u16) u16 {
    if (input_text.len == 0 or input_text[0] != '/') return 0;

    const available = maxSuggestionHeight(panel_bottom);
    if (available == 0) return 0;

    const token = slash.suggestionToken(input_text);
    const count = slash.matchingCount(token);
    const wanted: u16 = if (count == 0) 3 else @as(u16, @intCast(count + 2));
    return @min(wanted, available);
}

fn maxSuggestionHeight(panel_bottom: u16) u16 {
    if (panel_bottom <= 2) return 0;
    return @min(@as(u16, slash.commands.len + 2), panel_bottom - 1);
}

pub const Layout = struct {
    tiny: bool,
    input_row: u16,
    status_row: u16,
    footer_row: u16,
    suggestion_panel_bottom: u16,
    suggestion_height: u16,
};

pub fn layoutFor(size: TerminalSize, input_text: []const u8, compact: bool) Layout {
    const tiny = isTiny(size);
    if (tiny) {
        const input_row = @max(size.rows, 1);
        return .{
            .tiny = true,
            .input_row = input_row,
            .status_row = 1,
            .footer_row = if (size.rows >= 2) 2 else 1,
            .suggestion_panel_bottom = 1,
            .suggestion_height = 0,
        };
    }
    const fixed_rows: u16 = 2;
    const input_row = size.rows;
    const footer_row = size.rows - 1;
    const status_row = size.rows - 1;
    const suggestion_panel_bottom = status_row - 1;
    const height = suggestionHeight(input_text, size, compact);
    return .{
        .tiny = false,
        .input_row = input_row,
        .status_row = status_row,
        .footer_row = footer_row,
        .suggestion_panel_bottom = suggestion_panel_bottom,
        .suggestion_height = @min(height, fixed_rows + suggestion_panel_bottom),
    };
}

fn isTiny(size: TerminalSize) bool {
    return size.rows < 6 or size.cols < 20;
}

fn renderTiny(writer: anytype, s: *state.SessionState, style: Style, size: TerminalSize) !void {
    const input_row = @max(size.rows, 1);
    try writer.writeAll("\x1b[r");
    try writer.print("\x1b[1;1H{s}\x1b[K Ghost TUI: terminal too small ({d}x{d}){s}", .{
        style.status(),
        size.cols,
        size.rows,
        style.reset(),
    });
    if (size.rows >= 2) {
        try writer.print("\x1b[2;1H{s}\x1b[K read_only={s} retained={d} total={d} pruned={d}{s}", .{
            style.dim(),
            if (s.read_only) "on" else "off",
            s.history.items.len,
            s.total_turns,
            s.pruned_turns,
            style.reset(),
        });
    }
    s.previous_suggestion_height = 0;
    s.previous_panel_bottom = 1;
    try renderInputLine(writer, s, input_row, style);
}

fn clearSuggestionPanel(writer: anytype, panel_bottom: u16, height: u16) !void {
    if (height == 0) return;

    const top = panel_bottom - height + 1;
    var row = top;
    while (row <= panel_bottom) : (row += 1) {
        try writer.print("\x1b[{d};1H\x1b[K", .{row});
    }
}

fn prepareFrame(writer: anytype, s: *state.SessionState, size: TerminalSize, suggestion_height: u16, panel_bottom: u16, fixed_rows: u16, style: Style) !void {
    if (s.previous_render_rows == 0) {
        s.previous_render_rows = size.rows;
        s.previous_render_cols = size.cols;
        s.previous_fixed_rows = fixed_rows;
        s.previous_panel_bottom = panel_bottom;
        return;
    }

    const resized = s.previous_render_rows != size.rows or s.previous_render_cols != size.cols or s.previous_fixed_rows != fixed_rows;
    if (resized) {
        try repaintFrame(writer, s, size, suggestion_height, fixed_rows, style);
    } else if (s.previous_panel_bottom != panel_bottom) {
        if (s.previous_suggestion_height > 0 and s.previous_panel_bottom > 0) {
            try clearSuggestionPanel(writer, s.previous_panel_bottom, s.previous_suggestion_height);
            s.previous_suggestion_height = 0;
        }
    }

    s.previous_render_rows = size.rows;
    s.previous_render_cols = size.cols;
    s.previous_fixed_rows = fixed_rows;
    s.previous_panel_bottom = panel_bottom;
}

fn repaintFrame(writer: anytype, s: *state.SessionState, size: TerminalSize, suggestion_height: u16, fixed_rows: u16, style: Style) !void {
    try writer.writeAll("\x1b[r\x1b[2J\x1b[H");
    try writer.print("\x1b[2;{d}r", .{historyBottomRow(size, suggestion_height)});
    try writer.writeAll("\x1b[2;1H");
    for (s.history.items) |turn| {
        try writeTurn(writer, turn, style);
    }
    s.previous_suggestion_height = 0;
    s.previous_render_rows = size.rows;
    s.previous_render_cols = size.cols;
    s.previous_fixed_rows = fixed_rows;
}

fn historyBottomRow(size: TerminalSize, suggestion_height: u16) u16 {
    const base_bottom: u16 = if (size.rows > 4) size.rows - 3 else 1;
    if (suggestion_height == 0) return base_bottom;
    if (base_bottom <= suggestion_height) return 1;
    return base_bottom - suggestion_height;
}

fn commandDisplay(command: slash.SlashCommandSpec) []const u8 {
    return switch (command.kind) {
        .reasoning => "/reasoning <level>",
        .debug => "/debug on|off",
        .details => "/details on|off",
        .json => "/json on|off",
        .autopsy => "/autopsy <path>",
        .context => "/context <path>",
        else => command.name,
    };
}

fn systemIndicator(s: *const state.SessionState) []const u8 {
    if (std.mem.eql(u8, s.last_command_status, "thinking")) return "Thinking...";
    return "System Ready";
}

fn panelWidth(size: TerminalSize) u16 {
    return size.cols;
}

fn printPanelBorder(writer: anytype, row: u16, width: u16, title: []const u8) !void {
    try writer.print("\x1b[{d};1H+", .{row});
    const usable = if (width > 2) width - 2 else 0;
    var written: u16 = 0;
    if (title.len > 0 and usable > 4) {
        try writer.writeAll("--");
        written += 2;
        const title_len: u16 = @min(@as(u16, @intCast(title.len)), usable - written);
        try writer.writeAll(title[0..title_len]);
        written += title_len;
    }
    while (written < usable) : (written += 1) {
        try writer.writeAll("-");
    }
    try writer.writeAll("+");
}

fn panelContentWidth(width: u16, used: usize) usize {
    const w: usize = width;
    if (w <= used + 1) return 0;
    return w - used - 1;
}

fn panelHelpWidth(width: u16) usize {
    return panelContentWidth(width, 25);
}

fn writePadded(writer: anytype, text: []const u8, width: usize) !void {
    const written = @min(text.len, width);
    try writer.writeAll(text[0..written]);
    var i = written;
    while (i < width) : (i += 1) {
        try writer.writeAll(" ");
    }
}

fn writeTruncated(writer: anytype, text: []const u8, width: usize) !void {
    if (width == 0) return;
    const written = @min(text.len, width);
    try writer.writeAll(text[0..written]);
}

test "resize repaint clears screen and replays stored turns" {
    const testing = std.testing;
    var session = state.SessionState.init(testing.allocator, "test", null, false);
    defer session.deinit();
    session.previous_render_rows = 24;
    session.previous_render_cols = 80;
    session.previous_fixed_rows = 3;
    session.previous_panel_bottom = 21;
    session.previous_suggestion_height = 4;
    try session.history.append(.{
        .index = 1,
        .input = try testing.allocator.dupe(u8, "hello"),
        .reasoning = .balanced,
        .context_artifact = null,
        .response = null,
        .raw_output = try testing.allocator.dupe(u8, "{}"),
        .rendered_output = try testing.allocator.dupe(u8, "world\n"),
        .elapsed_ms = 7,
        .input_runes = 5,
        .output_runes = 5,
        .json_ok = true,
    });

    var out = std.ArrayList(u8).init(testing.allocator);
    defer out.deinit();

    try prepareFrame(out.writer(), &session, .{ .rows = 36, .cols = 100 }, 0, 33, 3, .{ .color = false });

    try testing.expect(std.mem.indexOf(u8, out.items, "\x1b[r\x1b[2J\x1b[H") != null);
    try testing.expect(std.mem.indexOf(u8, out.items, "+-- TURN 1") == null);
    try testing.expect(std.mem.indexOf(u8, out.items, "YOU") != null);
    try testing.expect(std.mem.indexOf(u8, out.items, "hello") != null);
    try testing.expect(std.mem.indexOf(u8, out.items, "GHOST") != null);
    try testing.expect(std.mem.indexOf(u8, out.items, "world") != null);
    try testing.expectEqual(@as(u16, 36), session.previous_render_rows);
    try testing.expectEqual(@as(u16, 100), session.previous_render_cols);
    try testing.expectEqual(@as(u16, 33), session.previous_panel_bottom);
    try testing.expectEqual(@as(u16, 0), session.previous_suggestion_height);
}
