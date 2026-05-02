# Commands

Top-level help is organized around Ghost operator workflows:

- **Core**: `ask`, `chat`, `fix`, `verify`
- **Inspection**: `autopsy`, `context`, `status`, `doctor`
- **Knowledge**: `packs`, `corpus`, `correction`, `nk`, `learn`
- **Advanced**: `rules`, `debug`
- **Interface**: `tui`

Every top-level command supports `ghost <command> --help` without resolving or
executing engine binaries.

### Default (no command)

Running `ghost` with no arguments launches the interactive TUI console — the same as `ghost tui`.

```bash
ghost
```

This is a renderer/front-door path. No doctor/status diagnostic, context/project
autopsy scan, correction proposal, verifier execution, pack mutation,
negative-knowledge mutation, correction review, reviewed correction inspection,
or reviewed negative-knowledge review/list/get is started by launch or idle rendering. Explicit
slash commands and submitted prompts may invoke engine binaries according to
their command contract.

### `ghost chat`
Conversational interface to task operator.
Usage: `ghost chat --message="explain this project" --reasoning=balanced`

### `ghost ask`
Short one-shot question. Proxies to chat internals using a limited session.
Usage: `ghost ask "what does this config do?"`

### `ghost corpus`
Explicit corpus lifecycle commands.

#### `ghost corpus ingest`
Stage corpus data through `ghost_corpus_ingest`.

Usage: `ghost corpus ingest ./corpus-fixture --project-shard=my-project --trust-class=project --source-label=fixture`
Usage: `ghost corpus ingest ./corpus-fixture --project-shard=my-project --trust-class=project --source-label=fixture --json`
Usage: `ghost corpus ingest ./corpus-fixture --project-shard=my-project --trust-class=project --source-label=fixture --debug`

This command is explicit only. It routes to `ghost_corpus_ingest <path>` with
optional `--project-shard=<id>`, `--trust-class=<class>`, and
`--source-label=<label>`. Human output says the result is **STAGED** and **NOT
LIVE**. Staged corpus is not visible to `ghost corpus ask` until
`ghost corpus apply-staged` succeeds.

`--json` preserves raw engine stdout exactly. The verified engine at
`707ae0c7e14f1f0eb91b2a536b89489eeea95e9c` emits JSON from
`ghost_corpus_ingest` but does not accept a separate `--json` flag, so the CLI
does not forward one. `--debug` writes routed argv, engine path, exit code, and
parse status to stderr.

#### `ghost corpus apply-staged`
Promote staged corpus into the live shard corpus through
`ghost_corpus_ingest --apply-staged`.

Usage: `ghost corpus apply-staged --project-shard=my-project`
Usage: `ghost corpus apply-staged --project-shard=my-project --json`
Usage: `ghost corpus apply-staged --project-shard=my-project --debug`

This command is explicit only. Human output says the staged corpus was applied /
promoted to the live corpus. After apply succeeds, `ghost corpus ask` can read
the live shard corpus. It does not run from help, startup, TUI launch, doctor,
or status.

`--json` preserves raw engine stdout exactly. `--debug` writes diagnostics to
stderr only.

#### `ghost corpus ask`
Run an explicit corpus-grounded ask through `ghost_gip` operation `corpus.ask`.

Usage: `ghost corpus ask "What does the corpus say about verifier execution?"`
Usage: `ghost corpus ask --json "What does the corpus say about verifier execution?"`
Usage: `ghost corpus ask --debug "What does the corpus say about verifier execution?"`
Usage: `ghost corpus ask --project-shard=my-project --max-results=3 --max-snippet-bytes=512 --require-citations "What does the corpus say about retention?"`

This command is explicit only. It sends `kind: "corpus.ask"` to
`ghost_gip --stdin` with `question`, optional `projectShard`, optional
`maxResults`, optional `maxSnippetBytes`, and optional `requireCitations`.
Existing `ghost ask` behavior is unchanged.

