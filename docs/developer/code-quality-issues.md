# Code Quality Issues

This document tracks code quality issues found in the Muxy codebase.

## 1. Silent Error Catching — RESOLVED

### Location
- `Muxy/Models/PipelineState.swift:156`

### Status
Fixed. Error is now logged with `print("[PipelineState] Failed to load workflows from \(workflowsDir): \(error)")`.

---

## 2. Hardcoded Shell Path — RESOLVED

### Location
- `Muxy/Models/PipelineState.swift`
- `Muxy/Models/ProjectHealthState.swift`
- `Muxy/Views/Health/ProjectHealthPanel.swift`

### Status
Fixed. All inline `Process()` usage replaced with `ShellRunner` which uses `GitProcessRunner.resolveExecutable("bash")` to find the shell path dynamically.

---

## 3. Silent `2>/dev/null` Suppression — RESOLVED

### Location
- `Muxy/Models/PipelineState.swift`
- `Muxy/Models/ProjectHealthState.swift`

### Status
Fixed. `ShellRunner` uses `workingDirectory` parameter instead of `cd ... 2>/dev/null`. Stderr suppression kept only for non-critical git commands where failure is expected.

---

## 4. Debug-Only Code Blocks

### Location
- `Muxy/Services/UpdateService.swift:98`
- `Muxy/Services/AppEnvironment.swift:6`
- `Muxy/Services/AIProviderIntegration.swift:75,117`

### Issue
```swift
#if DEBUG
// Dev-only code not included in release
#endif
```

### Impact
- Could cause release bugs if DEBUG-only code has side effects
- Feature might work in dev but fail in release

### Status
This is generally acceptable but should be reviewed per-case.

---

## 5. Duplicated Code — RESOLVED

### Location
- `PipelineState.swift` — private `shell()` method
- `ProjectHealthState.swift` — inline `Process()` ×4
- `ProjectHealthPanel.swift` — `runAction()` / `runActionWithOutput()`
- `PipelineState.swift`, `ProjectHealthState.swift`, `PipelinePanel.swift` — `timeAgo()` ×3

### Status
Fixed. Extracted:
- `ShellRunner` service (`Muxy/Services/ShellRunner.swift`) — replaces all inline Process/shell usage
- `Date.timeAgo(since:)` extension (`Muxy/Extensions/TimeFormatting.swift`) — replaces 3 duplicate timeAgo implementations

---

## Priority

1. **~~High~~**: Silent error catching (#1) — RESOLVED
2. **~~Medium~~**: Shell path portability (#2) — RESOLVED
3. **Low**: Debug blocks (#4)
4. **~~Consider~~**: `2>/dev/null` suppression (#3) — RESOLVED
5. **~~Medium~~**: Duplicated code (#5) — RESOLVED
