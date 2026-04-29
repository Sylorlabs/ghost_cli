# ghost_cli

`ghost_cli` is a user-facing CLI shell that wraps the `ghost_engine` low-level binaries.

## What is ghost_cli?
It is a thin product wrapper that provides a seamless, user-friendly experience on top of the powerful `ghost_engine`. It manages basic workflows, passes user intent, parses engine JSON outputs, and renders friendly terminal UI states.

## What it is NOT
- It is NOT a re-implementation of Ghost reasoning or engine logic.
- It does not contain support graphs, proof gates, verifier rules, or mutation logic.
- The `ghost_engine` remains the ultimate source of truth.

## Installation / Build

### Development Usage
To build the CLI locally:
```bash
zig build
./zig-out/bin/ghost --help
```

### Global Installation
To install `ghost` globally on your system:
```bash
./scripts/install.sh
```
This script will:
1. Build the project in `ReleaseSafe` mode.
2. Create a symlink at `/usr/local/bin/ghost` pointing to the built binary.
3. Detect existing command conflicts.

### Uninstall
To remove the global `ghost` command:
```bash
./scripts/uninstall.sh
```

## Usage
By default, the CLI looks for `ghost_engine` binaries in standard development paths, or `PATH`. You can override this using:
- The `--engine-root=<path>` CLI flag.
- The `GHOST_ENGINE_ROOT` environment variable.

Binary resolution is explicit: candidates are reported as engine-root, engine-root `zig-out`, dev fallback, or PATH candidates, and as executable, found-not-executable, or missing. Normal command execution requires an executable binary and fails before launch when the selected engine binary is missing.

**Running `ghost` with no arguments launches the interactive TUI console.**
In a non-interactive pipe or script, the TUI path exits cleanly and reports that
no CLI-owned TUI command, doctor check, context/project autopsy scan, verifier,
or pack mutation was started from that fallback path.

### Examples

```bash
# Launch interactive TUI (default — no args needed)
ghost

# General chat
ghost chat --message="explain this project" --reasoning=balanced

# One-shot questions
ghost ask "what does this config do?"

# Request a fix
ghost fix "make the failing runtime test pass" --reasoning=deep

# Verify workspace state
ghost verify --reasoning=deep
ghost verify --context-artifact=src/main.zig --reasoning=max

# Explicit Context Autopsy through GIP
ghost context autopsy "I need marketing advice for a launch"
ghost context autopsy --json "I need marketing advice for a launch"
ghost context autopsy --debug "I need marketing advice for a launch"

# Interactive TUI Console
ghost tui
ghost tui --reasoning=deep --compact --color=auto

# List knowledge packs
ghost packs list
ghost packs inspect zig_runtime_sync
ghost packs mount zig_runtime_sync --version=1.0.0

# Feedback and Distillation (Learn)
ghost learn candidates --project-shard=my-project
ghost learn show action_surface:candidate_local_guard --project-shard=my-project
ghost learn export action_surface:candidate_local_guard --project-shard=my-project --pack-id=my_pack --version=0.1.0 --approve

# Check environment status
ghost status

# Run project autopsy scan
ghost autopsy .

# Full first-tester diagnostics
ghost doctor
ghost doctor --report
```

### Knowledge Lifecycle
- **Reinforcement**: Local experience gathered during chat and task sessions.
- **Distillation Candidates**: Reviewed and aggregated knowledge ready for promotion.
- **Exported Packs**: User-approved knowledge units that act as non-authorizing hints for future reasoning.
- **Truth**: Proof and support gates in the engine still decide final validity of any claim.


### Reasoning Levels
Normal users specify `--reasoning=quick|balanced|deep|max`.

- **quick**: Fastest, minimal exploration. Best for simple queries.
- **balanced**: Default. Mix of speed and thoroughness.
- **deep**: Thorough, verifies when useful, may take longer.
- **max**: Most thorough. Uses the largest budget allowance without forcing expensive verification.

### Command Help and Options

Top-level help is grouped by operator workflow:

- Core: `ask`, `chat`, `fix`, `verify`
- Inspection: `autopsy`, `context`, `status`, `doctor`
- Knowledge: `packs`, `learn`
- Advanced: `debug`
- Interface: `tui`

Every top-level command supports `ghost <command> --help`.

Normal options stay focused on workflow: `--message`, `--reasoning`,
`--context-artifact`, and `--engine-root`. Output/debug controls include
`--json`, `--debug`, `--no-color`, `--color=auto|always|never`, and `--compact`
where meaningful. `--timeout-ms` is intentionally not exposed because the runner
does not have a safe timeout contract yet.

