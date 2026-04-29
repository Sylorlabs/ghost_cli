const std = @import("std");

pub const SlashKind = enum {
    none,
    help,
    quit,
    status,
    reasoning,
    debug,
    json,
    clear,
    doctor,
    autopsy,
    context,
    unknown,
};

pub const SlashCommand = struct {
    kind: SlashKind,
    arg: ?[]const u8 = null,
};

pub const SlashCommandSpec = struct {
    name: []const u8,
    kind: SlashKind,
    args: []const u8 = "",
    help: []const u8,
};

pub const commands = [_]SlashCommandSpec{
    .{ .name = "/help", .kind = .help, .help = "Show TUI help" },
    .{ .name = "/quit", .kind = .quit, .help = "Exit TUI" },
    .{ .name = "/status", .kind = .status, .help = "Show session status" },
    .{ .name = "/reasoning", .kind = .reasoning, .args = " <level>", .help = "Set quick|balanced|deep|max" },
    .{ .name = "/debug", .kind = .debug, .args = " on|off", .help = "Toggle debug diagnostics" },
    .{ .name = "/json", .kind = .json, .args = " on|off", .help = "Toggle raw JSON capture" },
    .{ .name = "/clear", .kind = .clear, .help = "Clear TUI history" },
    .{ .name = "/doctor", .kind = .doctor, .help = "Run explicit read-only diagnostics" },
    .{ .name = "/autopsy", .kind = .autopsy, .args = " <path>", .help = "Run explicit Project Autopsy scan" },
    .{ .name = "/context", .kind = .context, .args = " <path>", .help = "Set context artifact path" },
};

pub fn parse(text: []const u8) SlashCommand {
    if (text.len == 0 or text[0] != '/') return .{ .kind = .none };

    const token_end = std.mem.indexOfAny(u8, text, " \t") orelse text.len;
    const token = text[0..token_end];
    const arg = if (token_end < text.len) std.mem.trim(u8, text[token_end..], " \t") else "";

    for (commands) |command| {
        if (std.mem.eql(u8, token, command.name)) {
            return .{ .kind = command.kind, .arg = arg };
        }
    }

    return .{ .kind = .unknown, .arg = text };
}

pub fn shouldSubmitToEngine(text: []const u8) bool {
    return parse(text).kind == .none;
}

pub fn matchingCount(prefix: []const u8) usize {
    const token = suggestionToken(prefix);
    if (token.len == 0 or token[0] != '/') return 0;
    var count: usize = 0;
    for (commands) |command| {
        if (isPrefixMatch(token, command.name)) count += 1;
    }
    for (commands) |command| {
        if (isPrefixMatch(token, command.name)) continue;
        if (isFuzzyMatch(token, command.name)) count += 1;
    }
    return count;
}

pub fn findFirstMatch(prefix: []const u8) ?[]const u8 {
    return findNthMatch(prefix, 0);
}

pub fn findNthMatch(prefix: []const u8, n: usize) ?[]const u8 {
    if (findNthMatchingCommand(prefix, n)) |command| return command.name;
    return null;
}

pub fn findNthMatchingCommand(prefix: []const u8, n: usize) ?SlashCommandSpec {
    const token = suggestionToken(prefix);
    if (token.len == 0 or token[0] != '/') return null;
    var count: usize = 0;
    for (commands) |command| {
        if (isPrefixMatch(token, command.name)) {
            if (count == n) return command;
            count += 1;
        }
    }
    for (commands) |command| {
        if (isPrefixMatch(token, command.name)) continue;
        if (isStrongFuzzyMatch(token, command.name)) {
            if (count == n) return command;
            count += 1;
        }
    }
    for (commands) |command| {
        if (isPrefixMatch(token, command.name) or isStrongFuzzyMatch(token, command.name)) continue;
        if (isWeakFuzzyMatch(token, command.name)) {
            if (count == n) return command;
            count += 1;
        }
    }
    return null;
}

pub fn hasMatches(prefix: []const u8) bool {
    return matchingCount(prefix) > 0;
}

pub fn suggestionToken(input: []const u8) []const u8 {
    const token_end = std.mem.indexOfAny(u8, input, " \t") orelse input.len;
    return input[0..token_end];
}

pub fn isPrefixMatch(token: []const u8, command_name: []const u8) bool {
    return std.mem.startsWith(u8, command_name, token);
}

pub fn isFuzzyMatch(token: []const u8, command_name: []const u8) bool {
    return isStrongFuzzyMatch(token, command_name) or isWeakFuzzyMatch(token, command_name);
}

fn isStrongFuzzyMatch(token: []const u8, command_name: []const u8) bool {
    if (!isWeakFuzzyMatch(token, command_name)) return false;
    const query = token[1..];
    const candidate = command_name[1..];
    return query.len > 0 and candidate.len > 0 and query[0] == candidate[0];
}

fn isWeakFuzzyMatch(token: []const u8, command_name: []const u8) bool {
    if (token.len == 0 or token[0] != '/') return false;
    if (isPrefixMatch(token, command_name)) return true;
    if (token.len > command_name.len) return false;

    const query = token[1..];
    const candidate = command_name[1..];
    if (query.len == 0) return true;
    if (query.len < 2) return false;
    if (isSubsequence(query, candidate)) return true;
    return isSubsequenceWithOneAdjacentQuerySwap(query, candidate);
}

fn isSubsequence(query: []const u8, candidate: []const u8) bool {
    var query_index: usize = 0;
    for (candidate) |char| {
        if (query_index < query.len and query[query_index] == char) {
            query_index += 1;
            if (query_index == query.len) return true;
        }
    }
    return query_index == query.len;
}

fn isSubsequenceWithOneAdjacentQuerySwap(query: []const u8, candidate: []const u8) bool {
    if (query.len < 2) return false;

    var swap_index: usize = 0;
    while (swap_index + 1 < query.len) : (swap_index += 1) {
        var query_index: usize = 0;
        for (candidate) |char| {
            if (query_index >= query.len) break;
            const expected = if (query_index == swap_index)
                query[swap_index + 1]
            else if (query_index == swap_index + 1)
                query[swap_index]
            else
                query[query_index];

            if (expected == char) {
                query_index += 1;
                if (query_index == query.len) return true;
            }
        }
    }
    return false;
}
