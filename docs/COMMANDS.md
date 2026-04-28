# Commands

### Default (no command)

Running `ghost` with no arguments launches the interactive TUI console — the same as `ghost tui`.

```bash
ghost
```

This is a pure renderer/front-door path. No engine logic, Project Autopsy scanning, verifier execution, or pack mutation occurs on launch. The TUI presents an interactive prompt; the engine is only invoked when the user submits a query.

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

Usage: `ghost tui [--reasoning=quick|balanced|deep|max] [--context-artifact=<path>]`

History output uses the same renderer as terminal chat/ask output, including correction, negative-knowledge, and epistemic sections when the engine reports them. The status bar includes compact counters for corrections, applied/proposed negative knowledge, verifier requirements, suppressions, and routing warnings.

#### Keybindings
- `Ctrl+C`: Quit
- `Ctrl+R`: Cycle reasoning level (quick → balanced → deep → max)
- `Ctrl+D`: Toggle debug mode
- `Ctrl+L`: Clear history area
- `Esc`: Quit
- `q`: Quit (only when input is empty)

#### Slash Commands
- `/quit`: Exit TUI
- `/help`: Show help text
- `/status`: Show session turn count and settings
- `/reasoning <level>`: Change reasoning level
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

Default doctor is fast and non-mutating. It does not build the engine, run expensive tests, execute verifiers, mutate packs, or change negative knowledge. It reports the CLI version/path, current directory, `GHOST_ENGINE_ROOT`, resolved engine binaries, executable bits, Zig version, OS/arch, terminal, PATH resolution, and safe smoke checks.

Engine binaries tracked by `ghost doctor` and `ghost status`:

| Binary | Role | Core? |
|--------|------|-------|
| `ghost_task_operator` | Task/chat operator | Yes |
| `ghost_code_intel` | Code intelligence | Yes |
| `ghost_patch_candidates` | Patch candidate generation | Yes |
| `ghost_knowledge_pack` | Knowledge pack management | Yes |
| `ghost_gip` | GIP protocol / engine status | No |
| `ghost_project_autopsy` | Project Autopsy pass | No |

`ghost_project_autopsy` is detected and reported by `doctor`/`status`. Doctor also runs a **bounded, labeled, read-only smoke check** (`ghost_project_autopsy --version`) to confirm the binary responds. **No scan is ever run automatically.** Autopsy output is never treated as proof by the CLI.

`ghost doctor --report` prints a copy-paste tester report with OS, arch, cheap CPU/RAM/GPU probes, Zig version, Ghost version, engine root, resolved binaries, doctor result, and suggested next commands.

### `ghost debug`
Advanced user diagnostic tool. Bypasses JSON serialization or runs raw engine paths.
Usage: `ghost debug raw <engine-binary> [args...]`
Example: `ghost debug raw ghost_knowledge_pack list`

For rendered commands such as `ghost ask --debug`, debug output reports whether correction, negative-knowledge, and epistemic fields were detected without dumping large arrays.

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
