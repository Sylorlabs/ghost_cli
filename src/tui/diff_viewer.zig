const std = @import("std");

pub const PatchProposal = struct {
    diff: []const u8,
    allocator: std.mem.Allocator,

    pub fn deinit(self: PatchProposal) void {
        self.allocator.free(self.diff);
    }
};

pub const ApplyResult = struct {
    path: []const u8,
    allocator: std.mem.Allocator,

    pub fn deinit(self: ApplyResult) void {
        self.allocator.free(self.path);
    }
};

pub fn findPatchProposal(allocator: std.mem.Allocator, bytes: []const u8) !?PatchProposal {
    var parsed = std.json.parseFromSlice(std.json.Value, allocator, bytes, .{}) catch return null;
    defer parsed.deinit();
    return try findPatchProposalValue(allocator, parsed.value);
}

pub fn applyUnifiedDiff(allocator: std.mem.Allocator, diff: []const u8) !ApplyResult {
    var parser = DiffParser{ .diff = diff };
    const path = try parser.nextFilePath(allocator);
    errdefer allocator.free(path);

    const source = try std.fs.cwd().readFileAlloc(allocator, path, 10 * 1024 * 1024);
    defer allocator.free(source);
    const output = try applyToContent(allocator, source, diff);
    defer allocator.free(output);

    try std.fs.cwd().writeFile(.{ .sub_path = path, .data = output });
    return .{ .path = path, .allocator = allocator };
}

fn findPatchProposalValue(allocator: std.mem.Allocator, value: std.json.Value) !?PatchProposal {
    switch (value) {
        .object => |obj| {
            if (obj.get("patchProposal")) |candidate| {
                if (try parsePatchObject(allocator, candidate)) |proposal| return proposal;
            }
            if (obj.get("patch_proposal")) |candidate| {
                if (try parsePatchObject(allocator, candidate)) |proposal| return proposal;
            }
            if (try parsePatchObject(allocator, value)) |proposal| return proposal;

            var it = obj.iterator();
            while (it.next()) |entry| {
                if (try findPatchProposalValue(allocator, entry.value_ptr.*)) |proposal| return proposal;
            }
        },
        .array => |items| {
            for (items.items) |item| {
                if (try findPatchProposalValue(allocator, item)) |proposal| return proposal;
            }
        },
        else => {},
    }
    return null;
}

fn parsePatchObject(allocator: std.mem.Allocator, value: std.json.Value) !?PatchProposal {
    if (value != .object) return null;
    const obj = value.object;
    const diff_value = obj.get("preview_diff") orelse obj.get("previewDiff") orelse obj.get("diff") orelse return null;
    if (diff_value != .string or diff_value.string.len == 0) return null;
    if (std.mem.indexOf(u8, diff_value.string, "\n+++") == null) return null;
    return .{ .diff = try allocator.dupe(u8, diff_value.string), .allocator = allocator };
}

const DiffParser = struct {
    diff: []const u8,

    fn nextFilePath(self: *DiffParser, allocator: std.mem.Allocator) ![]const u8 {
        var it = std.mem.splitScalar(u8, self.diff, '\n');
        while (it.next()) |line| {
            if (!std.mem.startsWith(u8, line, "+++ ")) continue;
            const raw = std.mem.trim(u8, line[4..], " \r\t");
            const without_prefix = if (std.mem.startsWith(u8, raw, "b/")) raw[2..] else raw;
            if (without_prefix.len == 0 or std.fs.path.isAbsolute(without_prefix) or std.mem.indexOf(u8, without_prefix, "..") != null) {
                return error.UnsafePatchPath;
            }
            return try allocator.dupe(u8, without_prefix);
        }
        return error.PatchPathMissing;
    }
};

