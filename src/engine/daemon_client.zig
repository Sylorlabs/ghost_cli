const std = @import("std");

pub const SOCKET_PATH = "/tmp/ghost.sock";
const MAX_FRAME_BYTES: usize = 10 * 1024 * 1024;

pub fn isActive() bool {
    var stream = std.net.connectUnixSocket(SOCKET_PATH) catch return false;
    stream.close();
    return true;
}

pub fn request(allocator: std.mem.Allocator, payload: []const u8) ![]u8 {
    var stream = try std.net.connectUnixSocket(SOCKET_PATH);
    defer stream.close();
    try writeFrame(stream, payload);
    return try readFrame(allocator, stream);
}

fn writeFrame(stream: std.net.Stream, payload: []const u8) !void {
    if (payload.len > MAX_FRAME_BYTES) return error.RequestTooLarge;
    var len_buf: [4]u8 = undefined;
    std.mem.writeInt(u32, &len_buf, @intCast(payload.len), .little);
    try stream.writer().writeAll(&len_buf);
    try stream.writer().writeAll(payload);
}

fn readFrame(allocator: std.mem.Allocator, stream: std.net.Stream) ![]u8 {
    var len_buf: [4]u8 = undefined;
    try stream.reader().readNoEof(&len_buf);
    const len = std.mem.readInt(u32, &len_buf, .little);
    if (len > MAX_FRAME_BYTES) return error.ResponseTooLarge;
    const payload = try allocator.alloc(u8, len);
    errdefer allocator.free(payload);
    try stream.reader().readNoEof(payload);
    return payload;
}
