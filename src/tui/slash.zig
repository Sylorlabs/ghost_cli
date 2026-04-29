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
        if (std.mem.startsWith(u8, command.name, token)) count += 1;
    }
    return count;
}

pub fn hasMatches(prefix: []const u8) bool {
    return matchingCount(prefix) > 0;
}

pub fn suggestionToken(input: []const u8) []const u8 {
    const token_end = std.mem.indexOfAny(u8, input, " \t") orelse input.len;
    return input[0..token_end];
}
