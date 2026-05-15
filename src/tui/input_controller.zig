const std = @import("std");
const state = @import("state.zig");

const ConstraintCodebook = struct {
    const names = [_][]const u8{
        "LOCK_ORDER",
        "NO_ALLOC",
        "BOUNDS_CHECK",
    };

    const map = std.StaticStringMap(usize).initComptime(.{
        .{ "LOCK_ORDER", 0 },
        .{ "NO_ALLOC", 1 },
        .{ "BOUNDS_CHECK", 2 },
    });
};

const allowed_extensions = [_][]const u8{ ".cpp", ".h", ".zig", ".rs" };
const max_walk_depth: usize = 6;

pub fn refreshConstraintAutocomplete(s: *state.SessionState) void {
    const input = s.current_input.items;
    if (findLatestConstraintTrigger(input)) |trigger| {
        s.constraint_autocomplete.active = true;
        s.constraint_autocomplete.trigger_start = trigger.trigger_start;
        s.constraint_autocomplete.token_start = trigger.token_start;
        const count = matchingConstraintCount(currentConstraintToken(s));
        if (count == 0) {
            s.constraint_autocomplete.selected_index = 0;
        } else if (s.constraint_autocomplete.selected_index >= count) {
            s.constraint_autocomplete.selected_index = count - 1;
        }
    } else {
        s.constraint_autocomplete = .{};
    }
}

pub fn constraintCandidateCount(s: *const state.SessionState) usize {
    if (!s.constraint_autocomplete.active) return 0;
    return matchingConstraintCount(currentConstraintTokenConst(s));
}

pub fn constraintCandidateAt(s: *const state.SessionState, visible_index: usize) ?[]const u8 {
    if (!s.constraint_autocomplete.active) return null;
    return matchingConstraintAt(currentConstraintTokenConst(s), visible_index);
}

pub fn completeCurrentToken(s: *state.SessionState) !bool {
    refreshConstraintAutocomplete(s);
    if (s.constraint_autocomplete.active) {
        const selected = s.constraint_autocomplete.selected_index;
        const candidate = constraintCandidateAt(s, selected) orelse constraintCandidateAt(s, 0) orelse return false;
        s.current_input.shrinkRetainingCapacity(s.constraint_autocomplete.token_start);
        try s.current_input.appendSlice(candidate);
        s.constraint_autocomplete = .{};
        s.file_target_finder.clear();
        return true;
    }

    if (s.file_target_finder.active and s.file_target_finder.count > 0) {
        const selected = @min(s.file_target_finder.selected_index, s.file_target_finder.count - 1);
        const target = s.file_target_finder.targets[selected].text();
        if (s.current_input.items.len != 0 and !std.ascii.isWhitespace(s.current_input.items[s.current_input.items.len - 1])) {
            try s.current_input.append(' ');
        }
        try s.current_input.appendSlice(target);
        s.file_target_finder.clear();
        s.constraint_autocomplete = .{};
        return true;
    }

    return false;
}

pub fn moveSelection(s: *state.SessionState, delta: isize) void {
    if (s.file_target_finder.active and s.file_target_finder.count > 0) {
        s.file_target_finder.selected_index = steppedIndex(s.file_target_finder.selected_index, s.file_target_finder.count, delta);
        return;
    }

    refreshConstraintAutocomplete(s);
    const count = constraintCandidateCount(s);
    if (count > 0) {
        s.constraint_autocomplete.selected_index = steppedIndex(s.constraint_autocomplete.selected_index, count, delta);
    }
}

pub fn activateFileTargetFinder(s: *state.SessionState) !void {
    s.file_target_finder.clear();
    s.file_target_finder.active = true;
    try scanDirIntoFinder(std.fs.cwd(), ".", 0, &s.file_target_finder);
}

fn steppedIndex(index: usize, count: usize, delta: isize) usize {
    if (count == 0) return 0;
    if (delta < 0) return if (index == 0) count - 1 else index - 1;
    return (index + 1) % count;
}

const Trigger = struct {
    trigger_start: usize,
    token_start: usize,
};

fn findLatestConstraintTrigger(input: []const u8) ?Trigger {
    var latest: ?Trigger = null;
    var i: usize = 0;
    while (i < input.len) : (i += 1) {
        if (matchesWordTrigger(input, i, "WITH")) {
            latest = .{ .trigger_start = i, .token_start = i + "WITH".len };
        } else if (matchesWordTrigger(input, i, "AND")) {
            latest = .{ .trigger_start = i, .token_start = i + "AND".len };
        }
    }

    var trigger = latest orelse return null;
    if (trigger.token_start >= input.len or !std.ascii.isWhitespace(input[trigger.token_start])) return null;
    while (trigger.token_start < input.len and std.ascii.isWhitespace(input[trigger.token_start])) {
        trigger.token_start += 1;
    }
    if (trigger.token_start > input.len) return null;
    return trigger;
}

