# Pre-Commit Hooks

Muxy uses a comprehensive pre-commit verification system to ensure code quality before commits.

## Current Checks

| Check | Tool | Purpose |
|-------|------|---------|
| Formatting | SwiftFormat | Code style and layout |
| Linting | SwiftLint | Warnings, errors, best practices |
| Build | swift build | Compile verification |
| Secrets | Gitleaks | Scan for leaked secrets |
| Quality | Sentrux | Architectural gate |
| Architecture Tests | Swift Testing | Project structure, config files |

## Architecture Lint Tests

Located in `Tests/MuxyTests/Lint/MuxyArchitectureLint.swift`:

- `test_project_structure_exists` - Verifies Muxy, MuxyShared, MuxyServer, GhosttyKit exist
- `test_required_config_files_exist` - Verifies .swiftformat, .swiftlint.yml, .sentrux, .archon
- `test_no_debug_print_in_production` - Checks for debug prints in production code

Run with: `swift test --filter MuxyArchitectureLint`

## Danger (PR Automation)

Dangerfile at `Dangerfile.swift` (for CI):

- Checks CHANGELOG entries
- Warns on large PRs (>600 lines)
- Ensures assignees
- Checks for debug code
- Prevents .env files