Human-readable output is labeled **DRAFT** and **NON-AUTHORIZING**. Exact
`evidenceUsed` controls answer drafts. When the engine returns `answerDraft`,
the CLI renders it with bounded `evidenceUsed` fields such as corpus path,
source path, class, snippet, reason, provenance, and score. If the engine
reports `no_corpus_available`,
`insufficient_evidence`, or `conflicting_evidence`, human mode clearly says no
answer was produced and renders the unknowns. `candidateFollowups` are rendered
as candidates. `learningCandidates` are labeled **CANDIDATE ONLY / NOT
PERSISTED**.

When `capacityTelemetry` reports pressure or unknowns include
`capacity_limited`, the CLI prints `CAPACITY / COVERAGE WARNING` near the top.
This means Ghost did not inspect or retain all potentially relevant data.
Skipped, dropped, truncated, or capped data is partial coverage and cannot
support an answer. Exact evidence is still required for `answerDraft`; exact
retained evidence may produce a draft while the warning discloses incomplete
coverage.

`similarCandidates` may appear as **Similarity Hints / NON-AUTHORIZING**. They
are approximate local SimHash routing hints with fields such as corpus item/path,
Hamming distance, similarity score, reason `simhash_near_duplicate`, and
`nonAuthorizing: true`. They are not evidence, proof, or answer support; they do
not populate `evidenceUsed`, and approximate-only matches do not render an
answer draft.

Accepted reviewed corrections may influence `corpus.ask` as
**ACCEPTED CORRECTION INFLUENCE / NON-AUTHORIZING**. Human mode renders
`acceptedCorrectionWarnings`, `correctionInfluences`, `influenceTelemetry`, and
`futureBehaviorCandidates` when present. These fields are warnings and
candidate-only future behavior, not proof, evidence, support, or global
promotion. They are never rendered under Evidence Used. Exact repeated
`wrong_answer` patterns may suppress `answerDraft`; when that happens, human
mode says the draft was suppressed by accepted correction influence rather than
presenting it as no corpus or generic insufficient evidence.

Accepted reviewed negative knowledge may influence `corpus.ask` as
**REVIEWED NEGATIVE KNOWLEDGE INFLUENCE / NON-AUTHORIZING**. Human mode renders
`acceptedNegativeKnowledgeWarnings`, `negativeKnowledgeInfluences`,
`negativeKnowledgeTelemetry`, and NK-originated `futureBehaviorCandidates` when
present. These fields are warnings and candidate-only future behavior, not
proof, evidence, support, or global promotion. They are never rendered under
Evidence Used. Exact repeated known-bad answer patterns may suppress
`answerDraft`; when that happens, human mode says the draft was suppressed by
reviewed negative knowledge influence rather than presenting it as no corpus or
generic insufficient evidence.

`futureBehaviorCandidates` are rendered as **FUTURE BEHAVIOR CANDIDATES / NOT
APPLIED**. They are candidates only, are not persisted as corpus, pack, rule,
correction, or negative-knowledge updates by this operation, and do not execute
verifiers or checks.

Retrieval is bounded local matching over live shard corpus excerpts only. Exact
evidence remains required for answers. It is not semantic search, and there are
no Transformers, embeddings, or model adapters in this path. Mounted pack corpus
is not included yet. The command does not ingest corpus, read staged-only
corpus, mutate corpus, mutate packs, mutate negative knowledge, run commands,
run verifiers, persist learning candidates, or run automatically from startup,
TUI launch, doctor, or status.

`--json` preserves raw GIP stdout exactly. `--debug` writes diagnostics to
stderr only, including the engine binary path, GIP kind, argv/stdin summary,
exit code, and JSON parse status.

### `ghost rules`
Advanced/debug rule evaluation commands.

#### `ghost rules evaluate`
Run an explicit deterministic rule evaluation through `ghost_gip` operation
`rule.evaluate`.

Usage: `ghost rules evaluate --file request.json`
Usage: `ghost rules evaluate --json --file request.json`
Usage: `ghost rules evaluate --debug --file request.json`

The file must be a GIP-compatible JSON request with top-level
`kind: "rule.evaluate"`. The CLI reads the file, validates that kind, and sends
the bytes unchanged to `ghost_gip --stdin`. It does not invent a rule
mini-language.

