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
no CLI-owned TUI command, doctor check, context/project autopsy scan, correction
proposal/review/reviewed inspection, verifier, or pack mutation was started from that fallback path.

### Examples

```bash
# Launch interactive TUI (default — no args needed)
ghost

# General chat
ghost chat --message="explain this project" --reasoning=balanced

# One-shot questions
ghost ask "what does this config do?"

# Corpus-grounded ask through GIP
ghost corpus ingest ./corpus-fixture --project-shard=my-project --trust-class=project --source-label=fixture
ghost corpus apply-staged --project-shard=my-project
ghost corpus ask "What does the corpus say about verifier execution?"
ghost corpus ask --project-shard=my-project --max-results=3 --max-snippet-bytes=512 --require-citations "What does the corpus say about retention?"
ghost corpus ask --json "What does the corpus say about verifier execution?"
ghost corpus ask --debug "What does the corpus say about verifier execution?"

# Request a fix
ghost fix "make the failing runtime test pass" --reasoning=deep

# Verify workspace state
ghost verify --reasoning=deep
ghost verify --context-artifact=src/main.zig --reasoning=max

# Explicit Context Autopsy through GIP
ghost context autopsy "I need marketing advice for a launch"
ghost context autopsy "Summarize this context" --input-file logs/failure.log --input-max-bytes 65536
ghost context autopsy --json "I need marketing advice for a launch"
ghost context autopsy --debug "I need marketing advice for a launch"

# Explicit deterministic rule evaluation through GIP
ghost rules evaluate --file request.json
ghost rules evaluate --json --file request.json
ghost rules evaluate --debug --file request.json

# Explicit correction proposal through GIP
ghost correction propose --file request.json
ghost correction propose --json --file request.json
ghost correction propose --debug --file request.json

# Explicit correction review through GIP
ghost correction review --file request.json
ghost correction review --json --file request.json
ghost correction review --debug --file request.json

# Read-only reviewed correction inspection through GIP
ghost correction reviewed list --project-shard=my-project
ghost correction reviewed list --project-shard=my-project --decision=accepted
ghost correction reviewed list --project-shard=my-project --operation-kind=corpus.ask --limit=20 --offset=0
ghost correction reviewed get --project-shard=my-project --id=reviewed-1
ghost correction reviewed list --json --project-shard=my-project
ghost correction reviewed get --debug --project-shard=my-project --id=reviewed-1

# Interactive TUI Console
ghost tui
ghost tui --reasoning=deep --compact --color=auto
ghost tui --read-only

# List knowledge packs
ghost packs list
ghost packs inspect zig_runtime_sync
ghost packs mount zig_runtime_sync --version=1.0.0
ghost packs validate-autopsy-guidance --manifest=path/to/manifest.json
ghost packs validate-autopsy-guidance --pack-id=zig_runtime_sync --version=1.0.0
ghost packs validate-autopsy-guidance --all-mounted --project-shard=my-project
ghost packs validate-autopsy-guidance --manifest=path/to/manifest.json --max-guidance-bytes=524288

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
- **Autopsy Guidance Validation**: Explicit `ghost packs validate-autopsy-guidance` checks pack guidance shape/content via the engine. It first checks `ghost_knowledge_pack capabilities --json`, requires an advertised validation command and supported schema versions, and routes validation limit overrides only when advertised. Human mode renders clean success, warning, and error summaries without raw Zig traces; `--json` preserves raw engine stdout exactly. It is review-only: no pack mutation, no auto-fix, no auto-promotion, and no proof upgrade.
- **Corpus Lifecycle**: Explicit `ghost corpus ingest` stages corpus through `ghost_corpus_ingest`; explicit `ghost corpus apply-staged` promotes staged corpus into the live shard corpus. Staged corpus is not visible to `ghost corpus ask` before apply. `--json` preserves raw engine stdout; the verified engine emits JSON for ingest/apply without accepting a separate engine `--json` flag.
- **Corpus Ask**: Explicit `ghost corpus ask` calls `ghost_gip` operation `corpus.ask` against live shard corpus excerpts. Human output is **DRAFT** and **NON-AUTHORIZING**, renders bounded evidence and unknowns, labels learning candidates as candidate-only/not-persisted, renders `similarCandidates` separately as non-authorizing routing hints, and preserves raw stdout under `--json`. If `capacityTelemetry` reports pressure or `capacity_limited` unknowns are present, it prints **CAPACITY / COVERAGE WARNING**: skipped, dropped, truncated, or capped data is partial coverage and cannot support an answer. Accepted reviewed corrections may render as **ACCEPTED CORRECTION INFLUENCE / NON-AUTHORIZING** warnings, telemetry, and candidate-only future behavior; they are not proof, not evidence, not global promotion, and are never Evidence Used. Exact repeated `wrong_answer` patterns may suppress `answerDraft`; human mode says the draft was suppressed by accepted correction influence. Exact evidence is required for answer drafts; approximate similarity hints are not proof or Evidence Used. Retrieval is bounded local matching, not semantic search; there are no Transformers/embeddings/model adapters, and mounted pack corpus is not included yet.
- **Rule Evaluation**: Explicit `ghost rules evaluate --file <request.json>` calls `ghost_gip` operation `rule.evaluate` with the request file bytes. Human output is **DRAFT / NON-AUTHORIZING** and renders fired rules, candidates, obligations, unknowns, explanation traces, safety flags, and **RULE CAPACITY WARNING / NON-AUTHORIZING** when capacity telemetry reports pressure. Same-shard accepted reviewed corrections may render as **ACCEPTED CORRECTION INFLUENCE / NON-AUTHORIZING** warnings, influences, telemetry, exact repeated-output suppression, and **FUTURE BEHAVIOR CANDIDATES / NOT APPLIED**. Rule outputs and correction influence are candidates only, not proof or evidence; capacity-limited evaluation is incomplete; verifiers/checks are not executed; rules, packs, corpus, negative knowledge, and correction records are not mutated; accepted corrections are not globally promoted. Evaluation is deterministic bounded structural matching only: no recursive inference, no Prolog, no Transformers, no embeddings, no model adapters, no ranking model, no cloud calls, and no semantic search.
- **Correction Proposal**: Explicit `ghost correction propose --file <request.json>` calls `ghost_gip` operation `correction.propose` with the request file bytes. Human output renders correction candidates and learning candidates as **CORRECTION CANDIDATE ONLY**, **NOT PROOF**, **REVIEW REQUIRED**, **NO KNOWLEDGE MUTATED**, **NO VERIFIERS EXECUTED**, **NOT ACCEPTED**, and **NOT PERSISTED**. User corrections are signals, not proof; proposals do not mutate corpus, packs, or negative knowledge, do not execute verifier/check candidates, do not affect future behavior, and do not run as hidden learning. There is no `correction.accept` command yet.
- **Correction Review**: Explicit `ghost correction review --file <request.json>` calls `ghost_gip` operation `correction.review` with the request file bytes. Human output renders reviewed correction records as **REVIEWED CORRECTION RECORD**, **APPEND-ONLY**, **NOT PROOF**, **NON-AUTHORIZING**, **NO GLOBAL PROMOTION**, **NO KNOWLEDGE MUTATED**, **NO VERIFIERS EXECUTED**, and **FUTURE BEHAVIOR IS CANDIDATE-ONLY**. Accepted reviewed corrections are still not proof, do not mutate corpus/packs/negative knowledge, do not execute verifiers/checks, and do not imply global promotion.
- **Reviewed Correction Inspection**: Explicit `ghost correction reviewed list --project-shard=<id>` and `ghost correction reviewed get --project-shard=<id> --id=<record-id>` call `ghost_gip` operations `correction.reviewed.list` and `correction.reviewed.get`. The CLI builds read-only GIP requests from flags, never reads or writes `reviewed_corrections.jsonl` directly, and preserves raw stdout under `--json`. Human output is **READ-ONLY**, **NOT PROOF**, **NON-AUTHORIZING**, **NO KNOWLEDGE MUTATED**, and **NO VERIFIERS EXECUTED**. List output renders counts, warnings, capacity telemetry, and append-order records; get output renders the reviewed record summary, accepted/rejected details, append-only metadata, and warnings/not_found. The engine bounds reads to 128 records and 256 KiB; `--cursor=<n>` is only the current numeric offset alias.
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
- Knowledge: `packs`, `corpus`, `correction`, `learn`
- Advanced: `rules`, `debug`
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

`ghost --read-only` and `ghost tui --read-only` launch the TUI in a local
read-only mode. Local/session commands such as `/help`, `/status`, `/reasoning`,
`/debug`, `/json`, `/clear`, and `/context` remain available, while submitted
prompts plus `/doctor` and `/autopsy` are blocked locally. The blocked-command
message is `Read-only mode: command blocked: /name`, and the status bar shows
`read_only=on`.

Typing `/` shows lightweight native slash-command suggestions. Prefix matches
stay first, and compact fuzzy fragments such as `/rsn`, `/dbg`, `/ast`, and
`/ctx` suggest `/reasoning`, `/debug`, `/autopsy`, and `/context`. Invalid slash
commands are rejected in the TUI with a clear `ERROR` message and are not sent
to the engine as normal prompts.
The suggestion area grows upward from the lower command region when more matches
are visible, shrinks again as matches narrow, and reserves terminal rows so
history stays separate. Native ANSI color stays restrained: errors are red,
warnings are yellow, and the same labels remain readable with `--no-color`.
The TUI caches terminal dimensions and RAM/status metrics, refreshing them on
startup and periodic redraw instead of probing on every keypress. Resizes are
picked up without another keypress, command-panel rows are clipped to the
current width, and very small terminals hide suggestions rather than overlapping
the footer/input rows.

Engine prompt/response turns are retained in bounded TUI session history and rendered
with `YOU` and `GHOST` labels. `SYSTEM`, `COMMAND`, and `ERROR` labels are
render-only local messages for session status, local command output, and local
errors; they are not persisted as structured turn history entries. The default
retained history limit is 500 turns and can be changed with
`--max-history-turns=<n>`; the footer reports retained, total, and pruned turn
counts.

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
- **`ghost doctor`**: Runs read-only environment and tester diagnostics, including CLI path, engine binary resolution (all binaries including `ghost_project_autopsy`), Zig version, OS/arch, terminal, PATH, safe smoke checks, and knowledge-pack validation capability compatibility. A bounded `--version` smoke check confirms autopsy binary responds; a bounded `ghost_knowledge_pack capabilities --json` diagnostic reports validation compatibility; **no scan or validation is run**.
- **`ghost autopsy`**: Runs an explicit project structure analysis scan.
- **`ghost context autopsy`**: Runs an explicit `context.autopsy` GIP request. `--input-file <path>` adds explicit bounded file refs under `context.input_refs`; the engine reads those refs inside the CLI current workspace root and the CLI does not embed file contents. Human output is labeled **DRAFT** and **NON-AUTHORIZING** and renders input/artifact coverage when present. If coverage reports skipped, truncated, budget-hit, unread, or coverage-derived unknown material, human output prints `COVERAGE WARNING` and states that Ghost did not inspect all provided material; `--json` preserves raw engine stdout exactly.
- **`ghost corpus ingest`**: Stages corpus data explicitly. It does not make staged corpus live or visible to ask.
- **`ghost corpus apply-staged`**: Promotes staged corpus into live shard corpus explicitly.
- **`ghost corpus ask`**: Runs an explicit `corpus.ask` GIP request against live shard corpus only. Human output is labeled **DRAFT** and **NON-AUTHORIZING**. It renders `answerDraft` only when exact `evidenceUsed` supports one, shows `evidenceUsed`, unknowns, candidate followups, candidate-only learning candidates, separately labels `similarCandidates` as **Similarity Hints / NON-AUTHORIZING**, renders accepted reviewed correction influence as **ACCEPTED CORRECTION INFLUENCE / NON-AUTHORIZING**, renders `futureBehaviorCandidates` as **FUTURE BEHAVIOR CANDIDATES / NOT APPLIED**, renders trace flags, and prints **CAPACITY / COVERAGE WARNING** when telemetry or `capacity_limited` unknowns disclose partial coverage. No corpus, weak evidence, conflicting evidence, capped/skipped/truncated coverage without exact retained evidence, approximate-only similarity, or accepted correction suppression produces no answer. Accepted corrections are not proof or evidence, may suppress exact repeated bad patterns, and do not globally promote or mutate corpus, packs, or negative knowledge. It does not ingest corpus, mutate packs or negative knowledge, persist learning candidates, run commands, or run verifiers.
- **`ghost correction review`**: Records explicit accepted/rejected correction reviews through `correction.review`. It renders the reviewed record, decision, reviewer note, rejected reason when present, accepted learning outputs when present, future behavior candidate when present, append-only metadata, mutation flags, and authority flags. It preserves raw stdout under `--json`; debug diagnostics go to stderr.
- **`ghost correction reviewed list|get`**: Inspects reviewed correction records through read-only `correction.reviewed.list` and `correction.reviewed.get`. Records are not proof and do not mutate corpus, packs, negative knowledge, correction storage, or verifier state. List/get are bounded; malformed lines render as warnings/telemetry, and missing records render as `not_found`.
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
