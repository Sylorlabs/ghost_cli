const std = @import("std");
const state = @import("state.zig");
const slash = @import("slash.zig");
const stats = @import("stats.zig");

pub const TerminalSize = struct {
    rows: u16,
    cols: u16,
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

    pub fn cyan(self: Style) []const u8 {
        return self.code("\x1b[36m");
    }

    pub fn yellow(self: Style) []const u8 {
        return self.code("\x1b[33m");
    }

    pub fn red(self: Style) []const u8 {
        return self.code("\x1b[31m");
    }
};

pub fn getTerminalSize() TerminalSize {
    var winsize = std.posix.winsize{
        .row = 0,
        .col = 0,
        .xpixel = 0,
        .ypixel = 0,
    };
    const err = std.os.linux.ioctl(std.posix.STDOUT_FILENO, std.os.linux.T.IOCGWINSZ, @intFromPtr(&winsize));
    if (err == 0) {
        return .{ .rows = winsize.row, .cols = winsize.col };
    }
    return .{ .rows = 24, .cols = 80 };
}

pub fn initTerminal(writer: anytype, style: Style) !void {
    const size = getTerminalSize();
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
    const size = getTerminalSize();
    const input_row = size.rows;
    const footer_row = size.rows - 1;
    const status_row = size.rows - 2;
    const suggestion_panel_bottom = status_row - 1;
    const suggestion_height = suggestionHeight(s.current_input.items, size, false);

    try writer.print("\x1b[2;{d}r", .{historyBottomRow(size, suggestion_height)});

    try writer.print("\x1b[1;1H{s}\x1b[K GHOST {s} | engine={s} | mode=session | reasoning={s} | turns={d} | draft={d} verified={d} unresolved={d}{s}", .{
        style.header(),
        s.version,
        s.engine_root_label orelse "deferred",
        s.reasoning.toStr(),
        s.history.items.len,
        s.draft_count,
        s.verified_count,
        s.unresolved_count,
        style.reset(),
    });

    try writer.print("\x1b[{d};1H{s}\x1b[K status={s} | corr={d} nk={d}/{d} verifier_req={d} suppress={d} route={d} | debug={s} json={s}{s}", .{
        status_row,
        style.status(),
        s.last_command_status,
        s.last_counters.corrections,
        s.last_counters.nk_applied,
        s.last_counters.nk_candidates,
        s.last_counters.verifier_requirements,
        s.last_counters.suppressions,
        s.last_counters.routing_warnings,
        if (s.debug) "on" else "off",
        if (s.json_mode) "on" else "off",
        style.reset(),
    });

    const ram_str = if (s.last_ram_bytes) |b| try stats.formatBytes(s.allocator, b) else try s.allocator.dupe(u8, "n/a");
    defer s.allocator.free(ram_str);
    try writer.print("\x1b[{d};1H{s}\x1b[K context={s} | engine_root={s} | ram={s} | keys=Ctrl+R reasoning Ctrl+D debug Ctrl+L clear Ctrl+C quit | /help{s}", .{
        footer_row,
        style.dim(),
        s.context_artifact orelse "none",
        s.engine_root_label orelse "auto",
        ram_str,
        style.reset(),
    });

    try renderSlashSuggestions(writer, s.current_input.items, suggestion_panel_bottom, style);

    try writer.print("\x1b[{d};1H\x1b[K{s}ghost>{s} {s}", .{
        input_row,
        style.cyan(),
        style.reset(),
        s.current_input.items,
    });
}

pub fn renderCompact(writer: anytype, s: *state.SessionState, style: Style) !void {
    const size = getTerminalSize();
    const status_row = size.rows - 1;
    const suggestion_panel_bottom = status_row - 1;
    const suggestion_height = suggestionHeight(s.current_input.items, size, true);
    try writer.print("\x1b[2;{d}r", .{historyBottomRow(size, suggestion_height)});
    try writer.print("\x1b[{d};1H{s}\x1b[K Ghost {s} | {s} | turns={d} draft={d} verified={d} unresolved={d} | debug={s} | context={s}{s}", .{
        status_row,
        style.status(),
        s.version,
        s.reasoning.toStr(),
        s.history.items.len,
        s.draft_count,
        s.verified_count,
        s.unresolved_count,
        if (s.debug) "on" else "off",
        s.context_artifact orelse "none",
        style.reset(),
    });
    try renderSlashSuggestions(writer, s.current_input.items, suggestion_panel_bottom, style);
    try writer.print("\x1b[{d};1H\x1b[K{s}ghost>{s} {s}", .{
        size.rows,
        style.cyan(),
        style.reset(),
        s.current_input.items,
    });
}

pub fn renderFrame(writer: anytype, s: *state.SessionState, style: Style) !void {
    if (s.compact) {
        try renderCompact(writer, s, style);
    } else {
        try render(writer, s, style);
    }
}

pub fn renderHelp(writer: anytype, style: Style) !void {
    try writer.print(
        \\
        \\{s}Ghost TUI Help{s}
        \\{s}COMMAND{s}
    , .{ style.cyan(), style.reset(), style.cyan(), style.reset() });
    for (slash.commands) |command| {
        try writer.print("  {s}{s:<18} {s}\n", .{ command.name, command.args, command.help });
    }
    try writer.print(
        \\
        \\Keyboard: Ctrl+C quit | Ctrl+L clear | Ctrl+R reasoning | Ctrl+D debug | Esc quit
        \\
    , .{});
}

