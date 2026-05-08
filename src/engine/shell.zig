const std = @import("std");

pub const CommandProposal = struct {
    argv: []const []const u8,
    command_display: []const u8,
    cwd: ?[]const u8 = null,
    allocator: std.mem.Allocator,

    pub fn deinit(self: CommandProposal) void {
        for (self.argv) |arg| self.allocator.free(arg);
        self.allocator.free(self.argv);
        self.allocator.free(self.command_display);
        if (self.cwd) |cwd| self.allocator.free(cwd);
    }
};

pub const CommandResult = struct {
    stdout: []u8,
    stderr: []u8,
    exit_code: u8,
    allocator: std.mem.Allocator,

    pub fn deinit(self: CommandResult) void {
        self.allocator.free(self.stdout);
        self.allocator.free(self.stderr);
    }
};

pub fn findCommandProposal(allocator: std.mem.Allocator, bytes: []const u8) !?CommandProposal {
    var parsed = std.json.parseFromSlice(std.json.Value, allocator, bytes, .{}) catch return null;
    defer parsed.deinit();
    return try findCommandProposalValue(allocator, parsed.value);
}

pub fn execute(allocator: std.mem.Allocator, proposal: CommandProposal) !CommandResult {
    if (proposal.argv.len == 0) return error.EmptyCommandProposal;

    var child = std.process.Child.init(proposal.argv, allocator);
    child.stdin_behavior = .Ignore;
    child.stdout_behavior = .Pipe;
    child.stderr_behavior = .Pipe;
    if (proposal.cwd) |cwd| child.cwd = cwd;

    try child.spawn();

    var stdout = std.ArrayListUnmanaged(u8){};
    errdefer stdout.deinit(allocator);
    var stderr = std.ArrayListUnmanaged(u8){};
    errdefer stderr.deinit(allocator);
    try child.collectOutput(allocator, &stdout, &stderr, 256 * 1024);
    const term = try child.wait();

    return .{
        .stdout = try stdout.toOwnedSlice(allocator),
        .stderr = try stderr.toOwnedSlice(allocator),
        .exit_code = switch (term) {
            .Exited => |code| code,
            else => 1,
        },
        .allocator = allocator,
    };
}

pub fn renderCommandResultJson(writer: anytype, proposal: CommandProposal, result: CommandResult) !void {
    try writer.writeAll("{\"kind\":\"command.result\",\"command\":");
    try std.json.stringify(proposal.command_display, .{}, writer);
    try writer.writeAll(",\"argv\":[");
    for (proposal.argv, 0..) |arg, idx| {
        if (idx != 0) try writer.writeByte(',');
        try std.json.stringify(arg, .{}, writer);
    }
    try writer.writeAll("],\"cwd\":");
    if (proposal.cwd) |cwd| try std.json.stringify(cwd, .{}, writer) else try writer.writeAll("null");
    try writer.print(",\"exitCode\":{d},\"stdout\":", .{result.exit_code});
    try std.json.stringify(result.stdout, .{}, writer);
    try writer.writeAll(",\"stderr\":");
    try std.json.stringify(result.stderr, .{}, writer);
    try writer.writeAll(",\"commandsExecuted\":true}");
}

fn findCommandProposalValue(allocator: std.mem.Allocator, value: std.json.Value) !?CommandProposal {
    switch (value) {
        .object => |obj| {
            if (obj.get("commandProposal")) |candidate| {
                if (try parseCommandObject(allocator, candidate)) |proposal| return proposal;
            }
            if (obj.get("command_proposal")) |candidate| {
                if (try parseCommandObject(allocator, candidate)) |proposal| return proposal;
            }
            if (try parseCommandObject(allocator, value)) |proposal| return proposal;

            var it = obj.iterator();
            while (it.next()) |entry| {
                if (try findCommandProposalValue(allocator, entry.value_ptr.*)) |proposal| return proposal;
            }
        },
        .array => |items| {
            for (items.items) |item| {
                if (try findCommandProposalValue(allocator, item)) |proposal| return proposal;
            }
        },
        else => {},
    }
    return null;
}

