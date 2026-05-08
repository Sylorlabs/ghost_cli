const std = @import("std");
const builtin = @import("builtin");

pub const DEFAULT_ENGINE_TIMEOUT_MS: u64 = 30_000;
pub const TIMEOUT_EXIT_CODE: u8 = 124;

pub const ProcessResult = struct {
    stdout: []u8,
    stderr: []u8,
    exit_code: u8,
    timed_out: bool = false,
};

pub fn runEngineCommand(allocator: std.mem.Allocator, args: []const []const u8) !ProcessResult {
    return runEngineCommandWithEngineLogs(allocator, args, false);
}

pub fn runEngineCommandWithEngineLogs(allocator: std.mem.Allocator, args: []const []const u8, engine_logs: bool) !ProcessResult {
    var env_map = if (engine_logs) try std.process.getEnvMap(allocator) else null;
    defer if (env_map) |*map| map.deinit();
    if (env_map) |*map| try map.put("GHOST_ENGINE_DEBUG", "1");

    return runEngineCommandBounded(allocator, args, if (env_map) |*map| map else null, null, timeoutMs());
}

pub fn runEngineCommandWithTimeout(allocator: std.mem.Allocator, args: []const []const u8, timeout_ms: u64) !ProcessResult {
    return runEngineCommandBounded(allocator, args, null, null, timeout_ms);
}

pub fn runEngineCommandWithInput(allocator: std.mem.Allocator, args: []const []const u8, stdin_payload: []const u8) !ProcessResult {
    return runEngineCommandWithInputTimeout(allocator, args, stdin_payload, timeoutMs());
}

pub fn runEngineCommandWithInputTimeout(allocator: std.mem.Allocator, args: []const []const u8, stdin_payload: []const u8, timeout_ms: u64) !ProcessResult {
    return runEngineCommandBounded(allocator, args, null, stdin_payload, timeout_ms);
}

fn runEngineCommandBounded(
    allocator: std.mem.Allocator,
    args: []const []const u8,
    env_map: ?*const std.process.EnvMap,
    stdin_payload: ?[]const u8,
    timeout_ms: u64,
) !ProcessResult {
    var child = std.process.Child.init(args, allocator);
    child.stdin_behavior = if (stdin_payload == null) .Ignore else .Pipe;
    child.stdout_behavior = .Pipe;
    child.stderr_behavior = .Pipe;
    child.env_map = env_map;

    try child.spawn();
    errdefer _ = child.kill() catch {};
    var timeout_context = TimeoutContext{
        .pid = child.id,
        .timeout_ns = timeout_ms * std.time.ns_per_ms,
    };
    var killer = try std.Thread.spawn(.{}, timeoutKiller, .{&timeout_context});
    defer {
        markTimeoutDone(&timeout_context);
        killer.join();
    }

    if (stdin_payload) |payload| {
        child.stdin.?.writeAll(payload) catch |err| switch (err) {
            error.BrokenPipe => {},
            else => return err,
        };
        child.stdin.?.close();
        child.stdin = null;
    }

    var stdout_list: std.ArrayListUnmanaged(u8) = .empty;
    errdefer stdout_list.deinit(allocator);
    var stderr_list: std.ArrayListUnmanaged(u8) = .empty;
    errdefer stderr_list.deinit(allocator);
    try child.collectOutput(allocator, &stdout_list, &stderr_list, 10 * 1024 * 1024);
    const term = try child.wait();
    markTimeoutDone(&timeout_context);

    const stdout = try stdout_list.toOwnedSlice(allocator);
    errdefer allocator.free(stdout);
    var stderr = try stderr_list.toOwnedSlice(allocator);
    errdefer allocator.free(stderr);

    const timed_out = timeout_context.timedOut();
    if (timed_out) stderr = try appendTimeoutNotice(allocator, stderr, timeout_ms);

    return .{
        .stdout = stdout,
        .stderr = stderr,
        .exit_code = if (timed_out) TIMEOUT_EXIT_CODE else termExitCode(term),
        .timed_out = timed_out,
    };
}

