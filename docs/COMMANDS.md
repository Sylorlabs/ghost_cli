# Commands

Top-level help is organized around Ghost operator workflows:

- **Core**: `ask`, `chat`, `fix`, `verify`
- **Inspection**: `autopsy`, `context`, `status`, `doctor`
- **Knowledge**: `packs`, `learn`
- **Advanced**: `debug`
- **Interface**: `tui`

Every top-level command supports `ghost <command> --help` without resolving or
executing engine binaries.

### Default (no command)

Running `ghost` with no arguments launches the interactive TUI console — the same as `ghost tui`.

```bash
ghost
```

This is a renderer/front-door path. No doctor/status diagnostic, context/project
autopsy scan, verifier execution, pack mutation, or negative-knowledge mutation
is started by launch or idle rendering. Explicit slash commands and submitted
prompts may invoke engine binaries according to their command contract.

### `ghost chat`
Conversational interface to task operator.
Usage: `ghost chat --message="explain this project" --reasoning=balanced`

### `ghost ask`
Short one-shot question. Proxies to chat internals using a limited session.
Usage: `ghost ask "what does this config do?"`

### `ghost fix`
User asks Ghost to propose or perform a fix.
Usage: `ghost fix "make the failing runtime test pass" --reasoning=deep`

### `ghost verify`
Ask engine to verify current task/workspace state.
Usage: `ghost verify --reasoning=deep`
Usage: `ghost verify --context-artifact=src/main.zig --reasoning=max`

### `ghost context autopsy`
Run an explicit Context Autopsy GIP request using `ghost_gip`.

Usage: `ghost context autopsy "I need marketing advice for a launch"`
Usage: `ghost context autopsy --json "I need marketing advice for a launch"`
Usage: `ghost context autopsy --debug "I need marketing advice for a launch"`
Usage: `ghost context autopsy "Summarize this context" --input-file logs/failure.log`
Usage: `ghost context autopsy "Summarize this context" --input-file logs/failure.log --input-max-bytes 65536`

This command sends a minimal `context.autopsy` request only when explicitly
invoked. File inputs are explicit: `--input-file <path>` adds a bounded
file-backed `context.input_refs` entry for the engine to read inside the CLI's
current workspace root. The CLI passes that root to `ghost_gip --workspace`; it
does not read and embed file contents itself. Repeated `--input-file` flags are
allowed; `--input-max-bytes <bytes>` applies the same `maxBytes` value to every
input ref. Optional shared metadata flags are `--input-label`,
`--input-purpose`, and `--input-reason`.

It does not add hidden artifact refs, run hidden project/context scans, execute
verifiers, mutate packs, or mutate negative knowledge.

Human-readable output is labeled **DRAFT** and **NON-AUTHORIZING** and renders
signals, unknowns, risks, candidate actions, check candidates, pending
obligations, evidence expectations, pack influence, input coverage, artifact
coverage, and pack guidance trace fields when the engine returns them. Coverage
may report inputs requested, inputs read, bytes read, skipped inputs,
truncation/budget hits, and unknowns caused by unread or truncated regions. No
full-content claim is made when coverage reports truncation, skips, or unread
regions. `--json` preserves raw engine stdout exactly. `--debug` writes the
engine binary path, GIP kind, argv/stdin payload summary, input file ref count,
exit code, and parse status to stderr.

### `ghost packs`
Manage knowledge packs via `ghost_knowledge_pack`.

#### `ghost packs list`
List all available and mounted knowledge packs.
Usage: `ghost packs list`

#### `ghost packs inspect <pack-id>`
Show detailed information about a specific pack.
Usage: `ghost packs inspect zig_runtime_sync`
Usage: `ghost packs inspect zig_runtime_sync --version=1.0.0`

#### `ghost packs mount <pack-id>`
Mount a knowledge pack into the current session.
Usage: `ghost packs mount zig_runtime_sync`

#### `ghost packs unmount <pack-id>`
Unmount a knowledge pack.
Usage: `ghost packs unmount zig_runtime_sync`

### `ghost tui`
Interactive Ghost Console TUI. Provides a live cockpit view for interacting with the engine.

Usage: `ghost tui [--reasoning=quick|balanced|deep|max] [--context-artifact=<path>] [--no-color|--color=auto|always|never] [--compact]`

