# AGENTS.md

This document establishes expectations and best practices for all agents (human or automated) contributing to this fork. The goal is to move fast, work cleanly, and keep a clear focus on Nintendo Joy‑Con support.

## Fork Objective
- Improve and extend Joy‑Con (left/right) support in Godot with maximum event coverage: sticks, buttons, gyroscope/accelerometer, connection states, etc.
- Enable two usage modes:
  - **Pair vertical mode**: `Joy‑Con L` and `Joy‑Con R` used together, each held vertically by a player.
  - **Solo horizontal mode**: each Joy‑Con used alone, horizontally. Orientation reference:
    - `Joy‑Con L`: rotated 90° counter-clockwise.
    - `Joy‑Con R`: rotated 90° clockwise.

## Control Mapping (Reference)
- Joy‑Con L:
  - Buttons: `L` (shoulder), `ZL` (trigger), `SL` (no native Android event), `SR` (no native Android event), `−` (minus = select), `Capture` (button "o"), D‑pad, multi-directional stick.
- Joy‑Con R:
  - Buttons: `R` (shoulder), `ZR` (trigger), `SL` (no native Android event), `SR` (no native Android event), `+` (plus = start), `Home`, face buttons `X`, `Y`, `A`, `B`, multi-directional stick.
- Android notes: `SL`/`SR` may not emit native events; plan an abstraction layer and fallbacks.

## Workflow Principles
- **Conventional Commits**: always use the standard format.
  - Examples: `feat(input): add Joy-Con gyro mapping`, `fix(unix): correct evdev axis inversion`, `docs(agents): clarify push policy`.
- **Commits**: frequent and by feature.
  - One commit = one coherent unit (mapping, targeted fix, related docs).
  - Avoid catch-all commits.
- **Push policy**:
  - **From local**: ask explicitly before pushing to `origin`. Open an issue or draft PR and request approval.
  - **From cloud agents**: agents in isolated cloud environments (Cloud Build, Actions) may push their own feature branches without prior consent, as long as they follow naming conventions and don't target `4.3-joycon-fix` directly (use PRs).
- **Default branch**: `4.3-joycon-fix`.
  - Create feature branches: `feature/joycon-gyro`, `fix/android-sl-sr`, `docs/agents-guidelines`, etc.
- **Lean & focused**: do not stack unrelated changes; keep scope tight and goal-oriented.
- **Tooling**: run `npm install` once to enable commitlint + husky hooks locally (commit messages are linted before they land). If you saw a deprecated husky install warning before, rerun after pulling to refresh the hook.

## Agent Recommendations
- **Input abstraction**:
  - Centralize event mapping in a portable layer (Godot InputMap/input servers) to minimize platform divergence (Linux/Windows/Android).
- **Modes and orientations**:
  - Manage axis conversion and inversion per orientation (horizontal vs vertical, L vs R).
  - Define profiles: `pair-vertical`, `solo-horizontal-L`, `solo-horizontal-R` and switch dynamically.
- **Hardware robustness**:
  - Connection/disconnection detection, battery level (if available), sensor states (gyro/accel), latency.
  - Configurable deadzones, noise filtering, gyro smoothing.
- **Cross-platform compatibility**:
  - Linux (evdev/hid), Windows (XInput/HID), Android (InputDevice), others. Unify button/axis codes.
- **Testability**:
  - Include unit tests for mapping logic and simple dev scenes for manual validation (event echoing).
- **Documentation**:
  - Update README/docs when mappings or behavior change.

## Cloud & CI/CD Usage
- **Philosophy**: handle most actions in the cloud when practical.
  - Available tools: Cloud Build (GCP), Google Artifact Registry, GitHub Codespaces, GitHub Actions, GitHub Container Registry, Docker Hub.
  - Choose the right tool for the job (heavy builds → Cloud Build; integration/Godot modules → GitHub Actions; images → GAR/GHCR/Docker Hub).
- **Containers**:
  - Maintain reproducible Dockerfiles; leverage build caches.
  - Clear artifact and image tagging (semver, commit SHA).
- **Artifacts**:
  - Publish only what's useful (binaries, tests, mapping dumps); avoid large unnecessary objects.
- **Security**:
  - Store secrets/credentials via provider-specific stores; never commit them.

## Additional Guidelines
- **Naming**:
  - Branches: `feature/*`, `fix/*`, `chore/*`, `docs/*`.
  - Commits: `type(scope): subject` + concise body and `BREAKING CHANGE:` if applicable.
- **Pull Requests**:
  - Small, focused, with clear description and Joy‑Con mapping/test checklist.
  - Prefer Draft PRs to gather feedback before final push.
- **Review**:
  - At least one approval before merge; verify cross-platform mapping and performance.
- **Performance**:
  - Minimize input latency; avoid main-loop overhead; profile if needed.
- **Compatibility**:
  - Do not break other controllers; isolate Joy‑Con logic behind flags/profiles.
- **Logging**:
  - Concise, toggleable logs; avoid event-loop spam.
- **License & credits**:
  - Respect project license; do not introduce non-compatible copyrighted content.

## Conventional Commits Quick Reference
- `feat`: new feature.
- `fix`: bug fix.
- `docs`: documentation.
- `chore`: operational tasks (CI, build, deps).
- `refactor`: refactor without new feature or bugfix.
- `perf`: performance improvement.
- `test`: tests.
- `build`: build changes.
- `ci`: CI pipeline changes.

## Summary of Goals
- Maximize Joy‑Con event coverage.
- Deliver in small, coherent units with conventional commits.
- Leverage cloud infrastructure intelligently.
- Stay lean and goal-focused on the fork objectives.
