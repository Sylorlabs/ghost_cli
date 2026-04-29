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
    try writer.print("\x1b[2;{d}r", .{historyBottomRow(size)});
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
    const suggestion_row = size.rows - 3;

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

    try renderSlashSuggestions(writer, s.current_input.items, suggestion_row, style);

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
    const suggestion_row = size.rows - 2;
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
    try renderSlashSuggestions(writer, s.current_input.items, suggestion_row, style);
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

    try writer.print("\x1b[{d};1H", .{historyBottomRow(size)});

    try writer.print("{s}---- TURN {d} | {s} | {d}ms | json={s} ----{s}\n", .{ style.dim(), turn.index, turn.reasoning.toStr(), turn.elapsed_ms, if (turn.json_ok) "ok" else "raw", style.reset() });
    try writer.print("{s}YOU{s}\n{s}\n", .{ style.cyan(), style.reset(), turn.input });
    try writer.print("{s}GHOST{s}\n", .{ style.cyan(), style.reset() });
    try writer.writeAll(turn.rendered_output);
    try writer.writeAll("\n");
}

pub fn renderCommandMessage(writer: anytype, style: Style, comptime fmt: []const u8, args: anytype) !void {
    try writer.print("\n{s}COMMAND{s} ", .{ style.cyan(), style.reset() });
    try writer.print(fmt, args);
    try writer.writeAll("\n");
}

pub fn renderSystemMessage(writer: anytype, style: Style, comptime fmt: []const u8, args: anytype) !void {
    try writer.print("\n{s}SYSTEM{s} ", .{ style.yellow(), style.reset() });
    try writer.print(fmt, args);
    try writer.writeAll("\n");
}

pub fn renderInvalidSlashCommand(writer: anytype, style: Style, command: []const u8) !void {
    try renderSystemMessage(writer, style, "Not a valid command: {s}\nType /help for available commands", .{command});
}

pub fn clearHistoryArea(writer: anytype) !void {
    const size = getTerminalSize();
    // Move to 1,1
    try writer.writeAll("\x1b[1;1H");
    // Clear lines from 1 to height-2
    var i: usize = 1;
    while (i <= historyBottomRow(size)) : (i += 1) {
        try writer.print("\x1b[{d};1H\x1b[K", .{i});
    }
    try writer.writeAll("\x1b[1;1H");
}

pub fn renderSlashSuggestions(writer: anytype, input_text: []const u8, row: u16, style: Style) !void {
    try writer.print("\x1b[{d};1H\x1b[K", .{row});
    if (input_text.len == 0 or input_text[0] != '/') return;

    const token = slash.suggestionToken(input_text);
    const count = slash.matchingCount(token);
    if (count == 0) {
        try writer.print("{s}COMMAND{s} no matching slash commands | Type /help for available commands", .{ style.yellow(), style.reset() });
        return;
    }

    try writer.print("{s}COMMAND{s} ", .{ style.cyan(), style.reset() });
    var emitted: usize = 0;
    for (slash.commands) |command| {
        if (!std.mem.startsWith(u8, command.name, token)) continue;
        if (emitted > 0) try writer.writeAll("  ");
        try writer.print("{s}{s}", .{ command.name, command.args });
        emitted += 1;
    }
}

fn historyBottomRow(size: TerminalSize) u16 {
    return if (size.rows > 5) size.rows - 4 else 1;
}