fn applyToContent(allocator: std.mem.Allocator, source: []const u8, diff: []const u8) ![]u8 {
    var old_lines = std.ArrayList([]const u8).init(allocator);
    defer old_lines.deinit();
    var old_it = std.mem.splitScalar(u8, source, '\n');
    while (old_it.next()) |line| {
        if (old_it.index == null and line.len == 0 and std.mem.endsWith(u8, source, "\n")) break;
        try old_lines.append(line);
    }

    var out_lines = std.ArrayList([]const u8).init(allocator);
    defer out_lines.deinit();
    var diff_lines = std.ArrayList([]const u8).init(allocator);
    defer diff_lines.deinit();
    var it = std.mem.splitScalar(u8, diff, '\n');
    while (it.next()) |line| {
        try diff_lines.append(line);
    }

    var cursor: usize = 0;
    var i: usize = 0;
    while (i < diff_lines.items.len) : (i += 1) {
        const line = diff_lines.items[i];
        if (!std.mem.startsWith(u8, line, "@@ ")) continue;
        const old_start = try parseOldStart(line);
        const target = if (old_start == 0) @as(usize, 0) else old_start - 1;
        while (cursor < target and cursor < old_lines.items.len) : (cursor += 1) {
            try out_lines.append(old_lines.items[cursor]);
        }
        i += 1;
        while (i < diff_lines.items.len) : (i += 1) {
            const hunk_line = diff_lines.items[i];
            if (std.mem.startsWith(u8, hunk_line, "@@ ")) {
                i -= 1;
                break;
            }
            if (std.mem.startsWith(u8, hunk_line, "--- ") or std.mem.startsWith(u8, hunk_line, "+++ ")) break;
            if (hunk_line.len == 0) continue;
            switch (hunk_line[0]) {
                ' ' => {
                    const expected = trimCr(hunk_line[1..]);
                    if (cursor >= old_lines.items.len or !std.mem.eql(u8, old_lines.items[cursor], expected)) return error.PatchContextMismatch;
                    try out_lines.append(old_lines.items[cursor]);
                    cursor += 1;
                },
                '-' => {
                    const expected = trimCr(hunk_line[1..]);
                    if (cursor >= old_lines.items.len or !std.mem.eql(u8, old_lines.items[cursor], expected)) return error.PatchContextMismatch;
                    cursor += 1;
                },
                '+' => try out_lines.append(trimCr(hunk_line[1..])),
                '\\' => {},
                else => break,
            }
        }
    }
    while (cursor < old_lines.items.len) : (cursor += 1) {
        try out_lines.append(old_lines.items[cursor]);
    }

    var out = std.ArrayList(u8).init(allocator);
    defer out.deinit();
    for (out_lines.items, 0..) |line, idx| {
        if (idx != 0) try out.append('\n');
        try out.appendSlice(line);
    }
    if (std.mem.endsWith(u8, source, "\n")) try out.append('\n');
    return try out.toOwnedSlice();
}

fn parseOldStart(header: []const u8) !usize {
    const minus = std.mem.indexOfScalar(u8, header, '-') orelse return error.InvalidHunkHeader;
    const after = header[(minus + 1)..];
    const comma = std.mem.indexOfAny(u8, after, ", ") orelse return error.InvalidHunkHeader;
    return try std.fmt.parseInt(usize, after[0..comma], 10);
}

fn trimCr(line: []const u8) []const u8 {
    return std.mem.trimRight(u8, line, "\r");
}

test "applyUnifiedDiff applies one hunk" {
    const allocator = std.testing.allocator;
    const source = "one\ntwo\nthree\n";
    const diff =
        \\--- a/demo.txt
        \\+++ b/demo.txt
        \\@@ -1,3 +1,3 @@
        \\ one
        \\-two
        \\+TWO
        \\ three
        \\
    ;
    const output = try applyToContent(allocator, source, diff);
    defer allocator.free(output);
    try std.testing.expectEqualStrings("one\nTWO\nthree\n", output);
}

test "applyUnifiedDiff applies multiple hunks" {
    const allocator = std.testing.allocator;
    const source = "one\ntwo\nthree\nfour\nfive\n";
    const diff =
        \\--- a/demo.txt
        \\+++ b/demo.txt
        \\@@ -1,3 +1,3 @@
        \\ one
        \\-two
        \\+TWO
        \\ three
        \\@@ -4,2 +4,2 @@
        \\-four
        \\+FOUR
        \\ five
        \\
    ;
    const output = try applyToContent(allocator, source, diff);
    defer allocator.free(output);
    try std.testing.expectEqualStrings("one\nTWO\nthree\nFOUR\nfive\n", output);
}
