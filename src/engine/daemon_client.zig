const std = @import("std");

pub const SOCKET_PATH = "/tmp/ghost.sock";
pub const HEARTBEAT_PATH = "/dev/shm/ghostd.hot";
const MAX_FRAME_BYTES: usize = 10 * 1024 * 1024;

pub fn isActive() bool {
    return readHeartbeatHot() and probeSocket();
}

pub fn request(allocator: std.mem.Allocator, payload: []const u8) ![]u8 {
    if (!isActive()) return error.DaemonInactive;
    var stream = try std.net.connectUnixSocket(socketPath());
    defer stream.close();
    try writeFrame(stream, payload);
    return try readFrame(allocator, stream);
}

pub fn socketPath() []const u8 {
    return std.posix.getenv("GHOSTD_SOCKET_PATH") orelse SOCKET_PATH;
}

pub fn heartbeatPath() []const u8 {
    return std.posix.getenv("GHOSTD_HEARTBEAT_PATH") orelse HEARTBEAT_PATH;
}

fn readHeartbeatHot() bool {
    std.fs.accessAbsolute(socketPath(), .{}) catch return false;
    var file = std.fs.openFileAbsolute(heartbeatPath(), .{}) catch return false;
    defer file.close();
    var byte: [1]u8 = undefined;
    const n = file.read(&byte) catch return false;
    return n == 1 and byte[0] == '1';
}

fn probeSocket() bool {
    var stream = std.net.connectUnixSocket(socketPath()) catch return false;
    stream.close();
    return true;
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
