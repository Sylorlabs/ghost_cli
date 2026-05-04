const std = @import("std");
const locator = @import("../engine/locator.zig");
const process = @import("../engine/process.zig");

pub const PolicyOptions = struct {
    file_path: ?[]const u8 = null,
    json: bool = false,
    debug: bool = false,
};

const max_request_bytes = 1024 * 1024;
const usage = "Usage: ghost policy describe --file <request.json> [--json] [--debug]\n";

pub fn printHelp(writer: anytype) !void {
    try writer.print(
        \\policy
        \\
        \\Usage: ghost policy describe --file <request.json> [--json] [--debug]
        \\
        \\Read artifact/domain policy metadata through explicit GIP requests.
        \\
        \\Subcommands:
        \\  describe --file <request.json>  Run an artifact.policy.describe GIP request
        \\
        \\Safety:
        \\  This request runs only when this command is explicitly invoked.
        \\  Request files must be GIP-compatible JSON with kind "artifact.policy.describe".
        \\  The CLI sends request bytes unchanged to ghost_gip --stdin.
        \\  READ-ONLY.
        \\  NON-AUTHORIZING.
        \\  POLICY METADATA ONLY.
        \\  Policies are routing/scoring hints, not proof or support.
        \\  Code-specific policy is one domain profile, not the universal kernel.
        \\  COMMANDS NOT EXECUTED.
        \\  VERIFIERS NOT EXECUTED.
        \\  NO MUTATION.
        \\  `--json` preserves raw engine stdout exactly.
        \\  `--debug` writes diagnostics to stderr only.
        \\
    , .{});
}

pub fn printHelpForArgs(writer: anytype, args: []const []const u8) !void {
    if (args.len == 0) return printHelp(writer);
    if (std.mem.eql(u8, args[0], "describe")) return printDescribeHelp(writer);
    return printHelp(writer);
}

fn printDescribeHelp(writer: anytype) !void {
    try writer.print(
        \\policy describe
        \\
        \\Usage: ghost policy describe --file <request.json> [--json] [--debug]
        \\
        \\Reads a GIP-compatible artifact policy describe request from a file and
        \\sends it unchanged to ghost_gip --stdin. The request must include kind
        \\"artifact.policy.describe".
        \\
        \\Options:
        \\  --file <request.json>     Artifact policy GIP request file
        \\  --json                    Preserve raw GIP stdout exactly
        \\  --debug                   Diagnostics to stderr
        \\
        \\Safety:
        \\  Explicit invocation only.
        \\  READ-ONLY. NON-AUTHORIZING. POLICY METADATA ONLY.
        \\  Routing/scoring hints only; not proof, evidence, or support.
        \\  Code policy is a domain profile, not universal truth.
        \\  No commands executed. No verifiers executed. No policy state mutated.
        \\
    , .{});
}

pub fn executeFromArgs(
    allocator: std.mem.Allocator,
    engine_root: ?[]const u8,
    args: []const []const u8,
    base: PolicyOptions,
) !void {
    const sub = if (args.len > 0) args[0] else {
        try std.io.getStdErr().writer().print("{s}", .{usage});
        std.process.exit(1);
    };
    if (!std.mem.eql(u8, sub, "describe")) {
        try std.io.getStdErr().writer().print("Unknown policy command: {s}\n{s}", .{ sub, usage });
        std.process.exit(1);
    }

    var options = base;
    var i: usize = 1;
    while (i < args.len) : (i += 1) {
        const arg = args[i];
        if (std.mem.eql(u8, arg, "--file")) {
            i += 1;
            if (i >= args.len) try failMissingValue("--file");
            options.file_path = args[i];
        } else if (std.mem.startsWith(u8, arg, "--file=")) {
            const value = arg["--file=".len..];
            if (value.len == 0) try failMissingValue("--file");
            options.file_path = value;
        } else if (std.mem.startsWith(u8, arg, "--")) {
            try std.io.getStdErr().writer().print("Unknown policy describe option: {s}\n", .{arg});
            std.process.exit(1);
        } else {
            try std.io.getStdErr().writer().print("Unexpected policy describe argument: {s}\n", .{arg});
            std.process.exit(1);
        }
    }

    try executeDescribe(allocator, engine_root, options);
}

