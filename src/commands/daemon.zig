const std = @import("std");
const daemon_client = @import("../engine/daemon_client.zig");
const locator = @import("../engine/locator.zig");

const usage =
    \\Usage: ghost daemon <start|status|stop>
    \\
;

const START_TIMEOUT_NS: u64 = 30 * std.time.ns_per_s;

pub fn printHelp(writer: anytype) !void {
    try writer.writeAll(
        \\daemon
        \\
        \\Usage: ghost daemon <start|status|stop> [--engine-root=<path>]
        \\
        \\Controls the local ghostd resident engine process.
        \\
        \\Subcommands:
        \\  start   Spawn ghostd in the background and wait for the hot heartbeat flag
        \\  status  Report daemon status after checking the hot heartbeat flag
        \\  stop    Ask the active daemon to shut down
        \\
    );
}

pub fn executeFromArgs(allocator: std.mem.Allocator, engine_root: ?[]const u8, args: []const []const u8, debug: bool) !void {
    const sub = if (args.len > 0) args[0] else {
        try std.io.getStdErr().writer().writeAll(usage);
        std.process.exit(1);
    };
    if (std.mem.eql(u8, sub, "start")) return start(allocator, engine_root, debug);
    if (std.mem.eql(u8, sub, "status")) return status(allocator);
    if (std.mem.eql(u8, sub, "stop")) return stop(allocator);
    try std.io.getStdErr().writer().print("Unknown daemon command: {s}\n{s}", .{ sub, usage });
    std.process.exit(1);
}

fn start(allocator: std.mem.Allocator, engine_root: ?[]const u8, debug: bool) !void {
    if (daemon_client.isActive()) {
        try std.io.getStdOut().writer().print("ghostd already active socket={s}\n", .{daemon_client.socketPath()});
        return;
    }

    const bin_path = locator.findEngineBinary(allocator, engine_root, .ghostd) catch |err| {
        try locator.printLocatorError(std.io.getStdErr().writer(), .ghostd, engine_root, err);
        std.process.exit(1);
    };
    defer allocator.free(bin_path);

    var child = std.process.Child.init(&.{ "setsid", "-f", bin_path, "run" }, allocator);
    child.stdin_behavior = .Ignore;
    child.stdout_behavior = .Ignore;
    child.stderr_behavior = if (debug) .Inherit else .Ignore;
    try child.spawn();

    var timer = try std.time.Timer.start();
    while (timer.read() < START_TIMEOUT_NS) {
        if (daemonReady(allocator)) {
            try std.io.getStdOut().writer().print("ghostd active socket={s}\n", .{daemon_client.socketPath()});
            return;
        }
        std.Thread.sleep(25 * std.time.ns_per_ms);
    }
    try std.io.getStdErr().writer().print("ghostd start timed out waiting for heartbeat={s}\n", .{daemon_client.heartbeatPath()});
    std.process.exit(1);
}

fn daemonReady(allocator: std.mem.Allocator) bool {
    if (daemon_client.isActive()) return true;
    const response = daemon_client.request(allocator, "{\"kind\":\"daemon.status\"}") catch return false;
    allocator.free(response);
    return true;
}

fn status(allocator: std.mem.Allocator) !void {
    const payload = "{\"kind\":\"daemon.status\"}";
    const response = daemon_client.request(allocator, payload) catch {
        try std.io.getStdOut().writer().print("ghostd inactive socket={s}\n", .{daemon_client.socketPath()});
        return;
    };
    defer allocator.free(response);
    try std.io.getStdOut().writer().writeAll(response);
    try std.io.getStdOut().writer().writeByte('\n');
}

fn stop(allocator: std.mem.Allocator) !void {
    const payload = "{\"kind\":\"daemon.stop\"}";
    const response = daemon_client.request(allocator, payload) catch {
        try std.io.getStdOut().writer().print("ghostd inactive socket={s}\n", .{daemon_client.socketPath()});
        return;
    };
    defer allocator.free(response);
    try std.io.getStdOut().writer().writeAll(response);
    try std.io.getStdOut().writer().writeByte('\n');
}
