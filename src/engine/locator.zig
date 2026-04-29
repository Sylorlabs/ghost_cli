const std = @import("std");

pub const EngineBinaries = enum {
    ghost_task_operator,
    ghost_code_intel,
    ghost_patch_candidates,
    ghost_knowledge_pack,
    ghost_gip,
    ghost_project_autopsy,

    pub fn toStr(self: EngineBinaries) []const u8 {
        return switch (self) {
            .ghost_task_operator => "ghost_task_operator",
            .ghost_code_intel => "ghost_code_intel",
            .ghost_patch_candidates => "ghost_patch_candidates",
            .ghost_knowledge_pack => "ghost_knowledge_pack",
            .ghost_gip => "ghost_gip",
            .ghost_project_autopsy => "ghost_project_autopsy",
        };
    }

    pub fn isCore(self: EngineBinaries) bool {
        return switch (self) {
            .ghost_task_operator,
            .ghost_code_intel,
            .ghost_patch_candidates,
            .ghost_knowledge_pack,
            => true,
            .ghost_gip,
            .ghost_project_autopsy,
            => false,
        };
    }
};

pub const CandidateKind = enum {
    engine_root_direct,
    engine_root_zig_out,
    dev_fallback,
    path,

    pub fn label(self: CandidateKind) []const u8 {
        return switch (self) {
            .engine_root_direct => "engine-root",
            .engine_root_zig_out => "engine-root-zig-out",
            .dev_fallback => "dev-fallback-candidate",
            .path => "PATH-candidate",
        };
    }
};

pub const CandidateStatus = enum {
    missing,
    found_not_executable,
    executable,

    pub fn label(self: CandidateStatus) []const u8 {
        return switch (self) {
            .missing => "missing",
            .found_not_executable => "found-not-executable",
            .executable => "executable",
        };
    }
};

pub const Candidate = struct {
    path: []u8,
    kind: CandidateKind,
    status: CandidateStatus,
    resolved_path: ?[]u8 = null,

    pub fn deinit(self: *Candidate, allocator: std.mem.Allocator) void {
        allocator.free(self.path);
        if (self.resolved_path) |resolved| allocator.free(resolved);
    }
};

pub const Resolution = struct {
    binary: EngineBinaries,
    candidates: []Candidate,
    resolved_path: ?[]u8 = null,
    resolved_kind: ?CandidateKind = null,
    resolved_status: CandidateStatus = .missing,

    pub fn deinit(self: *Resolution, allocator: std.mem.Allocator) void {
        if (self.resolved_path) |path| allocator.free(path);
        for (self.candidates) |*candidate| candidate.deinit(allocator);
        allocator.free(self.candidates);
    }

    pub fn executablePath(self: Resolution) ?[]const u8 {
        if (self.resolved_status == .executable) return self.resolved_path;
        return null;
    }
};

pub const LocatorError = error{
    EngineBinaryMissing,
    EngineBinaryFoundNotExecutable,
};

pub fn allBinaries() []const EngineBinaries {
    return &.{
        .ghost_task_operator,
        .ghost_code_intel,
        .ghost_patch_candidates,
        .ghost_knowledge_pack,
        .ghost_gip,
        .ghost_project_autopsy,
    };
}

pub fn resolveEngineBinary(allocator: std.mem.Allocator, engine_root: ?[]const u8, binary: EngineBinaries) !Resolution {
    const candidates = try buildCandidates(allocator, engine_root, binary);
    errdefer {
        for (candidates) |*candidate| candidate.deinit(allocator);
        allocator.free(candidates);
    }

    var first_non_exec: ?usize = null;
    for (candidates, 0..) |candidate, index| {
        if (engine_root != null and candidate.kind != .engine_root_direct and candidate.kind != .engine_root_zig_out) continue;
        if (candidate.status == .executable) {
            const resolved = candidate.resolved_path orelse candidate.path;
            return Resolution{
                .binary = binary,
                .candidates = candidates,
                .resolved_path = try allocator.dupe(u8, resolved),
                .resolved_kind = candidate.kind,
                .resolved_status = .executable,
            };
        }
        if (candidate.status == .found_not_executable and first_non_exec == null) {
            first_non_exec = index;
        }
    }

    if (first_non_exec) |index| {
        return Resolution{
            .binary = binary,
            .candidates = candidates,
            .resolved_path = try allocator.dupe(u8, candidates[index].path),
            .resolved_kind = candidates[index].kind,
            .resolved_status = .found_not_executable,
        };
    }

    return Resolution{
        .binary = binary,
        .candidates = candidates,
        .resolved_path = null,
        .resolved_kind = null,
        .resolved_status = .missing,
    };
}

pub fn findEngineBinary(allocator: std.mem.Allocator, engine_root: ?[]const u8, binary: EngineBinaries) ![]u8 {
    var resolution = try resolveEngineBinary(allocator, engine_root, binary);
    defer resolution.deinit(allocator);

    if (resolution.executablePath()) |path| return try allocator.dupe(u8, path);
    return switch (resolution.resolved_status) {
        .found_not_executable => LocatorError.EngineBinaryFoundNotExecutable,
        .missing => LocatorError.EngineBinaryMissing,
        .executable => unreachable,
    };
}