Engine prompt/response turns are persisted in TUI session history and rendered
with `YOU` and `GHOST` labels plus turn separators. `SYSTEM`, `COMMAND`, and
`ERROR` are render-only labels for local session status, local command output,
and local errors. Ghost responses still use the same renderer as terminal
chat/ask output, including correction, negative-knowledge, and epistemic
sections when the engine reports them. The status bar includes compact counters
for corrections, applied/proposed negative knowledge, verifier requirements,
suppressions, and routing warnings.

If stdin/stdout is not an interactive TTY, `ghost`/`ghost tui` exits gracefully
with a message. The covered smoke path verifies that no CLI-owned TUI command,
doctor check, context/project autopsy scan, verifier, pack mutation, or
negative-knowledge mutation is started from that non-TTY fallback.

#### Keybindings
- `Ctrl+C`: Quit
- `Ctrl+R`: Cycle reasoning level (quick → balanced → deep → max)
- `Ctrl+D`: Toggle debug mode
- `Ctrl+L`: Clear history area
- `Esc`: Quit
- `q`: Quit (only when input is empty)

#### Slash Commands
Typing `/` in the TUI shows matching slash commands. Prefix matches remain first,
with lightweight fuzzy matches for compact command fragments:

- `/` shows all commands
- `/r` shows `/reasoning`
- `/rsn` shows `/reasoning`
- `/dbg` shows `/debug`
- `/ast` shows `/autopsy`
- `/ctx` shows `/context`
- unknown prefixes show `no matching slash commands`

The suggestion area grows upward from the lower command region as more commands match, shrinks as fewer commands match, and reserves terminal rows so history does not overlap the command list. Errors render red, warnings render yellow, and labels remain plain ASCII when color is disabled.

The TUI reads live terminal dimensions on each frame, redraws periodically while idle so resize changes are picked up without another keypress, and clips command-panel rows to the current terminal width.

Invalid slash commands are rejected locally with `Not a valid command: /name` and `Type /help for available commands`. They are not sent to the engine as chat prompts.

- `/quit`: Exit TUI
- `/help`: Show help text
- `/status`: Show session turn count and settings
- `/reasoning <level>`: Change reasoning level
- `/debug on|off`: Toggle debug diagnostics
- `/json on|off`: Toggle raw JSON capture for submitted prompts
- `/clear`: Clear the local TUI history
- `/doctor`: Explicitly run read-only doctor diagnostics
- `/autopsy <path>`: Explicitly run Project Autopsy for a path
- `/context <path>`: Set context artifact path

### `ghost learn`
Feedback/distillation surface for managing knowledge growth.

#### `ghost learn candidates`
List potential knowledge distillation candidates.
Usage: `ghost learn candidates --project-shard=my-project`

#### `ghost learn show <candidate-id>`
Show detailed metrics and provenance for a specific candidate.
Usage: `ghost learn show my_candidate --project-shard=my-project`

#### `ghost learn export <candidate-id>`
Export a reviewed candidate to a persistent knowledge pack.
Usage: `ghost learn export my_candidate --project-shard=my-project --pack-id=my_pack --version=1.0.0 --approve`

### `ghost status`
Show engine availability/status and binary availability.
Usage: `ghost status`

### `ghost doctor`
Run read-only environment diagnostics for first testers.
Usage: `ghost doctor`
Usage: `ghost doctor --json`
Usage: `ghost doctor --debug`
Usage: `ghost doctor --report`
Usage: `ghost doctor --full`
Usage: `ghost doctor --run-build-check`

Default doctor is fast and non-mutating. It does not build the engine, run
expensive tests, execute verifiers, mutate packs, or change negative knowledge.
It reports the CLI version/path, current directory, `GHOST_ENGINE_ROOT`, resolved
engine binaries, executable bits, Zig version, OS/arch, terminal, PATH
resolution, and bounded smoke checks.

Binary resolution is shared with normal command execution. Candidates are classified as `engine-root`, `engine-root-zig-out`, `dev-fallback-candidate`, or `PATH-candidate`, with status `executable`, `found-not-executable`, or `missing`. If `--engine-root`/`GHOST_ENGINE_ROOT` is set, normal execution resolves only the explicit root candidates and fails early if they are missing or not executable; dev fallback and PATH candidates remain visible as diagnostics.

Engine binaries tracked by `ghost doctor` and `ghost status`:

| Binary | Role | Core? |
|--------|------|-------|
| `ghost_task_operator` | Task/chat operator | Yes |
| `ghost_code_intel` | Code intelligence | Yes |
| `ghost_patch_candidates` | Patch candidate generation | Yes |
| `ghost_knowledge_pack` | Knowledge pack management | Yes |
| `ghost_gip` | GIP protocol / engine status / Context Autopsy | No |
| `ghost_project_autopsy` | Project Autopsy pass | No |

