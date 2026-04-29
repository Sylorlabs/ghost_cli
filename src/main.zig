const std = @import("std");
const paths = @import("config/paths.zig");
const chat = @import("commands/chat.zig");
const debug_cmd = @import("commands/debug.zig");
const doctor = @import("commands/doctor.zig");
const status = @import("commands/status.zig");
const packs = @import("commands/packs.zig");
const verify = @import("commands/verify.zig");
const learn = @import("commands/learn.zig");
const autopsy = @import("commands/autopsy.zig");
const tui = @import("commands/tui.zig");
const json_contracts = @import("engine/json_contracts.zig");

const build_version = "v0.1.0-hardened";

const CommandKind = enum {
    chat,
    ask,
    fix,
    verify,
    packs,
    learn,
    tui,
    status,
    doctor,
    debug,
    autopsy,
};

const CommandDef = struct {
    name: []const u8,
    kind: CommandKind,
    help: []const u8,
};

const command_registry = [_]CommandDef{
    .{ .name = "chat", .kind = .chat, .help = "Conversational interface to task operator" },
    .{ .name = "ask", .kind = .ask, .help = "Short one-shot question" },
    .{ .name = "fix", .kind = .fix, .help = "Propose or perform a fix" },
    .{ .name = "verify", .kind = .verify, .help = "Verify current workspace state" },
    .{ .name = "packs", .kind = .packs, .help = "Manage knowledge packs (list, inspect, mount, unmount)" },
    .{ .name = "learn", .kind = .learn, .help = "Feedback/distillation surface (candidates, show, export)" },
    .{ .name = "tui", .kind = .tui, .help = "Interactive Ghost Console TUI (same as default)" },
    .{ .name = "status", .kind = .status, .help = "Show engine availability/status" },
    .{ .name = "doctor", .kind = .doctor, .help = "Run read-only environment diagnostics" },
    .{ .name = "autopsy", .kind = .autopsy, .help = "Project Autopsy pass (explicit scan only)" },
    .{ .name = "debug", .kind = .debug, .help = "Advanced debug commands" },
};

const CliOptions = struct {
    explicit_engine_root: ?[]const u8 = null,
    json_out: bool = false,
    debug_mode: bool = false,
    reasoning_level: ?json_contracts.ReasoningLevel = null,
    context_artifact: ?[]const u8 = null,
    message: ?[]const u8 = null,
    version: ?[]const u8 = null,
    project_shard: ?[]const u8 = null,
    pack_id: ?[]const u8 = null,
    approve: bool = false,
    version_flag: bool = false,
    help_flag: bool = false,
    report: bool = false,
    full: bool = false,
    run_build_check: bool = false,
};

