# Why My Workflow Tooling Was Broken (And How It Works)

I added Archon, Sentrux, Graphify, and AI-powered git hooks to my macOS Swift project (Muxy). They're supposed to catch bugs, enforce architecture, and prevent secrets from leaking. But they did exactly nothing.

Here's why.

---

## The Three Tools

| Tool | What it does |
|------|-------------|
| **Archon** | AI agent workflow engine — coordinates multi-step tasks across agents |
| **Sentrux** | Architecture quality gate — scores your codebase on modularity, cycles, coupling, god files |
| **Graphify** | Knowledge graph — maps imports, dependencies, and agent attribution across the codebase |

Plus **git hooks** (pre-commit, pre-push, commit-msg, post-commit) that auto-run checks.

The idea:
```
Commit → pre-commit (lint + format + secrets) → pre-push (test + quality gate + full scan)
```

---

## Problem #1: The Project Isn't Node.js

The hooks came from a template. They had branches for every stack:

```bash
if [ -f "package.json" ]; then bun run lint    # Node
elif [ -f "Cargo.toml" ]; then cargo check      # Rust
elif [ -f "pubspec.yaml" ]; then flutter analyze # Flutter
elif ls *.xcodeproj *.xcworkspace 2>/dev/null; then  # Xcode/Swift
    swift format lint
fi
```

My project is **Swift-only**. But the hook checks for `*.xcodeproj` — which doesn't exist because Muxy uses **Swift Package Manager** (no Xcode project file). The `ls` fails silently. **The entire Swift branch never executes.**

Meanwhile Muxy already has `scripts/checks.sh` that runs the correct tools:

```bash
scripts/checks.sh
  ✅ Formatting     (swiftformat)
  ✅ Linting        (swiftlint)
  ✅ Build          (swift build)
  ✅ Test           (swift test)
```

The hooks just never called it.

---

## Problem #2: `2>/dev/null` Hides Everything

**39 instances** in the hooks. Every single command has `2>/dev/null` tacked on. When you do that:

```bash
swift-format lint $STAGED 2>/dev/null || true
```

...and `swift-format` is the **wrong tool** (the project uses `swiftformat`, different command), the error goes to /dev/null and `|| true` makes it pass anyway.

The hook reports success. The tool fails silently. You never know.

---

## Problem #3: Sentrux Paths Point to Nothing

Sentrux enforces architectural layers. My config had:

```toml
[[layers]]
name = "core"
paths = ["src/core/*"]
order = 0

[[layers]]
name = "domain"
paths = ["src/domain/*"]
order = 1
```

None of these directories exist. The actual modules are:

```
Muxy/
MuxyServer/
MuxyShared/
GhosttyKit/
Tests/
```

Sentrux doesn't warn about missing paths. It just applies rules to nothing and reports everything is clean. The quality score of 0.75 was a lie — there was nothing to measure.

---

## Problem #4: Dead Code in Workflows

Archon had `baseBranch: develop` — but the project uses `main`. Every workflow branches from a non-existent base. The `agent-hotfix` workflow backports to develop instead of main.

---

## The Meta Problem

The tools are not introspective. There's no layer that says:

- "Sentrux: zero of your 17 layer paths match actual code. Fix this."
- "Pre-commit: you're running `swift-format` but the project expects `swiftformat`. Fix this."
- "Hook: all your output goes to /dev/null. Nothing is being checked. Fix this."

The tools that are supposed to catch problems are themselves full of problems — and nothing checks the checkers.

---

## The Fix

Swap the template-generic configuration for project-specific configuration.

| Broken | Fixed |
|--------|-------|
| Template Sentrux paths | Actual module paths |
| `swift-format lint` | `scripts/checks.sh` |
| `2>/dev/null \|\| true` | Surface errors |
| xcodeproj detection | Direct SPM detection |
| `baseBranch: develop` | `baseBranch: main` |
| 6 stack branches | 1 Swift path |
| No introspection | Validate tooling at install |

---

## The Lesson

Workflow tooling is code. It needs the same treatment as application code:

1. **Test it.** Run the hooks. Verify they actually execute.
2. **Remove dead code.** If your project is one language, delete the other 5 branches.
3. **Don't suppress errors.** `2>/dev/null` is the enemy of reliability.
4. **Match your project.** Template configs are starting points, not endpoints.

The most valuable line in my entire workflow tooling isn't a quality gate or a knowledge graph — it's this:

```bash
scripts/checks.sh --fix
```

Because that's the one line that actually runs the right checks in the right way. Everything else was noise.