### TUI Console

The native TUI is terminal-only Zig code. It has a Ghost status header, engine
root/context footer, reasoning/debug/json indicators, and draft/verified/
unresolved counters from parsed engine output. Launching it and leaving it idle
does not run doctor, status, context/project autopsy, verifiers, scans, pack
mutation, or negative-knowledge mutation. Explicit slash commands and submitted
prompts may invoke engine binaries according to their command contract.

Typing `/` shows lightweight native slash-command suggestions. Prefix matches
stay first, and compact fuzzy fragments such as `/rsn`, `/dbg`, `/ast`, and
`/ctx` suggest `/reasoning`, `/debug`, `/autopsy`, and `/context`. Invalid slash
commands are rejected in the TUI with a clear `ERROR` message and are not sent
to the engine as normal prompts.
The suggestion area grows upward from the lower command region when more matches
are visible, shrinks again as matches narrow, and reserves terminal rows so
history stays separate. Native ANSI color stays restrained: errors are red,
warnings are yellow, and the same labels remain readable with `--no-color`.
The TUI reads the live terminal dimensions on each frame, redraws periodically
while idle so resizes are picked up without another keypress, and clips command
panel rows to the current width.

Engine prompt/response turns are persisted in TUI session history and rendered
with `YOU` and `GHOST` labels. `SYSTEM`, `COMMAND`, and `ERROR` labels are
render-only local messages for session status, local command output, and local
errors; they are not persisted as structured turn history entries.

Slash commands:

- `/help`
- `/quit`
- `/status`
- `/reasoning quick|balanced|deep|max`
- `/debug on|off`
- `/json on|off`
- `/clear`
- `/doctor`
- `/autopsy <path>`
- `/context <path>`

### Output States
- **Draft / unverified**: Fast output, assumptions are made, no verification steps ran.
- **Verified**: Result has been verified via the engine's verifiers (compilation, tests).
- **Unresolved**: The engine could not resolve the task (e.g., budget exhaustion, missing facts).
- **Correction Recorded**: Engine reported a correction record. The CLI labels it non-authorizing and does not present it as proof.
- **Negative Knowledge Applied/Candidate Proposed**: Engine reported prior-failure influence or review-needed candidates. The CLI labels these as non-authorizing and does not mutate negative knowledge.
- **Epistemic State**: Engine-provided epistemic render metadata, displayed without upgrading draft/unresolved/support status.

The CLI renders these labels only from explicit JSON fields. It does not infer negative-knowledge, verifier, suppression, routing, trust-decay, correction, or epistemic semantics from arbitrary text substrings.

## Troubleshooting
If `ghost_cli` encounters issues, use these commands to diagnose the problem:
- **`ghost status`**: Checks engine availability/status, including `ghost_project_autopsy`.
- **`ghost doctor`**: Runs read-only environment and tester diagnostics, including CLI path, engine binary resolution (all binaries including `ghost_project_autopsy`), Zig version, OS/arch, terminal, PATH, and safe smoke checks. A bounded `--version` smoke check confirms autopsy binary responds; **no scan is run**.
- **`ghost autopsy`**: Runs an explicit project structure analysis scan.
- **`ghost context autopsy`**: Runs an explicit `context.autopsy` GIP request. Human output is labeled **DRAFT** and **NON-AUTHORIZING**; `--json` preserves raw engine stdout exactly.
- **`ghost <command> --debug`**: Prints the exact engine binary path, arguments, exit code, JSON parse result, and whether correction/negative-knowledge/epistemic fields were detected.
- **`ghost <command> --json`**: Preserves raw engine stdout exactly; debug diagnostics and engine stderr are written to stderr.
- **`ghost debug raw <engine-binary> [args...]`**: Bypasses all CLI formatting to run an engine binary directly and print the raw text/JSON.

## First Tester Checklist

1. Clone `ghost_engine`.
2. Run `zig build`.
3. Run `zig build test`.
4. Run `zig build bench-serious-workflows`.
5. Run `zig build test-parity`.
6. Clone `ghost_cli`.
7. Run `zig build`.
8. Run `./zig-out/bin/ghost doctor`.
9. Set `GHOST_ENGINE_ROOT` to the `ghost_engine` repo root or `zig-out/bin`.
10. Run `ghost status`.
11. Run `ghost ask hello --debug`.
12. Run `ghost tui`.

## Bug Report Template

```text
Ghost bug report

What I ran:

What I expected:

What happened:

Output from `ghost doctor --report`:

Output from `ghost status`:

Output from the failing command with `--debug`:

Notes:
```
