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

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var args = try std.process.argsWithAllocator(allocator);
    defer args.deinit();

    // Skip executable name
    _ = args.next();

    var explicit_engine_root: ?[]const u8 = null;
    var json_out = false;
    var debug_mode = false;
    var reasoning_level: ?json_contracts.ReasoningLevel = null;
    var context_artifact: ?[]const u8 = null;
    var message: ?[]const u8 = null;
    var version: ?[]const u8 = null;
    var project_shard: ?[]const u8 = null;
    var pack_id: ?[]const u8 = null;
    var approve = false;
    var version_flag = false;
    var report = false;
    var full = false;
    var run_build_check = false;

    var cmd: ?[]const u8 = null;
    var leftover_args = std.ArrayList([]const u8).init(allocator);
    defer leftover_args.deinit();

    while (args.next()) |arg| {
        if (std.mem.startsWith(u8, arg, "--engine-root=")) {
            explicit_engine_root = arg["--engine-root=".len..];
        } else if (std.mem.eql(u8, arg, "--json")) {
            json_out = true;
        } else if (std.mem.eql(u8, arg, "--debug")) {
            debug_mode = true;
        } else if (std.mem.eql(u8, arg, "--approve")) {
            approve = true;
        } else if (std.mem.eql(u8, arg, "--report")) {
            report = true;
        } else if (std.mem.eql(u8, arg, "--full")) {
            full = true;
        } else if (std.mem.eql(u8, arg, "--run-build-check")) {
            run_build_check = true;
        } else if (std.mem.eql(u8, arg, "--version")) {
            version_flag = true;
        } else if (std.mem.startsWith(u8, arg, "--reasoning=")) {
            const level_str = arg["--reasoning=".len..];
            reasoning_level = std.meta.stringToEnum(json_contracts.ReasoningLevel, level_str);
        } else if (std.mem.startsWith(u8, arg, "--context-artifact=")) {
            context_artifact = arg["--context-artifact=".len..];
        } else if (std.mem.startsWith(u8, arg, "--message=")) {
            message = arg["--message=".len..];
        } else if (std.mem.startsWith(u8, arg, "--version=")) {
            version = arg["--version=".len..];
        } else if (std.mem.startsWith(u8, arg, "--project-shard=")) {
            project_shard = arg["--project-shard=".len..];
        } else if (std.mem.startsWith(u8, arg, "--pack-id=")) {
            pack_id = arg["--pack-id=".len..];
        } else if (std.mem.eql(u8, arg, "--help")) {
            printHelp();
            return;
        } else if (cmd == null) {
            cmd = arg;
        } else {
            try leftover_args.append(arg);
        }
    }

    if (version_flag) {
        std.debug.print("ghost_cli v0.1.0-hardened\n", .{});
        return;
    }

    if (cmd == null) {
        // No subcommand supplied — launch the TUI as the default interactive entrypoint.
        // This is a pure renderer/front-door path.  No engine logic lives here.
        var engine_paths_tui = try paths.discoverEngineRoot(allocator, explicit_engine_root);
        defer if (engine_paths_tui) |*ep| ep.deinit(allocator);
        const root_tui = if (engine_paths_tui) |ep| ep.root else null;
        try tui.execute(allocator, root_tui, .{
            .reasoning = reasoning_level,
            .context_artifact = context_artifact,
            .debug = debug_mode,
        });
        return;
    }

    var engine_paths = try paths.discoverEngineRoot(allocator, explicit_engine_root);
    defer if (engine_paths) |*ep| ep.deinit(allocator);
    const root = if (engine_paths) |ep| ep.root else null;

    if (std.mem.eql(u8, cmd.?, "chat")) {
        if (message == null and leftover_args.items.len > 0) message = leftover_args.items[0];
        try chat.execute(allocator, root, .{
            .message = message,
            .reasoning = reasoning_level,
            .context_artifact = context_artifact,
            .json = json_out,
            .debug = debug_mode,
        });
    } else if (std.mem.eql(u8, cmd.?, "ask")) {
        if (message == null and leftover_args.items.len > 0) message = leftover_args.items[0];
        try chat.execute(allocator, root, .{
            .message = message,
            .reasoning = reasoning_level orelse .balanced,
            .context_artifact = context_artifact,
            .json = json_out,
            .debug = debug_mode,
        });
    } else if (std.mem.eql(u8, cmd.?, "fix")) {
        if (message == null and leftover_args.items.len > 0) message = leftover_args.items[0];
        try chat.execute(allocator, root, .{
            .message = message,
            .reasoning = reasoning_level orelse .deep,
            .context_artifact = context_artifact,
            .json = json_out,
            .debug = debug_mode,
        });
    } else if (std.mem.eql(u8, cmd.?, "verify")) {
        try verify.execute(allocator, root, .{
            .reasoning = reasoning_level,
            .context_artifact = context_artifact,
            .json = json_out,
            .debug = debug_mode,
        });
    } else if (std.mem.eql(u8, cmd.?, "packs")) {
        const sub = if (leftover_args.items.len > 0) leftover_args.items[0] else "list";
        const p_id = if (leftover_args.items.len > 1) leftover_args.items[1] else null;
        try packs.execute(allocator, root, .{
            .subcommand = sub,
            .pack_id = p_id,
            .version = version,
            .json = json_out,
            .debug = debug_mode,
        });
    } else if (std.mem.eql(u8, cmd.?, "learn")) {
        const sub = if (leftover_args.items.len > 0) leftover_args.items[0] else {
            std.debug.print("Usage: ghost learn <candidates|show|export>\n", .{});
            return;
        };
        const c_id = if (leftover_args.items.len > 1) leftover_args.items[1] else null;
        try learn.execute(allocator, root, .{
            .subcommand = sub,
            .project_shard = project_shard,
            .candidate_id = c_id,
            .pack_id = pack_id,
            .version = version,
            .approve = approve,
            .json = json_out,
            .debug = debug_mode,
        });
    } else if (std.mem.eql(u8, cmd.?, "tui")) {
        try tui.execute(allocator, root, .{
            .reasoning = reasoning_level,
            .context_artifact = context_artifact,
            .debug = debug_mode,
        });
    } else if (std.mem.eql(u8, cmd.?, "status")) {
        try status.execute(allocator, root, debug_mode, "v0.1.0-hardened");
    } else if (std.mem.eql(u8, cmd.?, "doctor")) {
        try doctor.execute(allocator, root, .{
            .json = json_out,
            .debug = debug_mode,
            .report = report,
            .full = full,
            .run_build_check = run_build_check,
            .version = "v0.1.0-hardened",
        });
    } else if (std.mem.eql(u8, cmd.?, "debug")) {
        try debug_cmd.execute(allocator, root, leftover_args.items, json_out);
    } else if (std.mem.eql(u8, cmd.?, "autopsy")) {
        const path = if (leftover_args.items.len > 0) leftover_args.items[0] else null;
        try autopsy.execute(allocator, root, .{
            .path = path,
            .json = json_out,
            .debug = debug_mode,
        });
    } else {
        std.debug.print("Unknown command: {s}\n", .{cmd.?});
        printHelp();
    }
}

fn printHelp() void {
    std.debug.print(
        \\ghost_cli - User-facing CLI for ghost_engine
        \\
        \\Usage: ghost [command] [options]
        \\
        \\  Running ghost with no arguments launches the interactive TUI console.
        \\
        \\Commands:
        \\
        \\  (none)   Launch interactive TUI console (default)
        \\  chat     Conversational interface to task operator
        \\  ask      Short one-shot question
        \\  fix      Propose or perform a fix
        \\  verify   Verify current workspace state
        \\  packs    Manage knowledge packs (list, inspect, mount, unmount)
        \\  learn    Feedback/distillation surface (candidates, show, export)
        \\  tui      Interactive Ghost Console TUI (same as default)
        \\  status   Show engine availability/status
        \\  doctor   Run read-only environment diagnostics
        \\  autopsy  Project Autopsy pass (explicit scan only)
        \\  debug    Advanced debug commands
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