Human-readable output is labeled **DRAFT / NON-AUTHORIZING** and includes:
fired rules, emitted candidates, emitted obligations, unknowns, explanation
trace, and safety flags. It prints these required safety labels:
`RULE OUTPUTS ARE CANDIDATES ONLY`, `NOT PROOF`, `VERIFIERS NOT EXECUTED`, and
`PACKS / CORPUS / NEGATIVE KNOWLEDGE NOT MUTATED`.

When `capacityTelemetry` reports pressure, the CLI prints `RULE CAPACITY
WARNING / NON-AUTHORIZING`. Output, fired-rule, or rule caps mean evaluation is
incomplete: emitted rule outputs remain candidates only, rejected or capped
outputs are not proof, and no support gate was discharged.

When same-shard accepted reviewed corrections influence `rule.evaluate`, human
mode renders **ACCEPTED CORRECTION INFLUENCE / NON-AUTHORIZING**. It displays
`acceptedCorrectionWarnings`, `correctionInfluences`, `influenceTelemetry`, and
`futureBehaviorCandidates` separately from fired rules and emitted outputs.
Accepted correction influence is not proof, not evidence, not support, and not
global promotion. Exact repeated bad rule outputs may be suppressed; when that
happens, human mode says a rule output was suppressed by accepted correction
influence and does not render the suppressed output as active.

When same-shard accepted reviewed negative knowledge influences `rule.evaluate`,
human mode renders **REVIEWED NEGATIVE KNOWLEDGE INFLUENCE /
NON-AUTHORIZING**. It displays `acceptedNegativeKnowledgeWarnings`,
`negativeKnowledgeInfluences`, `negativeKnowledgeTelemetry`, and NK-originated
`futureBehaviorCandidates` separately from fired rules and emitted outputs.
Reviewed NK influence is not proof, not evidence, not support, and not global
promotion. Exact repeated known-bad rule outputs may be suppressed; when that
happens, human mode says a rule output was suppressed by reviewed negative
knowledge influence and does not render the suppressed output as active.

`futureBehaviorCandidates` are rendered as **FUTURE BEHAVIOR CANDIDATES / NOT
APPLIED**. They are candidates only, are not persisted as rule, corpus, pack, or
negative-knowledge updates by this operation, and do not execute verifiers or
checks.

Rule evaluation is deterministic bounded rule matching over request-local facts
and rules. If `projectShard` / `project_shard` is supplied, accepted reviewed
corrections and accepted reviewed negative knowledge are read from that same
shard only. Matching is conservative and structural: exact text, substring, or
deterministic fingerprint matching against rule/output/obligation/unknown/trace
fields. It is not recursive inference, not Prolog, not semantic search, and
does not use Transformers, embeddings, model adapters, ranking models, cloud
calls, or network calls. It does not execute emitted checks or verifier
candidates, mutate rules, mutate corpus, mutate packs, mutate negative
knowledge, mutate correction records, globally promote corrections or reviewed
NK, or grant proof/support.

This command is explicit only. It does not run from help, startup, TUI launch,
doctor, status, `corpus ask`, `context autopsy`, or pack validation.

`--json` preserves raw GIP stdout exactly. `--debug` writes diagnostics to
stderr only, including engine path, GIP kind, input file path, stdin byte count,
exit code, and parse status.

### `ghost correction`
Explicit correction proposal and review commands.

#### `ghost correction propose`
Run an explicit correction proposal through `ghost_gip` operation
`correction.propose`.

Usage: `ghost correction propose --file request.json`
Usage: `ghost correction propose --json --file request.json`
Usage: `ghost correction propose --debug --file request.json`

The file must be a full GIP-compatible JSON request with top-level
`kind: "correction.propose"`. The CLI reads the file, validates that kind, and
sends the bytes unchanged to `ghost_gip --stdin`. It does not invent a
correction mini-language and does not auto-fill fields from previous CLI output.

Human-readable output renders the correction candidate, correction type,
original operation/request information when present, disputed output, user
correction, evidence refs, proposed learning outputs, learning candidates,
unknowns, mutation flags, and authority flags. It prints these required safety
labels: `CORRECTION CANDIDATE ONLY`, `NOT PROOF`, `REVIEW REQUIRED`,
`NO KNOWLEDGE MUTATED`, `NO VERIFIERS EXECUTED`, `NOT ACCEPTED`, and
`NOT PERSISTED`.

