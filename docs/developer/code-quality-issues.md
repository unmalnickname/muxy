# Code Quality Issues

This document tracks code quality issues found in the Muxy codebase.

## 1. Silent Error Catching

### Location
- `Muxy/Models/PipelineState.swift:150`

### Issue
```swift
} catch {}  // Swallows all errors silently
```

### Impact
Workflow loading failures are invisible to users. No logging, no fallback, no user feedback.

### Recommended Fix
```swift
} catch {
    print("Failed to load workflows from \(file): \(error)")
    // Optionally: skip invalid workflows but continue loading others
}
```

---

## 2. Hardcoded Shell Path

### Location
Multiple files use `/bin/bash` directly:
- `Muxy/Models/ProjectHealthState.swift:86,172,200`
- `Muxy/Models/PipelineState.swift:286,494`
- `Muxy/Views/Health/ProjectHealthPanel.swift:387,485`

### Issue
```swift
task.launchPath = "/bin/bash"
```

### Impact
- macOS may move bash in future releases
- `/usr/bin/env bash` is more portable
- Prevents running on systems where bash isn't at /bin

### Recommended Fix
```swift
task.launchPath = "/usr/bin/env"
task.arguments = ["bash", "-c", "..."]
```

---

## 3. Silent `2>/dev/null` Suppression

### Location
Multiple commands in `PipelineState.swift` and `ProjectHealthState.swift`

### Issue
```bash
cd '\(projectPath)' 2>/dev/null && git rev-parse 2>/dev/null
```

### Impact
- Command failures are invisible
- Hard to debug when features break
- User sees "pending" or "skipped" with no explanation

### Recommended Fix
Only suppress stderr for expected non-fatal output:
```bash
cd '\(projectPath)' && git rev-parse 2>&1 || echo "git-error"
```

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

## Priority

1. **High**: Silent error catching (#1)
2. **Medium**: Shell path portability (#2)
3. **Low**: Debug blocks (#4)
4. **Consider**: `2>/dev/null` suppression (#3)