pub fn executeDescribe(allocator: std.mem.Allocator, engine_root: ?[]const u8, options: PolicyOptions) !void {
    const file_path = options.file_path orelse {
        try std.io.getStdErr().writer().print("{s}", .{usage});
        std.process.exit(1);
    };
    if (std.mem.trim(u8, file_path, " \r\n\t").len == 0) {
        try std.io.getStdErr().writer().print("policy describe --file must be non-empty\n", .{});
        std.process.exit(1);
    }

    const request = std.fs.cwd().readFileAlloc(allocator, file_path, max_request_bytes) catch |err| {
        try std.io.getStdErr().writer().print("Error: failed to read artifact.policy.describe request file '{s}': {s}\n", .{ file_path, @errorName(err) });
        std.process.exit(1);
    };
    defer allocator.free(request);

    var parsed = std.json.parseFromSlice(std.json.Value, allocator, request, .{}) catch |err| {
        if (options.debug) try std.io.getStdErr().writer().print("[DEBUG] Parse Status: FAILED ({s})\n", .{@errorName(err)});
        try std.io.getStdErr().writer().print("Error: artifact.policy.describe request file is not valid JSON: {s}\n", .{@errorName(err)});
        std.process.exit(1);
    };
    defer parsed.deinit();

    if (!hasArtifactPolicyDescribeKind(parsed.value)) {
        if (options.debug) try std.io.getStdErr().writer().print("[DEBUG] Parse Status: FAILED (kind mismatch)\n", .{});
        try std.io.getStdErr().writer().print("Error: request file must contain top-level kind \"artifact.policy.describe\".\n", .{});
        std.process.exit(1);
    }

    const bin_path = locator.findEngineBinary(allocator, engine_root, .ghost_gip) catch |err| {
        try locator.printLocatorError(std.io.getStdErr().writer(), .ghost_gip, engine_root, err);
        std.process.exit(1);
    };
    defer allocator.free(bin_path);

    const argv = &[_][]const u8{ bin_path, "--stdin" };
    if (options.debug) {
        try std.io.getStdErr().writer().print("[DEBUG] Engine Binary: {s}\n", .{bin_path});
        try std.io.getStdErr().writer().print("[DEBUG] GIP Kind: artifact.policy.describe\n", .{});
        try std.io.getStdErr().writer().print("[DEBUG] Input File: {s}\n", .{file_path});
        try std.io.getStdErr().writer().print("[DEBUG] Stdin Byte Count: {d}\n", .{request.len});
    }

    const result = process.runEngineCommandWithInput(allocator, argv, request) catch |err| {
        try std.io.getStdErr().writer().print("\x1b[31m[!] Error:\x1b[0m Failed to execute artifact.policy.describe: {}\n", .{err});
        try std.io.getStdErr().writer().print("\x1b[33mHint:\x1b[0m Run `ghost status` to verify your environment.\n", .{});
        std.process.exit(1);
    };
    defer {
        allocator.free(result.stdout);
        allocator.free(result.stderr);
    }

    if (options.debug) try std.io.getStdErr().writer().print("[DEBUG] Exit Code: {d}\n", .{result.exit_code});

    if (options.json) {
        if (options.debug) try std.io.getStdErr().writer().print("[DEBUG] Parse Status: SKIPPED (raw passthrough)\n", .{});
        try std.io.getStdOut().writer().writeAll(result.stdout);
        if (result.stderr.len > 0) try std.io.getStdErr().writer().writeAll(result.stderr);
        if (result.exit_code != 0) std.process.exit(result.exit_code);
        return;
    }

    if (result.exit_code != 0) {
        try std.io.getStdErr().writer().print("\x1b[31m[!] Engine Error (Exit Code {d}):\x1b[0m\n", .{result.exit_code});
        if (result.stderr.len > 0) {
            try std.io.getStdErr().writer().writeAll(result.stderr);
            if (result.stderr[result.stderr.len - 1] != '\n') try std.io.getStdErr().writer().writeByte('\n');
        } else if (result.stdout.len > 0) {
            try std.io.getStdErr().writer().writeAll(result.stdout);
            if (result.stdout[result.stdout.len - 1] != '\n') try std.io.getStdErr().writer().writeByte('\n');
        }
        std.process.exit(result.exit_code);
    }

    var out_parsed = std.json.parseFromSlice(std.json.Value, allocator, result.stdout, .{}) catch |err| {
        if (options.debug) try std.io.getStdErr().writer().print("[DEBUG] Parse Status: FAILED ({s})\n", .{@errorName(err)});
        try std.io.getStdErr().writer().print("Error: Failed to parse engine output as artifact.policy.describe JSON.\n", .{});
        try std.io.getStdErr().writer().print("Raw output:\n{s}\n", .{result.stdout});
        return;
    };
    defer out_parsed.deinit();

    if (options.debug) try std.io.getStdErr().writer().print("[DEBUG] Parse Status: ok\n", .{});

    try printArtifactPolicyResult(std.io.getStdOut().writer(), out_parsed.value);
}

