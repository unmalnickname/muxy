import SwiftUI

struct ProjectHealthPanel: View {
    @Bindable var state: ProjectHealthState
    let projectPath: String
    let projectName: String
    let onRefresh: () -> Void
    let onOpenFile: (String) -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
            Rectangle().fill(MuxyTheme.border).frame(height: 1)
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Color.clear.frame(height: 10)
                    qualitySection
                        .padding(.horizontal, 10)
                    sectionSpacer
                    validationSection
                        .padding(.horizontal, 10)
                    sectionSpacer
                    workflowSection
                        .padding(.horizontal, 10)
                    sectionSpacer
                    toolsSection
                        .padding(.horizontal, 10)
                    if state.ciStatus != nil {
                        sectionSpacer
                        ciSection
                            .padding(.horizontal, 10)
                    }
                    if !state.piEvents.isEmpty {
                        sectionSpacer
                        piSection
                            .padding(.horizontal, 10)
                    }
                    sectionSpacer
                    actionsSection
                        .padding(.horizontal, 10)
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

    private var validationSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionHeader("Workflow Validation")
            if let passed = state.validationPassed {
                HStack(spacing: 8) {
                    Image(systemName: passed ? "checkmark.shield.fill" : "exclamationmark.shield.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(passed ? .green : .red)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(passed ? "All checks passed" : "Issues detected")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(MuxyTheme.fg)
                        if let detail = state.validationDetail {
                            Text(detail)
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(MuxyTheme.fgDim)
                        }
                    }
                }
                .padding(.vertical, 4)
            } else {
                HStack(spacing: 8) {
                    Image(systemName: "shield")
                        .font(.system(size: 14))
                        .foregroundStyle(MuxyTheme.fgDim)
                    Text("Not yet validated")
                        .font(.system(size: 12))
                        .foregroundStyle(MuxyTheme.fgDim)
                }
                .padding(.vertical, 4)
            }
        }
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

    private var workflowSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader("Agent Workflow")
            ForEach(state.workflowItems) { item in
                workflowRow(item)
            }
        }
    }

    private func workflowRow(_ item: WorkflowItem) -> some View {
        let isMissing = item.status == .missing
        return HStack(spacing: 8) {
            statusIcon(item.status)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Text(item.name)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(isMissing ? MuxyTheme.fgMuted : MuxyTheme.fg)
                    if isMissing {
                        Text("— not found")
                            .font(.system(size: 10))
                            .foregroundStyle(MuxyTheme.fgDim)
                    }
                }
                Text(item.description)
                    .font(.system(size: 10))
                    .foregroundStyle(MuxyTheme.fgDim)
            }
            Spacer(minLength: 0)
            if isMissing {
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
            } else {
                Text(item.name)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(MuxyTheme.fgDim)
                    .onTapGesture {
                        onOpenFile(item.relativePath)
                    }
                    .onHover { hovering in
                        if hovering { NSCursor.pointingHand.push() } else { NSCursor.pop() }
                    }
            }
        }
        .padding(.vertical, 4)
        .opacity(isMissing ? 0.7 : 1)
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
            statusIcon(tool.installed ? .installed : .missing)
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
                        ProgressView()
                            .controlSize(.small)
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
                        Button("Open") {
                            NSWorkspace.shared.open(url)
                        }
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
                    Circle()
                        .fill(MuxyTheme.accent)
                        .frame(width: 4, height: 4)
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
        HStack(spacing: 8) {
            let missing = state.workflowItems.count(where: { $0.status == .missing })
            let toolMissing = state.globalTools.count(where: { !$0.installed })
            let total = missing + toolMissing
            if total > 0 {
                Button {
                    confirmAndFix()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "wrench.adjustable")
                            .font(.system(size: 10, weight: .medium))
                        Text("Fix All (\(total))")
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(MuxyTheme.accent, in: Capsule())
                }
                .buttonStyle(.plain)
            } else {
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
        case .installed:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 13))
                .foregroundStyle(.green)
        case .missing:
            Image(systemName: "circle")
                .font(.system(size: 13))
                .foregroundStyle(MuxyTheme.fgDim.opacity(0.5))
        case .needsAction:
            Image(systemName: "exclamationmark.circle.fill")
                .font(.system(size: 13))
                .foregroundStyle(MuxyTheme.accent)
        }
    }

    private func createFile(at relativePath: String) {
        let fullPath = (projectPath as NSString).appendingPathComponent(relativePath)
        let fm = FileManager.default
        var isDir: ObjCBool = false
        if fm.fileExists(atPath: fullPath, isDirectory: &isDir) { return }
        if relativePath.hasSuffix("/") || !relativePath.contains(".") {
            try? fm.createDirectory(at: URL(fileURLWithPath: fullPath), withIntermediateDirectories: true)
        } else {
            let dir = (fullPath as NSString).deletingLastPathComponent
            try? fm.createDirectory(at: URL(fileURLWithPath: dir), withIntermediateDirectories: true)
            fm.createFile(atPath: fullPath, contents: Data("# \(relativePath)\n".utf8))
        }
    }

    private func runAction(_ command: String) {
        let task = Process()
        task.launchPath = "/bin/bash"
        task.arguments = ["-c", command]
        try? task.run()
    }

    private func confirmAndFix() {
        let alert = NSAlert()
        alert.messageText = "Fix All Issues?"
        alert.informativeText = "This will install missing tools and run setup commands."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Fix All")
        alert.addButton(withTitle: "Cancel")
        guard let window = NSApp.keyWindow ?? NSApp.mainWindow,
              alert.runModal() == .alertFirstButtonReturn
        else { return }
        let installs = state.globalTools.filter { !$0.installed }.compactMap(\.installHint)
        let setups = state.workflowItems.filter { $0.status == .missing }.compactMap(\.action)
        for cmd in installs + setups {
            runAction(cmd)
        }
        onRefresh()
    }
}
