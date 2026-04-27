const std = @import("std");
const state = @import("state.zig");
const stats = @import("stats.zig");

pub const TerminalSize = struct {
    rows: u16,
    cols: u16,
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

pub fn initTerminal(writer: anytype) !void {
    const size = getTerminalSize();
    // Clear screen
    try writer.writeAll("\x1b[2J\x1b[H");
    // Set scroll region: 1 to height-2
    try writer.print("\x1b[1;{d}r", .{size.rows - 2});
    // Move cursor to top of scroll region
    try writer.writeAll("\x1b[1;1H");
}

pub fn deinitTerminal(writer: anytype) !void {
    // Reset scroll region
    try writer.writeAll("\x1b[r");
    // Clear screen
    try writer.writeAll("\x1b[2J\x1b[H");
}

pub fn render(writer: anytype, s: *state.SessionState) !void {
    const size = getTerminalSize();

    // 1. Render Status Bar (absolute position)
    try writer.print("\x1b[{d};1H\x1b[44;37m\x1b[K", .{size.rows - 1});
    const ram_str = if (s.last_ram_bytes) |b| try stats.formatBytes(s.allocator, b) else try s.allocator.dupe(u8, "n/a");
    defer s.allocator.free(ram_str);

    try writer.print(" reasoning={s} | in={d} runes | ram={s} | corr={d} nk={d}/{d} verifiers={d} suppress={d} route={d} | debug={s} | context={s}", .{
        s.reasoning.toStr(),
        stats.countRunes(s.current_input.items),
        ram_str,
        s.last_counters.corrections,
        s.last_counters.nk_applied,
        s.last_counters.nk_candidates,
        s.last_counters.verifier_requirements,
        s.last_counters.suppressions,
        s.last_counters.routing_warnings,
        if (s.debug) "on" else "off",
        s.context_artifact orelse "none",
    });
    try writer.writeAll("\x1b[0m");

    // 2. Render Chatbox (absolute position)
    try writer.print("\x1b[{d};1H\x1b[K> {s}", .{ size.rows, s.current_input.items });
}

pub fn renderTurn(writer: anytype, turn: state.Turn) !void {
    const size = getTerminalSize();

    // Move cursor to bottom of scroll region to append new content
    try writer.print("\x1b[{d};1H", .{size.rows - 2});

    try writer.print("\x1b[2m──────────────────── Response {d} · {s} · {d}ms ────────────────────\x1b[0m\n", .{ turn.index, turn.reasoning.toStr(), turn.elapsed_ms });
    try writer.writeAll(turn.rendered_output);
    try writer.writeAll("\n");
}

pub fn clearHistoryArea(writer: anytype) !void {
    const size = getTerminalSize();
    // Move to 1,1
    try writer.writeAll("\x1b[1;1H");
    // Clear lines from 1 to height-2
    var i: usize = 1;
    while (i <= size.rows - 2) : (i += 1) {
        try writer.print("\x1b[{d};1H\x1b[K", .{i});
    }
    try writer.writeAll("\x1b[1;1H");
}
