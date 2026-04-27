const std = @import("std");
const state = @import("state.zig");
const render = @import("render.zig");
const input = @import("input.zig");
const stats = @import("stats.zig");
const runner = @import("../engine/runner.zig");
const json_contracts = @import("../engine/json_contracts.zig");
const terminal_render = @import("../render/terminal.zig");

pub fn run(allocator: std.mem.Allocator, engine_root: ?[]const u8, initial_reasoning: ?json_contracts.ReasoningLevel, initial_context: ?[]const u8, initial_debug: bool) !void {
    var s = state.SessionState.init(allocator);
    defer s.deinit();

    if (initial_reasoning) |r| s.reasoning = r;
    if (initial_context) |c| s.context_artifact = try allocator.dupe(u8, c);
    s.debug = initial_debug;

    const stdin = std.io.getStdIn();
    const stdout = std.io.getStdOut();
    const writer = stdout.writer();

    var raw_mode = try input.RawMode.enable();
    defer raw_mode.disable();

    try render.initTerminal(writer);
    defer render.deinitTerminal(writer) catch {};

    while (true) {
        s.last_ram_bytes = stats.getCliRamRss();
        try render.render(writer, &s);

        const key = try input.readKey(stdin.reader());
        switch (key) {
            .ctrl => |c| {
                switch (c) {
                    'C' => break,
                    'R' => s.cycleReasoning(),
                    'D' => s.debug = !s.debug,
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

                if (std.mem.eql(u8, cmd_text, "/quit")) break;
                if (std.mem.eql(u8, cmd_text, "/help")) {
                    try writer.writeAll("\n\x1b[36m[HELP] Commands:\x1b[0m /quit, /help, /status, /reasoning <level>, /context <path>\n");
                    try writer.writeAll("\x1b[36m[HELP] Keys:\x1b[0m Ctrl+C (quit), Ctrl+R (cycle reasoning), Ctrl+D (debug), Ctrl+L (clear history)\n");
                    continue;
                }
                if (std.mem.startsWith(u8, cmd_text, "/reasoning ")) {
                    const level_str = cmd_text[11..];
                    if (std.meta.stringToEnum(json_contracts.ReasoningLevel, level_str)) |level| {
                        s.reasoning = level;
                        try writer.print("\n\x1b[32m[INFO] Reasoning set to: {s}\x1b[0m\n", .{@tagName(level)});
                    } else {
                        try writer.print("\n\x1b[31m[ERROR] Invalid reasoning level: {s}. Use quick|balanced|deep|max\x1b[0m\n", .{level_str});
                    }
                    continue;
                }
                if (std.mem.startsWith(u8, cmd_text, "/context ")) {
                    const path = cmd_text[9..];
                    if (s.context_artifact) |ca| allocator.free(ca);
                    s.context_artifact = try allocator.dupe(u8, path);
                    try writer.print("\n\x1b[32m[INFO] Context artifact set to: {s}\x1b[0m\n", .{path});
                    continue;
                }
                if (std.mem.eql(u8, cmd_text, "/status")) {
                    // This is a bit tricky to run in TUI as it might scroll the region
                    // But we can just print it.
                    try writer.writeAll("\n\x1b[36m--- TUI Session Status ---\x1b[0m\n");
                    try writer.print("Turns: {d}\n", .{s.history.items.len});
                    try writer.print("Reasoning: {s}\n", .{@tagName(s.reasoning)});
                    try writer.print("Debug: {s}\n", .{if (s.debug) "on" else "off"});
                    continue;
                }

                try handleSubmit(allocator, engine_root, &s, cmd_text, writer);
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

fn handleSubmit(allocator: std.mem.Allocator, engine_root: ?[]const u8, s: *state.SessionState, cmd_text: []const u8, writer: anytype) !void {
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
        try writer.print("\n[ERROR] Failed to run engine: {}\n", .{err});
        return;
    };
    defer res.deinit();

    const elapsed = @as(u64, @intCast(std.time.milliTimestamp() - start_time));

    var rendered_buf = std.ArrayList(u8).init(allocator);
    defer rendered_buf.deinit();

    var json_ok = false;

    if (json_contracts.parseEngineJson(allocator, res.stdout)) |parsed| {
        // defer parsed.deinit(); // We'd need to copy the response if we deinit here
        // For now, let's just render it into our buffer
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
    try render.renderTurn(writer, turn);
}
