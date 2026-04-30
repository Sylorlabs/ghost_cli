# Ghost CLI Project Instructions

## Architecture & Principles
- **Native Zig CLI/TUI:** Keep Ghost CLI terminal-native and Zig-native. Do not add Node, Electron, React, or web UI layers.
- **Renderer-only boundary:** Do not reinterpret engine proof/support locally. Preserve raw engine JSON exactly in `--json` mode.
- **Side-effect discipline:** Do not add hidden scans, verifiers, mutations, pack validation, or autopsy runs behind startup, `doctor`, `status`, or TUI launch.
- **Debug separation:** Keep debug and diagnostic chatter on stderr so stdout remains usable for command output and JSON passthrough.
- **TUI integrity:** Interactive terminal behavior must be robust against fast-pasted input and PTY-based automation.
- **PTY testing:** Use PTY-based integration tests (`src/integration_test.zig`) to verify terminal behavior, escape sequences, and interactive flows.

## TUI Input Handling
- **Single-byte consumption:** Ordinary input should be consumed one byte at a time to prevent dropping fast-pasted chunks like `/cmd\r`.
- **Escape sequences:** Multi-byte escape sequences, including arrows, must be buffered and identified without discarding subsequent valid input.

## Verification & Git Hygiene
- Run `zig build` and `zig build test --summary all`; require all tests to pass before push.
- Manually verify TUI features that touch:
  - Color and no-color modes (`--no-color`, `NO_COLOR=1`).
  - Resizing/Repainting.
  - Slash command suggestions and execution.
  - Signal handling (`Ctrl+C`, `Ctrl+D`, etc.).
- Stage exact file lists only. Do not use `git add .`.
- Finish committed work with a clean `git status --short --untracked-files=all`.
