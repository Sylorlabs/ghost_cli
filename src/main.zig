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
const context_cmd = @import("commands/context.zig");
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
    context,
};

const CommandGroup = enum {
    core,
    inspection,
    knowledge,
    advanced,
    interface,

    fn title(self: CommandGroup) []const u8 {
        return switch (self) {
            .core => "Core",
            .inspection => "Inspection",
            .knowledge => "Knowledge",
            .advanced => "Advanced",
            .interface => "Interface",
        };
    }
};

const CommandDef = struct {
    name: []const u8,
    kind: CommandKind,
    help: []const u8,
    group: CommandGroup,
    usage: []const u8,
};

const command_registry = [_]CommandDef{
    .{ .name = "ask", .kind = .ask, .group = .core, .help = "Short one-shot question", .usage = "ghost ask [options] <message>" },
    .{ .name = "chat", .kind = .chat, .group = .core, .help = "Conversational interface to task operator", .usage = "ghost chat [options] --message=\"...\"" },
    .{ .name = "fix", .kind = .fix, .group = .core, .help = "Ask Ghost for a fix-oriented response", .usage = "ghost fix [options] <message>" },
    .{ .name = "verify", .kind = .verify, .group = .core, .help = "Ask the engine to verify current workspace state", .usage = "ghost verify [options]" },
    .{ .name = "autopsy", .kind = .autopsy, .group = .inspection, .help = "Project Autopsy pass (explicit scan only)", .usage = "ghost autopsy [--json] [--debug] [path]" },
    .{ .name = "context", .kind = .context, .group = .inspection, .help = "Context Autopsy pass (explicit GIP request only)", .usage = "ghost context autopsy [--json] [--debug] [--input-file <path>] <description>" },
    .{ .name = "status", .kind = .status, .group = .inspection, .help = "Show engine availability/status", .usage = "ghost status [--debug]" },
    .{ .name = "doctor", .kind = .doctor, .group = .inspection, .help = "Run read-only environment diagnostics", .usage = "ghost doctor [--json|--report] [--debug] [--full] [--run-build-check]" },
    .{ .name = "packs", .kind = .packs, .group = .knowledge, .help = "Manage knowledge packs", .usage = "ghost packs <list|inspect|mount|unmount|validate-autopsy-guidance> [options]" },
    .{ .name = "learn", .kind = .learn, .group = .knowledge, .help = "Feedback/distillation surface", .usage = "ghost learn <candidates|show|export> [options]" },
    .{ .name = "debug", .kind = .debug, .group = .advanced, .help = "Advanced raw engine diagnostics", .usage = "ghost debug raw <engine-binary> [args...]" },
    .{ .name = "tui", .kind = .tui, .group = .interface, .help = "Interactive Ghost operator console", .usage = "ghost tui [options]" },
};