pub fn printLocatorError(writer: anytype, binary: EngineBinaries, engine_root: ?[]const u8, err: anyerror) !void {
    const reason = switch (err) {
        LocatorError.EngineBinaryMissing => "missing",
        LocatorError.EngineBinaryFoundNotExecutable => "found but not executable",
        else => "could not be resolved",
    };
    try writer.print("\x1b[31m[!] Error:\x1b[0m Engine binary '{s}' is {s}.\n", .{ binary.toStr(), reason });
    if (engine_root) |root| {
        try writer.print("\x1b[33mHint:\x1b[0m Checked engine root: {s}\n", .{root});
        try writer.print("\x1b[33mHint:\x1b[0m If GHOST_ENGINE_ROOT points to the repo root, run `zig build` in ghost_engine.\n", .{});
    }
    try writer.print("\x1b[33mFix:\x1b[0m Set --engine-root=<path>, GHOST_ENGINE_ROOT, or put the engine binary on PATH.\n", .{});
}

/// Returns a prioritized list of candidate paths for compatibility with older tests.
/// Caller must free the returned slice and all strings within it.
pub fn getCandidatePaths(allocator: std.mem.Allocator, engine_root: ?[]const u8, binary: EngineBinaries) ![][]u8 {
    const candidates = try buildCandidates(allocator, engine_root, binary);
    defer {
        for (candidates) |*candidate| candidate.deinit(allocator);
        allocator.free(candidates);
    }

    var paths = std.ArrayList([]u8).init(allocator);
    errdefer {
        for (paths.items) |path| allocator.free(path);
        paths.deinit();
    }
    for (candidates) |candidate| try paths.append(try allocator.dupe(u8, candidate.path));
    return paths.toOwnedSlice();
}

pub fn checkBinaryExists(path: []const u8) bool {
    return classifyCandidate(std.heap.page_allocator, path, if (hasPathSeparator(path)) .engine_root_direct else .path) == .executable;
}

pub fn checkPathExists(path: []const u8) bool {
    if (!hasPathSeparator(path)) return pathExecutableOnPath(std.heap.page_allocator, path) != null;
    var file = std.fs.cwd().openFile(path, .{}) catch return false;
    file.close();
    return true;
}

pub fn checkPathExecutable(path: []const u8) bool {
    return classifyCandidate(std.heap.page_allocator, path, if (hasPathSeparator(path)) .engine_root_direct else .path) == .executable;
}

fn buildCandidates(allocator: std.mem.Allocator, engine_root: ?[]const u8, binary: EngineBinaries) ![]Candidate {
    const bin_name = binary.toStr();
    var list = std.ArrayList(Candidate).init(allocator);
    errdefer {
        for (list.items) |*item| item.deinit(allocator);
        list.deinit();
    }

    if (engine_root) |root| {
        try appendPathCandidate(allocator, &list, try std.fs.path.join(allocator, &.{ root, bin_name }), .engine_root_direct);
        try appendPathCandidate(allocator, &list, try std.fs.path.join(allocator, &.{ root, "zig-out", "bin", bin_name }), .engine_root_zig_out);
    }

    try appendPathCandidate(allocator, &list, try std.fs.path.join(allocator, &.{ "../ghost_engine/zig-out/bin", bin_name }), .dev_fallback);
    try appendPathCandidate(allocator, &list, try allocator.dupe(u8, bin_name), .path);
    return list.toOwnedSlice();
}

fn appendPathCandidate(allocator: std.mem.Allocator, list: *std.ArrayList(Candidate), owned_path: []u8, kind: CandidateKind) !void {
    errdefer allocator.free(owned_path);
    var resolved_path: ?[]u8 = null;
    const status = classifyCandidateWithResolved(allocator, owned_path, kind, &resolved_path);
    errdefer if (resolved_path) |resolved| allocator.free(resolved);
    try list.append(.{
        .path = owned_path,
        .kind = kind,
        .status = status,
        .resolved_path = resolved_path,
    });
}

fn classifyCandidate(allocator: std.mem.Allocator, path: []const u8, kind: CandidateKind) CandidateStatus {
    var resolved_path: ?[]u8 = null;
    const status = classifyCandidateWithResolved(allocator, path, kind, &resolved_path);
    if (resolved_path) |resolved| allocator.free(resolved);
    return status;
}

fn classifyCandidateWithResolved(allocator: std.mem.Allocator, path: []const u8, kind: CandidateKind, resolved_path: *?[]u8) CandidateStatus {
    if (kind == .path and !hasPathSeparator(path)) {
        if (pathExecutableOnPath(allocator, path)) |resolved| {
            resolved_path.* = resolved;
            return .executable;
        }
        return .missing;
    }

    var file = std.fs.cwd().openFile(path, .{}) catch return .missing;
    file.close();
    std.posix.access(path, std.posix.X_OK) catch return .found_not_executable;
    return .executable;
}

fn pathExecutableOnPath(allocator: std.mem.Allocator, name: []const u8) ?[]u8 {
    if (name.len == 0 or hasPathSeparator(name)) return null;
    const path_env = std.posix.getenv("PATH") orelse return null;
    var it = std.mem.splitScalar(u8, path_env, ':');
    while (it.next()) |dir| {
        const search_dir = if (dir.len == 0) "." else dir;
        const candidate = std.fs.path.join(allocator, &.{ search_dir, name }) catch continue;
        if (classifyCandidate(allocator, candidate, .engine_root_direct) == .executable) return candidate;
        allocator.free(candidate);
    }
    return null;
}

fn hasPathSeparator(path: []const u8) bool {
    return std.mem.indexOfScalar(u8, path, '/') != null or std.mem.indexOfScalar(u8, path, '\\') != null;
}
