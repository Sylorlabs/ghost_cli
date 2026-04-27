# Engine Contract

## Supported Binaries
`ghost_cli` communicates with the engine via specific binary interfaces.
- `ghost_task_operator`
- `ghost_code_intel`
- `ghost_patch_candidates`
- `ghost_knowledge_pack`

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

These sections are display-only. The CLI does not execute verifiers, corrections, negative-knowledge review/mutation APIs, pack mutation, or MCP calls.

### Rules
1. The CLI must never reinterpret verification results.
2. The CLI must silently handle unknown or extra JSON fields.
3. The CLI must degrade gracefully if optional fields are missing.
4. When `--json` is set, raw engine stdout is preserved exactly and terminal rendering is skipped.
5. When `JSON` formatting cannot be parsed (e.g., an engine panic or bad trace log), the CLI falls back to dumping raw text output without interpretation.
6. If JSON is parsed but no recognized fields exist, it renders "Status: Parsed JSON, unrecognized contract".