User corrections are signals, not proof. Correction proposals are
candidate-only and review-required. Rendering them does not mutate corpus,
packs, or negative knowledge; does not execute verifier/check candidates; does
not persist learning candidates; does not accept the correction; and does not
affect future behavior. There is no hidden learning and no `correction.accept`
command yet.

This command is explicit only. It does not run from help, startup, TUI launch,
doctor, status, `corpus ask`, `rules evaluate`, `context autopsy`, or pack
validation.

`--json` preserves raw GIP stdout exactly. `--debug` writes diagnostics to
stderr only, including engine path, GIP kind, input file path, stdin byte count,
exit code, and parse status.

#### `ghost correction review`
Run an explicit correction review through `ghost_gip` operation
`correction.review`.

Usage: `ghost correction review --file request.json`
Usage: `ghost correction review --json --file request.json`
Usage: `ghost correction review --debug --file request.json`

The file must be a full GIP-compatible JSON request with top-level
`kind: "correction.review"`. The CLI reads the file, validates that kind, and
sends the bytes unchanged to `ghost_gip --stdin`. It does not invent accept /
reject flags yet and does not auto-fill fields from previous proposal output.

Human-readable output renders the reviewed correction record, decision,
reviewer note, rejected reason when present, accepted learning outputs when
present, future behavior candidate when present, append-only storage metadata,
mutation flags, and authority flags. It prints these required safety labels:
`REVIEWED CORRECTION RECORD`, `APPEND-ONLY`, `NOT PROOF`,
`NON-AUTHORIZING`, `NO GLOBAL PROMOTION`, `NO KNOWLEDGE MUTATED`,
`NO VERIFIERS EXECUTED`, and `FUTURE BEHAVIOR IS CANDIDATE-ONLY`.

Correction review records explicit accept/reject decisions. Accepted reviewed
corrections are still not proof, do not mutate corpus, packs, or negative
knowledge, do not execute verifier/check candidates, and do not imply global
promotion. Future behavior is candidate-only.

This command is explicit only. It does not run from help, startup, TUI launch,
doctor, status, `correction propose`, `corpus ask`, `rules evaluate`,
`context autopsy`, or pack validation.

`--json` preserves raw GIP stdout exactly. `--debug` writes diagnostics to
stderr only, including engine path, GIP kind, input file path, stdin byte count,
exit code, and parse status.

#### `ghost correction reviewed list`
Inspect reviewed correction records through `ghost_gip` operation
`correction.reviewed.list`.

Usage: `ghost correction reviewed list --project-shard=my-project`
Usage: `ghost correction reviewed list --project-shard=my-project --decision=accepted`
Usage: `ghost correction reviewed list --project-shard=my-project --decision=rejected`
Usage: `ghost correction reviewed list --project-shard=my-project --decision=all --operation-kind=corpus.ask`
Usage: `ghost correction reviewed list --project-shard=my-project --limit=20 --offset=40`
Usage: `ghost correction reviewed list --json --project-shard=my-project`
Usage: `ghost correction reviewed list --debug --project-shard=my-project`

The CLI builds the GIP JSON request from flags and sends it to
`ghost_gip --stdin`. It does not read or write `reviewed_corrections.jsonl`
directly. `--cursor=<n>` is accepted as the engine's current numeric alias for
`--offset=<n>`; it is not documented as an opaque cursor.

Human output is labeled **REVIEWED CORRECTION RECORDS / READ-ONLY** and always
prints `READ-ONLY`, `NOT PROOF`, `NON-AUTHORIZING`, `NO KNOWLEDGE MUTATED`, and
`NO VERIFIERS EXECUTED`. It renders project shard, `totalRead`,
`returnedCount`, `malformedLines`, warnings, capacity telemetry when present,
records in append order, decision, id, operation kind, reviewer note summary
when present, and authority/mutation flags.

This command is bounded by the engine: at most 128 records and 256 KiB are read
per request. Missing storage returns an empty list. Malformed lines render as
warnings and telemetry; they do not crash the CLI.

This command is explicit only. It does not run from help, startup, TUI launch,
doctor, status, `correction propose`, `correction review`, `corpus ask`,
`rules evaluate`, `context autopsy`, or pack validation.

