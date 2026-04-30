const std = @import("std");

pub const TerminalSize = struct {
    rows: u16,
    cols: u16,
};

pub const default_size = TerminalSize{ .rows = 24, .cols = 80 };

pub fn fallbackSize() TerminalSize {
    return default_size;
}

pub fn validOrDefault(rows: u16, cols: u16) TerminalSize {
    if (rows == 0 or cols == 0) return default_size;
    return .{ .rows = rows, .cols = cols };
}

pub fn getSize() TerminalSize {
    return querySize(std.posix.STDOUT_FILENO) orelse default_size;
}

pub fn querySize(fd: std.posix.fd_t) ?TerminalSize {
    if (comptime hasWindowSizeIoctl()) {
        var winsize = std.posix.winsize{
            .row = 0,
            .col = 0,
            .xpixel = 0,
            .ypixel = 0,
        };
        const rc = std.posix.system.ioctl(fd, std.posix.system.T.IOCGWINSZ, @intFromPtr(&winsize));
        if (rc == 0 and winsize.row > 0 and winsize.col > 0) {
            return .{ .rows = winsize.row, .cols = winsize.col };
        }
    }
    return null;
}

fn hasWindowSizeIoctl() bool {
    return comptime @hasDecl(std.posix.system, "ioctl") and
        @hasDecl(std.posix.system, "T") and
        @hasDecl(std.posix.system.T, "IOCGWINSZ");
}

test "terminal size fallback uses safe default" {
    try std.testing.expectEqual(default_size, fallbackSize());
    try std.testing.expectEqual(default_size, validOrDefault(0, 80));
    try std.testing.expectEqual(default_size, validOrDefault(24, 0));
    try std.testing.expectEqual(TerminalSize{ .rows = 10, .cols = 40 }, validOrDefault(10, 40));
}
