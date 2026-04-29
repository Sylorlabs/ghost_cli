const std = @import("std");
const state = @import("state.zig");
const render = @import("render.zig");
const input = @import("input.zig");
const slash = @import("slash.zig");
const stats = @import("stats.zig");
const runner = @import("../engine/runner.zig");
const json_contracts = @import("../engine/json_contracts.zig");
const terminal_render = @import("../render/terminal.zig");
const doctor = @import("../commands/doctor.zig");
const autopsy = @import("../commands/autopsy.zig");

pub const SlashKind = slash.SlashKind;
pub const SlashCommand = slash.SlashCommand;

pub const ColorMode = enum {
    auto,
    always,
    never,
};

pub const RunOptions = struct {
    reasoning: ?json_contracts.ReasoningLevel = null,
    context_artifact: ?[]const u8 = null,
    debug: bool = false,
    color: ColorMode = .auto,
    compact: bool = false,
    version: []const u8,
    engine_root_label: ?[]const u8 = null,
};

pub fn parseSlashCommand(text: []const u8) SlashCommand {
    return slash.parse(text);
}

pub fn shouldSubmitToEngine(text: []const u8) bool {
    return slash.shouldSubmitToEngine(text);
}

pub fn run(allocator: std.mem.Allocator, engine_root: ?[]const u8, options: RunOptions) !void {
    if (!input.isTty()) {
        try render.renderNonTty(std.io.getStdErr().writer());
        return;
    }

    const color_enabled = try colorEnabled(allocator, options.color);
    const style = render.Style{ .color = color_enabled };

    var s = state.SessionState.init(allocator, options.version, options.engine_root_label, options.compact);
    defer s.deinit();

    if (options.reasoning) |r| s.reasoning = r;
    if (options.context_artifact) |c| s.context_artifact = try allocator.dupe(u8, c);
    s.debug = options.debug;

    const stdin = std.io.getStdIn();
    const stdout = std.io.getStdOut();
    const writer = stdout.writer();

    var raw_mode = try input.RawMode.enable();
    defer raw_mode.disable();

    try render.initTerminal(writer, style);
    defer render.deinitTerminal(writer) catch {};

    while (true) {
        s.last_ram_bytes = stats.getCliRamRss();
        try render.renderFrame(writer, &s, style);

        const key = try input.readKey(stdin.reader());
        switch (key) {
            .ctrl => |c| {
                switch (c) {
                    'C' => break,
                    'R' => s.cycleReasoning(),
                    'D' => {
                        s.debug = !s.debug;
                        s.last_command_status = if (s.debug) "debug on" else "debug off";
                    },
                    'L' => {
                        s.clearHistory();
                        try render.clearHistoryArea(writer);
                    },
                    else => {},
                }
            },
            .esc => break,
            .enter => {
                if (s.current_input.items.len == 0) continue;

                const cmd_text = try allocator.dupe(u8, s.current_input.items);
                defer allocator.free(cmd_text);
                s.current_input.clearRetainingCapacity();

                if (try handleSlash(allocator, engine_root, &s, cmd_text, writer, style)) |should_quit| {
                    if (should_quit) break;
                    continue;
                }

                try handleSubmit(allocator, engine_root, &s, cmd_text, writer, style);
            },
            .backspace => {
                if (s.current_input.items.len > 0) {
                    _ = s.current_input.pop();
                }
            },
            .char => |c| {
                if (s.current_input.items.len == 0 and c == 'q') break;
                try s.current_input.append(c);
            },
            else => {},
        }
    }
}

fn colorEnabled(allocator: std.mem.Allocator, mode: ColorMode) !bool {
    return switch (mode) {
        .always => true,
        .never => false,
        .auto => blk: {
            const no_color = std.process.getEnvVarOwned(allocator, "NO_COLOR") catch |err| switch (err) {
                error.EnvironmentVariableNotFound => break :blk true,
                else => return err,
            };
            allocator.free(no_color);
            break :blk false;
        },
    };
}

