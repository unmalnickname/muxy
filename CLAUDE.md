# Muxy

Requires macOS 14+ and Swift 6.0+. No external dependency managers needed — everything is SPM-based.

## Linting & Formatting

Requires `swiftlint` and `swiftformat` (`brew install swiftlint swiftformat`).

```bash
scripts/checks.sh        # Run all checks (formatting, linting, build)
scripts/checks.sh --fix  # Auto-fix formatting and linting issues
swiftformat --lint .      # Check formatting only
swiftlint lint --strict   # Check linting only
```

Run `scripts/checks.sh --fix` after every task.

## Build & Install

```bash
scripts/dev-install.sh   # Build, bundle, sign, install to /Applications, and launch
scripts/build-release.sh --arch arm64 --version 0.X.Y  # Signed release build + DMG
```

Always use `--product Muxy` (not `--target Muxy`) — the latter compiles without linking the binary.

## Architecture

- Muxy is a macOS terminal multiplexer built with SwiftUI that uses [libghostty](https://github.com/ghostty-org/ghostty) for terminal emulation and rendering via Metal.
- The architecture of the app is documented at `./docs/developer/architecture.md` and must always be up to date.

### Core Components

- **GhosttyService** (singleton) — Manages the single `ghostty_app_t` instance per process. Loads config from `~/.config/ghostty/config`, runs a 120fps tick timer, and handles clipboard callbacks.

- **GhosttyTerminalNSView** — AppKit `NSView` that hosts a ghostty surface (`ghostty_surface_t`). Handles all keyboard/mouse input routing to libghostty and manages the Metal rendering layer. This is bridged into SwiftUI via `GhosttyTerminalRepresentable`.

- **AppState** (@Observable) — Manages the mapping of projects → tabs → split pane trees. Tracks active project, active tab per project, and provides tab lifecycle operations (create, close, select).

- **ProjectStore** (@Observable) — Persists projects as JSON to `~/Library/Application Support/Muxy/projects.json`. Projects are directories the user adds via NSOpenPanel.

## GhosttyKit Integration

`GhosttyKit/` is a C module wrapping `ghostty.h` — the libghostty API. The precompiled static library lives in `GhosttyKit.xcframework/` (gitignored, downloaded via `scripts/setup.sh`).

Key libghostty types: `ghostty_app_t` (app), `ghostty_surface_t` (terminal surface), `ghostty_config_t` (configuration). Surfaces are created when terminal views move to a window and destroyed on removal.

The xcframework is built via GitHub Actions on the [muxy-app/ghostty](https://github.com/muxy-app/ghostty) fork. See [docs/developer/building-ghostty.md](docs/developer/building-ghostty.md) for details.

## Data Persistence

- **Projects:** `~/Library/Application Support/Muxy/projects.json`
- **Ghostty config:** `~/.config/ghostty/config`
- **Terminal state (tabs, splits):** in-memory only, lost on app close

## NSViewRepresentable Pitfalls

- Never return a cached/reused NSView from `makeNSView`. SwiftUI assumes it gets a fresh view and breaks silently when it doesn't (blank views, lost input).
- To keep an NSView alive across tab switches, keep the `NSViewRepresentable` mounted in the view tree (e.g. all tabs in a ZStack with `opacity(0)` + `allowsHitTesting(false)` for inactive ones) rather than conditionally removing it and relying on a registry cache.
- When debugging blank/empty NSView issues, first check whether the NSView is being re-mounted from a detached state — that's the most common cause.

## Top Level Rules

- Security first
- Native Only
- Maintainability
- Scalability
- Clean Code
- Clean Architecture
- Best Practices
- No Hacky Solutions

## Main Rules

- No commenting allowed in the codebase
- All code must be self-explanatory and cleanly structured
- Use early returns instead of nested conditionals
- Don't patch symptoms, fix root causes
- For every task, Consider how it will impact the architecture and code quality, not just the immediate problem
- Follow the existing code's pattern but offer refactors if they improve code quality and maintainability.
- Use logs for debugging.
- If the feature is testable, then you must write tests.
- Avoid long PR descriptions. It is for humans and keep it in 3 lines maximum.
- Upload screenshots or recordings for the PRs.
- Never answer any question without a proper investigation and exploring the codebase.


## Code Review

- Review the PRs/Code against the purpose of the PR/Issue/Asked. If you find unrelated issues to the PR during the review, Report them in a separate section.
- Apply review recommendations only after user's confirmation.

<!-- gitnexus:start -->
# GitNexus — Code Intelligence

This project is indexed by GitNexus as **muxy** (12131 symbols, 141235 relationships, 300 execution flows). Use the GitNexus MCP tools to understand code, assess impact, and navigate safely.

> If any GitNexus tool warns the index is stale, run `npx gitnexus analyze` in terminal first.

## Always Do

- **MUST run impact analysis before editing any symbol.** Before modifying a function, class, or method, run `gitnexus_impact({target: "symbolName", direction: "upstream"})` and report the blast radius (direct callers, affected processes, risk level) to the user.
- **MUST run `gitnexus_detect_changes()` before committing** to verify your changes only affect expected symbols and execution flows.
- **MUST warn the user** if impact analysis returns HIGH or CRITICAL risk before proceeding with edits.
- When exploring unfamiliar code, use `gitnexus_query({query: "concept"})` to find execution flows instead of grepping. It returns process-grouped results ranked by relevance.
- When you need full context on a specific symbol — callers, callees, which execution flows it participates in — use `gitnexus_context({name: "symbolName"})`.

## Never Do

- NEVER edit a function, class, or method without first running `gitnexus_impact` on it.
- NEVER ignore HIGH or CRITICAL risk warnings from impact analysis.
- NEVER rename symbols with find-and-replace — use `gitnexus_rename` which understands the call graph.
- NEVER commit changes without running `gitnexus_detect_changes()` to check affected scope.

## Resources

| Resource | Use for |
|----------|---------|
| `gitnexus://repo/muxy/context` | Codebase overview, check index freshness |
| `gitnexus://repo/muxy/clusters` | All functional areas |
| `gitnexus://repo/muxy/processes` | All execution flows |
| `gitnexus://repo/muxy/process/{name}` | Step-by-step execution trace |

## CLI

| Task | Read this skill file |
|------|---------------------|
| Understand architecture / "How does X work?" | `.claude/skills/gitnexus/gitnexus-exploring/SKILL.md` |
| Blast radius / "What breaks if I change X?" | `.claude/skills/gitnexus/gitnexus-impact-analysis/SKILL.md` |
| Trace bugs / "Why is X failing?" | `.claude/skills/gitnexus/gitnexus-debugging/SKILL.md` |
| Rename / extract / split / refactor | `.claude/skills/gitnexus/gitnexus-refactoring/SKILL.md` |
| Tools, resources, schema reference | `.claude/skills/gitnexus/gitnexus-guide/SKILL.md` |
| Index, status, clean, wiki CLI commands | `.claude/skills/gitnexus/gitnexus-cli/SKILL.md` |

<!-- gitnexus:end -->
