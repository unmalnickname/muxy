import SwiftUI

struct PipelinePanel: View {
    @Bindable var state: PipelineState
    let projectPath: String
    let projectName: String
    let onRefresh: () -> Void

    var body: some View {
        Text("Pipeline Panel (disabled)")
            .frame(maxWidth: .infinity, maxHeight: .infinity)
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
            Image(systemName: "arrow.triangle.branch")
                .font(.system(size: 13))
                .foregroundStyle(MuxyTheme.accent)
            Text("Pipeline")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(MuxyTheme.fg)
            Spacer(minLength: 0)
            if let lastRun = state.lastRun {
                HStack(spacing: 4) {
                    Circle()
                        .fill(.green)
                        .frame(width: 6, height: 6)
                    Text(timeAgo(lastRun))
                        .font(.system(size: 10))
                        .foregroundStyle(MuxyTheme.fgDim)
                }
                .help("Auto-refreshing every 30s")
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

                            let violations = wf.violationCount
                            if violations > 0 {
                                Text("\(violations)")
                                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 2)
                                    .background(Color.orange)
                                    .cornerRadius(6)
                            }

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
        let critical = wf.steps.filter { $0.status == .skipped && $0.severity == .critical }
        let hasViolations = !wf.dependencyViolations.isEmpty

        if !skipped.isEmpty || hasViolations {
            HStack(spacing: 8) {
                Image(systemName: critical.isEmpty ? "exclamationmark.triangle.fill" : "xmark.shield.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(critical.isEmpty ? .orange : .red)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Workflow not fully followed")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(MuxyTheme.fg)
                    HStack(spacing: 6) {
                        if !skipped.isEmpty {
                            Text("\(skipped.count) step\(skipped.count == 1 ? "" : "s") skipped")
                        }
                        if hasViolations {
                            Text("\(wf.dependencyViolations.count) dependency violation\(wf.dependencyViolations.count == 1 ? "" : "s")")
                        }
                    }
                    .font(.system(size: 11))
                    .foregroundStyle(MuxyTheme.fgDim)
                }
            }
            .padding(10)
            .background((critical.isEmpty ? Color.orange : Color.red).opacity(0.1))
            .cornerRadius(6)
            .overlay(RoundedRectangle(cornerRadius: 6).stroke((critical.isEmpty ? Color.orange : Color.red).opacity(0.3), lineWidth: 1))
        } else if wf.steps.contains(where: { $0.status == .pending }) {
            HStack(spacing: 8) {
                Image(systemName: "clock")
                    .font(.system(size: 14))
                    .foregroundStyle(MuxyTheme.accent)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Workflow in progress")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(MuxyTheme.fg)
                    Text("Some steps still pending")
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

    private func dependencyViolationsSection(_ wf: WorkflowDef) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            sectionHeader("Dependency Violations")
            ForEach(wf.dependencyViolations, id: \.self) { violation in
                HStack(spacing: 6) {
                    Image(systemName: "link.broken")
                        .font(.system(size: 11))
                        .foregroundStyle(.red)
                    Text(violation)
                        .font(.system(size: 10))
                        .foregroundStyle(MuxyTheme.fgDim)
                }
                .padding(.vertical, 2)
            }
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
            stepIcon(step)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    severityBadge(step.severity)
                    Text(step.name)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(step.status == .skipped ? MuxyTheme.fgMuted : MuxyTheme.fg)
                }
                if let evidence = step.evidence {
                    Text(evidence)
                        .font(.system(size: 10))
                        .foregroundStyle(MuxyTheme.fgDim)
                        .lineLimit(3)
                }
            }
            Spacer(minLength: 0)
            Text(String(step.orderIndex + 1))
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(MuxyTheme.fgDim.opacity(0.5))
        }
        .padding(.vertical, 4)
        .opacity(step.status == .skipped ? 0.7 : 1)
    }

    @ViewBuilder
    private func severityBadge(_ severity: StepSeverity) -> some View {
        switch severity {
        case .critical:
            Image(systemName: "exclamationmark.octagon.fill")
                .font(.system(size: 9))
                .foregroundStyle(.red)
        case .warning:
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 9))
                .foregroundStyle(.orange)
        case .info:
            Color.clear.frame(width: 0, height: 0)
        }
    }

    private func stepIcon(_ step: PipelineStep) -> some View {
        switch step.status {
        case .followed:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 13))
                .foregroundStyle(.green)
        case .skipped:
            Image(systemName: step.severity == .critical ? "xmark.circle.fill" : "exclamationmark.circle.fill")
                .font(.system(size: 13))
                .foregroundStyle(step.severity == .critical ? .red : .orange)
        case .pending:
            Image(systemName: "circle")
                .font(.system(size: 13))
                .foregroundStyle(MuxyTheme.fgDim.opacity(0.5))
        }
    }

    private var historySection: some View {
        VStack(alignment: .leading, spacing: 4) {
            sectionHeader("Recent Runs")
            ForEach(state.history.prefix(5)) { record in
                HStack(spacing: 6) {
                    let passed = record.stepResults.allSatisfy { $0.status == "followed" }
                    Image(systemName: passed ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(passed ? .green : .orange)
                    Text(record.workflowName)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(MuxyTheme.fg)
                    Spacer(minLength: 0)
                    Text(timeAgo(record.date))
                        .font(.system(size: 9))
                        .foregroundStyle(MuxyTheme.fgDim)
                }
                .padding(.vertical, 2)
            }
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
        Date.timeAgo(since: date)
    }
}
