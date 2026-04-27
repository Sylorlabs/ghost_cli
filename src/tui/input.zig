const std = @import("std");

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
    var buf: [8]u8 = undefined;
    const n = try reader.read(&buf);
    if (n == 0) return .unsupported;

    if (n == 1) {
        const c = buf[0];
        if (c == 13 or c == 10) return .enter;
        if (c == 27) return .esc;
        if (c == 127 or c == 8) return .backspace;
        if (c == 9) return .tab;
        if (c < 32) return Key{ .ctrl = c + 64 };
        return Key{ .char = c };
    }

    if (n >= 3 and buf[0] == 27 and buf[1] == '[') {
        return switch (buf[2]) {
            'A' => .up,
            'B' => .down,
            'C' => .right,
            'D' => .left,
            else => .unsupported,
        };
    }

    return .unsupported;
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

        raw.cc[@intFromEnum(std.posix.V.MIN)] = 1;
        raw.cc[@intFromEnum(std.posix.V.TIME)] = 0;

        try std.posix.tcsetattr(stdin_fd, .FLUSH, raw);

        return RawMode{ .original_termios = original };
    }

    pub fn disable(self: RawMode) void {
        std.posix.tcsetattr(std.posix.STDIN_FILENO, .FLUSH, self.original_termios) catch {};
    }
};
