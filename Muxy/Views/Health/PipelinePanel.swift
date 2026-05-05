import SwiftUI

struct PipelinePanel: View {
    @Bindable var state: PipelineState
    let projectPath: String
    let projectName: String
    let onRefresh: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
            Rectangle().fill(MuxyTheme.border).frame(height: 1)
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Color.clear.frame(height: 10)
                    workflowSelector
                        .padding(.horizontal, 10)
                    if let wf = state.activeWorkflow {
                        sectionSpacer
                        workflowStatusBanner(wf)
                            .padding(.horizontal, 10)
                        sectionSpacer
                        stepsSection(wf)
                            .padding(.horizontal, 10)
                    }
                    sectionSpacer
                    toolValidationSection
                        .padding(.horizontal, 10)
                    Color.clear.frame(height: 12)
                }
            }
        }
        .background(MuxyTheme.bg)
        .onChange(of: projectPath) { _, _ in onRefresh() }
    }

    private var sectionSpacer: some View {
        Rectangle()
            .fill(MuxyTheme.border)
            .frame(height: 1)
            .padding(.vertical, 8)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "arrow.triangle.branch")
                .font(.system(size: 13))
                .foregroundStyle(MuxyTheme.accent)
            Text("Pipeline")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(MuxyTheme.fg)
            Spacer(minLength: 0)
            if let lastRun = state.lastRun {
                Text(timeAgo(lastRun))
                    .font(.system(size: 10))
                    .foregroundStyle(MuxyTheme.fgDim)
            }
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

    private var workflowSelector: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("WORKFLOW")
                .font(.system(size: 10, weight: .bold))
                .tracking(0.5)
                .foregroundStyle(MuxyTheme.fgDim)
            if state.workflows.isEmpty {
                Text("No workflows found in .archon/workflows/")
                    .font(.system(size: 11))
                    .foregroundStyle(MuxyTheme.fgMuted)
            } else {
                ForEach(state.workflows) { wf in
                    let isActive = wf.id == state.activeWorkflowID
                    let wid = wf.id
                    Button(action: { state.activeWorkflowID = wid }, label: {
                        HStack(spacing: 6) {
                            Image(systemName: isActive ? "circle.fill" : "circle")
                                .font(.system(size: 8))
                                .foregroundStyle(isActive ? MuxyTheme.accent : MuxyTheme.fgDim)
                            Text(wf.name)
                                .font(.system(size: 11, weight: isActive ? .semibold : .regular))
                                .foregroundStyle(isActive ? MuxyTheme.fg : MuxyTheme.fgMuted)
                            Spacer(minLength: 0)
                            let followed = wf.steps.count(where: { $0.status == .followed })
                            let total = wf.steps.count
                            Text("\(followed)/\(total)")
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(MuxyTheme.fgDim)
                        }
                        .contentShape(Rectangle())
                    })
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func workflowStatusBanner(_ wf: WorkflowDef) -> some View {
        let skipped = wf.steps.filter { $0.status == .skipped }
        let pending = wf.steps.filter { $0.status == .pending }

        if !skipped.isEmpty {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Workflow not fully followed")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(MuxyTheme.fg)
                    Text("\(skipped.count) step\(skipped.count == 1 ? "" : "s") skipped")
                        .font(.system(size: 11))
                        .foregroundStyle(MuxyTheme.fgDim)
                }
            }
            .padding(10)
            .background(Color.orange.opacity(0.1))
            .cornerRadius(6)
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.orange.opacity(0.3), lineWidth: 1))
        } else if !pending.isEmpty {
            HStack(spacing: 8) {
                Image(systemName: "clock")
                    .font(.system(size: 14))
                    .foregroundStyle(MuxyTheme.accent)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Workflow in progress")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(MuxyTheme.fg)
                    Text("\(pending.count) step\(pending.count == 1 ? "" : "s") pending")
                        .font(.system(size: 11))
                        .foregroundStyle(MuxyTheme.fgDim)
                }
            }
            .padding(10)
            .background(MuxyTheme.accent.opacity(0.08))
            .cornerRadius(6)
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(MuxyTheme.accent.opacity(0.2), lineWidth: 1))
        } else {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(.green)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Workflow completed")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(MuxyTheme.fg)
                    Text("All steps followed")
                        .font(.system(size: 11))
                        .foregroundStyle(MuxyTheme.fgDim)
                }
            }
            .padding(10)
            .background(Color.green.opacity(0.08))
            .cornerRadius(6)
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.green.opacity(0.2), lineWidth: 1))
        }
    }

    private func stepsSection(_ wf: WorkflowDef) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader("Steps")
            ForEach(wf.steps) { step in
                stepRow(step)
            }
        }
    }

    private func stepRow(_ step: PipelineStep) -> some View {
        HStack(spacing: 8) {
            stepIcon(step.status)
            VStack(alignment: .leading, spacing: 1) {
                Text(step.name)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(step.status == .skipped ? MuxyTheme.fgMuted : MuxyTheme.fg)
                if let evidence = step.evidence {
                    Text(evidence)
                        .font(.system(size: 10))
                        .foregroundStyle(MuxyTheme.fgDim)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
        .opacity(step.status == .skipped ? 0.7 : 1)
    }

    private func stepIcon(_ status: StepStatus) -> some View {
        switch status {
        case .followed:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 13))
                .foregroundStyle(.green)
        case .skipped:
            Image(systemName: "exclamationmark.circle.fill")
                .font(.system(size: 13))
                .foregroundStyle(.orange)
        case .pending:
            Image(systemName: "circle")
                .font(.system(size: 13))
                .foregroundStyle(MuxyTheme.fgDim.opacity(0.5))
        }
    }

    private var toolValidationSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionHeader("Tooling Health")
            HStack(spacing: 8) {
                Image(systemName: "checkmark.shield.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(toolValidationColor)
                VStack(alignment: .leading, spacing: 1) {
                    if let passed = state.toolValidationPassed {
                        Text(passed ? "All checks passed" : "Issues detected")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(MuxyTheme.fg)
                        if let detail = state.toolValidationDetail {
                            Text(detail)
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(MuxyTheme.fgDim)
                        }
                    } else {
                        Text("Not yet validated")
                            .font(.system(size: 12))
                            .foregroundStyle(MuxyTheme.fgDim)
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }

    private var toolValidationColor: Color {
        guard let passed = state.toolValidationPassed else { return MuxyTheme.fgDim }
        return passed ? .green : .red
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.system(size: 10, weight: .bold))
            .tracking(0.5)
            .foregroundStyle(MuxyTheme.fgDim)
            .padding(.bottom, 4)
    }

    private func timeAgo(_ date: Date) -> String {
        let interval = -date.timeIntervalSinceNow
        switch interval {
        case ..<60: return "\(Int(interval))s ago"
        case ..<3600: return "\(Int(interval / 60))m ago"
        case ..<86400: return "\(Int(interval / 3600))h ago"
        default: return "\(Int(interval / 86400))d ago"
        }
    }
}