pub fn renderStatus(writer: anytype, s: *state.SessionState, style: Style) !void {
    try writer.print(
        \\
        \\{s}SYSTEM{s} TUI Session Status
        \\  turns={d}
        \\  reasoning={s}
        \\  debug={s}
        \\  json={s}
        \\  context={s}
        \\  engine_root={s}
        \\  last={s}
        \\
    , .{
        style.cyan(),
        style.reset(),
        s.history.items.len,
        s.reasoning.toStr(),
        if (s.debug) "on" else "off",
        if (s.json_mode) "on" else "off",
        s.context_artifact orelse "none",
        s.engine_root_label orelse "auto",
        s.last_command_status,
    });
}

pub fn renderNonTty(writer: anytype) !void {
    try writer.writeAll(
        \\Ghost TUI requires an interactive TTY.
        \\No engine command was run. No doctor, autopsy, verifier, scan, or pack mutation was triggered.
        \\Use `ghost --help`, `ghost ask ...`, or run `ghost tui` from a terminal.
        \\
    );
}

pub fn renderInputStats(writer: anytype, s: *state.SessionState, style: Style) !void {
    const size = getTerminalSize();
    try writer.print("\x1b[{d};1H{s}\x1b[K input={d} runes | context={s}{s}", .{
        size.rows - 1,
        style.dim(),
        stats.countRunes(s.current_input.items),
        s.context_artifact orelse "none",
        style.reset(),
    });
}

pub fn renderTurn(writer: anytype, turn: state.Turn, style: Style) !void {
    const size = getTerminalSize();

    try writer.print("\x1b[{d};1H", .{historyBottomRow(size, 0)});

    try writer.print("{s}+-- TURN {d} | {s} | {d}ms | json={s} --+{s}\n", .{ style.dim(), turn.index, turn.reasoning.toStr(), turn.elapsed_ms, if (turn.json_ok) "ok" else "raw", style.reset() });
    try writer.print("{s}[YOU]  {s}{s}\n", .{ style.cyan(), style.reset(), turn.input });
    try writer.print("{s}[GHOST]{s}\n", .{ style.cyan(), style.reset() });
    try writer.writeAll(turn.rendered_output);
    try writer.writeAll("\n");
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
    const size = getTerminalSize();
    // Move to 1,1
    try writer.writeAll("\x1b[1;1H");
    // Clear lines from 1 to height-2
    var i: usize = 1;
    while (i <= historyBottomRow(size, 0)) : (i += 1) {
        try writer.print("\x1b[{d};1H\x1b[K", .{i});
    }
    try writer.writeAll("\x1b[1;1H");
}

pub fn renderSlashSuggestions(writer: anytype, input_text: []const u8, panel_bottom: u16, style: Style) !void {
    try clearSuggestionPanel(writer, panel_bottom);

    const height = suggestionHeightForPanel(input_text, panel_bottom);
    if (height == 0) return;

    const top = panel_bottom - height + 1;

    const token = slash.suggestionToken(input_text);
    const count = slash.matchingCount(token);
    const size = getTerminalSize();
    const width = panelWidth(size);
    if (count == 0) {
        try printPanelBorder(writer, top, width, " slash commands ");
        try writer.print("\x1b[{d};1H| {s}[WARN]{s} no matching slash commands | Type /help for available commands", .{ top + 1, style.yellow(), style.reset() });
        try printPanelBorder(writer, top + 2, width, "");
        return;
    }

    try printPanelBorder(writer, top, width, " slash commands ");
    var emitted: usize = 0;
    var row = top + 1;
    const row_limit = panel_bottom - 1;
    for (slash.commands) |command| {
        if (!std.mem.startsWith(u8, command.name, token)) continue;
        if (row > row_limit) break;
        try writer.print("\x1b[{d};1H| {s}{s:<21}{s} {s}", .{ row, style.cyan(), commandDisplay(command), style.reset(), command.help });
        emitted += 1;
        row += 1;
    }
    if (emitted < count and row <= row_limit) {
        try writer.print("\x1b[{d};1H| {s}[WARN]{s} {d} more command(s) hidden by terminal height", .{ row, style.yellow(), style.reset(), count - emitted });
    }
    try printPanelBorder(writer, panel_bottom, width, "");
}

pub fn suggestionHeight(input_text: []const u8, size: TerminalSize, compact: bool) u16 {
    const fixed_rows: u16 = if (compact) 2 else 3;
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

fn clearSuggestionPanel(writer: anytype, panel_bottom: u16) !void {
    const height = maxSuggestionHeight(panel_bottom);
    if (height == 0) return;

    const top = panel_bottom - height + 1;
    var row = top;
    while (row <= panel_bottom) : (row += 1) {
        try writer.print("\x1b[{d};1H\x1b[K", .{row});
    }
}

fn historyBottomRow(size: TerminalSize, suggestion_height: u16) u16 {
    const base_bottom: u16 = if (size.rows > 5) size.rows - 4 else 1;
    if (suggestion_height == 0) return base_bottom;
    if (base_bottom <= suggestion_height) return 1;
    return base_bottom - suggestion_height;
}

fn commandDisplay(command: slash.SlashCommandSpec) []const u8 {
    return switch (command.kind) {
        .reasoning => "/reasoning <level>",
        .debug => "/debug on|off",
        .json => "/json on|off",
        .autopsy => "/autopsy <path>",
        .context => "/context <path>",
        else => command.name,
    };
}

fn panelWidth(size: TerminalSize) u16 {
    if (size.cols < 48) return size.cols;
    return @min(size.cols, 96);
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
