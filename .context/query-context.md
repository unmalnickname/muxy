# SigMap Query Context
Generated: 2026-05-11T00:55:34.143Z

## Muxy/Services/WorktreeStore.swift
```
class WorktreeStore
func loadAll(projects)
func ensurePrimary(for project)
func list(for projectID) → [Worktree]
func projectID(forWorktreePath path) → UUID?
func primary(for projectID) → Worktree?
func worktree(projectID, worktreeID) → Worktree?
func preferred(for projectID, matching preferredID) → Worktree?
func add(_ worktree, to projectID)
```

## Muxy/Views/Components/SearchableListPicker.swift
```
struct SearchableListPicker
```

## Muxy/Views/VCS/PullRequestsListView.swift
```
struct PullRequestsListView
struct PullRequestRow
struct PullRequestsAutoSyncMenu
```

## Muxy/Services/Git/GitWorktreeService.swift
```
struct GitWorktreeRecord
protocol GitWorktreeListing
async func listWorktrees(repoPath) → [GitWorktreeRecord]
actor GitWorktreeService
async func isGitRepository(_ path) → Bool
async func hasUncommittedChanges(worktreePath) → Bool
async func listWorktrees(repoPath) → [GitWorktreeRecord]
async func addWorktree(repoPath, path, branch, createBranch)
async func removeWorktree(repoPath, path, force)
async func deleteBranch(repoPath, branch, force)
func flush()
```

## mcp-servers/graphify-mcp.py
```
def graphify_run(*args, timeout)
def handle_initialize(req)
def handle_list_tools(req)
def handle_call_tool(req)
def error(req_id, msg)
def result(req_id, text)
def read_stdio()
def write_stdio(obj)
def main_stdio()
def main_http(port)
```