const ParsedCli = struct {
    options: CliOptions = .{},
    command: ?CommandKind = null,
    command_name: ?[]const u8 = null,
    leftover_args: std.ArrayList([]const u8),

    fn init(allocator: std.mem.Allocator) ParsedCli {
        return .{ .leftover_args = std.ArrayList([]const u8).init(allocator) };
    }

    fn deinit(self: *ParsedCli) void {
        self.leftover_args.deinit();
    }
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var args = try std.process.argsWithAllocator(allocator);
    defer args.deinit();
    _ = args.next();

    var parsed = ParsedCli.init(allocator);
    defer parsed.deinit();
    try parseArgs(&args, &parsed);

    if (parsed.options.help_flag) {
        try printHelp(std.io.getStdErr().writer());
        return;
    }

    if (parsed.options.version_flag) {
        try std.io.getStdErr().writer().print("ghost_cli {s}\n", .{build_version});
        return;
    }

    if (parsed.command == null) {
        try runDefaultTui(allocator, parsed.options);
        return;
    }

    var engine_paths = try paths.discoverEngineRoot(allocator, parsed.options.explicit_engine_root);
    defer if (engine_paths) |*ep| ep.deinit(allocator);
    const root = if (engine_paths) |ep| ep.root else null;

    switch (parsed.command.?) {
        .chat => try runChatLike(allocator, root, &parsed, null),
        .ask => try runChatLike(allocator, root, &parsed, .balanced),
        .fix => try runChatLike(allocator, root, &parsed, .deep),
        .verify => try verify.execute(allocator, root, .{
            .reasoning = parsed.options.reasoning_level,
            .context_artifact = parsed.options.context_artifact,
            .json = parsed.options.json_out,
            .debug = parsed.options.debug_mode,
        }),
        .packs => try runPacks(allocator, root, parsed),
        .learn => try runLearn(allocator, root, parsed),
        .tui => try tui.execute(allocator, root, .{
            .reasoning = parsed.options.reasoning_level,
            .context_artifact = parsed.options.context_artifact,
            .debug = parsed.options.debug_mode,
        }),
        .status => try status.execute(allocator, root, parsed.options.debug_mode, build_version),
        .doctor => try doctor.execute(allocator, root, .{
            .json = parsed.options.json_out,
            .debug = parsed.options.debug_mode,
            .report = parsed.options.report,
            .full = parsed.options.full,
            .run_build_check = parsed.options.run_build_check,
            .version = build_version,
        }),
        .debug => try debug_cmd.execute(allocator, root, parsed.leftover_args.items, parsed.options.json_out),
        .autopsy => try autopsy.execute(allocator, root, .{
            .path = if (parsed.leftover_args.items.len > 0) parsed.leftover_args.items[0] else null,
            .json = parsed.options.json_out,
            .debug = parsed.options.debug_mode,
        }),
    }
}

fn parseArgs(args: *std.process.ArgIterator, parsed: *ParsedCli) !void {
    while (args.next()) |arg| {
        if (try parseFlag(arg, &parsed.options)) continue;
        if (parsed.command == null) {
            if (lookupCommand(arg)) |command| {
                parsed.command = command.kind;
                parsed.command_name = command.name;
            } else {
                try std.io.getStdErr().writer().print("Unknown command: {s}\n", .{arg});
                try printHelp(std.io.getStdErr().writer());
                std.process.exit(1);
            }
        } else {
            try parsed.leftover_args.append(arg);
        }
    }
}

fn parseFlag(arg: []const u8, options: *CliOptions) !bool {
    if (std.mem.startsWith(u8, arg, "--engine-root=")) {
        options.explicit_engine_root = arg["--engine-root=".len..];
    } else if (std.mem.eql(u8, arg, "--json")) {
        options.json_out = true;
    } else if (std.mem.eql(u8, arg, "--debug")) {
        options.debug_mode = true;
    } else if (std.mem.eql(u8, arg, "--approve")) {
        options.approve = true;
    } else if (std.mem.eql(u8, arg, "--report")) {
        options.report = true;
    } else if (std.mem.eql(u8, arg, "--full")) {
        options.full = true;
    } else if (std.mem.eql(u8, arg, "--run-build-check")) {
        options.run_build_check = true;
    } else if (std.mem.eql(u8, arg, "--version")) {
        options.version_flag = true;
    } else if (std.mem.eql(u8, arg, "--help")) {
        options.help_flag = true;
    } else if (std.mem.startsWith(u8, arg, "--reasoning=")) {
        const level_str = arg["--reasoning=".len..];
        options.reasoning_level = std.meta.stringToEnum(json_contracts.ReasoningLevel, level_str);
    } else if (std.mem.startsWith(u8, arg, "--context-artifact=")) {
        options.context_artifact = arg["--context-artifact=".len..];
    } else if (std.mem.startsWith(u8, arg, "--message=")) {
        options.message = arg["--message=".len..];
    } else if (std.mem.startsWith(u8, arg, "--version=")) {
        options.version = arg["--version=".len..];
    } else if (std.mem.startsWith(u8, arg, "--project-shard=")) {
        options.project_shard = arg["--project-shard=".len..];
    } else if (std.mem.startsWith(u8, arg, "--pack-id=")) {
        options.pack_id = arg["--pack-id=".len..];
    } else {
        return false;
    }
    return true;
}

