const std = @import("std");
const runner = @import("../engine/runner.zig");
const json_contracts = @import("../engine/json_contracts.zig");
const terminal = @import("../render/terminal.zig");

pub const PacksOptions = struct {
    subcommand: []const u8,
    pack_id: ?[]const u8 = null,
    version: ?[]const u8 = null,
    manifest: ?[]const u8 = null,
    all_mounted: bool = false,
    project_shard: ?[]const u8 = null,
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
    } else if (std.mem.eql(u8, options.subcommand, "validate-autopsy-guidance")) {
        try executeValidateAutopsyGuidance(allocator, engine_root, options);
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
        try std.io.getStdOut().writer().writeAll(res.stdout);
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
        try std.io.getStdOut().writer().writeAll(res.stdout);
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

fn executeValidateAutopsyGuidance(allocator: std.mem.Allocator, engine_root: ?[]const u8, options: PacksOptions) !void {
    if (options.manifest == null and options.pack_id == null and !options.all_mounted) {
        std.debug.print("\x1b[31m[!] Error:\x1b[0m Usage: ghost packs validate-autopsy-guidance (--manifest=<path> | --pack-id=<id> --version=<v> | --all-mounted --project-shard=<id>) [--json]\n", .{});
        std.process.exit(1);
    }
    if (options.pack_id != null and options.version == null) {
        std.debug.print("\x1b[31m[!] Error:\x1b[0m --version is required with --pack-id for validate-autopsy-guidance\n", .{});
        std.process.exit(1);
    }
    if (options.all_mounted and options.project_shard == null) {
        std.debug.print("\x1b[31m[!] Error:\x1b[0m --project-shard is required with --all-mounted for validate-autopsy-guidance\n", .{});
        std.process.exit(1);
    }

    var argv = std.ArrayList([]const u8).init(allocator);
    defer argv.deinit();
    var owned_args = std.ArrayList([]u8).init(allocator);
    defer {
        for (owned_args.items) |arg| allocator.free(arg);
        owned_args.deinit();
    }

    try argv.append("validate-autopsy-guidance");
    if (options.manifest) |manifest| {
        const arg = try std.fmt.allocPrint(allocator, "--manifest={s}", .{manifest});
        try owned_args.append(arg);
        try argv.append(arg);
    }
    if (options.pack_id) |pack_id| {
        const arg = try std.fmt.allocPrint(allocator, "--pack-id={s}", .{pack_id});
        try owned_args.append(arg);
        try argv.append(arg);
    }
    if (options.version) |version| {
        const arg = try std.fmt.allocPrint(allocator, "--version={s}", .{version});
        try owned_args.append(arg);
        try argv.append(arg);
    }
    if (options.all_mounted) {
        try argv.append("--all-mounted");
    }
    if (options.project_shard) |project_shard| {
        const arg = try std.fmt.allocPrint(allocator, "--project-shard={s}", .{project_shard});
        try owned_args.append(arg);
        try argv.append(arg);
    }
    if (options.json) {
        try argv.append("--json");
    }

    const res = try runner.run(allocator, .{
        .engine_root = engine_root,
        .binary = .ghost_knowledge_pack,
        .argv = argv.items,
        .json = true,
        .debug = options.debug,
    });
    defer res.deinit();

    if (res.stdout.len > 0) try std.io.getStdOut().writer().writeAll(res.stdout);
    if (res.stderr.len > 0) try std.io.getStdErr().writer().writeAll(res.stderr);
    if (res.exit_code != 0) std.process.exit(res.exit_code);
}