`--json` preserves raw GIP stdout exactly. `--debug` writes diagnostics to
stderr only, including engine path, GIP kind, project shard, stdin byte count,
exit code, and parse status.

#### `ghost correction reviewed get`
Inspect one reviewed correction record through `ghost_gip` operation
`correction.reviewed.get`.

Usage: `ghost correction reviewed get --project-shard=my-project --id=reviewed-1`
Usage: `ghost correction reviewed get --json --project-shard=my-project --id=reviewed-1`
Usage: `ghost correction reviewed get --debug --project-shard=my-project --id=reviewed-1`

The CLI builds the GIP JSON request from flags and sends it to
`ghost_gip --stdin`. It does not read or write `reviewed_corrections.jsonl`
directly.

Human output is labeled **REVIEWED CORRECTION RECORD / READ-ONLY** and always
prints `READ-ONLY`, `NOT PROOF`, `NON-AUTHORIZING`, `NO KNOWLEDGE MUTATED`, and
`NO VERIFIERS EXECUTED`. It renders the full reviewed record summary, decision,
reviewer note, accepted learning outputs, rejected reason, future behavior
candidate, append-only metadata, warnings for missing/malformed data, and
authority/mutation flags.

Missing storage or a missing record renders cleanly as `not_found`. Reviewed
records remain read-only inspection data: not proof, not evidence support, not
global promotion, and not authorization for future output.

This command is explicit only. It does not run from help, startup, TUI launch,
doctor, status, `correction propose`, `correction review`, `corpus ask`,
`rules evaluate`, `context autopsy`, or pack validation.

`--json` preserves raw GIP stdout exactly. `--debug` writes diagnostics to
stderr only, including engine path, GIP kind, project shard, record id, stdin
byte count, exit code, and parse status.

#### `ghost correction influence status`
Inspect read-only influence status counts and bounded records through `ghost_gip`
operation `correction.influence.status`.

Usage: `ghost correction influence status --project-shard=my-project`
Usage: `ghost correction influence status --project-shard=my-project --operation-kind=corpus.ask`
Usage: `ghost correction influence status --project-shard=my-project --include-records`
Usage: `ghost correction influence status --project-shard=my-project --include-records --limit=5`

The CLI builds the GIP JSON request from flags and sends it to `ghost_gip --stdin`.
It does not read or write `reviewed_corrections.jsonl` directly.

Human output is labeled **CORRECTION INFLUENCE STATUS / READ-ONLY** and always
prints `READ-ONLY`, `NOT PROOF`, `NON-AUTHORIZING`, `NO GLOBAL PROMOTION`,
`NO KNOWLEDGE MUTATED`, `NO VERIFIERS EXECUTED`, and `STATUS COUNTS ARE OPERATOR DIAGNOSTICS ONLY`.

It renders accepted/rejected records, malformed lines, operation kind counts,
correction type counts, influence kind counts, warnings, and capacity telemetry.
If `--include-records` is passed, it renders the sampled reviewed records.

This command is explicit only. It does not run from help, startup, TUI launch,
doctor, status, `correction propose`, `correction review`, `corpus ask`,
`rules evaluate`, `context autopsy`, or pack validation.

`--json` preserves raw GIP stdout exactly. `--debug` writes diagnostics to
stderr only, including engine path, GIP kind, project shard, operation filter,
includeRecords, limit, stdin byte count, exit code, and parse status.

### `ghost nk`
Explicit reviewed negative-knowledge commands.

#### `ghost nk review`
Run an explicit reviewed negative-knowledge decision through `ghost_gip`
operation `negative_knowledge.review`.

Usage: `ghost nk review --file request.json`
Usage: `ghost nk review --json --file request.json`
Usage: `ghost nk review --debug --file request.json`

The file must be a full GIP-compatible JSON request with top-level
`kind: "negative_knowledge.review"`. The CLI reads the file, validates that
kind, and sends the bytes unchanged to `ghost_gip --stdin`. It does not invent
accept/reject flags yet and does not read or write
`negative_knowledge/reviewed_negative_knowledge.jsonl` directly.