fn lookupCommand(name: []const u8) ?CommandDef {
    for (command_registry) |command| {
        if (std.mem.eql(u8, name, command.name)) return command;
    }
    return null;
}

fn runDefaultTui(allocator: std.mem.Allocator, options: CliOptions) !void {
    var engine_paths_tui = try paths.discoverEngineRoot(allocator, options.explicit_engine_root);
    defer if (engine_paths_tui) |*ep| ep.deinit(allocator);
    const root_tui = if (engine_paths_tui) |ep| ep.root else null;
    try tui.execute(allocator, root_tui, .{
        .reasoning = options.reasoning_level,
        .context_artifact = options.context_artifact,
        .debug = options.debug_mode,
    });
}

fn runChatLike(allocator: std.mem.Allocator, root: ?[]const u8, parsed: *ParsedCli, default_reasoning: ?json_contracts.ReasoningLevel) !void {
    var message = parsed.options.message;
    if (message == null and parsed.leftover_args.items.len > 0) message = parsed.leftover_args.items[0];
    const reasoning = if (parsed.options.reasoning_level) |level| level else default_reasoning;
    try chat.execute(allocator, root, .{
        .message = message,
        .reasoning = reasoning,
        .context_artifact = parsed.options.context_artifact,
        .json = parsed.options.json_out,
        .debug = parsed.options.debug_mode,
    });
}

fn runPacks(allocator: std.mem.Allocator, root: ?[]const u8, parsed: ParsedCli) !void {
    const sub = if (parsed.leftover_args.items.len > 0) parsed.leftover_args.items[0] else "list";
    const p_id = if (parsed.leftover_args.items.len > 1) parsed.leftover_args.items[1] else null;
    try packs.execute(allocator, root, .{
        .subcommand = sub,
        .pack_id = p_id,
        .version = parsed.options.version,
        .json = parsed.options.json_out,
        .debug = parsed.options.debug_mode,
    });
}

fn runLearn(allocator: std.mem.Allocator, root: ?[]const u8, parsed: ParsedCli) !void {
    const sub = if (parsed.leftover_args.items.len > 0) parsed.leftover_args.items[0] else {
        try std.io.getStdErr().writer().print("Usage: ghost learn <candidates|show|export>\n", .{});
        return;
    };
    const c_id = if (parsed.leftover_args.items.len > 1) parsed.leftover_args.items[1] else null;
    try learn.execute(allocator, root, .{
        .subcommand = sub,
        .project_shard = parsed.options.project_shard,
        .candidate_id = c_id,
        .pack_id = parsed.options.pack_id,
        .version = parsed.options.version,
        .approve = parsed.options.approve,
        .json = parsed.options.json_out,
        .debug = parsed.options.debug_mode,
    });
}

fn printHelp(writer: anytype) !void {
    try writer.print(
        \\ghost_cli - User-facing CLI for ghost_engine
        \\
        \\Usage: ghost [command] [options]
        \\
        \\  Running ghost with no arguments launches the interactive TUI console.
        \\
        \\Commands:
        \\
        \\  (none)   Launch interactive TUI console (default)
        \\
    , .{});
    for (command_registry) |command| {
        try writer.print("  {s:<8} {s}\n", .{ command.name, command.help });
    }
    try writer.print(
        \\
        \\Options:
        \\
        \\  --message="..."        The message/request to send
        \\  --reasoning=<level>    quick|balanced|deep|max
        \\  --context-artifact=<p> Pass a path as context
        \\  --version              Show version information
        \\  --version=<v>          Specific version for packs/distillation
        \\  --project-shard=<s>    Project shard ID for distillation
        \\  --pack-id=<id>         Target pack ID for export
        \\  --approve              Approve distillation export
        \\  --report               Print copy-paste tester report for doctor
        \\  --full                 Include optional doctor checks
        \\  --run-build-check      Let doctor run `zig build --help`
        \\  --engine-root=<path>   Explicitly set path to ghost_engine binaries
        \\  --json                 Output in JSON format
        \\  --debug                Show debug information
        \\  --help                 Show this help message
        \\
    , .{});
}
