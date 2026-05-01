# Engine Contract

## Supported Binaries
`ghost_cli` communicates with the engine via specific binary interfaces.
- `ghost_task_operator`
- `ghost_code_intel`
- `ghost_patch_candidates`
- `ghost_knowledge_pack`
- `ghost_gip`
- `ghost_corpus_ingest`

## JSON Output Contract
The CLI expects structured JSON output from the engine when `--render=json` is provided.

### Task Operator Chat Response Shape
The CLI supports several JSON shapes for the task operator, including nested result objects.

```json
{
  "formatVersion": "ghost_conversation_session_v1",
  "sessionId": "conv-...",
  "lastResult": {
    "kind": "unresolved",
    "selected_mode": "unresolved",
    "stop_reason": "unresolved",
    "summary": "blocked because ambiguity",
    "detail": "..."
  },
  "pendingObligations": [
    { "id": "...", "label": "...", "required_for": "..." }
  ],
  "currentIntent": {
    "status": "unresolved"
  },
  "epistemic_render": {
    "state_label": "unresolved",
    "authority_statement": "does not prove support"
  },
  "corrections": {
    "summary": "Prior response overstated support",
    "items": []
  },
  "negative_knowledge": {
    "influence_summary": "prior failure influenced routing",
    "applied_records": [],
    "proposed_candidates": [],
    "trust_decay_candidates": [],
    "items": []
  }
}
```

### Supported Fields (Consolidated)
The CLI consolidates fields from the top level and nested objects:

- **Status**: `status`, `claim_status`, `lastResult.status`, `lastResult.kind`, `currentIntent.status`.
- **Verification State**: `verification_state`, `verificationState`, `lastResult.selected_mode`.
- **Draft Status**: `is_draft`, `isDraft`, or status/state equal to `draft`.
- **Summary**: `summary`, `lastResult.summary`.
- **Detail**: `detail`, `message`, `response`, `lastResult.detail`.
- **Suggested Action**: `suggested_action`, `suggestedAction`, `escalation_hint`, `escalationHint`.
- **Obligations**: `pending_obligations`, `pendingObligations`, `missing_obligations`, `missingObligations`.
- **Ambiguities**: `pending_ambiguities`, `pendingAmbiguities`, `ambiguity_sets`, `ambiguity_choices`.
- **Epistemic Render**: `epistemic_render`, including optional labels/statements from the engine renderer.
- **Corrections**: `corrections.summary`, `corrections.items[]`.
- **Negative Knowledge**: `negative_knowledge.influence_summary`, `negative_knowledge.applied_records[]`, `negative_knowledge.proposed_candidates[]`, `negative_knowledge.trust_decay_candidates[]`, `negative_knowledge.items[]`.

Semantic labels for negative-knowledge items are selected only from explicit structured discriminator fields (`kind`, `type`, `event`, or `category`) with known exact values. The CLI does not infer verifier requirements, suppressions, routing warnings, trust decay, corrections, or epistemic state from arbitrary prose, summaries, IDs, or nested string substrings.

### Renderer Labels
When present, correction, negative-knowledge, and epistemic fields are displayed with explicit non-authorizing labels:

- `Epistemic State`
- `Correction Recorded`
- `Negative Knowledge Applied`
- `Negative Knowledge Candidate Proposed`
- `Stronger Verifier Required`
- `Exact Repeat Suppressed`
- `Routing Warning`
- `Trust Decay Candidate Proposed`
- `Next Action`

These sections are display-only. Rendering them does not execute verifiers,
corrections, negative-knowledge review/mutation APIs, pack mutation, or MCP
calls. Explicit user commands may still invoke engine binaries according to
their command contract.

### Rules
1. The CLI must never reinterpret verification results.
2. The CLI must silently handle unknown or extra JSON fields.
3. The CLI must degrade gracefully if optional fields are missing.
4. When `--json` is set, raw engine stdout is preserved exactly and terminal rendering is skipped.
5. Debug diagnostics are written to stderr so they do not corrupt JSON stdout.
6. Engine stderr is written to stderr in JSON passthrough mode and reported on stderr for human mode failures.
7. When `JSON` formatting cannot be parsed (e.g., an engine panic or bad trace log), the CLI falls back to dumping raw text output without interpretation.
8. If JSON is parsed but no recognized fields exist, it renders "Status: Parsed JSON, unrecognized contract".

## Knowledge Pack Autopsy Guidance Validation

`ghost packs validate-autopsy-guidance` routes explicitly to
`ghost_knowledge_pack validate-autopsy-guidance` only after a compatibility
handshake against `ghost_knowledge_pack capabilities --json`.

The CLI requires capabilities to advertise:

- `validate-autopsy-guidance`
- target flags `--manifest`, `--pack-id`, `--version`, `--all-mounted`,
  `--project-shard`
- `--json`
- at least one supported autopsy guidance schema version

If capabilities are unavailable, incomplete, or unparsable, the CLI fails before
routing validation and prints a compatibility error with the resolved engine
binary path and version when known. It suggests `ghost doctor` or upgrading /
rebuilding `ghost_engine`. Command help remains offline and does not query the
engine.

