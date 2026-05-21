# Repository Guidelines

## Project Structure & Module Organization
This repository is a small C utility project focused on Apple Watch battery discovery via `companion_proxy`.

- `src/`: Source files (currently `watch_battery.c`).
- `scripts/`: Developer scripts for build/run workflows.
  - `build-watch-battery.sh` – compile via Makefile.
  - `watch-battery.sh` – run the CLI wrapper.
- `bin/`: Local build outputs (`watch_battery`, `watch_battery_bundled`).
- `lib/`: Optional local dependency artifacts.
- `RESEARCH.md`: Ongoing protocol/tooling notes and findings.

## Build, Test, and Development Commands
- `make build` — compile `src/watch_battery.c` into `bin/watch_battery`.
- `make run` — build (if needed) and run with no arguments.
- `make run-json` — run with `--json` output.
- `make run-watch-only` — run with `--watch-only`.
- `./scripts/build-watch-battery.sh` — lightweight entrypoint for building.
- `./scripts/watch-battery.sh [flags]` — run wrapper for `bin/watch_battery`.
- `make clean` — remove generated binary at `bin/watch_battery`.

## Coding Style & Naming Conventions
- Language: C (ANSI-compatible, POSIX/macOS APIs).
- Indentation: 4 spaces.
- Naming: `snake_case` for functions/variables, `kebab` style only for docs/scripts, avoid short opaque names.
- Use explicit error handling for all libimobiledevice calls.
- Prefer small, single-purpose helpers over large inline blocks.

## Testing Guidelines
- No automated test suite is currently wired in this repo.
- Manual verification is acceptable for now:
  - build succeeds.
  - command returns watch battery when iPhone/watch are paired.
  - `--json` output parses as valid JSON and includes expected `udid`, `battery` and `isWatch` fields.

## Commit & Pull Request Guidelines
- Keep commits focused and descriptive, e.g. `feat: add --watch-only json output`.
- Include:
  - summary of behavior change
  - commands run (build/validation)
  - any environment/device assumptions.
- If binary files are changed intentionally, call that out explicitly.

## Security & Environment Notes
- Do not commit real UDIDs, Bluetooth MACs, or other device identifiers without redaction.
- Never test on production/managed phones without explicit user consent.
- Keep local `watch_battery` credentials/config external and out of source control.