const CliOptions = struct {
    explicit_engine_root: ?[]const u8 = null,
    json_out: bool = false,
    debug_mode: bool = false,
    color_mode: tui.ColorMode = .auto,
    compact: bool = false,
    reasoning_level: ?json_contracts.ReasoningLevel = null,
    context_artifact: ?[]const u8 = null,
    message: ?[]const u8 = null,
    version: ?[]const u8 = null,
    project_shard: ?[]const u8 = null,
    pack_id: ?[]const u8 = null,
    manifest: ?[]const u8 = null,
    all_mounted: bool = false,
    max_guidance_bytes: ?[]const u8 = null,
    max_array_items: ?[]const u8 = null,
    max_string_bytes: ?[]const u8 = null,
    approve: bool = false,
    version_flag: bool = false,
    help_flag: bool = false,
    subcommand_help: bool = false,
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

    if (parsed.options.help_flag and parsed.command == null) {
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

    if (parsed.options.subcommand_help or parsed.options.help_flag) {
        try printCommandHelp(std.io.getStdErr().writer(), parsed.command.?);
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
        .packs => try packs.executeFromArgs(allocator, root, parsed.leftover_args.items, .{
            .subcommand = "list",
            .pack_id = parsed.options.pack_id,
            .version = parsed.options.version,
            .manifest = parsed.options.manifest,
            .all_mounted = parsed.options.all_mounted,
            .project_shard = parsed.options.project_shard,
            .max_guidance_bytes = parsed.options.max_guidance_bytes,
            .max_array_items = parsed.options.max_array_items,
            .max_string_bytes = parsed.options.max_string_bytes,
            .json = parsed.options.json_out,
            .debug = parsed.options.debug_mode,
        }),
        .learn => try runLearn(allocator, root, parsed),
        .tui => try tui.execute(allocator, root, .{
            .reasoning = parsed.options.reasoning_level,
            .context_artifact = parsed.options.context_artifact,
            .debug = parsed.options.debug_mode,
            .color = parsed.options.color_mode,
            .compact = parsed.options.compact,
            .version = build_version,
            .engine_root_label = root,
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
        .context => try context_cmd.executeFromArgs(allocator, root, parsed.leftover_args.items, parsed.options.json_out, parsed.options.debug_mode),
    }
}

fn parseArgs(args: *std.process.ArgIterator, parsed: *ParsedCli) !void {
    while (args.next()) |arg| {
        if (std.mem.eql(u8, arg, "--help")) {
            if (parsed.command == null) {
                parsed.options.help_flag = true;
            } else {
                parsed.options.subcommand_help = true;
            }
            continue;
        }
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
    } else if (std.mem.eql(u8, arg, "--no-color")) {
        options.color_mode = .never;
    } else if (std.mem.startsWith(u8, arg, "--color=")) {
        const mode_str = arg["--color=".len..];
        options.color_mode = std.meta.stringToEnum(tui.ColorMode, mode_str) orelse {
            try std.io.getStdErr().writer().print("Invalid --color value: {s}. Use auto|always|never.\n", .{mode_str});
            std.process.exit(1);
        };
    } else if (std.mem.eql(u8, arg, "--compact")) {
        options.compact = true;
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
    } else if (std.mem.startsWith(u8, arg, "--reasoning=")) {
        const level_str = arg["--reasoning=".len..];
        options.reasoning_level = std.meta.stringToEnum(json_contracts.ReasoningLevel, level_str) orelse {
            try std.io.getStdErr().writer().print("Invalid --reasoning value: {s}. Use quick|balanced|deep|max.\n", .{level_str});
            std.process.exit(1);
        };
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
    } else if (std.mem.startsWith(u8, arg, "--manifest=")) {
        options.manifest = arg["--manifest=".len..];
    } else if (std.mem.eql(u8, arg, "--all-mounted")) {
        options.all_mounted = true;
    } else if (std.mem.startsWith(u8, arg, "--max-guidance-bytes=")) {
        options.max_guidance_bytes = arg["--max-guidance-bytes=".len..];
    } else if (std.mem.startsWith(u8, arg, "--max-array-items=")) {
        options.max_array_items = arg["--max-array-items=".len..];
    } else if (std.mem.startsWith(u8, arg, "--max-string-bytes=")) {
        options.max_string_bytes = arg["--max-string-bytes=".len..];
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
        .color = options.color_mode,
        .compact = options.compact,
        .version = build_version,
        .engine_root_label = root_tui,
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
    inline for (.{ CommandGroup.core, CommandGroup.inspection, CommandGroup.knowledge, CommandGroup.advanced, CommandGroup.interface }) |group| {
        try writer.print("\n  {s}:\n", .{group.title()});
        for (command_registry) |command| {
            if (command.group == group) {
                try writer.print("    {s:<8} {s}\n", .{ command.name, command.help });
            }
        }
    }
    try writer.print(
        \\
        \\Common options:
        \\
        \\  --message="..."        The message/request to send
        \\  --reasoning=<level>    quick|balanced|deep|max
        \\  --context-artifact=<p> Pass a path as context
        \\  --version              Show version information
        \\  --engine-root=<path>   Explicitly set path to ghost_engine binaries
        \\  --help                 Show help
        \\
        \\Output options:
        \\
        \\  --json                 Preserve raw engine JSON where supported
        \\  --no-color             Disable ANSI color in native TUI surfaces
        \\  --color=<mode>         auto|always|never
        \\  --compact              Use tighter native TUI layout
        \\
        \\Advanced/debug options:
        \\
        \\  --version=<v>          Specific version for packs/distillation
        \\  --project-shard=<s>    Project shard ID for distillation
        \\  --pack-id=<id>         Target pack ID for export
        \\  --manifest=<path>      Knowledge pack manifest path
        \\  --all-mounted          Target all mounted packs where supported
        \\  --max-guidance-bytes=<n> Override autopsy guidance byte limit when engine supports it
        \\  --max-array-items=<n>  Override autopsy guidance array item limit when engine supports it
        \\  --max-string-bytes=<n> Override autopsy guidance string byte limit when engine supports it
        \\  --approve              Approve distillation export
        \\  --report               Print copy-paste tester report for doctor
        \\  --full                 Include optional doctor checks
        \\  --run-build-check      Let doctor run `zig build --help`
        \\  --debug                Show debug information
        \\
        \\Use `ghost <command> --help` for command-specific usage.
        \\
    , .{});
}

fn printCommandHelp(writer: anytype, kind: CommandKind) !void {
    if (kind == .context) return context_cmd.printHelp(writer);
    if (kind == .packs) return packs.printHelp(writer);

    const command = commandByKind(kind).?;
    try writer.print("{s}\n\nUsage: {s}\n\n{s}\n", .{ command.name, command.usage, command.help });
    switch (kind) {
        .ask, .chat, .fix => try writer.print(
            \\
            \\Options:
            \\  --message="..."        Message to send
            \\  --reasoning=<level>    quick|balanced|deep|max
            \\  --context-artifact=<p> Attach explicit context path
            \\  --engine-root=<path>   Resolve engine binaries from path
            \\  --json                 Preserve raw engine stdout exactly
            \\  --debug                Diagnostics to stderr
            \\
        , .{}),
        .verify => try writer.print(
            \\
            \\Options:
            \\  --reasoning=<level>    quick|balanced|deep|max
            \\  --context-artifact=<p> Attach explicit context path
            \\  --engine-root=<path>   Resolve engine binaries from path
            \\  --json                 Preserve raw engine stdout exactly
            \\  --debug                Diagnostics to stderr
            \\
        , .{}),
        .tui => try writer.print(
            \\
            \\Options:
            \\  --reasoning=<level>    quick|balanced|deep|max
            \\  --context-artifact=<p> Set active context artifact
            \\  --engine-root=<path>   Resolve engine binaries from path when commands run
            \\  --debug                Start with debug mode on
            \\  --no-color             Disable ANSI color
            \\  --color=<mode>         auto|always|never
            \\  --compact              Tighter layout
            \\
            \\Slash commands:
            \\  /help, /quit, /status, /reasoning <level>, /debug on|off, /json on|off
            \\  /clear, /doctor, /autopsy <path>, /context <path>
            \\  Typing / shows prefix-first fuzzy suggestions. Invalid slash commands are rejected locally.
            \\
            \\Safety:
            \\  Launching or idling in the TUI does not start doctor/status, context/project autopsy,
            \\  verifiers, scans, pack mutation, or negative-knowledge mutation.
            \\  Explicit slash commands and submitted prompts may invoke engine binaries.
            \\
        , .{}),
        .doctor => try writer.print(
            \\
            \\Options:
            \\  --json                 Emit diagnostic JSON
            \\  --report               Copy-paste tester report
            \\  --full                 Include optional probes
            \\  --run-build-check      Run `zig build --help` only
            \\  --debug                Include candidate resolution detail
            \\
        , .{}),
        .status => try writer.print("\nOptions:\n  --debug                Include candidate resolution detail\n", .{}),
        .autopsy => try writer.print(
            \\
            \\Options:
            \\  --json                 Preserve raw autopsy JSON exactly
            \\  --debug                Diagnostics to stderr
            \\
            \\Safety:
            \\  This scan runs only when this command is explicitly invoked.
            \\
        , .{}),
        .context, .packs => unreachable,
        .learn => try writer.print(
            \\
            \\Subcommands:
            \\  candidates --project-shard=<id>
            \\  show <candidate-id> --project-shard=<id>
            \\  export <candidate-id> --project-shard=<id> --pack-id=<id> --version=<v> --approve
            \\
        , .{}),
        .debug => try writer.print("\nAdvanced raw diagnostic command. Does not reinterpret engine output.\n", .{}),
    }
}

fn commandByKind(kind: CommandKind) ?CommandDef {
    for (command_registry) |command| {
        if (command.kind == kind) return command;
    }
    return null;
}
