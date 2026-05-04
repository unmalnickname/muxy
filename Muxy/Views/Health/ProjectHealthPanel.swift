import SwiftUI

struct ProjectHealthPanel: View {
    @Bindable
    var state: ProjectHealthState
    let projectPath: String
    let projectName: String
    let onRefresh: () -> Void
    let onOpenFile: (String) -> Void
    let onOpenProfile: ((String) -> Void)?
    let onSelectAgent: ((String) -> Void)?
    let onClearAgent: (() -> Void)?

    var body: some View {
        VStack(spacing: 0) {
            header
            Rectangle().fill(MuxyTheme.border).frame(height: 1)
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Color.clear.frame(height: 10)
                    qualitySection.padding(.horizontal, 10)
                    sectionSpacer
                    insightsSection.padding(.horizontal, 10)
                    sectionSpacer
                    taskContextSection.padding(.horizontal, 10)
                    sectionSpacer
                    workflowSection.padding(.horizontal, 10)
                    sectionSpacer
                    toolsSection.padding(.horizontal, 10)
                    if state.ciStatus != nil {
                        sectionSpacer
                        ciSection.padding(.horizontal, 10)
                    }
                    if !state.piEvents.isEmpty {
                        sectionSpacer
                        piSection.padding(.horizontal, 10)
                    }
                    sectionSpacer
                    actionsSection.padding(.horizontal, 10)
                    Color.clear.frame(height: 12)
                }
            }
        }
        .background(MuxyTheme.bg)
    }

    private var sectionSpacer: some View {
        Rectangle()
            .fill(MuxyTheme.border)
            .frame(height: 1)
            .padding(.vertical, 8)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "heart.circle.fill")
                .font(.system(size: 13))
                .foregroundStyle(MuxyTheme.accent)
            Text("Project Health")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(MuxyTheme.fg)
            Spacer(minLength: 0)
            Button(action: onRefresh) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(MuxyTheme.fgMuted)
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Refresh")
        }
        .padding(.horizontal, 10)
        .frame(height: 32)
    }

    private var qualitySection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "gauge.open.with.lines.needle.33percent")
                    .font(.system(size: 18))
                    .foregroundStyle(MuxyTheme.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Quality Score")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(MuxyTheme.fgDim)
                    Text("\(state.qualityScore)")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(MuxyTheme.fg)
                    HStack(spacing: 12) {
                        Label("God files: \(state.godFileCount)", systemImage: "doc.badge.gearshape")
                            .font(.system(size: 10))
                            .foregroundStyle(MuxyTheme.fgDim)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, 4)
        }
    }

    @State
    private var popoverAgent: AgentProfile?
    @State
    private var showAgentRoster = false
    @State
    private var rosterSelectedAgent: AgentProfile?
    @State
    private var showTaskPicker = false
    @State
    private var draftTaskType = "unknown"
    @State
    private var draftDescription = ""

    private var insightsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader("Insights")
            ForEach(state.insights) { insight in
                HStack(spacing: 8) {
                    statusIcon(insight.status)
                    VStack(alignment: .leading, spacing: 1) {
                        HStack(spacing: 4) {
                            Text(insight.label + ":")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(MuxyTheme.fgDim)
                            if insight.agentProfile != nil {
                                Text(insight.value)
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundStyle(MuxyTheme.accent)
                                    .underline()
                                    .onTapGesture { popoverAgent = insight.agentProfile }
                                    .onHover { hovering in
                                        if hovering { NSCursor.pointingHand.push() } else { NSCursor.pop() }
                                    }
                                Text("(\(agentProfiles.count))")
                                    .font(.system(size: 9))
                                    .foregroundStyle(MuxyTheme.fgDim)
                                    .onTapGesture { showAgentRoster = true }
                                    .onHover { hovering in
                                        if hovering { NSCursor.pointingHand.push() } else { NSCursor.pop() }
                                    }
                            } else {
                                Text(insight.value)
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundStyle(MuxyTheme.fg)
                            }
                        }
                    }
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 3)
            }
        }
        .popover(item: $popoverAgent) { agent in
            AgentPopoverView(
                agent: agent,
                isSelected: agent.id == state.selectedAgent,
                onOpenProfile: onOpenProfile,
                onSelect: { onSelectAgent?(agent.id) },
                onClear: onClearAgent
            )
        }
        .popover(isPresented: $showAgentRoster) {
            AgentRosterView(
                selectedAgent: $rosterSelectedAgent,
                selectedId: state.selectedAgent,
                onOpenProfile: onOpenProfile,
                onSelect: { onSelectAgent?($0) }
            )
            .onChange(of: rosterSelectedAgent) { _, newAgent in
                if let agent = newAgent {
                    popoverAgent = agent
                    rosterSelectedAgent = nil
                    showAgentRoster = false
                }
            }
        }
    }

    private var taskContextSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader("Task Context")

            // Task type row
            HStack(spacing: 8) {
                Image(systemName: taskTypeIcon(state.currentTaskType))
                    .font(.system(size: 13))
                    .foregroundStyle(state.currentTaskType == "unknown" ? MuxyTheme.fgDim : MuxyTheme.accent)
                VStack(alignment: .leading, spacing: 1) {
                    Text(taskTypeLabels[state.currentTaskType] ?? "Unknown Task")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(MuxyTheme.fg)
                    Text("Auto-detected from \(state.currentTaskType == "unknown" ? "branch" : "branch name")")
                        .font(.system(size: 10))
                        .foregroundStyle(MuxyTheme.fgDim)
                }
                Spacer(minLength: 0)
                Button("Change") { showTaskPicker = true }
                    .buttonStyle(.plain)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(MuxyTheme.accent)
            }
            .padding(.vertical, 4)

            // Context suggestions
            if !state.contextSuggestions.isEmpty {
                ForEach(state.contextSuggestions) { suggestion in
                    HStack(spacing: 8) {
                        switch suggestion.severity {
                        case .missing:
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 11))
                                .foregroundStyle(.red)
                        case .partial:
                            Image(systemName: "exclamationmark.circle.fill")
                                .font(.system(size: 11))
                                .foregroundStyle(.orange)
                        case .optional:
                            Image(systemName: "info.circle.fill")
                                .font(.system(size: 11))
                                .foregroundStyle(MuxyTheme.fgDim)
                        }
                        VStack(alignment: .leading, spacing: 0) {
                            Text(suggestion.skillName)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(MuxyTheme.fg)
                            Text(suggestion.reason)
                                .font(.system(size: 9))
                                .foregroundStyle(MuxyTheme.fgDim)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, 2)
                }
            }

            // Apply context button
            if state.currentTaskType != "unknown" {
                HStack(spacing: 8) {
                    Button {
                        let needs: [String] = if state.availableSkills.isEmpty {
                            []
                        } else {
                            state.contextSuggestions.filter { $0.severity == .missing }.map(\.skillName)
                        }
                        state.applyContext(
                            taskType: state.currentTaskType,
                            description: state.taskDescription,
                            skills: needs,
                            projectPath: projectPath
                        )
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "doc.badge.plus")
                                .font(.system(size: 10))
                            Text("Apply Context")
                                .font(.system(size: 10, weight: .medium))
                        }
                        .foregroundStyle(MuxyTheme.accent)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(MuxyTheme.accent.opacity(0.1))
                        .cornerRadius(6)
                    }
                    .buttonStyle(.plain)

                    if let session = state.lastSession {
                        Spacer(minLength: 0)
                        Text("Last: \(session.agent ?? "?") · \(session.status ?? "?")")
                            .font(.system(size: 9))
                            .foregroundStyle(MuxyTheme.fgDim)
                    }
                }
                .padding(.top, 4)
            }
        }
        .popover(isPresented: $showTaskPicker) {
            taskPickerPopover
        }
    }

    private var taskPickerPopover: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Set Task Type")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(MuxyTheme.fg)

            let validTypes = ["feature", "fix", "refactor", "ui", "docs", "chore", "hotfix", "test", "unknown"]
            ForEach(validTypes, id: \.self) { type in
                HStack(spacing: 8) {
                    Image(systemName: type == state.currentTaskType ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 12))
                        .foregroundStyle(type == state.currentTaskType ? .green : MuxyTheme.fgDim)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(taskTypeLabels[type] ?? type)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(MuxyTheme.fg)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 3)
                .padding(.horizontal, 4)
                .contentShape(Rectangle())
                .onTapGesture {
                    state.applyContext(
                        taskType: type,
                        description: state.taskDescription,
                        skills: state.contextSuggestions.filter { $0.severity == .missing }.map(\.skillName),
                        projectPath: projectPath
                    )
                    showTaskPicker = false
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 4) {
                Text("Description (optional)")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(MuxyTheme.fgDim)
                TextField("What are you working on?", text: $draftDescription)
                    .textFieldStyle(.plain)
                    .font(.system(size: 10))
                    .padding(6)
                    .background(MuxyTheme.fgDim.opacity(0.1))
                    .cornerRadius(6)
                    .onSubmit {
                        state.applyContext(
                            taskType: state.currentTaskType,
                            description: draftDescription,
                            skills: state.contextSuggestions.filter { $0.severity == .missing }.map(\.skillName),
                            projectPath: projectPath
                        )
                        showTaskPicker = false
                    }
            }
        }
        .padding(12)
        .frame(width: 240)
        .background(MuxyTheme.bg)
    }

    private func taskTypeIcon(_ type: String) -> String {
        switch type {
        case "feature": "star.circle.fill"
        case "fix": "wrench.circle.fill"
        case "refactor": "arrow.triangle.branch"
        case "ui": "paintpalette.fill"
        case "docs": "doc.text.fill"
        case "chore": "gearshape.fill"
        case "hotfix": "flame.fill"
        case "test": "checkmark.circle.fill"
        default: "questionmark.circle"
        }
    }

    private var workflowSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader("Agent Workflow")
            ForEach(state.workflowItems) { item in
                workflowRow(item)
            }
        }
    }

    private func workflowRow(_ item: WorkflowItem) -> some View {
        HStack(spacing: 8) {
            statusIcon(item.status)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Text(item.name)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(item.status == .missing ? MuxyTheme.fgMuted : MuxyTheme.fg)
                    if item.status == .missing {
                        Text("— not found")
                            .font(.system(size: 10))
                            .foregroundStyle(MuxyTheme.fgDim)
                    }
                }
                Text(item.description)
                    .font(.system(size: 10))
                    .foregroundStyle(MuxyTheme.fgDim)
                if let detail = item.detail, item.status != .missing {
                    Text(detail)
                        .font(.system(size: 9))
                        .foregroundStyle(MuxyTheme.fgDim.opacity(0.7))
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            if item.status == .missing {
                if item.relativePath.hasPrefix("Branch") || item.relativePath.isEmpty {
                    EmptyView()
                } else {
                    Button("Create") {
                        createFile(at: item.relativePath)
                        onRefresh()
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(MuxyTheme.accent)
                    if let action = item.action {
                        Button("Setup") {
                            runAction(action)
                            onRefresh()
                        }
                        .buttonStyle(.plain)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(MuxyTheme.fgMuted)
                    }
                }
            } else if !item.relativePath.isEmpty {
                Text(item.relativePath)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(MuxyTheme.fgDim)
                    .onTapGesture { onOpenFile(item.relativePath) }
                    .onHover { hovering in
                        if hovering { NSCursor.pointingHand.push() } else { NSCursor.pop() }
                    }
            }
        }
        .padding(.vertical, 4)
        .opacity(item.status == .missing ? 0.7 : 1)
    }

    private var toolsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader("Global Tools")
            ForEach(state.globalTools) { tool in
                toolRow(tool)
            }
        }
    }

    private func toolRow(_ tool: GlobalToolItem) -> some View {
        HStack(spacing: 8) {
            statusIcon(tool.installed ? .active : .missing)
            VStack(alignment: .leading, spacing: 1) {
                Text(tool.name)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(MuxyTheme.fg)
                if let version = tool.version, tool.installed {
                    Text(version)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(MuxyTheme.fgDim)
                }
            }
            Spacer(minLength: 0)
            if !tool.installed, let hint = tool.installHint {
                Button("Install") {
                    runAction(hint)
                    onRefresh()
                }
                .buttonStyle(.plain)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(MuxyTheme.accent)
            }
        }
        .padding(.vertical, 4)
    }

    private var ciSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader("CI Status")
            if let ci = state.ciStatus {
                HStack(spacing: 8) {
                    switch ci.status {
                    case .passed:
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(.green)
                    case .failed:
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(.red)
                    case .running:
                        ProgressView().controlSize(.small)
                    case .unknown:
                        Image(systemName: "questionmark.circle")
                            .font(.system(size: 14))
                            .foregroundStyle(MuxyTheme.fgDim)
                    }
                    VStack(alignment: .leading, spacing: 1) {
                        Text(ci.branch)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(MuxyTheme.fg)
                        if let ago = ci.lastRunAgo {
                            Text("Last run \(ago)")
                                .font(.system(size: 10))
                                .foregroundStyle(MuxyTheme.fgDim)
                        }
                    }
                    Spacer(minLength: 0)
                    if let urlStr = ci.url, let url = URL(string: urlStr) {
                        Button("Open") { NSWorkspace.shared.open(url) }
                            .buttonStyle(.plain)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(MuxyTheme.accent)
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }

    private var piSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader("Pi Agent Extension")
            HStack(spacing: 6) {
                Image(systemName: "sparkle.magnifyingglass")
                    .font(.system(size: 11))
                    .foregroundStyle(MuxyTheme.fgDim)
                Text("Fired \(state.piEvents.count) time\(state.piEvents.count == 1 ? "" : "s")")
                    .font(.system(size: 11))
                    .foregroundStyle(MuxyTheme.fg)
            }
            .padding(.vertical, 6)
            ForEach(state.piEvents.prefix(3)) { event in
                HStack(spacing: 6) {
                    Circle().fill(MuxyTheme.accent).frame(width: 4, height: 4)
                    Text(event.event)
                        .font(.system(size: 10))
                        .foregroundStyle(MuxyTheme.fgDim)
                        .lineLimit(1)
                }
                .padding(.vertical, 2)
            }
        }
    }

    private var actionsSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            let missingWorkflow = state.workflowItems.filter { $0.status == .missing }
            let partialWorkflow = state.workflowItems.filter { $0.status == .partial }
            let toolMissing = state.globalTools.filter { !$0.installed }
            let missingCount = missingWorkflow.count + toolMissing.count

            if missingCount > 0 {
                HStack(spacing: 6) {
                    ForEach(missingWorkflow.prefix(3)) { item in
                        Text(item.name)
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(.red.opacity(0.8))
                    }
                    if missingWorkflow.count > 3 {
                        Text("+\(missingWorkflow.count - 3) more")
                            .font(.system(size: 9))
                            .foregroundStyle(MuxyTheme.fgDim)
                    }
                }
                .lineLimit(1)
                HStack(spacing: 8) {
                    Button {
                        confirmAndFix()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "wrench.adjustable")
                                .font(.system(size: 10, weight: .medium))
                            Text("Fix All (\(missingCount))")
                                .font(.system(size: 10, weight: .semibold))
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(MuxyTheme.accent, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    Text(breakdown(missing: missingWorkflow.count, tools: toolMissing.count))
                        .font(.system(size: 9))
                        .foregroundStyle(MuxyTheme.fgDim)
                }
            }
            if !partialWorkflow.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(.orange)
                    ForEach(partialWorkflow.prefix(4)) { item in
                        Text(item.name + (item.detail.map { ": \($0)" } ?? ""))
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(.orange)
                            .lineLimit(1)
                    }
                    if partialWorkflow.count > 4 {
                        Text("+\(partialWorkflow.count - 4) more")
                            .font(.system(size: 9))
                            .foregroundStyle(MuxyTheme.fgDim)
                    }
                }
                .lineLimit(1)
            }
            if missingCount == 0, partialWorkflow.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.green)
                    Text("All systems operational")
                        .font(.system(size: 11))
                        .foregroundStyle(MuxyTheme.fgDim)
                }
            }
            Spacer(minLength: 0)
        }
    }

    private func breakdown(missing: Int, tools: Int) -> String {
        var parts: [String] = []
        if missing > 0 { parts.append("\(missing) workflow") }
        if tools > 0 { parts.append("\(tools) tool") }
        return parts.joined(separator: " · ")
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.system(size: 10, weight: .bold))
            .tracking(0.5)
            .foregroundStyle(MuxyTheme.fgDim)
            .padding(.bottom, 4)
    }

    @ViewBuilder
    private func statusIcon(_ status: ItemStatus) -> some View {
        switch status {
        case .active:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 13))
                .foregroundStyle(.green)
        case .partial:
            Image(systemName: "exclamationmark.circle.fill")
                .font(.system(size: 13))
                .foregroundStyle(.orange)
        case .missing:
            Image(systemName: "circle")
                .font(.system(size: 13))
                .foregroundStyle(MuxyTheme.fgDim.opacity(0.5))
        }
    }

    private func createFile(at relativePath: String) {
        let fullPath = (projectPath as NSString).appendingPathComponent(relativePath)
        let fm = FileManager.default
        var isDir: ObjCBool = false
        if fm.fileExists(atPath: fullPath, isDirectory: &isDir) { return }
        if Self.isDirectoryPath(relativePath) {
            try? fm.createDirectory(at: URL(fileURLWithPath: fullPath), withIntermediateDirectories: true)
        } else {
            let dir = (fullPath as NSString).deletingLastPathComponent
            try? fm.createDirectory(at: URL(fileURLWithPath: dir), withIntermediateDirectories: true)
            fm.createFile(atPath: fullPath, contents: Data("# \(relativePath)\n".utf8))
        }
    }

    private static func isDirectoryPath(_ relativePath: String) -> Bool {
        if relativePath.hasSuffix("/") { return true }
        let name = (relativePath as NSString).lastPathComponent
        guard name.contains(".") else { return true }
        if name.hasPrefix(".") {
            return !name.dropFirst().contains(".")
        }
        return false
    }

    private func runAction(_ command: String) {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/bash")
        task.arguments = ["-c", command]
        try? task.run()
    }

    private func confirmAndFix() {
        let missingItems = state.workflowItems.filter { $0.status == .missing }
        let missingTools = state.globalTools.filter { !$0.installed }

        let alert = NSAlert()
        alert.messageText = "Fix \(missingItems.count + missingTools.count) Issues?"
        var info = "Will install:\n"
        for item in missingItems {
            info += "  • \(item.name)"
            if let action = item.action { info += " → \(action)" }
            info += "\n"
        }
        for tool in missingTools {
            info += "  • \(tool.name)"
            if let hint = tool.installHint { info += " → \(hint)" }
            info += "\n"
        }
        alert.informativeText = info
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Fix All")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let installs = missingTools.compactMap(\.installHint)
        let setups = missingItems.compactMap(\.action)
        for cmd in installs + setups {
            runAction(cmd)
        }
        onRefresh()
    }
}

