import AppKit
import SwiftUI

struct MainContentArea: View {
    let appState: AppState
    let projectStore: ProjectStore
    let worktreeStore: WorktreeStore
    let sidebarExpanded: Bool
    let sidebarCollapsedStyle: SidebarCollapsedStyle
    let sidebarExpandedStyle: SidebarExpandedStyle
    @Binding var vcsPanelVisible: Bool
    @Binding var vcsPanelWidth: CGFloat
    let vcsStates: [WorktreeKey: VCSTabState]
    @Binding var fileTreePanelVisible: Bool
    @Binding var fileTreePanelWidth: Double
    let fileTreeStates: [WorktreeKey: FileTreeState]
    @Binding var healthPanelVisible: Bool
    let healthState: ProjectHealthState
    @Binding var pipelinePanelVisible: Bool
    let pipelineState: PipelineState

    var body: some View {
        HStack(spacing: 0) {
            sidebarView
            workspaceArea
            sidePanels
        }
    }

    private var sidebarView: some View {
        HStack(spacing: 0) {
            Sidebar()
            if !SidebarLayout.isHidden(expanded: sidebarExpanded, collapsedStyle: sidebarCollapsedStyle) {
                Rectangle().fill(MuxyTheme.border).frame(width: 1)
                    .accessibilityHidden(true)
            }
        }
        .fixedSize(horizontal: true, vertical: false)
        .background(MuxyTheme.bg)
    }

    private var workspaceArea: some View {
        ZStack {
            MuxyTheme.bg
            if let project = activeProject,
               appState.workspaceRoot(for: project.id) == nil,
               let worktree = resolvedActiveWorktree(for: project)
            {
                EmptyProjectPlaceholder(project: project) {
                    appState.selectWorktree(projectID: project.id, worktree: worktree)
                }
            } else if let project = activeProjectWithWorkspace,
                      let activeKey = appState.activeWorktreeKey(for: project.id)
            {
                ForEach(mountedWorktreeKeys(for: project), id: \.self) { key in
                    TerminalArea(
                        project: project,
                        worktreeKey: key,
                        isActiveProject: key == activeKey
                    )
                    .opacity(key == activeKey ? 1 : 0)
                    .allowsHitTesting(key == activeKey)
                    .zIndex(key == activeKey ? 1 : 0)
                }
            }
        }
    }

    @ViewBuilder
    private var sidePanels: some View {
        if vcsPanelVisible, VCSDisplayMode.current == .attached, let state = activeVCSState {
            HStack(spacing: 0) {
                sidePanelResizeHandle { delta in
                    vcsPanelWidth = max(200, min(800, vcsPanelWidth - delta))
                }
                VCSTabView(state: state, focused: false, onFocus: {})
                    .frame(width: vcsPanelWidth)
            }
        } else if fileTreePanelVisible, let treeState = activeFileTreeState {
            HStack(spacing: 0) {
                sidePanelResizeHandle { delta in
                    let next = fileTreePanelWidth - Double(delta)
                    fileTreePanelWidth = max(180.0, min(600.0, next))
                }
                FileTreeView(
                    state: treeState,
                    onOpenFile: { filePath in
                        guard let projectID = appState.activeProjectID else { return }
                        appState.openFile(filePath, projectID: projectID, preserveFocus: true)
                    },
                    onOpenTerminal: { directory in
                        guard let projectID = appState.activeProjectID else { return }
                        appState.dispatch(.createTabInDirectory(
                            projectID: projectID, areaID: nil, directory: directory
                        ))
                    },
                    onFileMoved: { oldPath, newPath in
                        appState.handleFileMoved(from: oldPath, to: newPath)
                    }
                )
                .id(treeState.rootPath)
                .frame(width: CGFloat(fileTreePanelWidth))
            }
        } else if healthPanelVisible, let project = activeProject {
            healthPanelContent(project: project)
        } else if pipelinePanelVisible, let project = activeProject {
            pipelinePanelContent(project: project)
        }
    }

