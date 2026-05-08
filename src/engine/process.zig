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

pub const DynamicTaskGraphNode = struct {
    id: []u8,
    label: []u8,

    fn deinit(self: *DynamicTaskGraphNode, allocator: std.mem.Allocator) void {
        allocator.free(self.id);
        allocator.free(self.label);
        self.* = undefined;
    }
};

pub const DynamicTaskGraphEdge = struct {
    from: []u8,
    to: []u8,
    relation: []u8,

    fn deinit(self: *DynamicTaskGraphEdge, allocator: std.mem.Allocator) void {
        allocator.free(self.from);
        allocator.free(self.to);
        allocator.free(self.relation);
        self.* = undefined;
    }
};

pub const DynamicTaskGraph = struct {
    allocator: std.mem.Allocator,
    request_hash: []u8,
    nodes: []DynamicTaskGraphNode,
    edges: []DynamicTaskGraphEdge,
    ephemeral: bool = true,

    pub fn deinit(self: *DynamicTaskGraph) void {
        self.allocator.free(self.request_hash);
        for (self.nodes) |*node| node.deinit(self.allocator);
        self.allocator.free(self.nodes);
        for (self.edges) |*edge| edge.deinit(self.allocator);
        self.allocator.free(self.edges);
        self.* = undefined;
    }
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
    var dynamic_graph = try buildDynamicTaskGraph(allocator, args, stdin_payload);
    defer dynamic_graph.deinit();

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

pub fn buildDynamicTaskGraph(
    allocator: std.mem.Allocator,
    args: []const []const u8,
    stdin_payload: ?[]const u8,
) !DynamicTaskGraph {
    const request_hash = try hashProcessRequest(allocator, args, stdin_payload);
    errdefer allocator.free(request_hash);

    var nodes = std.ArrayList(DynamicTaskGraphNode).init(allocator);
    errdefer {
        for (nodes.items) |*node| node.deinit(allocator);
        nodes.deinit();
    }
    var edges = std.ArrayList(DynamicTaskGraphEdge).init(allocator);
    errdefer {
        for (edges.items) |*edge| edge.deinit(allocator);
        edges.deinit();
    }

    try appendGraphNode(allocator, &nodes, "cli.request", "CLI request envelope");
    try appendGraphNode(allocator, &nodes, "engine.process", "Ghost engine subprocess");
    try appendGraphEdge(allocator, &edges, "cli.request", "engine.process", "executes");
    if (stdin_payload) |_| {
        try appendGraphNode(allocator, &nodes, "stdin.payload", "GIP stdin payload");
        try appendGraphEdge(allocator, &edges, "stdin.payload", "engine.process", "feeds");
    }
    for (args, 0..) |arg, idx| {
        const id = try std.fmt.allocPrint(allocator, "argv.{d}", .{idx});
        try appendGraphNodeOwned(allocator, &nodes, id, arg);
        try appendGraphEdge(allocator, &edges, id, "engine.process", "argv");
    }

    return .{
        .allocator = allocator,
        .request_hash = request_hash,
        .nodes = try nodes.toOwnedSlice(),
        .edges = try edges.toOwnedSlice(),
    };
}

fn appendGraphNode(
    allocator: std.mem.Allocator,
    nodes: *std.ArrayList(DynamicTaskGraphNode),
    id: []const u8,
    label: []const u8,
) !void {
    try appendGraphNodeOwned(allocator, nodes, try allocator.dupe(u8, id), label);
}

fn appendGraphNodeOwned(
    allocator: std.mem.Allocator,
    nodes: *std.ArrayList(DynamicTaskGraphNode),
    id: []u8,
    label: []const u8,
) !void {
    errdefer allocator.free(id);
    try nodes.append(.{
        .id = id,
        .label = try allocator.dupe(u8, label),
    });
}

fn appendGraphEdge(
    allocator: std.mem.Allocator,
    edges: *std.ArrayList(DynamicTaskGraphEdge),
    from: []const u8,
    to: []const u8,
    relation: []const u8,
) !void {
    try edges.append(.{
        .from = try allocator.dupe(u8, from),
        .to = try allocator.dupe(u8, to),
        .relation = try allocator.dupe(u8, relation),
    });
}

fn hashProcessRequest(allocator: std.mem.Allocator, args: []const []const u8, stdin_payload: ?[]const u8) ![]u8 {
    var hasher = std.crypto.hash.sha2.Sha256.init(.{});
    for (args) |arg| {
        hasher.update(arg);
        hasher.update(&.{0});
    }
    if (stdin_payload) |payload| hasher.update(payload);
    var digest: [std.crypto.hash.sha2.Sha256.digest_length]u8 = undefined;
    hasher.final(&digest);
    const prefix = "sha256:";
    var out = try allocator.alloc(u8, prefix.len + digest.len * 2);
    @memcpy(out[0..prefix.len], prefix);
    const hex = "0123456789abcdef";
    for (digest, 0..) |byte, idx| {
        out[prefix.len + idx * 2] = hex[byte >> 4];
        out[prefix.len + idx * 2 + 1] = hex[byte & 0x0f];
    }
    return out;
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

test "engine process builds ephemeral dynamic task graph envelope" {
    const allocator = std.testing.allocator;
    var graph = try buildDynamicTaskGraph(allocator, &.{ "ghost_engine", "--gip" }, "{\"kind\":\"corpus.ask\"}");
    defer graph.deinit();

    try std.testing.expect(graph.ephemeral);
    try std.testing.expect(std.mem.startsWith(u8, graph.request_hash, "sha256:"));
    try std.testing.expect(graph.nodes.len >= 4);
    try std.testing.expect(graph.edges.len >= 3);
}
