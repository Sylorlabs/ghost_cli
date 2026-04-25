const std = @import("std");
const runner = @import("../engine/runner.zig");
const json_contracts = @import("../engine/json_contracts.zig");
const terminal = @import("../render/terminal.zig");

pub const PacksOptions = struct {
    subcommand: []const u8,
    pack_id: ?[]const u8 = null,
    version: ?[]const u8 = null,
    json: bool = false,
    debug: bool = false,
};

pub fn execute(allocator: std.mem.Allocator, engine_root: ?[]const u8, options: PacksOptions) !void {
    if (std.mem.eql(u8, options.subcommand, "list")) {
        try executeList(allocator, engine_root, options);
    } else if (std.mem.eql(u8, options.subcommand, "inspect")) {
        try executeInspect(allocator, engine_root, options);
    } else if (std.mem.eql(u8, options.subcommand, "mount")) {
        try executeMount(allocator, engine_root, options);
    } else if (std.mem.eql(u8, options.subcommand, "unmount")) {
        try executeUnmount(allocator, engine_root, options);
    } else {
        std.debug.print("Unknown packs subcommand: {s}\n", .{options.subcommand});
        std.process.exit(1);
    }
}

fn executeList(allocator: std.mem.Allocator, engine_root: ?[]const u8, options: PacksOptions) !void {
    const res = try runner.run(allocator, .{
        .engine_root = engine_root,
        .binary = .ghost_knowledge_pack,
        .argv = &[_][]const u8{ "list", "--json" },
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

    const parsed = json_contracts.parsePackListJson(allocator, res.stdout) catch |err| {
        std.debug.print("\x1b[31m[!] Error:\x1b[0m Failed to parse engine JSON: {}\n", .{err});
        std.debug.print("\x1b[33mRaw Output:\x1b[0m\n{s}\n", .{res.stdout});
        return;
    };
    defer parsed.deinit();

    try terminal.printPackList(std.io.getStdOut().writer(), parsed.value);
}

fn executeInspect(allocator: std.mem.Allocator, engine_root: ?[]const u8, options: PacksOptions) !void {
    const pack_id = options.pack_id orelse {
        std.debug.print("\x1b[31m[!] Error:\x1b[0m Usage: ghost packs inspect <pack-id>\n", .{});
        std.process.exit(1);
    };

    var argv = std.ArrayList([]const u8).init(allocator);
    defer argv.deinit();

    try argv.append("inspect");
    try argv.append(pack_id);
    try argv.append("--json");

    if (options.version) |v| {
        try argv.append("--version");
        try argv.append(v);
    }

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

    const parsed = json_contracts.parsePackInfoJson(allocator, res.stdout) catch |err| {
        std.debug.print("\x1b[31m[!] Error:\x1b[0m Failed to parse engine JSON: {}\n", .{err});
        std.debug.print("\x1b[33mRaw Output:\x1b[0m\n{s}\n", .{res.stdout});
        return;
    };
    defer parsed.deinit();

    try terminal.printPackInfo(std.io.getStdOut().writer(), parsed.value);
}

fn executeMount(allocator: std.mem.Allocator, engine_root: ?[]const u8, options: PacksOptions) !void {
    const pack_id = options.pack_id orelse {
        std.debug.print("\x1b[31m[!] Error:\x1b[0m Usage: ghost packs mount <pack-id>\n", .{});
        std.process.exit(1);
    };

    var argv = std.ArrayList([]const u8).init(allocator);
    defer argv.deinit();

    try argv.append("mount");
    try argv.append(pack_id);

    if (options.version) |v| {
        try argv.append("--version");
        try argv.append(v);
    }

    const res = try runner.run(allocator, .{
        .engine_root = engine_root,
        .binary = .ghost_knowledge_pack,
        .argv = argv.items,
        .debug = options.debug,
    });
    defer res.deinit();

    if (res.exit_code == 0) {
        std.debug.print("Successfully mounted pack '{s}'\n", .{pack_id});
        std.debug.print("Run 'ghost packs list' to see current state.\n", .{});
    } else {
        std.process.exit(res.exit_code);
    }
}

fn executeUnmount(allocator: std.mem.Allocator, engine_root: ?[]const u8, options: PacksOptions) !void {
    const pack_id = options.pack_id orelse {
        std.debug.print("\x1b[31m[!] Error:\x1b[0m Usage: ghost packs unmount <pack-id>\n", .{});
        std.process.exit(1);
    };

    var argv = std.ArrayList([]const u8).init(allocator);
    defer argv.deinit();

    try argv.append("unmount");
    try argv.append(pack_id);

    if (options.version) |v| {
        try argv.append("--version");
        try argv.append(v);
    }

    const res = try runner.run(allocator, .{
        .engine_root = engine_root,
        .binary = .ghost_knowledge_pack,
        .argv = argv.items,
        .debug = options.debug,
    });
    defer res.deinit();

    if (res.exit_code == 0) {
        std.debug.print("Successfully unmounted pack '{s}'\n", .{pack_id});
        std.debug.print("Run 'ghost packs list' to see current state.\n", .{});
    } else {
        std.process.exit(res.exit_code);
    }
}
