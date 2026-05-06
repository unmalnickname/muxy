# Bug Fix: validate-workflow.sh Path Issue

## Problem

Both `PipelineState` and `ProjectHealthState` called `scripts/validate-workflow.sh` relative to the project being viewed:

```swift
// BROKEN: Assumes script exists in project directory
task.arguments = ["-c", "cd '\(projectPath)' 2>/dev/null && scripts/validate-workflow.sh --ci 2>&1"]
```

This fails for projects that don't have `scripts/validate-workflow.sh` bundled.

## Root Cause

The `validate-workflow.sh` script is designed to validate a project's workflow tooling. However, the code assumed every project would have a copy of this script, which is not the case for external projects viewed in Muxy.

## Solution

The script is now bundled inside the Muxy app resources and loaded via `Bundle.main`:

```swift
let validateScript = Bundle.main.path(forResource: "validate-workflow", ofType: "sh", inDirectory: "Scripts")
    ?? (Bundle.main.bundlePath as NSString).appendingPathComponent("Contents/Resources/Scripts/validate-workflow.sh")
```

Files modified:
1. `Muxy/Models/PipelineState.swift` — `runToolValidation()` method
2. `Muxy/Models/ProjectHealthState.swift` — `runValidation()` method
3. `Muxy/Resources/scripts/validate-workflow.sh` — copied from `scripts/validate-workflow.sh`

## Fallback Behavior

If the script is not bundled (e.g., in development):
- `toolValidationPassed` / `validationPassed` set to `nil`
- Detail message: "validate-workflow.sh not bundled"

This ensures graceful degradation rather than crashes.