fn parseCommandObject(allocator: std.mem.Allocator, value: std.json.Value) !?CommandProposal {
    if (value != .object) return null;
    const obj = value.object;

    const has_proposal_marker =
        hasStringValue(obj.get("kind"), "command.proposal") or
        hasStringValue(obj.get("kind"), "command.run.proposal") or
        obj.get("requiresApproval") != null or
        obj.get("requires_approval") != null or
        obj.get("command_id") != null or
        obj.get("commandId") != null;

    if (obj.get("argv")) |argv_value| {
        if (argv_value == .array and argv_value.array.items.len != 0 and has_proposal_marker) {
            return try proposalFromArgv(allocator, argv_value.array.items, optionalString(obj.get("cwd")));
        }
    }

    const command_value = obj.get("command") orelse obj.get("commandText") orelse obj.get("command_text") orelse return null;
    if (!has_proposal_marker or command_value != .string or command_value.string.len == 0) return null;
    return try proposalFromCommandString(allocator, command_value.string, optionalString(obj.get("cwd")));
}

fn proposalFromArgv(allocator: std.mem.Allocator, items: []const std.json.Value, cwd: ?[]const u8) !CommandProposal {
    var argv = try allocator.alloc([]const u8, items.len);
    errdefer allocator.free(argv);
    for (items, 0..) |item, idx| {
        if (item != .string) return error.InvalidCommandProposal;
        argv[idx] = try allocator.dupe(u8, item.string);
    }
    errdefer for (argv) |arg| allocator.free(arg);

    return .{
        .argv = argv,
        .command_display = try joinCommandDisplay(allocator, argv),
        .cwd = if (cwd) |value| try allocator.dupe(u8, value) else null,
        .allocator = allocator,
    };
}

fn proposalFromCommandString(allocator: std.mem.Allocator, command: []const u8, cwd: ?[]const u8) !CommandProposal {
    var argv = try allocator.alloc([]const u8, 3);
    errdefer allocator.free(argv);
    argv[0] = try allocator.dupe(u8, "/bin/sh");
    argv[1] = try allocator.dupe(u8, "-lc");
    argv[2] = try allocator.dupe(u8, command);
    errdefer for (argv) |arg| allocator.free(arg);

    return .{
        .argv = argv,
        .command_display = try allocator.dupe(u8, command),
        .cwd = if (cwd) |value| try allocator.dupe(u8, value) else null,
        .allocator = allocator,
    };
}

fn joinCommandDisplay(allocator: std.mem.Allocator, argv: []const []const u8) ![]const u8 {
    var out = std.ArrayList(u8).init(allocator);
    defer out.deinit();
    for (argv, 0..) |arg, idx| {
        if (idx != 0) try out.append(' ');
        try out.appendSlice(arg);
    }
    return try out.toOwnedSlice();
}

fn optionalString(value: ?std.json.Value) ?[]const u8 {
    const v = value orelse return null;
    if (v != .string or v.string.len == 0) return null;
    return v.string;
}

fn hasStringValue(value: ?std.json.Value, expected: []const u8) bool {
    const v = value orelse return false;
    return v == .string and std.mem.eql(u8, v.string, expected);
}

test "findCommandProposal reads argv proposal" {
    const allocator = std.testing.allocator;
    const json =
        \\{"result":{"commandProposal":{"kind":"command.proposal","argv":["zig","build"],"requiresApproval":true}}}
    ;
    const proposal = (try findCommandProposal(allocator, json)).?;
    defer proposal.deinit();
    try std.testing.expectEqualStrings("zig build", proposal.command_display);
    try std.testing.expectEqualStrings("zig", proposal.argv[0]);
    try std.testing.expectEqualStrings("build", proposal.argv[1]);
}
