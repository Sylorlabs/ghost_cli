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

### Examples

```bash
# General chat
ghost chat --message="explain this project" --reasoning=balanced

# One-shot questions
ghost ask "what does this config do?"

# Request a fix
ghost fix "make the failing runtime test pass" --reasoning=deep

# Verify workspace state
ghost verify --reasoning=deep
ghost verify --context-artifact=src/main.zig --reasoning=max

# Interactive TUI Console
ghost tui

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

### Output States
- **Draft / unverified**: Fast output, assumptions are made, no verification steps ran.
- **Verified**: Result has been verified via the engine's verifiers (compilation, tests).
- **Unresolved**: The engine could not resolve the task (e.g., budget exhaustion, missing facts).
- **Correction Recorded**: Engine reported a correction record. The CLI labels it non-authorizing and does not present it as proof.
- **Negative Knowledge Applied/Candidate Proposed**: Engine reported prior-failure influence or review-needed candidates. The CLI labels these as non-authorizing and does not mutate negative knowledge.
- **Epistemic State**: Engine-provided epistemic render metadata, displayed without upgrading draft/unresolved/support status.

## Troubleshooting
If `ghost_cli` encounters issues, use these commands to diagnose the problem:
- **`ghost status`**: Checks if the CLI can find the required `ghost_engine` binaries.
- **`ghost <command> --debug`**: Prints the exact engine binary path, arguments, exit code, JSON parse result, and whether correction/negative-knowledge/epistemic fields were detected.
- **`ghost debug raw <engine-binary> [args...]`**: Bypasses all CLI formatting to run an engine binary directly and print the raw text/JSON.
