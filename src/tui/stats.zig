const std = @import("std");

pub fn countRunes(text: []const u8) usize {
    var count: usize = 0;
    var i: usize = 0;
    while (i < text.len) {
        const length = std.unicode.utf8ByteSequenceLength(text[i]) catch 1;
        count += 1;
        i += length;
    }
    return count;
}

pub fn getCliRamRss() ?usize {
    // On Linux, we can read /proc/self/statm
    const file = std.fs.openFileAbsolute("/proc/self/statm", .{}) catch return null;
    defer file.close();

    var buf: [128]u8 = undefined;
    const bytes_read = file.readAll(&buf) catch return null;
    const content = buf[0..bytes_read];

    var it = std.mem.tokenizeScalar(u8, content, ' ');
    _ = it.next() orelse return null; // total size
    const rss_pages_str = it.next() orelse return null;
    const rss_pages = std.fmt.parseInt(usize, rss_pages_str, 10) catch return null;

    // Standard page size is 4KB, but we should ideally check it.
    // For MVP, 4096 is a safe bet on most Linux.
    return rss_pages * 4096;
}

pub fn formatBytes(allocator: std.mem.Allocator, bytes: usize) ![]u8 {
    if (bytes < 1024) return std.fmt.allocPrint(allocator, "{d}B", .{bytes});
    if (bytes < 1024 * 1024) return std.fmt.allocPrint(allocator, "{d}KB", .{bytes / 1024});
    return std.fmt.allocPrint(allocator, "{d}MB", .{bytes / (1024 * 1024)});
}
