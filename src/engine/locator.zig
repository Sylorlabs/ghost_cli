const std = @import("std");
const paths = @import("../config/paths.zig");

pub const EngineBinaries = enum {
    ghost_task_operator,
    ghost_code_intel,
    ghost_patch_candidates,
    ghost_knowledge_pack,

    pub fn toStr(self: EngineBinaries) []const u8 {
        return switch (self) {
            .ghost_task_operator => "ghost_task_operator",
            .ghost_code_intel => "ghost_code_intel",
            .ghost_patch_candidates => "ghost_patch_candidates",
            .ghost_knowledge_pack => "ghost_knowledge_pack",
        };
    }
};

/// Attempts to find the engine binary using a prioritized list of candidate paths.
/// Returns the first path that exists on disk.
/// If none exist, returns the most likely path (usually based on engine_root).
pub fn findEngineBinary(allocator: std.mem.Allocator, engine_root: ?[]const u8, binary: EngineBinaries) ![]u8 {
    const candidates = try getCandidatePaths(allocator, engine_root, binary);
    defer {
        for (candidates) |c| allocator.free(c);
        allocator.free(candidates);
    }

    for (candidates) |cand| {
        if (checkBinaryExists(cand)) {
            return try allocator.dupe(u8, cand);
        }
    }

    // Return the first candidate (preferred) if none found
    return try allocator.dupe(u8, candidates[0]);
}

/// Returns a prioritized list of candidate paths for a binary.
/// Caller must free the returned slice and all strings within it.
pub fn getCandidatePaths(allocator: std.mem.Allocator, engine_root: ?[]const u8, binary: EngineBinaries) ![][]u8 {
    const bin_name = binary.toStr();
    var list = std.ArrayList([]u8).init(allocator);
    errdefer {
        for (list.items) |item| allocator.free(item);
        list.deinit();
    }

    if (engine_root) |root| {
        // 1. root/binary
        try list.append(try std.fs.path.join(allocator, &[_][]const u8{ root, bin_name }));
        // 2. root/zig-out/bin/binary
        try list.append(try std.fs.path.join(allocator, &[_][]const u8{ root, "zig-out", "bin", bin_name }));
    }

    // 4. Dev fallback
    const dev_path = "../ghost_engine/zig-out/bin";
    try list.append(try std.fs.path.join(allocator, &[_][]const u8{ dev_path, bin_name }));

    // 3. PATH lookup
    try list.append(try allocator.dupe(u8, bin_name));

    return list.toOwnedSlice();
}

pub fn checkBinaryExists(path: []const u8) bool {
    if (std.mem.indexOfScalar(u8, path, std.fs.path.sep) == null) {
        // PATH lookup candidate - we don't check existence here, assume it might exist in PATH.
        return false; 
    }
    var file = std.fs.cwd().openFile(path, .{}) catch return false;
    file.close();
    return true;
}