fn matchesWordTrigger(input: []const u8, index: usize, word: []const u8) bool {
    if (index + word.len > input.len) return false;
    if (index > 0 and !std.ascii.isWhitespace(input[index - 1])) return false;
    if (!std.ascii.eqlIgnoreCase(input[index .. index + word.len], word)) return false;
    if (index + word.len < input.len and !std.ascii.isWhitespace(input[index + word.len])) return false;
    return true;
}

fn currentConstraintToken(s: *const state.SessionState) []const u8 {
    return currentConstraintTokenConst(s);
}

fn currentConstraintTokenConst(s: *const state.SessionState) []const u8 {
    if (!s.constraint_autocomplete.active) return "";
    const input = s.current_input.items;
    if (s.constraint_autocomplete.token_start >= input.len) return "";
    var end = s.constraint_autocomplete.token_start;
    while (end < input.len and !std.ascii.isWhitespace(input[end])) : (end += 1) {}
    return input[s.constraint_autocomplete.token_start..end];
}

fn matchingConstraintCount(token: []const u8) usize {
    var count: usize = 0;
    for (ConstraintCodebook.names) |name| {
        if (matchesConstraint(name, token)) count += 1;
    }
    return count;
}

fn matchingConstraintAt(token: []const u8, visible_index: usize) ?[]const u8 {
    var count: usize = 0;
    for (ConstraintCodebook.names) |name| {
        if (!matchesConstraint(name, token)) continue;
        if (count == visible_index) return name;
        count += 1;
    }
    return null;
}

fn matchesConstraint(name: []const u8, token: []const u8) bool {
    if (ConstraintCodebook.map.get(name) == null) return false;
    if (token.len == 0) return true;
    if (token.len > name.len) return false;
    return std.ascii.eqlIgnoreCase(name[0..token.len], token);
}

fn scanDirIntoFinder(dir: std.fs.Dir, rel_path: []const u8, depth: usize, finder: *state.FileTargetFinder) !void {
    if (depth > max_walk_depth or finder.count >= finder.targets.len) return;

    var iterable = dir.openDir(rel_path, .{ .iterate = true }) catch return;
    defer iterable.close();

    var it = iterable.iterate();
    while (finder.count < finder.targets.len) {
        const entry = it.next() catch return;
        const e = entry orelse break;
        if (e.name.len == 0 or e.name[0] == '.') continue;

        var path_buf: [state.MAX_FILE_TARGET_PATH_BYTES]u8 = undefined;
        const child_path = if (std.mem.eql(u8, rel_path, "."))
            std.fmt.bufPrint(&path_buf, "{s}", .{e.name}) catch continue
        else
            std.fmt.bufPrint(&path_buf, "{s}/{s}", .{ rel_path, e.name }) catch continue;
        switch (e.kind) {
            .directory => try scanDirIntoFinder(dir, child_path, depth + 1, finder),
            .file => {
                if (!isAllowedSourceFile(child_path)) continue;
                var target = &finder.targets[finder.count];
                @memset(&target.path, 0);
                @memcpy(target.path[0..child_path.len], child_path);
                target.len = child_path.len;
                finder.count += 1;
            },
            else => {},
        }
    }
}

fn isAllowedSourceFile(path: []const u8) bool {
    for (allowed_extensions) |ext| {
        if (std.mem.endsWith(u8, path, ext)) return true;
    }
    return false;
}

test "constraint autocomplete detects WITH trigger and tab completes token" {
    var s = state.SessionState.init(std.testing.allocator, "test", null, false);
    defer s.deinit();
    try s.current_input.appendSlice("prove target WITH LO");

    refreshConstraintAutocomplete(&s);
    try std.testing.expect(s.constraint_autocomplete.active);
    try std.testing.expectEqualStrings("LOCK_ORDER", constraintCandidateAt(&s, 0).?);
    try std.testing.expect(try completeCurrentToken(&s));
    try std.testing.expectEqualStrings("prove target WITH LOCK_ORDER", s.current_input.items);
}

test "constraint autocomplete detects AND trigger" {
    var s = state.SessionState.init(std.testing.allocator, "test", null, false);
    defer s.deinit();
    try s.current_input.appendSlice("prove target WITH LOCK_ORDER AND B");

    refreshConstraintAutocomplete(&s);
    try std.testing.expect(s.constraint_autocomplete.active);
    try std.testing.expectEqualStrings("BOUNDS_CHECK", constraintCandidateAt(&s, 0).?);
}