    private func healthPanelContent(project: Project) -> some View {
        HStack(spacing: 0) {
            sidePanelResizeHandle { _ in healthPanelVisible = false }
            ProjectHealthPanel(
                state: healthState,
                projectPath: activeProjectPath(for: project),
                projectName: project.name,
                onRefresh: { healthState.refresh(projectPath: activeProjectPath(for: project)) },
                onOpenFile: { relativePath in
                    healthPanelVisible = false
                    let basePath = activeProjectPath(for: project)
                    let fullPath = basePath.hasSuffix("/") ? basePath + relativePath : basePath + "/" + relativePath
                    guard let projectID = appState.activeProjectID else { return }
                    appState.openFile(fullPath, projectID: projectID)
                },
                onOpenProfile: { absolutePath in
                    healthPanelVisible = false
                    guard let projectID = appState.activeProjectID else { return }
                    appState.openFile(absolutePath, projectID: projectID)
                },
                onSelectAgent: { agentName in
                    healthState.selectAgent(agentName, projectPath: activeProjectPath(for: project))
                },
                onClearAgent: { healthState.clearAgent(projectPath: activeProjectPath(for: project)) }
            )
            .frame(width: 320)
            .onChange(of: appState.activeProjectID) { _, _ in
                guard let project = activeProject else { return }
                healthState.selectedAgent = nil
                healthState.refresh(projectPath: activeProjectPath(for: project))
            }
        }
    }

    private func pipelinePanelContent(project: Project) -> some View {
        HStack(spacing: 0) {
            sidePanelResizeHandle { _ in pipelinePanelVisible = false }
            PipelinePanel(
                state: pipelineState,
                projectPath: activeProjectPath(for: project),
                projectName: project.name,
                onRefresh: { pipelineState.refresh(projectPath: activeProjectPath(for: project)) }
            )
            .frame(width: 320)
            .onChange(of: appState.activeProjectID) { _, _ in
                guard let project = activeProject else { return }
                pipelineState.startPolling(projectPath: activeProjectPath(for: project))
            }
        }
    }

    private var activeProject: Project? {
        guard let pid = appState.activeProjectID else { return nil }
        return projectStore.projects.first { $0.id == pid }
    }

    private var activeProjectWithWorkspace: Project? {
        guard let project = activeProject,
              appState.workspaceRoot(for: project.id) != nil
        else { return nil }
        return project
    }

    private var projectsWithWorkspaces: [Project] {
        projectStore.projects.filter { appState.workspaceRoot(for: $0.id) != nil }
    }

    private var activeVCSState: VCSTabState? {
        guard let project = activeProject,
              let key = appState.activeWorktreeKey(for: project.id)
        else { return nil }
        return vcsStates[key]
    }

    private var activeFileTreeState: FileTreeState? {
        guard let project = activeProject,
              let key = appState.activeWorktreeKey(for: project.id)
        else { return nil }
        return fileTreeStates[key]
    }

    private func resolvedActiveWorktree(for project: Project) -> Worktree? {
        worktreeStore.preferred(for: project.id, matching: appState.activeWorktreeID[project.id])
    }

    private func mountedWorktreeKeys(for project: Project) -> [WorktreeKey] {
        appState.workspaceRoots.keys
            .filter { $0.projectID == project.id }
            .sorted { $0.worktreeID.uuidString < $1.worktreeID.uuidString }
    }

    private func sidePanelResizeHandle(onDrag: @escaping (CGFloat) -> Void) -> some View {
        Rectangle().fill(MuxyTheme.border).frame(width: 1)
            .accessibilityHidden(true)
            .overlay {
                Color.clear
                    .frame(width: 5)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 1)
                            .onChanged { v in onDrag(v.translation.width) }
                    )
                    .onHover { on in
                        if on { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
                    }
            }
    }

    private func activeProjectPath(for project: Project) -> String {
        worktreeStore.preferred(for: project.id, matching: appState.activeWorktreeID[project.id])?.path ?? project.path
    }
}
