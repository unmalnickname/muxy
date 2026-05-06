# Health Panel

The Health Panel provides a comprehensive view of project workflow tooling, quality gates, and development environment status.

## Access

**Shortcut:** `Cmd+Shift+H` or click the heart icon in the sidebar.

## Sections

### Workflow Validation
Runs `scripts/validate-workflow.sh` to verify:
- Sentrux layer paths exist on disk
- Git hooks are active and valid
- Required stack tools installed (swiftformat, swiftlint, gitleaks, sentrux)
- Archon baseBranch exists
- Graphify config patterns match project files

### Quality Metrics
Displays code quality metrics when `.sentrux/baseline.json` exists:
- Quality score (0-10000)
- God file count
- Test coverage

### Workflow Items
Checks for required project files:
| Item | Path | Purpose |
|------|------|---------|
| checks | `scripts/checks.sh` | Format, lint, build pipeline |
| validate | `scripts/validate-workflow.sh` | Workflow tooling self-validation |
| githooks | `.githooks/` | Pre-commit + pre-push hooks |
| sentrux | `.sentrux/` | Architectural quality gates |
| archon | `.archon/` | AI workflow definitions |
| graphify | `.graphify/` | Knowledge graph tracking |
| gitleaks | `.gitleaks.toml` | Secret scanning |
| doppler | `.doppler.yaml` | Secrets management |

### Tools
Checks for installed development tools:
- swiftformat
- swiftlint
- sentrux
- gitleaks

### Actions
- **Refresh:** Re-scan all health metrics
- **Open Config:** Click any workflow item to open its config file