fn hasArtifactPolicyDescribeKind(value: std.json.Value) bool {
    const obj = switch (value) {
        .object => |o| o,
        else => return false,
    };
    const kind = obj.get("kind") orelse return false;
    return switch (kind) {
        .string => |s| std.mem.eql(u8, s, "artifact.policy.describe"),
        else => false,
    };
}

fn printArtifactPolicyResult(writer: anytype, value: std.json.Value) !void {
    try writer.print("Artifact Policy Metadata\n", .{});
    try writer.print("State: READ-ONLY / NON-AUTHORIZING / POLICY METADATA ONLY\n", .{});
    try writer.print("Policies are routing/scoring hints, not proof or support.\n", .{});
    try writer.print("Code-specific policy is one domain profile, not the universal kernel.\n", .{});
    try writer.print("COMMANDS NOT EXECUTED\n", .{});
    try writer.print("VERIFIERS NOT EXECUTED\n", .{});
    try writer.print("NO MUTATION\n\n", .{});

    if (findError(value)) |err_value| {
        try writer.print("Engine Rejected Request:\n", .{});
        try printJsonValue(writer, err_value, 2);
        try writer.print("\n", .{});
        return;
    }

    const policy_value = findArtifactPolicy(value) orelse {
        try writer.print("No artifactPolicy result payload was present.\n", .{});
        return;
    };
    const policy = switch (policy_value) {
        .object => |obj| obj,
        else => {
            try printJsonValue(writer, policy_value, 2);
            try writer.print("\n", .{});
            return;
        },
    };

    try printStringFieldAny(writer, policy, &.{ "activeProfile", "active_profile", "profile", "policyProfile" }, "Active Profile");
    try printStringFieldAny(writer, policy, &.{ "defaultProfile", "default_profile" }, "Default Profile");
    try printStringFieldAny(writer, policy, &.{ "policyName", "policy_name", "name" }, "Policy Name");
    try printStringFieldAny(writer, policy, &.{ "domainFamily", "domain_family", "domain" }, "Domain");

    try printSectionAny(writer, policy, &.{ "interventionPolicy", "intervention_policy", "interventions" }, "Intervention Policy Metadata");
    try printSectionAny(writer, policy, &.{ "evidenceFamilyPolicy", "evidence_family_policy", "evidenceFamilies", "evidence_families" }, "Evidence Family Policy Metadata");
    try printSectionAny(writer, policy, &.{ "hypothesisPriorPolicy", "hypothesis_prior_policy", "hypothesisPriors", "hypothesis_priors" }, "Hypothesis Prior Policy Metadata");
    try printSectionAny(writer, policy, &.{ "trustDecayPolicy", "trust_decay_policy", "trustDecay", "trust_decay" }, "Trust Decay Policy Metadata");
    try printSectionAny(writer, policy, &.{ "domainProfiles", "domain_profiles", "profiles" }, "Domain Profiles");
    try printSectionAny(writer, policy, &.{ "authority", "authorityFlags", "safety", "safetyFlags" }, "Authority / Safety Flags");
    try printEnvelopeSafety(writer, value);

    try writer.print("\nNotice: artifact.policy.describe exposes policy metadata only. The CLI does not infer proof, evidence, support, verifier success, or mutation from policy fields.\n", .{});
}

