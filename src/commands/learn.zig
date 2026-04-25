const std = @import("std");
const runner = @import("../engine/runner.zig");
const json_contracts = @import("../engine/json_contracts.zig");
const terminal = @import("../render/terminal.zig");

pub const LearnOptions = struct {
    subcommand: []const u8,
    project_shard: ?[]const u8 = null,
    candidate_id: ?[]const u8 = null,
    pack_id: ?[]const u8 = null,
    version: ?[]const u8 = null,
    approve: bool = false,
    json: bool = false,
    debug: bool = false,
};

pub fn execute(allocator: std.mem.Allocator, engine_root: ?[]const u8, options: LearnOptions) !void {
    if (std.mem.eql(u8, options.subcommand, "candidates")) {
        try executeCandidates(allocator, engine_root, options);
    } else if (std.mem.eql(u8, options.subcommand, "show")) {
        try executeShow(allocator, engine_root, options);
    } else if (std.mem.eql(u8, options.subcommand, "export")) {
        try executeExport(allocator, engine_root, options);
    } else if (std.mem.eql(u8, options.subcommand, "feedback")) {
        std.debug.print("feedback submission TODO: verify engine CLI support\n", .{});
    } else {
        std.debug.print("Unknown learn subcommand: {s}\n", .{options.subcommand});
        std.process.exit(1);
    }
}

fn executeCandidates(allocator: std.mem.Allocator, engine_root: ?[]const u8, options: LearnOptions) !void {
    const shard = options.project_shard orelse {
        std.debug.print("\x1b[31m[!] Error:\x1b[0m --project-shard is required for learn candidates\n", .{});
        std.process.exit(1);
    };

    var argv = std.ArrayList([]const u8).init(allocator);
    defer argv.deinit();

    try argv.append("distill-list");
    try argv.append("--project-shard");
    try argv.append(shard);
    try argv.append("--json");

    const res = try runner.run(allocator, .{
        .engine_root = engine_root,
        .binary = .ghost_knowledge_pack,
        .argv = argv.items,
        .json = true,
        .debug = options.debug,
    });
    defer res.deinit();

    if (options.json) {
        std.debug.print("{s}\n", .{res.stdout});
        return;
    }

    if (res.exit_code != 0) {
        std.process.exit(res.exit_code);
    }

    const parsed = json_contracts.parseCandidateListJson(allocator, res.stdout) catch |err| {
        std.debug.print("\x1b[31m[!] Error:\x1b[0m Failed to parse engine JSON: {}\n", .{err});
        if (options.debug) std.debug.print("\x1b[33mRaw Output:\x1b[0m\n{s}\n", .{res.stdout});
        return;
    };
    defer parsed.deinit();

    try terminal.printCandidateList(std.io.getStdOut().writer(), parsed.value);
}

fn executeShow(allocator: std.mem.Allocator, engine_root: ?[]const u8, options: LearnOptions) !void {
    const shard = options.project_shard orelse {
        std.debug.print("\x1b[31m[!] Error:\x1b[0m --project-shard is required for learn show\n", .{});
        std.process.exit(1);
    };
    const cand_id = options.candidate_id orelse {
        std.debug.print("\x1b[31m[!] Error:\x1b[0m candidate-id is required for learn show\n", .{});
        std.process.exit(1);
    };

    var argv = std.ArrayList([]const u8).init(allocator);
    defer argv.deinit();

    try argv.append("distill-show");
    try argv.append("--project-shard");
    try argv.append(shard);
    try argv.append("--candidate-id");
    try argv.append(cand_id);
    try argv.append("--json");

    const res = try runner.run(allocator, .{
        .engine_root = engine_root,
        .binary = .ghost_knowledge_pack,
        .argv = argv.items,
        .json = true,
        .debug = options.debug,
    });
    defer res.deinit();

    if (options.json) {
        std.debug.print("{s}\n", .{res.stdout});
        return;
    }

    if (res.exit_code != 0) {
        std.process.exit(res.exit_code);
    }

    const parsed = json_contracts.parseCandidateInfoJson(allocator, res.stdout) catch |err| {
        std.debug.print("\x1b[31m[!] Error:\x1b[0m Failed to parse engine JSON: {}\n", .{err});
        if (options.debug) std.debug.print("\x1b[33mRaw Output:\x1b[0m\n{s}\n", .{res.stdout});
        return;
    };
    defer parsed.deinit();

    try terminal.printCandidateDetail(std.io.getStdOut().writer(), parsed.value);
}

fn executeExport(allocator: std.mem.Allocator, engine_root: ?[]const u8, options: LearnOptions) !void {
    const shard = options.project_shard orelse {
        std.debug.print("\x1b[31m[!] Error:\x1b[0m --project-shard is required for learn export\n", .{});
        std.process.exit(1);
    };
    const cand_id = options.candidate_id orelse {
        std.debug.print("\x1b[31m[!] Error:\x1b[0m candidate-id is required for learn export\n", .{});
        std.process.exit(1);
    };
    const pack_id = options.pack_id orelse {
        std.debug.print("\x1b[31m[!] Error:\x1b[0m --pack-id is required for learn export\n", .{});
        std.process.exit(1);
    };
    const version = options.version orelse {
        std.debug.print("\x1b[31m[!] Error:\x1b[0m --version is required for learn export\n", .{});
        std.process.exit(1);
    };

    if (!options.approve) {
        std.debug.print("\x1b[31m[!] Error:\x1b[0m --approve is required to export a candidate to a knowledge pack.\n", .{});
        std.process.exit(1);
    }

    var argv = std.ArrayList([]const u8).init(allocator);
    defer argv.deinit();

    try argv.append("distill-export");
    try argv.append("--project-shard");
    try argv.append(shard);
    try argv.append("--candidate-id");
    try argv.append(cand_id);
    try argv.append("--pack-id");
    try argv.append(pack_id);
    try argv.append("--version");
    try argv.append(version);
    try argv.append("--approve");
    try argv.append("--json");

    const res = try runner.run(allocator, .{
        .engine_root = engine_root,
        .binary = .ghost_knowledge_pack,
        .argv = argv.items,
        .json = true,
        .debug = options.debug,
    });
    defer res.deinit();

    if (options.json) {
        std.debug.print("{s}\n", .{res.stdout});
        return;
    }

    if (res.exit_code != 0) {
        std.process.exit(res.exit_code);
    }

    const parsed = json_contracts.parseExportResultJson(allocator, res.stdout) catch |err| {
        std.debug.print("\x1b[31m[!] Error:\x1b[0m Failed to parse engine JSON: {}\n", .{err});
        if (options.debug) std.debug.print("\x1b[33mRaw Output:\x1b[0m\n{s}\n", .{res.stdout});
        return;
    };
    defer parsed.deinit();

    try terminal.printExportResult(std.io.getStdOut().writer(), parsed.value);
}