Human-readable output renders the reviewed negative-knowledge record, decision,
reviewer note, rejected reason when present, source candidate id, source
correction review id when present, candidate snapshot, append-only metadata,
mutation flags, and authority flags. It prints these required safety labels:
`REVIEWED NEGATIVE KNOWLEDGE RECORD`, `APPEND-ONLY`, `NOT PROOF`,
`NOT EVIDENCE`, `NON-AUTHORIZING`, `NO GLOBAL PROMOTION`,
`NO CORPUS OR PACK MUTATION`, `NO VERIFIERS EXECUTED`, and
`ACCEPTED NK MAY INFLUENCE SAME-SHARD CORPUS/RULE OUTPUTS ONLY AS
NON-AUTHORIZING WARNINGS, SUPPRESSION, OR CANDIDATES`.

Reviewed NK records are append-only and project-shard local. Accepted reviewed
NK is durable and inspectable, but it is still not proof, not evidence, not
global promotion. It may influence same-shard `corpus.ask` and `rule.evaluate`
only as non-authorizing warnings, suppression, stronger-evidence/verifier
candidates, or future behavior candidates. Influence uses conservative
structural matching only; no semantic search, embeddings, Transformers, model
adapters, ranking model, cloud calls, or network calls are used.
`negativeKnowledgeMutation:true` means only that this explicit review appended
a reviewed NK record.

This command is explicit only. It does not run from help, startup, TUI launch,
doctor, status, correction commands, `corpus ask`, `rules evaluate`,
`context autopsy`, or pack validation.

`--json` preserves raw GIP stdout exactly. `--debug` writes diagnostics to
stderr only, including engine path, GIP kind, input file path, stdin byte count,
exit code, and parse status.

#### `ghost nk reviewed list`
Inspect reviewed negative-knowledge records through `ghost_gip` operation
`negative_knowledge.reviewed.list`.

Usage: `ghost nk reviewed list --project-shard=my-project`
Usage: `ghost nk reviewed list --project-shard=my-project --decision=accepted`
Usage: `ghost nk reviewed list --project-shard=my-project --decision=rejected`
Usage: `ghost nk reviewed list --project-shard=my-project --decision=all`
Usage: `ghost nk reviewed list --project-shard=my-project --limit=20 --offset=40`
Usage: `ghost nk reviewed list --json --project-shard=my-project`
Usage: `ghost nk reviewed list --debug --project-shard=my-project`

The CLI builds the GIP JSON request from flags and sends it to
`ghost_gip --stdin`. It does not read or write
`negative_knowledge/reviewed_negative_knowledge.jsonl` directly. `--cursor=<n>`
is accepted as the current numeric alias for `--offset=<n>`.

Human output is labeled **REVIEWED NEGATIVE KNOWLEDGE RECORDS / READ-ONLY** and
always prints `READ-ONLY`, `NOT PROOF`, `NOT EVIDENCE`, `NON-AUTHORIZING`,
`NO KNOWLEDGE MUTATED`, and `NO VERIFIERS EXECUTED`. It renders project shard,
counts, malformed line warnings, capacity telemetry, record summaries in append
order, decisions, ids, and mutation/authority flags.

Missing storage returns an empty list. Malformed JSONL lines render as warnings
and telemetry; they do not crash the CLI.

This command is explicit only. It does not run from help, startup, TUI launch,
doctor, status, correction commands, `corpus ask`, `rules evaluate`,
`context autopsy`, or pack validation.

`--json` preserves raw GIP stdout exactly. `--debug` writes diagnostics to
stderr only, including engine path, GIP kind, project shard, stdin byte count,
exit code, and parse status.

#### `ghost nk reviewed get`
Inspect one reviewed negative-knowledge record through `ghost_gip` operation
`negative_knowledge.reviewed.get`.

Usage: `ghost nk reviewed get --project-shard=my-project --id=nk-reviewed-1`
Usage: `ghost nk reviewed get --json --project-shard=my-project --id=nk-reviewed-1`
Usage: `ghost nk reviewed get --debug --project-shard=my-project --id=nk-reviewed-1`

The CLI builds the GIP JSON request from flags and sends it to
`ghost_gip --stdin`. It does not read or write
`negative_knowledge/reviewed_negative_knowledge.jsonl` directly.