fn findArtifactPolicy(value: std.json.Value) ?std.json.Value {
    const obj = switch (value) {
        .object => |o| o,
        else => return null,
    };
    if (obj.get("artifactPolicy")) |policy| return policy;
    if (obj.get("artifact_policy")) |policy| return policy;
    if (obj.get("result")) |result| {
        const result_obj = switch (result) {
            .object => |o| o,
            else => return result,
        };
        if (result_obj.get("artifactPolicy")) |policy| return policy;
        if (result_obj.get("artifact_policy")) |policy| return policy;
        return result;
    }
    return null;
}

fn findError(value: std.json.Value) ?std.json.Value {
    const obj = switch (value) {
        .object => |o| o,
        else => return null,
    };
    if (obj.get("error")) |err| return err;
    if (obj.get("status")) |status| {
        if (status == .string and std.mem.eql(u8, status.string, "rejected")) return value;
    }
    return null;
}

fn printStringFieldAny(writer: anytype, obj: std.json.ObjectMap, fields: []const []const u8, label: []const u8) !void {
    for (fields) |field| {
        if (obj.get(field)) |value| {
            switch (value) {
                .string => |s| {
                    try writer.print("{s}: {s}\n", .{ label, s });
                    return;
                },
                else => {},
            }
        }
    }
}

fn printSectionAny(writer: anytype, obj: std.json.ObjectMap, fields: []const []const u8, label: []const u8) !void {
    for (fields) |field| {
        if (obj.get(field)) |value| {
            if (isEmptyJson(value)) return;
            try writer.print("\n{s}:\n", .{label});
            try printJsonValue(writer, value, 2);
            try writer.print("\n", .{});
            return;
        }
    }
}

fn printEnvelopeSafety(writer: anytype, value: std.json.Value) !void {
    const obj = switch (value) {
        .object => |o| o,
        else => return,
    };
    var printed = false;
    inline for (.{ "readOnly", "nonAuthorizing", "mutatesState", "commandsExecuted", "verifiersExecuted", "supportGranted", "proofGranted" }) |field| {
        if (obj.get(field)) |field_value| {
            if (!printed) {
                try writer.print("\nGIP Safety Metadata:\n", .{});
                printed = true;
            }
            try writer.print("  {s}: ", .{field});
            try printInlineJsonValue(writer, field_value);
            try writer.print("\n", .{});
        }
    }
}

fn isEmptyJson(value: std.json.Value) bool {
    return switch (value) {
        .array => |arr| arr.items.len == 0,
        .object => |obj| obj.count() == 0,
        else => false,
    };
}

fn printInlineJsonValue(writer: anytype, value: std.json.Value) !void {
    switch (value) {
        .string => |s| try writer.print("{s}", .{s}),
        .integer => |i| try writer.print("{d}", .{i}),
        .float => |f| try writer.print("{d}", .{f}),
        .bool => |b| try writer.print("{s}", .{if (b) "true" else "false"}),
        .null => try writer.print("null", .{}),
        else => try std.json.stringify(value, .{}, writer),
    }
}

fn printJsonValue(writer: anytype, value: std.json.Value, indent: usize) !void {
    var string = std.ArrayList(u8).init(std.heap.page_allocator);
    defer string.deinit();
    try std.json.stringify(value, .{ .whitespace = .indent_2 }, string.writer());
    var lines = std.mem.splitScalar(u8, string.items, '\n');
    while (lines.next()) |line| {
        try writer.writeByteNTimes(' ', indent);
        try writer.print("{s}\n", .{line});
    }
}

fn failMissingValue(flag: []const u8) !noreturn {
    try std.io.getStdErr().writer().print("{s} requires a value\n", .{flag});
    std.process.exit(1);
}
