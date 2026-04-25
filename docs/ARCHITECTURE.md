# Architecture

## Core Principle
`ghost_cli` is a **thin product shell**. 

The architecture strictly adheres to separating product UX from engine reasoning.

## Components

1. **CLI Commands (`src/commands/`)**:
   - Handle argument parsing and basic routing for `chat`, `ask`, `fix`, `verify`, `packs`, `learn`, `status`, `debug`.
   - Formats user arguments into engine arguments (e.g. mapping `--reasoning=deep` to specific engine flags).

2. **Engine Invocation (`src/engine/`)**:
   - `locator.zig`: Resolves the absolute path to engine binaries like `ghost_task_operator`.
   - `process.zig`: Executes engine binaries safely and captures `stdout`/`stderr` and exit codes.
   - `json_contracts.zig`: Defines the schema for mapping engine JSON output to internal representations.

3. **Renderers (`src/render/`)**:
   - Translate engine output into user-friendly CLI text (colors, progress, states).
   - Ensure states like `Draft`, `Verified`, and `Unresolved` are unambiguously printed.

## Forbidden Patterns
- **No Engine Logic**: The CLI must never calculate paths, perform proofs, or interpret human-readable engine texts when a JSON contract exists.
- **No Direct Mutation**: Modifying knowledge packs must be requested via `ghost_knowledge_pack`.
- **Honest Rendering**: Drafts must never be visually promoted to Verified. Unresolved must never be suppressed.