fn handleSlash(allocator: std.mem.Allocator, engine_root: ?[]const u8, s: *state.SessionState, text: []const u8, writer: anytype, style: render.Style) !?bool {
    const command = parseSlashCommand(text);
    switch (command.kind) {
        .none => return null,
        .quit => return true,
        .help => {
            try render.renderHelp(writer, style);
            s.last_command_status = "help";
        },
        .status => {
            try render.renderStatus(writer, s, style);
            s.last_command_status = "status";
        },
        .clear => {
            s.clearHistory();
            try render.clearHistoryArea(writer);
        },
        .reasoning => {
            const level_str = command.arg orelse "";
            if (std.meta.stringToEnum(json_contracts.ReasoningLevel, level_str)) |level| {
                s.reasoning = level;
                s.last_command_status = "reasoning changed";
                try render.renderCommandMessage(writer, style, "reasoning={s}", .{level.toStr()});
            } else {
                s.last_command_status = "invalid reasoning";
                try render.renderErrorMessage(writer, style, "Invalid reasoning level: {s}. Use quick|balanced|deep|max", .{level_str});
            }
        },
        .debug => {
            const setting = command.arg orelse "";
            if (std.mem.eql(u8, setting, "on")) s.debug = true else if (std.mem.eql(u8, setting, "off")) s.debug = false else s.debug = !s.debug;
            s.last_command_status = if (s.debug) "debug on" else "debug off";
            try render.renderCommandMessage(writer, style, "debug={s}", .{if (s.debug) "on" else "off"});
        },
        .json => {
            const setting = command.arg orelse "";
            if (std.mem.eql(u8, setting, "on")) s.json_mode = true else if (std.mem.eql(u8, setting, "off")) s.json_mode = false else s.json_mode = !s.json_mode;
            s.last_command_status = if (s.json_mode) "json on" else "json off";
            try render.renderCommandMessage(writer, style, "json={s}", .{if (s.json_mode) "on" else "off"});
        },
        .doctor => {
            s.last_command_status = "doctor requested";
            try render.renderCommandMessage(writer, style, "doctor: explicit read-only diagnostics", .{});
            try doctor.execute(allocator, engine_root, .{
                .json = false,
                .debug = s.debug,
                .report = false,
                .full = false,
                .run_build_check = false,
                .version = s.version,
            });
        },
        .autopsy => {
            const path = command.arg orelse "";
            if (path.len == 0) {
                s.last_command_status = "autopsy path required";
                try render.renderErrorMessage(writer, style, "/autopsy requires an explicit path", .{});
            } else {
                s.last_command_status = "autopsy requested";
                try render.renderCommandMessage(writer, style, "autopsy: explicit scan: {s}", .{path});
                try autopsy.execute(allocator, engine_root, .{ .path = path, .json = false, .debug = s.debug });
            }
        },
        .context => {
            const path = command.arg orelse "";
            if (path.len == 0) {
                s.last_command_status = "context path required";
                try render.renderErrorMessage(writer, style, "/context requires a path", .{});
            } else {
                if (s.context_artifact) |ca| allocator.free(ca);
                s.context_artifact = try allocator.dupe(u8, path);
                s.last_command_status = "context changed";
                try render.renderCommandMessage(writer, style, "context={s}", .{path});
            }
        },
        .unknown => {
            s.last_command_status = "unknown slash command";
            try render.renderInvalidSlashCommand(writer, style, command.arg orelse text);
        },
    }
    return false;
}

fn handleSubmit(allocator: std.mem.Allocator, engine_root: ?[]const u8, s: *state.SessionState, cmd_text: []const u8, writer: anytype, style: render.Style) !void {
    const start_time = std.time.milliTimestamp();

    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const aa = arena.allocator();

    var argv = std.ArrayList([]const u8).init(aa);
    try argv.append("chat");
    try argv.append("--message");
    try argv.append(cmd_text);

    var buf: [64]u8 = undefined;
    const reasoning_arg = try std.fmt.bufPrint(&buf, "--reasoning={s}", .{s.reasoning.toStr()});
    try argv.append(try aa.dupe(u8, reasoning_arg));

    if (s.context_artifact) |art| {
        try argv.append("--context-artifact");
        try argv.append(art);
    }

    try argv.append("--render=json");

    const res = runner.run(allocator, .{
        .engine_root = engine_root,
        .binary = .ghost_task_operator,
        .argv = argv.items,
        .json = true,
        .debug = s.debug,
    }) catch |err| {
        try render.renderErrorMessage(writer, style, "Failed to run engine: {}", .{err});
        return;
    };
    defer res.deinit();

    const elapsed = @as(u64, @intCast(std.time.milliTimestamp() - start_time));

    var rendered_buf = std.ArrayList(u8).init(allocator);
    defer rendered_buf.deinit();

    var json_ok = false;

    if (s.json_mode) {
        try rendered_buf.appendSlice(res.stdout);
        json_ok = true;
    } else if (json_contracts.parseEngineJson(allocator, res.stdout)) |parsed| {
        // defer parsed.deinit(); // We'd need to copy the response if we deinit here
        // For now, let's just render it into our buffer
        s.last_counters = json_contracts.renderCounters(parsed.value);
        s.recordResponseState(parsed.value);
        if (s.debug) try terminal_render.printDebugFieldDetection(rendered_buf.writer(), parsed.value);
        try terminal_render.printEngineOutput(rendered_buf.writer(), parsed.value);
        json_ok = true;
        parsed.deinit();
    } else |_| {
        try rendered_buf.appendSlice(res.stdout);
        if (res.stderr.len > 0) {
            try rendered_buf.appendSlice("\nStderr:\n");
            try rendered_buf.appendSlice(res.stderr);
        }
    }

    const turn = state.Turn{
        .index = s.history.items.len + 1,
        .input = try allocator.dupe(u8, cmd_text),
        .reasoning = s.reasoning,
        .context_artifact = if (s.context_artifact) |ca| try allocator.dupe(u8, ca) else null,
        .response = null, // TODO: store response if needed
        .raw_output = try allocator.dupe(u8, res.stdout),
        .rendered_output = try rendered_buf.toOwnedSlice(),
        .elapsed_ms = elapsed,
        .input_runes = stats.countRunes(cmd_text),
        .output_runes = stats.countRunes(rendered_buf.items),
        .json_ok = json_ok,
    };

    try s.history.append(turn);
    s.last_command_status = if (res.exit_code == 0) "engine response" else "engine error";
    try render.renderTurn(writer, turn, style);
}
