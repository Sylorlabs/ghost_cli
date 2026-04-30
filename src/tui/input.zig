const std = @import("std");

pub fn isTty() bool {
    return std.posix.isatty(std.posix.STDIN_FILENO) and std.posix.isatty(std.posix.STDOUT_FILENO);
}

pub const Key = union(enum) {
    char: u8,
    ctrl: u8,
    enter,
    backspace,
    esc,
    up,
    down,
    left,
    right,
    tab,
    unsupported,
};

pub fn readKey(reader: anytype) !Key {
    var buf: [1]u8 = undefined;
    const n = try reader.read(&buf);
    if (n == 0) return .unsupported;

    const c = buf[0];
    if (c == 13 or c == 10) return .enter;
    if (c == 127 or c == 8) return .backspace;
    if (c == 9) return .tab;
    if (c < 32 and c != 27) return Key{ .ctrl = c + 64 };
    if (c != 27) return Key{ .char = c };

    var seq: [2]u8 = undefined;
    const seq_len = try reader.read(&seq);
    if (seq_len == 0) return .esc;
    if (seq_len >= 2 and seq[0] == '[') {
        return switch (seq[1]) {
            'A' => .up,
            'B' => .down,
            'C' => .right,
            'D' => .left,
            else => .unsupported,
        };
    }

    return .esc;
}

test "readKey consumes pasted text one key at a time" {
    var stream = std.io.fixedBufferStream("/notreal\r");
    const reader = stream.reader();

    try std.testing.expectEqual(Key{ .char = '/' }, try readKey(reader));
    try std.testing.expectEqual(Key{ .char = 'n' }, try readKey(reader));
    try std.testing.expectEqual(Key{ .char = 'o' }, try readKey(reader));
    try std.testing.expectEqual(Key{ .char = 't' }, try readKey(reader));
    try std.testing.expectEqual(Key{ .char = 'r' }, try readKey(reader));
    try std.testing.expectEqual(Key{ .char = 'e' }, try readKey(reader));
    try std.testing.expectEqual(Key{ .char = 'a' }, try readKey(reader));
    try std.testing.expectEqual(Key{ .char = 'l' }, try readKey(reader));
    try std.testing.expectEqual(Key.enter, try readKey(reader));
}

test "readKey keeps arrow escape handling" {
    var stream = std.io.fixedBufferStream("\x1b[A\x1b[B\x1b[C\x1b[D");
    const reader = stream.reader();

    try std.testing.expectEqual(Key.up, try readKey(reader));
    try std.testing.expectEqual(Key.down, try readKey(reader));
    try std.testing.expectEqual(Key.right, try readKey(reader));
    try std.testing.expectEqual(Key.left, try readKey(reader));
}

pub const RawMode = struct {
    original_termios: std.posix.termios,

    pub fn enable() !RawMode {
        const stdin_fd = std.posix.STDIN_FILENO;
        const original = try std.posix.tcgetattr(stdin_fd);
        var raw = original;

        // Raw mode flags
        raw.iflag.BRKINT = false;
        raw.iflag.ICRNL = false;
        raw.iflag.INPCK = false;
        raw.iflag.ISTRIP = false;
        raw.iflag.IXON = false;

        raw.oflag.OPOST = false;

        raw.cflag.CSIZE = .CS8;

        raw.lflag.ECHO = false;
        raw.lflag.ICANON = false;
        raw.lflag.IEXTEN = false;
        raw.lflag.ISIG = false;

        raw.cc[@intFromEnum(std.posix.V.MIN)] = 0;
        raw.cc[@intFromEnum(std.posix.V.TIME)] = 1;

        try std.posix.tcsetattr(stdin_fd, .FLUSH, raw);

        return RawMode{ .original_termios = original };
    }

    pub fn disable(self: RawMode) !void {
        try std.posix.tcsetattr(std.posix.STDIN_FILENO, .FLUSH, self.original_termios);
    }
};

pub const TerminalGuard = struct {
    raw_mode: RawMode,
    terminal_initialized: bool = false,
    restored: bool = false,

    pub fn enable() !TerminalGuard {
        return .{ .raw_mode = try RawMode.enable() };
    }

    pub fn markTerminalInitialized(self: *TerminalGuard) void {
        self.terminal_initialized = true;
    }

    pub fn restore(self: *TerminalGuard, terminal_writer: anytype, warning_writer: anytype) void {
        if (self.restored) return;
        self.restored = true;

        if (self.terminal_initialized) {
            @import("render.zig").deinitTerminal(terminal_writer) catch |err| {
                warnCleanupFailure(warning_writer, "screen", err);
            };
        }

        self.raw_mode.disable() catch |err| {
            warnCleanupFailure(warning_writer, "raw mode", err);
        };
    }
};

pub fn warnCleanupFailure(writer: anytype, label: []const u8, err: anyerror) void {
    writer.print("warning: terminal cleanup failed during {s}: {s}\n", .{ label, @errorName(err) }) catch {};
}

test "cleanup warning path is visible" {
    var out = std.ArrayList(u8).init(std.testing.allocator);
    defer out.deinit();

    warnCleanupFailure(out.writer(), "raw mode", error.AccessDenied);
    try std.testing.expect(std.mem.indexOf(u8, out.items, "warning: terminal cleanup failed during raw mode: AccessDenied") != null);
}