Human output is labeled **REVIEWED NEGATIVE KNOWLEDGE RECORD / READ-ONLY** and
always prints `READ-ONLY`, `NOT PROOF`, `NOT EVIDENCE`, `NON-AUTHORIZING`,
`NO KNOWLEDGE MUTATED`, and `NO VERIFIERS EXECUTED`. It renders the full record
summary, warnings for malformed lines, `not_found` cleanly when missing, and
authority/mutation flags.

Reviewed NK inspection is read-only. Records are durable and inspectable but are
not proof, not evidence, not global promotion, and not broad future behavior
influence in Phase 11A.

This command is explicit only. It does not run from help, startup, TUI launch,
doctor, status, correction commands, `corpus ask`, `rules evaluate`,
`context autopsy`, or pack validation.

`--json` preserves raw GIP stdout exactly. `--debug` writes diagnostics to
stderr only, including engine path, GIP kind, project shard, record id, stdin
byte count, exit code, and parse status.

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
regions. When input or artifact coverage reports skipped, truncated, budget-hit,
unread, or coverage-derived unknown regions, human output prints a prominent
`COVERAGE WARNING` block near the top:

```text
COVERAGE WARNING
- Some referenced input was truncated or skipped.
- Ghost did not inspect all provided material.
- Treat conclusions as partial and non-authorizing.
```

`--json` preserves raw engine stdout exactly. `--debug` writes the
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

#### `ghost packs validate-autopsy-guidance`
Validate Knowledge Pack autopsy guidance through `ghost_knowledge_pack`.

Usage: `ghost packs validate-autopsy-guidance --manifest=path/to/manifest.json`
Usage: `ghost packs validate-autopsy-guidance --pack-id=zig_runtime_sync --version=1.0.0`
Usage: `ghost packs validate-autopsy-guidance --all-mounted --project-shard=my-project`
Usage: `ghost packs validate-autopsy-guidance --json --manifest=path/to/manifest.json`
Usage: `ghost packs validate-autopsy-guidance --manifest=path/to/manifest.json --max-guidance-bytes=524288 --max-array-items=128 --max-string-bytes=2048`

This is an explicit review-only validation command. It does not mutate packs,
auto-fix guidance, auto-promote guidance, run automatically from TUI launch,
doctor, status, or startup, and does not treat valid guidance as proof.

Before routing validation, the CLI queries
`ghost_knowledge_pack capabilities --json` and requires the engine to advertise
`validate-autopsy-guidance`, the required target flags, and at least one
supported autopsy guidance schema version. If capabilities are unavailable or
incomplete, the command fails with a compatibility error that includes the
resolved engine binary path/version when known and suggests `ghost doctor` or an
engine upgrade. Help remains offline and does not require engine availability.

The currently supported schema reported by the engine is
`ghost.autopsy_guidance.v1`. Legacy unversioned guidance shapes remain accepted
by the engine for compatibility, but they render as warnings rather than proof
or promotion.

Human mode renders concise pass, warning, and error summaries from the engine's
JSON validation contract and suppresses raw Zig traces or low-level stderr.
Validation failures still exit non-zero. `--json` asks the engine for JSON and
preserves raw engine stdout exactly. `--debug` writes diagnostics to stderr,
including the engine path, capability parse result, routed argv, exit code, and
validation parse status.

Limit override flags are routed only when the engine capabilities endpoint
advertises them:

- `--max-guidance-bytes=<n>`
- `--max-array-items=<n>`
- `--max-string-bytes=<n>`

### `ghost tui`
Interactive Ghost Console TUI. Provides a live cockpit view for interacting with the engine.

Usage: `ghost tui [--reasoning=quick|balanced|deep|max] [--context-artifact=<path>] [--no-color|--color=auto|always|never] [--compact] [--read-only] [--max-history-turns=<n>]`

Engine prompt/response turns are retained in bounded TUI session history and rendered
with `YOU` and `GHOST` labels plus turn separators. `SYSTEM`, `COMMAND`, and
`ERROR` are render-only labels for local session status, local command output,
and local errors. Ghost responses still use the same renderer as terminal
chat/ask output, including correction, negative-knowledge, and epistemic
sections when the engine reports them. The status bar includes compact counters
for corrections, applied/proposed negative knowledge, verifier requirements,
suppressions, and routing warnings.