const TimeoutContext = struct {
    mutex: std.Thread.Mutex = .{},
    cond: std.Thread.Condition = .{},
    done: bool = false,
    timed_out: bool = false,
    pid: std.process.Child.Id,
    timeout_ns: u64,

    fn timedOut(self: *TimeoutContext) bool {
        self.mutex.lock();
        defer self.mutex.unlock();
        return self.timed_out;
    }
};

fn timeoutKiller(context: *TimeoutContext) void {
    context.mutex.lock();
    while (!context.done) {
        context.cond.timedWait(&context.mutex, context.timeout_ns) catch |err| switch (err) {
            error.Timeout => {
                if (context.done) break;
                context.timed_out = true;
                const pid = context.pid;
                context.mutex.unlock();
                terminateProcess(pid, false);
                std.time.sleep(250 * std.time.ns_per_ms);
                context.mutex.lock();
                if (!context.done) {
                    context.mutex.unlock();
                    terminateProcess(pid, true);
                    context.mutex.lock();
                }
                break;
            },
        };
    }
    context.mutex.unlock();
}

fn markTimeoutDone(context: *TimeoutContext) void {
    context.mutex.lock();
    context.done = true;
    context.cond.signal();
    context.mutex.unlock();
}

fn terminateProcess(pid: std.process.Child.Id, force: bool) void {
    switch (builtin.os.tag) {
        .windows => return,
        else => {
            const signal: u8 = if (force) @as(u8, std.posix.SIG.KILL) else @as(u8, std.posix.SIG.TERM);
            std.posix.kill(pid, signal) catch {};
        },
    }
}

fn termExitCode(term: std.process.Child.Term) u8 {
    return switch (term) {
        .Exited => |code| code,
        else => 1,
    };
}

fn timeoutMs() u64 {
    const raw = std.posix.getenv("GHOST_CLI_ENGINE_TIMEOUT_MS") orelse return DEFAULT_ENGINE_TIMEOUT_MS;
    const parsed = std.fmt.parseUnsigned(u64, raw, 10) catch return DEFAULT_ENGINE_TIMEOUT_MS;
    return if (parsed == 0) DEFAULT_ENGINE_TIMEOUT_MS else parsed;
}

fn appendTimeoutNotice(allocator: std.mem.Allocator, stderr: []u8, timeout_ms: u64) ![]u8 {
    defer allocator.free(stderr);
    if (stderr.len == 0) {
        return std.fmt.allocPrint(allocator, "ghost_cli: engine subprocess timed out after {d}ms and was terminated\n", .{timeout_ms});
    }
    return std.fmt.allocPrint(allocator, "{s}\nghost_cli: engine subprocess timed out after {d}ms and was terminated\n", .{ stderr, timeout_ms });
}

test "engine command timeout terminates hanging subprocess" {
    if (builtin.os.tag == .windows) return error.SkipZigTest;
    const allocator = std.testing.allocator;
    const result = try runEngineCommandWithTimeout(allocator, &.{ "/bin/sh", "-c", "sleep 2" }, 50);
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);
    try std.testing.expect(result.timed_out);
    try std.testing.expectEqual(TIMEOUT_EXIT_CODE, result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, result.stderr, "timed out") != null);
}

test "engine command stdin timeout recovers from non-reading subprocess" {
    if (builtin.os.tag == .windows) return error.SkipZigTest;
    const allocator = std.testing.allocator;
    const payload = "payload";
    const result = try runEngineCommandWithInputTimeout(allocator, &.{ "/bin/sh", "-c", "sleep 2" }, payload, 50);
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);
    try std.testing.expect(result.timed_out);
    try std.testing.expectEqual(TIMEOUT_EXIT_CODE, result.exit_code);
}