private struct AgentPopoverView: View {
    let agent: AgentProfile
    var isSelected: Bool = false
    let onOpenProfile: ((String) -> Void)?
    let onSelect: (() -> Void)?
    let onClear: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "person.circle.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(MuxyTheme.accent)
                Text(agent.name)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(MuxyTheme.fg)
                if isSelected {
                    Text("Selected")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.green)
                        .cornerRadius(4)
                }
            }

            Text(agent.role)
                .font(.system(size: 11))
                .foregroundStyle(MuxyTheme.fgDim)

            Divider()

            VStack(alignment: .leading, spacing: 4) {
                Text("Strengths")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.green)
                ForEach(agent.strengths, id: \.self) { s in
                    HStack(spacing: 4) {
                        Circle().fill(.green).frame(width: 4, height: 4)
                        Text(s).font(.system(size: 10)).foregroundStyle(MuxyTheme.fg)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Weaknesses")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.orange)
                ForEach(agent.weaknesses, id: \.self) { w in
                    HStack(spacing: 4) {
                        Circle().fill(.orange).frame(width: 4, height: 4)
                        Text(w).font(.system(size: 10)).foregroundStyle(MuxyTheme.fg)
                    }
                }
            }

            Divider()

            HStack(spacing: 4) {
                Text("Best for:")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(MuxyTheme.fgDim)
                Text(agent.bestFor)
                    .font(.system(size: 10))
                    .foregroundStyle(MuxyTheme.fg)
            }

            Divider()

            HStack(spacing: 8) {
                if isSelected, let onClear {
                    Button {
                        onClear()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "xmark.circle")
                                .font(.system(size: 10))
                            Text("Deselect")
                                .font(.system(size: 10, weight: .medium))
                        }
                        .foregroundStyle(.red)
                        .padding(.vertical, 4)
                        .padding(.horizontal, 10)
                        .background(.red.opacity(0.1))
                        .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                } else if let onSelect {
                    Button {
                        onSelect()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark.circle")
                                .font(.system(size: 10))
                            Text("Use This Agent")
                                .font(.system(size: 10, weight: .medium))
                        }
                        .foregroundStyle(MuxyTheme.accent)
                        .padding(.vertical, 4)
                        .padding(.horizontal, 10)
                        .background(MuxyTheme.accent.opacity(0.1))
                        .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                }

                if let path = agent.skillPath {
                    Button {
                        let fullPath = NSString(string: path).expandingTildeInPath
                        onOpenProfile?(fullPath)
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "doc.text.magnifyingglass")
                                .font(.system(size: 10))
                            Text("Open Profile")
                                .font(.system(size: 10, weight: .medium))
                        }
                        .foregroundStyle(MuxyTheme.fgDim)
                        .padding(.vertical, 4)
                        .padding(.horizontal, 10)
                        .background(MuxyTheme.fgDim.opacity(0.1))
                        .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(14)
        .frame(width: 280)
        .background(MuxyTheme.bg)
    }
}

