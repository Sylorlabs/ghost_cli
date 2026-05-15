const std = @import("std");
const runner = @import("../engine/runner.zig");
const json_contracts = @import("../engine/json_contracts.zig");
const corpus = @import("corpus.zig");

// --- L0 Vibe-Buffer & Triviality Shard ---
fn isTrivial(message: []const u8) bool {
    const trimmed = std.mem.trim(u8, message, " \t\r\n");
    if (trimmed.len < 5) return true;

    var only_math = true;
    var has_digit = false;
    for (trimmed) |c| {
        switch (c) {
            '0'...'9' => has_digit = true,
            '+', '-', '*', '/', ' ', '\t', '(', ')' => {},
            else => {
                only_math = false;
                break;
            },
        }
    }
    return only_math and has_digit;
}

fn evaluateSimpleMath(expr: []const u8) ?i64 {
    var op: u8 = 0;
    var op_idx: usize = 0;
    for (expr, 0..) |c, i| {
        if (c == '+' or c == '-' or c == '*' or c == '/') {
            if (i == 0 and c == '-') continue;
            op = c;
            op_idx = i;
            break;
        }
    }
    if (op == 0) return null;

    const left_str = std.mem.trim(u8, expr[0..op_idx], " \t()");
    const right_str = std.mem.trim(u8, expr[op_idx + 1 ..], " \t()");

    const left = std.fmt.parseInt(i64, left_str, 10) catch return null;
    const right = std.fmt.parseInt(i64, right_str, 10) catch return null;

    return switch (op) {
        '+' => left + right,
        '-' => left - right,
        '*' => left * right,
        '/' => if (right != 0) @divTrunc(left, right) else null,
        else => null,
    };
}

fn scalarResolver(message: []const u8, is_json: bool) !void {
    const stdout = std.io.getStdOut().writer();

    var math_res_buf: [64]u8 = undefined;
    var result_str: []const u8 = "Trivial Filler";
    if (evaluateSimpleMath(message)) |val| {
        result_str = try std.fmt.bufPrint(&math_res_buf, "{d}", .{val});
    } else {
        result_str = message;
    }

    if (is_json) {
        try stdout.print(
            \\{{"type": "triviality_shard", "rank": 1, "input": "{s}", "result": "{s}", "message": "Indexed into omniprogress_lattice as Rank-1 Truth"}}
            \\
        , .{ message, result_str });
    } else {
        try stdout.print("[L0 Vibe-Buffer] Common Sense Gateway activated.\n", .{});
        try stdout.print("[Standard Reality] Bypassing Dark Space search.\n", .{});
        try stdout.print("[Scalar Resolver] '{s}' => {s}\n", .{ message, result_str });
        try stdout.print("[Triviality Shard] Indexed into omniprogress_lattice as Rank-1 Truth.\n", .{});
    }
}
// -----------------------------------------

pub const Options = struct {
    message: ?[]const u8 = null,
    project_shard: ?[]const u8 = null,
    extra_args: []const []const u8 = &.{},
    json: bool = false,
    debug: bool = false,
};

pub fn execute(allocator: std.mem.Allocator, engine_root: ?[]const u8, options: Options) !void {
    if (options.message) |message| {
        if (isTrivial(message)) {
            try scalarResolver(message, options.json);
            return;
        }
    }

    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const aa = arena.allocator();

    var argv = std.ArrayList([]const u8).init(aa);
    try argv.append("invent");

    if (options.project_shard) |shard| {
        try argv.append(try std.fmt.allocPrint(aa, "--project-shard={s}", .{shard}));
    }
    if (options.message) |message| {
        try argv.append(try std.fmt.allocPrint(aa, "--message={s}", .{message}));
    }
    for (options.extra_args) |arg| {
        try argv.append(arg);
    }
    if (options.json) try argv.append("--render=json");

    const res = try runner.run(allocator, .{
        .engine_root = engine_root,
        .binary = .ghost_invent,
        .argv = argv.items,
        .json = options.json,
        .debug = options.debug,
    });
    defer res.deinit();

    if (res.stdout.len > 0) try std.io.getStdOut().writer().writeAll(res.stdout);
    if (res.stderr.len > 0) try std.io.getStdErr().writer().writeAll(res.stderr);
    if (res.exit_code != 0) std.process.exit(res.exit_code);

    if (!options.json and options.debug) {
        _ = json_contracts;
        _ = corpus;
    }
}

pub fn printHelp(writer: anytype) !void {
    try writer.writeAll(
        \\Usage: ghost invent --project-shard=<name> --message="..."
        \\
        \\Runs architectural synthesis through the live corpus, Cross-Domain Projector,
        \\and Medic Loop. This bypasses corpus.ask extraction and parameter-match
        \\gates; ordinary CLI/GIP math and logic prompts route through the Z3 path.
        \\Output is non-authorizing by design.
        \\
        \\Options:
        \\  --project-shard=<s>    Project corpus shard to load
        \\  --message="..."        Synthesis target prompt
        \\  --prompt="..."         Alias accepted by the engine
        \\  --assimilate           Mark run as assimilating already-ingested live corpus
        \\  --hypothesis-source-file=<path>
        \\                         Override projected source for sandbox proof runs
        \\  --hypothesis-sandbox=<path>
        \\                         Absolute sandbox root; default is /tmp/ghost_sandbox
        \\  --json                 Emit raw engine JSON
        \\  --debug                Show engine invocation diagnostics
        \\
    );
}
