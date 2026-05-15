const std = @import("std");
const locator = @import("../engine/locator.zig");
const process = @import("../engine/process.zig");

pub const Options = struct {
    json: bool = false,
    debug: bool = false,
};

const usage =
    \\Usage:
    \\  ghost gemma weights inspect [--path <model.gguf>] [--json] [--debug] [--tensor-prefix <prefix>] [--limit <n>]
    \\  ghost gemma matmul calibrate [--path <model.gguf>] [--tensor <name>] [--rows <n>] [--seed <u64>] [--json] [--debug]
    \\  ghost gemma inference smoke --text <text> [--path <model.gguf>] [--top-k <n>] [--embedding-len <n>] [--session-id <u64>] [--json] [--debug]
    \\  ghost gemma inference plan [--path <model.gguf>] [--json] [--debug] [--limit <n>]
    \\  ghost gemma agent route --intent <query|etch|prove|converse> --subject <text> [--hint <text>...] [--confidence <low|medium|high>] [--needs-ghost <true|false>] [--json] [--debug]
    \\
;

pub fn printHelp(writer: anytype) !void {
    try writer.writeAll(
        \\gemma
        \\
        \\Usage:
        \\  ghost gemma weights inspect [--path <model.gguf>] [--json] [--debug] [--tensor-prefix <prefix>] [--limit <n>]
        \\  ghost gemma matmul calibrate [--path <model.gguf>] [--tensor <name>] [--rows <n>] [--seed <u64>] [--json] [--debug]
        \\  ghost gemma inference smoke --text <text> [--path <model.gguf>] [--top-k <n>] [--embedding-len <n>] [--session-id <u64>] [--json] [--debug]
        \\  ghost gemma inference plan [--path <model.gguf>] [--json] [--debug] [--limit <n>]
        \\  ghost gemma agent route --intent <query|etch|prove|converse> --subject <text> [--hint <text>...] [--confidence <low|medium|high>] [--needs-ghost <true|false>] [--json] [--debug]
        \\
        \\Read Ghost-native Gemma GGUF metadata and run deterministic numeric
        \\calibration, rune inference smoke, Vulkan forward schedule inspection,
        \\and strict agent routing through explicit engine surfaces.
        \\
        \\Safety:
        \\  Explicit invocation only.
        \\  READ-ONLY.
        \\  NON-AUTHORIZING.
        \\  WEIGHT METADATA ONLY.
        \\  Matmul calibration is numeric Q8_0 validation only; it is not inference.
        \\  Inference smoke is a phase harness; it is not full model inference.
        \\  Inference plan is scheduler inspection; it is not numeric output.
        \\  Agent routing is strict and does not use hidden fallbacks.
        \\  No tokenizer path is started.
        \\  No KV cache is allocated.
        \\  No meaning matrix mutation occurs.
        \\  `--json` preserves raw engine stdout exactly.
        \\
    );
}

pub fn printHelpForArgs(writer: anytype, args: []const []const u8) !void {
    if (args.len == 0) return printHelp(writer);
    if (std.mem.eql(u8, args[0], "weights")) return printHelp(writer);
    if (std.mem.eql(u8, args[0], "matmul")) return printHelp(writer);
    if (std.mem.eql(u8, args[0], "inference")) return printHelp(writer);
    if (std.mem.eql(u8, args[0], "agent")) return printHelp(writer);
    return printHelp(writer);
}

pub fn executeFromArgs(
    allocator: std.mem.Allocator,
    engine_root: ?[]const u8,
    args: []const []const u8,
    options: Options,
) !void {
    if (args.len < 2 or !isKnownCommand(args[0], args[1])) {
        try std.io.getStdErr().writer().writeAll(usage);
        std.process.exit(1);
    }

    const bin_path = locator.findEngineBinary(allocator, engine_root, .ghost_gemma) catch |err| {
        try locator.printLocatorError(std.io.getStdErr().writer(), .ghost_gemma, engine_root, err);
        std.process.exit(1);
    };
    defer allocator.free(bin_path);

    var argv = std.ArrayList([]const u8).init(allocator);
    defer argv.deinit();
    try argv.append(bin_path);
    try argv.append(args[0]);
    try argv.append(args[1]);
    if (options.json) try argv.append("--json");
    for (args[2..]) |arg| try argv.append(arg);

    if (options.debug) {
        try std.io.getStdErr().writer().print("[DEBUG] Engine Binary: {s}\n", .{bin_path});
        try std.io.getStdErr().writer().print("[DEBUG] Command: gemma.{s}.{s}\n", .{ args[0], args[1] });
        try std.io.getStdErr().writer().print("[DEBUG] Engine argv:", .{});
        for (argv.items) |arg| try std.io.getStdErr().writer().print(" {s}", .{arg});
        try std.io.getStdErr().writer().writeByte('\n');
    }

    const result = process.runEngineCommand(allocator, argv.items) catch |err| {
        try std.io.getStdErr().writer().print("Error: failed to execute gemma command: {s}\n", .{@errorName(err)});
        std.process.exit(1);
    };
    defer {
        allocator.free(result.stdout);
        allocator.free(result.stderr);
    }

    if (options.debug) try std.io.getStdErr().writer().print("[DEBUG] Exit Code: {d}\n", .{result.exit_code});
    if (result.stdout.len > 0) try std.io.getStdOut().writer().writeAll(result.stdout);
    if (result.stderr.len > 0) try std.io.getStdErr().writer().writeAll(result.stderr);
    if (result.exit_code != 0) std.process.exit(result.exit_code);
}

fn isKnownCommand(first: []const u8, second: []const u8) bool {
    return (std.mem.eql(u8, first, "weights") and std.mem.eql(u8, second, "inspect")) or
        (std.mem.eql(u8, first, "matmul") and std.mem.eql(u8, second, "calibrate")) or
        (std.mem.eql(u8, first, "inference") and std.mem.eql(u8, second, "smoke")) or
        (std.mem.eql(u8, first, "inference") and std.mem.eql(u8, second, "plan")) or
        (std.mem.eql(u8, first, "agent") and std.mem.eql(u8, second, "route"));
}
