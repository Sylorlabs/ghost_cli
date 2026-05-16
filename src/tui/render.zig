const std = @import("std");
const state = @import("state.zig");
const input_controller = @import("input_controller.zig");
const slash = @import("slash.zig");
const stats = @import("stats.zig");
const terminal = @import("terminal.zig");

pub const TerminalSize = terminal.TerminalSize;

pub const BoundingBox = struct {
    x: u16,
    y: u16,
    width: u16,
    height: u16,
};

pub const TelemetryPane = struct {
    bounds: BoundingBox,
};

const DashboardLayout = struct {
    chat: BoundingBox,
    telemetry: TelemetryPane,
    session_hot: BoundingBox,
    divider_col: u16,
    input_row: u16,
    suggestion_row: u16,
};

const PaneBuffer = struct {
    allocator: std.mem.Allocator,
    lines: std.ArrayList([]u8),

    fn init(allocator: std.mem.Allocator) PaneBuffer {
        return .{
            .allocator = allocator,
            .lines = std.ArrayList([]u8).init(allocator),
        };
    }

    fn deinit(self: *PaneBuffer) void {
        for (self.lines.items) |line| self.allocator.free(line);
        self.lines.deinit();
    }

    fn appendLine(self: *PaneBuffer, text: []const u8) !void {
        try self.lines.append(try self.allocator.dupe(u8, text));
    }

    fn appendFmt(self: *PaneBuffer, comptime fmt: []const u8, args: anytype) !void {
        const text = try std.fmt.allocPrint(self.allocator, fmt, args);
        defer self.allocator.free(text);
        try self.appendLine(text);
    }

    fn appendWrapped(self: *PaneBuffer, text: []const u8, width: u16) !void {
        if (width == 0) return;
        if (text.len == 0) {
            try self.appendLine("");
            return;
        }
        const wrap_width: usize = width;
        var start: usize = 0;
        while (start < text.len) {
            const remaining = text[start..];
            const take = @min(remaining.len, wrap_width);
            try self.appendLine(remaining[0..take]);
            start += take;
        }
    }

    fn flushScrolled(self: *const PaneBuffer, writer: anytype, bounds: BoundingBox) !void {
        if (bounds.width == 0 or bounds.height == 0) return;
        const visible: usize = bounds.height;
        const start: usize = if (self.lines.items.len > visible) self.lines.items.len - visible else 0;
        var row: u16 = 0;
        while (row < bounds.height) : (row += 1) {
            const idx = start + row;
            if (idx >= self.lines.items.len) break;
            try writeAtBox(writer, bounds, row, self.lines.items[idx]);
        }
    }
};

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

    pub fn pulse(self: Style) []const u8 {
        return self.code("\x1b[5m");
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

    pub fn green(self: Style) []const u8 {
        return self.code("\x1b[32m");
    }

    pub fn brightGreen(self: Style) []const u8 {
        return self.code("\x1b[92m");
    }

    pub fn blue(self: Style) []const u8 {
        return self.code("\x1b[34m");
    }

    pub fn brightRed(self: Style) []const u8 {
        return self.code("\x1b[91m");
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
    const layout = dashboardLayoutFor(size, s.current_input.items, compact);

    try writer.writeAll("\x1b[r");
    try clearRows(writer, size.rows);
    try writeFmtAt(writer, 1, 1, size.cols, "{s} Ghost TUI {s} shard={s} | daemon={s} | neural={s} | {s}{s}", .{
        if (s.yolo_mode) style.red() else style.header(),
        style.reset(),
        s.project_shard orelse "all",
        if (s.daemon_active) "hot" else "off",
        if (s.neural_layer_active) "active" else "off",
        systemIndicator(s),
        style.reset(),
    });

    if (layout.chat.height != 0) {
        var row: u16 = 0;
        while (row < layout.chat.height) : (row += 1) {
            try writeAt(writer, contentOriginRow() + row, layout.divider_col, 1, "|");
        }
        if (s.pending_patch != null) {
            try renderDiffPane(writer, s, style, contentOriginRow() + layout.chat.y, contentOriginRow() + layout.chat.y + layout.chat.height - 1, layout.chat.x + 1, layout.chat.width);
        } else {
            try renderConversationPane(writer, s, style, layout.chat);
        }
        try renderTelemetryPane(writer, s, style, layout.telemetry);
        try renderSessionHotPane(writer, s, style, layout.session_hot);
    }

    try renderSlashSuggestionsWithSize(writer, s, layout.suggestion_row, style, size);
    try renderInputLine(writer, s, layout.input_row, style);
    try renderCommandCenterOverlay(writer, s, style, size, layout.input_row);

    s.previous_render_rows = size.rows;
    s.previous_render_cols = size.cols;
}

pub fn dashboardLayoutFor(size: TerminalSize, input_text: []const u8, compact: bool) DashboardLayout {
    const suggestion_height = suggestionHeight(input_text, size, compact);
    const input_row = size.rows;
    const content_height: u16 = if (size.rows > 2 + suggestion_height) size.rows - 2 - suggestion_height else 1;
    const desired_left: u16 = @as(u16, @intCast((@as(usize, size.cols) * 60) / 100));
    const max_left: u16 = if (size.cols > 18) size.cols - 18 else size.cols - 2;
    const left_width: u16 = @min(@max(@as(u16, 24), @min(desired_left, max_left)), if (size.cols > 2) size.cols - 2 else 1);
    const divider_col: u16 = @min(left_width + 1, size.cols);
    const right_col: u16 = @min(divider_col + 1, size.cols);
    const right_content_col: u16 = @min(right_col + 1, size.cols);
    const right_content_width: u16 = if (right_content_col <= size.cols) size.cols - right_content_col + 1 else 0;
    const telemetry_height: u16 = @min(content_height, @max(@as(u16, 4), content_height / 2));
    const session_y: u16 = telemetry_height;

    return .{
        .chat = .{
            .x = 0,
            .y = 0,
            .width = if (left_width > 1) left_width - 1 else left_width,
            .height = content_height,
        },
        .telemetry = .{
            .bounds = .{
                .x = if (right_content_col > 0) right_content_col - 1 else 0,
                .y = 0,
                .width = right_content_width,
                .height = telemetry_height,
            },
        },
        .session_hot = .{
            .x = if (right_content_col > 0) right_content_col - 1 else 0,
            .y = session_y,
            .width = right_content_width,
            .height = content_height - telemetry_height,
        },
        .divider_col = divider_col,
        .input_row = input_row,
        .suggestion_row = size.rows - 1,
    };
}

fn contentOriginRow() u16 {
    return 2;
}

fn renderConversationPane(writer: anytype, s: *state.SessionState, style: Style, bounds: BoundingBox) !void {
    var pane = PaneBuffer.init(s.allocator);
    defer pane.deinit();

    try pane.appendFmt("{s}CONSOLE{s}", .{ style.cyan(), style.reset() });
    if (bounds.height <= 1) {
        try pane.flushScrolled(writer, bounds);
        return;
    }
    const rows_available = bounds.height - 1;
    const max_turns: usize = @max(@as(usize, 1), rows_available / 5 + 1);
    const start = if (s.history.items.len > max_turns) s.history.items.len - max_turns else 0;
    for (s.history.items[start..]) |turn| {
        try pane.appendFmt("{s}YOU{s}", .{ style.userText(), style.reset() });
        try pane.appendWrapped(turn.input, bounds.width);
        try pane.appendFmt("{s}GHOST{s}", .{ style.ghostText(), style.reset() });
        const output = visibleTurnOutput(s, turn);
        var it = std.mem.splitScalar(u8, output, '\n');
        while (it.next()) |line| {
            const trimmed = std.mem.trimRight(u8, line, "\r");
            if (trimmed.len == 0) continue;
            try pane.appendWrapped(trimmed, bounds.width);
        }
        try pane.appendLine("");
    }
    try pane.flushScrolled(writer, bounds);
}

fn renderDiffPane(writer: anytype, s: *state.SessionState, style: Style, top: u16, bottom: u16, col: u16, width: u16) !void {
    if (top > bottom or width == 0) return;
    try writeFmtAt(writer, top, col, width, "{s}+-- ACCEPT EDITS / DIFF REVIEW --+{s}", .{ style.blue(), style.reset() });
    if (top + 1 <= bottom) {
        try writeFmtAt(writer, top + 1, col, width, "{s}[Press Shift+Tab to Accept Edits, or ESC to Reject]{s}", .{ style.blue(), style.reset() });
    }
    var row = top + 2;
    const proposal = s.pending_patch orelse return;
    var it = std.mem.splitScalar(u8, proposal.diff, '\n');
    while (it.next()) |line| {
        if (row > bottom) break;
        const trimmed = std.mem.trimRight(u8, line, "\r");
        const color = if (std.mem.startsWith(u8, trimmed, "+") and !std.mem.startsWith(u8, trimmed, "+++"))
            style.green()
        else if (std.mem.startsWith(u8, trimmed, "-") and !std.mem.startsWith(u8, trimmed, "---"))
            style.red()
        else if (std.mem.startsWith(u8, trimmed, "@@"))
            style.cyan()
        else
            "";
        try writeFmtAt(writer, row, col, width, "{s}{s}{s}", .{ color, trimmed, style.reset() });
        row += 1;
    }
    if (row <= bottom) {
        try writeFmtAt(writer, row, col, width, "{s}+{s}", .{ style.blue(), style.reset() });
    }
}

fn visibleTurnOutput(s: *const state.SessionState, turn: state.Turn) []const u8 {
    if (s.typing_turn_index) |idx| {
        if (idx == turn.index) return turn.rendered_output[0..@min(s.typing_output_bytes, turn.rendered_output.len)];
    }
    return turn.rendered_output;
}

fn renderTelemetryPane(writer: anytype, s: *state.SessionState, style: Style, pane: TelemetryPane) !void {
    const bounds = pane.bounds;
    if (bounds.width == 0 or bounds.height == 0) return;
    var buf = PaneBuffer.init(s.allocator);
    defer buf.deinit();

    try buf.appendFmt("{s}DAEMON TELEMETRY{s}", .{ style.cyan(), style.reset() });
    try appendProofMatrix(&buf, s, style);
    try buf.appendFmt("heartbeat: {s}", .{if (s.daemon_active) "hot" else "off"});
    try buf.appendFmt("domain: {s}", .{s.daemon_pipeline_domain orelse "none"});
    try buf.appendFmt("z3: {s}", .{s.daemon_pipeline_z3_status orelse "idle"});
    try buf.appendFmt("confidence: {s}", .{s.daemon_pipeline_confidence_band orelse "yellow_heuristic"});
    var vram_buf: [32]u8 = undefined;
    try buf.appendFmt("VRAM resident: {s}", .{formatBytes(&vram_buf, s.daemon_vram_resident_bytes)});
    var l1_buf: [32]u8 = undefined;
    try buf.appendFmt("L1 index: {s}", .{formatBytes(&l1_buf, s.daemon_l1_concept_index_bytes)});
    var hot_buf: [32]u8 = undefined;
    try buf.appendFmt("hot-page: {s}", .{formatBytes(&hot_buf, s.daemon_hot_page_bytes)});
    var raw_buf: [32]u8 = undefined;
    try buf.appendFmt("raw shard VRAM: {s}", .{formatBytes(&raw_buf, s.daemon_raw_shard_vram_bytes)});
    try buf.appendFmt("vault ingest: {s}", .{if (s.daemon_vault_ingest_active) "active" else if (s.daemon_vault_ingest_recent) "recent" else "idle"});
    try buf.appendFmt("vault files/errors: {d}/{d}", .{ s.daemon_vault_ingested_files, s.daemon_vault_ingest_errors });
    try buf.flushScrolled(writer, bounds);
}

fn appendProofMatrix(buf: *PaneBuffer, s: *state.SessionState, style: Style) !void {
    try buf.appendFmt("{s}PROOF MATRIX{s}", .{ style.cyan(), style.reset() });
    var line = std.ArrayList(u8).init(s.allocator);
    defer line.deinit();
    for (s.proof_slots, 0..) |slot, idx| {
        const slot_style = switch (slot) {
            .empty => style.dim(),
            .pending => try std.fmt.allocPrint(s.allocator, "{s}{s}", .{ style.pulse(), style.yellow() }),
            .verified => style.brightGreen(),
            .failed => style.brightRed(),
        };
        defer if (slot == .pending) s.allocator.free(slot_style);

        try line.writer().print("{s}█{s}", .{ slot_style, style.reset() });
        if (idx == 7) try line.append(' ');
    }
    try buf.appendLine(line.items);
}

fn renderSessionHotPane(writer: anytype, s: *state.SessionState, style: Style, bounds: BoundingBox) !void {
    if (bounds.width == 0 or bounds.height == 0) return;
    var buf = PaneBuffer.init(s.allocator);
    defer buf.deinit();

    try buf.appendFmt("{s}SESSION HOT{s}", .{ style.cyan(), style.reset() });
    try buf.appendFmt("target: {s}", .{s.daemon_context_target orelse "none"});
    var session_buf: [32]u8 = undefined;
    try buf.appendFmt("working bytes: {s}", .{formatBytes(&session_buf, s.daemon_session_hot_bytes)});
    try buf.appendFmt("reasoning: {s}", .{s.reasoning.toStr()});
    try buf.appendFmt("mounts: {d}", .{s.active_session_mounts.items.len});
    try buf.appendFmt("last: {s}", .{s.last_command_status});
    try buf.appendFmt("{s}ENGINE TRACE{s}", .{ style.cyan(), style.reset() });
    try buf.appendFmt("authority: {s}", .{s.engine_trace.authority orelse "unknown"});
    try buf.appendFmt("state: {s}", .{s.engine_trace.engine_state orelse s.last_command_status});
    try buf.appendFmt("source: {s}", .{s.engine_trace.source orelse "none"});
    try buf.appendFmt("stop: {s}", .{s.engine_trace.stop_reason orelse "none"});
    try buf.appendFmt("trace: {s}", .{s.engine_trace.trace_flags orelse "none"});
    try buf.flushScrolled(writer, bounds);
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

fn writeAtBox(writer: anytype, bounds: BoundingBox, row_offset: u16, text: []const u8) !void {
    try writeAt(writer, contentOriginRow() + bounds.y + row_offset, bounds.x + 1, bounds.width, text);
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
    if (s.pending_command) |proposal| {
        try writer.print("\x1b[{d};1H\x1b[K{s}[Ghost requests to run: `{s}`] - (y/N){s}", .{
            row,
            style.yellow(),
            proposal.command_display,
            style.reset(),
        });
        return;
    }
    if (s.pending_patch != null) {
        try writer.print("\x1b[{d};1H\x1b[K{s}[Press Shift+Tab to Accept Edits, or ESC to Reject]{s}", .{
            row,
            style.blue(),
            style.reset(),
        });
        return;
    }
    const prompt_cols: usize = if (s.yolo_mode) 16 else 8;
    if (s.yolo_mode) {
        try writer.print("\x1b[{d};1H\x1b[K{s}[! YOLO] ghost>{s} {s}", .{
            row,
            style.red(),
            style.reset(),
            s.current_input.items,
        });
    } else {
        try writer.print("\x1b[{d};1H\x1b[K{s}ghost>{s} {s}", .{
            row,
            style.cyan(),
            style.reset(),
            s.current_input.items,
        });
    }

    if (!s.yolo_mode and std.mem.indexOfAny(u8, s.current_input.items, " \t") == null) {
        if (slash.findNthMatch(s.current_input.items, s.suggestion_index)) |matched| {
            if (slash.isPrefixMatch(s.current_input.items, matched) and matched.len > s.current_input.items.len) {
                try writer.print("{s}{s}{s}", .{
                    style.dim(),
                    matched[s.current_input.items.len..],
                    style.reset(),
                });
                // Move cursor back to the end of actual input
                try writer.print("\x1b[{d};{d}H", .{ row, @as(u16, @intCast(prompt_cols + s.current_input.items.len)) });
            }
        }
    }
}

fn renderCommandCenterOverlay(writer: anytype, s: *state.SessionState, style: Style, size: TerminalSize, input_row: u16) !void {
    if (s.file_target_finder.active and s.file_target_finder.count > 0) {
        try renderFileTargetMenu(writer, s, style, size, input_row);
        return;
    }
    if (input_controller.constraintCandidateCount(s) > 0) {
        try renderConstraintMenu(writer, s, style, size, input_row);
    }
}

fn renderConstraintMenu(writer: anytype, s: *state.SessionState, style: Style, size: TerminalSize, input_row: u16) !void {
    const count = @min(input_controller.constraintCandidateCount(s), @as(usize, 3));
    if (count == 0 or input_row <= count + 1) return;
    const top: u16 = @intCast(input_row - count - 1);
    const width: u16 = @min(size.cols, 42);
    try writeFmtAt(writer, top, 1, width, "{s}GIP CONSTRAINTS{s}", .{ style.cyan(), style.reset() });
    var i: usize = 0;
    while (i < count) : (i += 1) {
        const candidate = input_controller.constraintCandidateAt(s, i) orelse continue;
        const marker = if (i == s.constraint_autocomplete.selected_index) ">" else " ";
        try writeFmtAt(writer, top + 1 + @as(u16, @intCast(i)), 1, width, "{s} {s}", .{ marker, candidate });
    }
}

fn renderFileTargetMenu(writer: anytype, s: *state.SessionState, style: Style, size: TerminalSize, input_row: u16) !void {
    const count = @min(s.file_target_finder.count, @as(usize, 5));
    if (count == 0 or input_row <= count + 1) return;
    const top: u16 = @intCast(input_row - count - 1);
    const width: u16 = @min(size.cols, 70);
    try writeFmtAt(writer, top, 1, width, "{s}FILE TARGETS{s}", .{ style.cyan(), style.reset() });
    var i: usize = 0;
    while (i < count) : (i += 1) {
        const marker = if (i == s.file_target_finder.selected_index) ">" else " ";
        try writeFmtAt(writer, top + 1 + @as(u16, @intCast(i)), 1, width, "{s} {s}", .{ marker, s.file_target_finder.targets[i].text() });
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
        \\                       Ctrl+T file targets | Tab complete GIP/file target | Ctrl+Y toggle YOLO
        \\                       Shift+Tab accept pending diff | y/N approve command
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
            if (s.yolo_mode) style.red() else style.dim(),
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
    if (s.yolo_mode) return "YOLO MODE";
    if (s.pending_command != null) return "Command approval pending";
    if (s.pending_patch != null) return "Patch approval pending";
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

test "right telemetry pane remains anchored after long chat render" {
    const testing = std.testing;
    var session = state.SessionState.init(testing.allocator, "test", null, false);
    defer session.deinit();
    session.daemon_active = true;
    session.daemon_l1_concept_index_bytes = 4096;
    session.daemon_hot_page_bytes = 8192;
    try session.setEngineTrace(.{
        .authority = "NON-AUTHORIZING",
        .engine_state = "concept_void",
        .source = "Neuro-Symbolic Engine",
        .trace_flags = "l1Hit=storage",
    });
    var long_output = std.ArrayList(u8).init(testing.allocator);
    defer long_output.deinit();
    var line: usize = 0;
    while (line < 100) : (line += 1) {
        try long_output.writer().print("proof line {d}: A gigabyte is a unit of digital storage equal to about one billion bytes and this proof output must stay in the left viewport only.\n", .{line});
    }
    try session.history.append(.{
        .index = 1,
        .input = try testing.allocator.dupe(u8, "what is a gigabyte"),
        .reasoning = .balanced,
        .context_artifact = null,
        .response = null,
        .raw_output = try testing.allocator.dupe(u8, "{}"),
        .rendered_output = try testing.allocator.dupe(u8, long_output.items),
        .elapsed_ms = 7,
        .input_runes = 18,
        .output_runes = 32,
        .json_ok = true,
    });

    var out = std.ArrayList(u8).init(testing.allocator);
    defer out.deinit();

    try renderWithSize(out.writer(), &session, .{ .color = false }, .{ .rows = 30, .cols = 100 });

    const layout = dashboardLayoutFor(.{ .rows = 30, .cols = 100 }, session.current_input.items, false);
    try testing.expectEqual(@as(u16, 0), layout.telemetry.bounds.y);
    try testing.expectEqual(@as(u16, 62), layout.telemetry.bounds.x);
    try testing.expectEqual(@as(u16, 38), layout.telemetry.bounds.width);
    try testing.expect(std.mem.indexOf(u8, out.items, "\x1b[2;63HDAEMON TELEMETRY") != null);
    try testing.expect(std.mem.indexOf(u8, out.items, "\x1b[11;63Hhot-page: 8.0 KiB") != null);
    try testing.expect(std.mem.indexOf(u8, out.items, "\x1b[23;63Hauthority: NON-AUTHORIZING") != null);
    try testing.expect(std.mem.indexOf(u8, out.items, "proof line 99: A gigabyte is a unit") != null);
    try testing.expect(std.mem.indexOf(u8, out.items, "\x1b[2;63Hproof line") == null);
}