By default, the TUI retains up to 500 turns. `--max-history-turns=<n>` changes
that retained-turn bound; older turns are pruned from the local display history.
The footer reports retained, total, and pruned turn counts.

`--read-only` launches the TUI in local/read-only mode. It allows local/session
commands such as `/help`, `/status`, `/reasoning`, `/debug`, `/json`, `/clear`,
and `/context`, but blocks submitted prompts plus slash commands that invoke
engine operations beyond local session state. `/doctor` and `/autopsy` are
blocked with `Read-only mode: command blocked: /name`. Read-only mode is visible
in the TUI status bar.

If stdin/stdout is not an interactive TTY, `ghost`/`ghost tui` exits gracefully
with a message. The covered smoke path verifies that no CLI-owned TUI command,
doctor check, context/project autopsy scan, correction proposal/review/reviewed
inspection, reviewed negative-knowledge review/list/get, verifier, pack
mutation, or negative-knowledge mutation is started
from that non-TTY fallback.

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

The TUI caches terminal dimensions and refreshes them on startup and periodic
redraw, so resize changes are picked up without probing the terminal on every
keypress. Command-panel rows are clipped to the current terminal width. Very
small terminals use a compact fallback and hide slash suggestions rather than
overlapping the status/footer/input rows.

Invalid slash commands are rejected locally with `Not a valid command: /name` and `Type /help for available commands`. They are not sent to the engine as chat prompts.

- `/quit`: Exit TUI
- `/help`: Show help text
- `/status`: Show session turn count and settings
- `/reasoning <level>`: Change reasoning level
- `/debug on|off`: Toggle debug diagnostics
- `/json on|off`: Toggle raw JSON capture for submitted prompts
- `/clear`: Clear the local TUI history
- `/doctor`: Explicitly run read-only doctor diagnostics; blocked by TUI `--read-only`
- `/autopsy <path>`: Explicitly run Project Autopsy for a path; blocked by TUI `--read-only`
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
expensive tests, execute verifiers, run validation, mutate packs, or change negative knowledge.
It reports the CLI version/path, current directory, `GHOST_ENGINE_ROOT`, resolved
engine binaries, executable bits, Zig version, OS/arch, terminal, PATH
resolution, bounded smoke checks, and knowledge-pack validation capability
compatibility.

Binary resolution is shared with normal command execution. Candidates are classified as `engine-root`, `engine-root-zig-out`, `dev-fallback-candidate`, or `PATH-candidate`, with status `executable`, `found-not-executable`, or `missing`. If `--engine-root`/`GHOST_ENGINE_ROOT` is set, normal execution resolves only the explicit root candidates and fails early if they are missing or not executable; dev fallback and PATH candidates remain visible as diagnostics.

Engine binaries tracked by `ghost doctor` and `ghost status`:

| Binary | Role | Core? |
|--------|------|-------|
| `ghost_task_operator` | Task/chat operator | Yes |
| `ghost_code_intel` | Code intelligence | Yes |
| `ghost_patch_candidates` | Patch candidate generation | Yes |
| `ghost_knowledge_pack` | Knowledge pack management | Yes |
| `ghost_gip` | GIP protocol / engine status / Context Autopsy / Corpus Ask | No |
| `ghost_project_autopsy` | Project Autopsy pass | No |

`ghost_project_autopsy` is detected and reported by `doctor`/`status`. Doctor
also runs a **bounded, labeled, read-only smoke check**
(`ghost_project_autopsy --version`) to confirm the binary responds. No
context/project autopsy scan is run by help, doctor/status diagnostics, TUI
launch, TUI idle rendering, non-TTY fallback, or invalid slash commands. Autopsy
output is never treated as proof by the CLI.

`ghost doctor` and `ghost status` also run the bounded read-only diagnostic
`ghost_knowledge_pack capabilities --json` when that binary is executable. This
diagnostic does not run validation and does not mutate packs. It reports whether
capabilities are available, whether `validate-autopsy-guidance` is advertised,
which schema versions are supported, and which validation limit flags are
advertised. Missing or old capability output is reported as a compatibility
warning with an upgrade/rebuild suggestion; it does not make doctor fail hard
unless normal binary availability checks already fail.

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