Supported target forms:

- `--manifest=<path>`
- `--pack-id=<id> --version=<v>`
- `--all-mounted --project-shard=<id>`

The currently supported engine schema is `ghost.autopsy_guidance.v1`. The engine
may accept legacy unversioned guidance shapes for compatibility; the CLI renders
those as warnings in human mode. Validation limits are engine-owned. The CLI
routes these overrides only when the capabilities endpoint advertises them:

- `--max-guidance-bytes=<n>`
- `--max-array-items=<n>`
- `--max-string-bytes=<n>`

The CLI does not parse, reinterpret, or upgrade validation results into proof.
Human mode asks the engine for JSON, renders clean success, warning, and failure
summaries, suppresses raw Zig traces/stderr, and propagates non-zero validation
errors. JSON mode passes `--json` to the engine and preserves raw engine stdout
exactly. Debug diagnostics go to stderr and include engine path, capability
result, routed argv, exit code, and parse status. The command is never run
automatically by help, startup, TUI launch, doctor, or status, and it does not
mutate packs, auto-fix guidance, or auto-promote guidance.

`ghost doctor` and `ghost status` may run
`ghost_knowledge_pack capabilities --json` as a bounded read-only diagnostic.
That diagnostic reports compatibility only: capabilities availability,
`validate-autopsy-guidance` support, supported schema versions, and advertised
validation limit flags. It does not run validation, mutate packs, auto-fix
guidance, auto-promote guidance, or treat capability availability as proof.
Unavailable or unparsable capabilities render a compatibility warning and an
engine upgrade/rebuild suggestion.

## Corpus Lifecycle

`ghost corpus ingest` routes explicitly to `ghost_corpus_ingest <path>`.
Supported CLI flags are `--project-shard=<id>`, `--trust-class=<class>`, and
`--source-label=<label>`. Human mode renders the result as STAGED and states
that staged corpus is not live and is not visible to `corpus.ask` until
apply-staged succeeds.

`ghost corpus apply-staged` routes explicitly to
`ghost_corpus_ingest --apply-staged` with optional `--project-shard=<id>`.
Human mode states that staged corpus was applied/promoted to the live shard
corpus.

The verified engine at `707ae0c7e14f1f0eb91b2a536b89489eeea95e9c` emits JSON
from `ghost_corpus_ingest` but does not advertise a separate `--json` flag, so
the CLI does not forward one. In CLI `--json` mode, raw engine stdout is
preserved exactly for ingest and apply-staged. Debug diagnostics are written to
stderr and include engine path, operation, routed argv, exit code, and parse
status.

These lifecycle commands are explicit only. Help, startup, TUI launch, doctor,
and status do not run corpus ingest, apply-staged, or ask. The lifecycle does
not mutate packs, mutate negative knowledge, run verifiers, persist learning
candidates, add Transformers/model adapters, or provide semantic black-box
search.

## Corpus Ask

`ghost corpus ask` routes explicitly to `ghost_gip --stdin` with GIP
`kind: "corpus.ask"`. The CLI request body includes `question`, optional
`projectShard`, optional `maxResults`, optional `maxSnippetBytes`, and optional
`requireCitations`. `ghost ask` remains the chat/task-operator one-shot command.

Human mode renders only the engine's corpus ask result. It labels the output
DRAFT and NON-AUTHORIZING, renders `answerDraft` only when present, renders
bounded `evidenceUsed`, and renders `unknowns`, `candidateFollowups`,
`learningCandidates`, and trace fields without upgrading authority. If the
engine reports `no_corpus_available`, `insufficient_evidence`, or
`conflicting_evidence`, no answer is rendered; the CLI states that no answer was
produced and shows the unknown/conflict status.

`learningCandidates` are displayed as CANDIDATE ONLY / NOT PERSISTED. Rendering
them does not persist learning, mutate corpus, mutate packs, mutate negative
knowledge, run commands, or run verifiers. Trace flags such as
`corpusMutation`, `packMutation`, `negativeKnowledgeMutation`,
`commandsExecuted`, and `verifiersExecuted` are display-only engine facts.

`--json` preserves raw engine stdout exactly. `--debug` writes diagnostics to
stderr only: engine binary path, GIP kind, argv/stdin summary, exit code, and
parse status.

The engine retrieval limitation is user-visible: corpus ask is bounded lexical
matching over live shard corpus excerpts. It reads live shard corpus only;
staged corpus is invisible until apply-staged succeeds. It is not semantic
search, and mounted pack corpus is not included yet. There are no Transformers
or model adapters in this CLI path.

## Context Autopsy Coverage Warnings

Human `ghost context autopsy` output is always labeled DRAFT and
NON-AUTHORIZING. When `inputCoverage` or `artifactCoverage` reports skipped
inputs/files, truncation, budget hits, unread regions, or unknowns from
uninspected material, the CLI prints a top-of-output warning:

```text
COVERAGE WARNING
- Some referenced input was truncated or skipped.
- Ghost did not inspect all provided material.
- Treat conclusions as partial and non-authorizing.
```

The warning is display-only and does not reinterpret engine authority. `--json`
continues to preserve raw engine stdout exactly.