private struct AgentRosterView: View {
    @Binding
    var selectedAgent: AgentProfile?
    var selectedId: String?
    let onOpenProfile: ((String) -> Void)?
    let onSelect: (String) -> Void
    @State
    private var hoveredAgent: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text("All Agents")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(MuxyTheme.fg)
                Spacer(minLength: 0)
                if let selectedId {
                    Text("Selected: \(selectedId)")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.green)
                }
            }
            .padding(.bottom, 4)

            ForEach(Array(agentProfiles.values).sorted(by: { $0.name < $1.name })) { agent in
                HStack(spacing: 10) {
                    Image(systemName: agent.id == selectedId ? "checkmark.circle.fill" : "person.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(agent.id == selectedId ? .green : MuxyTheme.fgDim)
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(agent.name)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(MuxyTheme.fg)
                            if agent.id == selectedId {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundStyle(.green)
                            }
                        }
                        Text(agent.role)
                            .font(.system(size: 9))
                            .foregroundStyle(MuxyTheme.fgDim)
                            .lineLimit(2)
                    }
                    Spacer(minLength: 0)
                    Button("Select") {
                        onSelect(agent.id)
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(agent.id == selectedId ? .green : MuxyTheme.accent)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background((agent.id == selectedId ? Color.green : MuxyTheme.accent).opacity(0.1))
                    .cornerRadius(4)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(hoveredAgent == agent.id ? MuxyTheme.fgDim.opacity(0.1) : .clear)
                .cornerRadius(6)
                .onTapGesture { onSelect(agent.id) }
                .onHover { hovering in
                    hoveredAgent = hovering ? agent.id : nil
                    if hovering { NSCursor.pointingHand.push() } else { NSCursor.pop() }
                }
            }
        }
        .padding(12)
        .frame(width: 340)
        .background(MuxyTheme.bg)
    }
}