`ghost_project_autopsy` is detected and reported by `doctor`/`status`. Doctor
also runs a **bounded, labeled, read-only smoke check**
(`ghost_project_autopsy --version`) to confirm the binary responds. No
context/project autopsy scan is run by help, doctor/status diagnostics, TUI
launch, TUI idle rendering, non-TTY fallback, or invalid slash commands. Autopsy
output is never treated as proof by the CLI.

`ghost doctor --report` prints a copy-paste tester report with OS, arch, cheap CPU/RAM/GPU probes, Zig version, Ghost version, engine root, resolved binaries, doctor result, and suggested next commands.

### `ghost autopsy`
Run an explicit Project Autopsy scan using `ghost_project_autopsy`. This command
is for explicit user execution only; help, doctor/status diagnostics, TUI
launch, TUI idle rendering, non-TTY fallback, and invalid slash commands do not
start it.

Usage: `ghost autopsy [path]`
Usage: `ghost autopsy --json [path]`
Usage: `ghost autopsy --debug [path]`

The human-readable output provides a concise summary of detected languages, build systems, safe command candidates, verifier plan candidates, and gaps/unknowns. All output is marked as **DRAFT** and **NON-AUTHORIZING**.

### `ghost context autopsy`
Run an explicit Context Autopsy request through `ghost_gip`.

Usage: `ghost context autopsy <description>`
Usage: `ghost context autopsy --json <description>`
Usage: `ghost context autopsy --debug <description>`
Usage: `ghost context autopsy <description> --input-file <path> [--input-file <path>] [--input-max-bytes <bytes>]`

The CLI constructs only the minimal GIP request with
`kind=context.autopsy` and the supplied description, plus explicit
`context.input_refs` entries when `--input-file` is supplied. File refs are read
by the engine through bounded refs under the CLI current workspace root; the CLI
does not read and embed file contents. It does not attach hidden artifact refs
automatically and does not run hidden scans, verifiers, pack mutation, or
negative-knowledge mutation. Human rendering is marked **DRAFT** and
**NON-AUTHORIZING**. When input coverage reports truncation, skips, or unread
regions, the output is not a full-content claim.

### `ghost debug`
Advanced user diagnostic tool. Bypasses JSON serialization or runs raw engine paths.
Usage: `ghost debug raw <engine-binary> [args...]`
Example: `ghost debug raw ghost_knowledge_pack list`

For rendered commands such as `ghost ask --debug`, debug output reports whether correction, negative-knowledge, and epistemic fields were detected without dumping large arrays.

When `--json` is set, engine stdout is passed through exactly. Debug diagnostics and engine stderr go to stderr.

### Common and Advanced Options

Common workflow options:

- `--message="..."`: message/request to send where supported
- `--reasoning=quick|balanced|deep|max`: engine-supported public reasoning level
- `--context-artifact=<path>`: explicit context path
- `--engine-root=<path>`: explicit `ghost_engine` binary root

Output options:

- `--json`: preserve raw engine stdout exactly where the command promises JSON passthrough
- `--no-color`: disable ANSI color in native TUI surfaces
- `--color=auto|always|never`: control native TUI color
- `--compact`: use a tighter native TUI layout

Advanced/debug options:

- `--debug`: diagnostics to stderr for rendered commands
- `--project-shard=<id>`, `--pack-id=<id>`, `--version=<v>`, `--approve`: knowledge lifecycle options
- `--report`, `--full`, `--run-build-check`: doctor-only diagnostics options

Not implemented: `--timeout-ms` and normal-command `--raw`. There is no runner
timeout contract yet, and raw engine execution remains scoped to
`ghost debug raw <engine-binary> [args...]`.

## First Tester Checklist

1. Clone `ghost_engine`.
2. Run `zig build`.
3. Run `zig build test`.
4. Run `zig build bench-serious-workflows`.
5. Run `zig build test-parity`.
6. Clone `ghost_cli`.
7. Run `zig build`.
8. Run `./zig-out/bin/ghost doctor`.
9. Set `GHOST_ENGINE_ROOT`.
10. Run `ghost status`.
11. Run `ghost ask hello --debug`.
12. Run `ghost tui`.

## Copy-Paste Bug Report Template

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
