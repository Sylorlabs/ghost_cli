const std = @import("std");
const state = @import("state.zig");
const json_contracts = @import("../engine/json_contracts.zig");

pub const Conversation = struct {
    name: []const u8,
    turns: []state.Turn,
};

pub fn getConversationDir(allocator: std.mem.Allocator) ![]u8 {
    const home = std.posix.getenv("HOME") orelse return error.HomeNotFound;
    const path = try std.fs.path.join(allocator, &.{ home, ".config", "ghost", "conversations" });
    std.fs.cwd().makePath(path) catch {};
    return path;
}

pub fn saveConversation(allocator: std.mem.Allocator, name: []const u8, turns: []const state.Turn) !void {
    const dir_path = try getConversationDir(allocator);
    defer allocator.free(dir_path);

    const file_name = try std.fmt.allocPrint(allocator, "{s}.json", .{name});
    defer allocator.free(file_name);

    const full_path = try std.fs.path.join(allocator, &.{ dir_path, file_name });
    defer allocator.free(full_path);

    var file = try std.fs.createFileAbsolute(full_path, .{});
    defer file.close();

    var out = std.ArrayList(u8).init(allocator);
    defer out.deinit();

    try std.json.stringify(.{
        .name = name,
        .turns = turns,
    }, .{}, out.writer());

    try file.writeAll(out.items);
}

pub fn listConversations(allocator: std.mem.Allocator) ![][]u8 {
    const dir_path = try getConversationDir(allocator);
    defer allocator.free(dir_path);

    var dir = try std.fs.openDirAbsolute(dir_path, .{ .iterate = true });
    defer dir.close();

    var list = std.ArrayList([]u8).init(allocator);
    errdefer {
        for (list.items) |item| allocator.free(item);
        list.deinit();
    }

    var it = dir.iterate();
    while (try it.next()) |entry| {
        if (entry.kind == .file and std.mem.endsWith(u8, entry.name, ".json")) {
            const name = entry.name[0 .. entry.name.len - 5];
            try list.append(try allocator.dupe(u8, name));
        }
    }

    return list.toOwnedSlice();
}

pub fn loadConversation(allocator: std.mem.Allocator, name: []const u8) !Conversation {
    const dir_path = try getConversationDir(allocator);
    defer allocator.free(dir_path);

    const file_name = try std.fmt.allocPrint(allocator, "{s}.json", .{name});
    defer allocator.free(file_name);

    const full_path = try std.fs.path.join(allocator, &.{ dir_path, file_name });
    defer allocator.free(full_path);

    const file = try std.fs.openFileAbsolute(full_path, .{});
    defer file.close();

    const bytes = try file.readToEndAlloc(allocator, 10 * 1024 * 1024);
    defer allocator.free(bytes);

    const parsed = try std.json.parseFromSlice(Conversation, allocator, bytes, .{ .ignore_unknown_fields = true });
    // Note: We leak the parsed value because turns need to stay in SessionState
    // and we'll dupe them into it.
    return parsed.value;
}
