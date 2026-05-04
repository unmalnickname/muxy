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
                    currentRunSection.padding(.horizontal, 10)
                    if state.history.isEmpty {
                        sectionSpacer
                        idleSection.padding(.horizontal, 10)
                    }
                    if !state.history.isEmpty {
                        sectionSpacer
                        historySection.padding(.horizontal, 10)
                    }
                    Color.clear.frame(height: 12)
                }
            }
        }
        .background(MuxyTheme.bg)
        .onAppear { state.startPolling(projectPath: projectPath) }
        .onDisappear { state.stopPolling() }
    }

    private var sectionSpacer: some View {
        Rectangle()
            .fill(MuxyTheme.border)
            .frame(height: 1)
            .padding(.vertical, 8)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "point.3.connected.trianglepath.dotted")
                .font(.system(size: 13))
                .foregroundStyle(state.isLive ? .green : MuxyTheme.accent)
            Text("Pipeline")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(MuxyTheme.fg)
            if state.isLive {
                Circle()
                    .fill(.green)
                    .frame(width: 6, height: 6)
            }
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

    private var currentRunSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader(state.isLive ? "Running" : "Last Run")
            if let run = state.currentRun {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        statusIcon(run.overallStatus)
                        Text(run.hookType)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(MuxyTheme.fg)
                        if let started = run.startedAt {
                            Text(timeAgo(from: started))
                                .font(.system(size: 9))
                                .foregroundStyle(MuxyTheme.fgDim)
                        }
                    }
                    .padding(.bottom, 4)
                    ForEach(run.steps) { step in
                        HStack(spacing: 8) {
                            stepIcon(step.status)
                            Text(step.name)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(step.status == .failed ? .red : MuxyTheme.fg)
                            Spacer(minLength: 0)
                            if let dur = step.duration {
                                Text(String(format: "%.1fs", dur))
                                    .font(.system(size: 9, design: .monospaced))
                                    .foregroundStyle(MuxyTheme.fgDim)
                            } else if step.status == .running {
                                ProgressView()
                                    .controlSize(.small)
                                    .scaleEffect(0.6)
                            } else if step.status == .waiting {
                                Text("waiting")
                                    .font(.system(size: 9))
                                    .foregroundStyle(MuxyTheme.fgDim)
                            }
                        }
                        .padding(.vertical, 3)
                        .padding(.leading, 4)
                    }
                }
                .padding(.vertical, 4)
                .padding(8)
                .background(run.overallStatus == .failed ? MuxyTheme.bg.opacity(0.5) : Color.clear)
                .cornerRadius(6)
            }
        }
    }

    private var idleSection: some View {
        VStack(alignment: .center, spacing: 6) {
            Color.clear.frame(height: 8)
            Image(systemName: "point.3.connected.trianglepath.dotted")
                .font(.system(size: 24))
                .foregroundStyle(MuxyTheme.fgDim.opacity(0.4))
            Text("No pipeline activity yet")
                .font(.system(size: 11))
                .foregroundStyle(MuxyTheme.fgDim)
            Text("Run git commit or git push to see hooks execute")
                .font(.system(size: 9))
                .foregroundStyle(MuxyTheme.fgDim.opacity(0.6))
                .multilineTextAlignment(.center)
            Color.clear.frame(height: 8)
        }
        .frame(maxWidth: .infinity)
    }

    private var historySection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader("History")
            ForEach(state.history.prefix(10)) { entry in
                HStack(spacing: 8) {
                    Image(systemName: entry.result == "passed" ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(entry.result == "passed" ? .green : .red)
                    Text(entry.hookType)
                        .font(.system(size: 11))
                        .foregroundStyle(MuxyTheme.fg)
                    Text("\(entry.passedCount)/\(entry.stepCount)")
                        .font(.system(size: 9))
                        .foregroundStyle(MuxyTheme.fgDim)
                    if let dur = entry.duration {
                        Text(String(format: "%.1fs", dur))
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(MuxyTheme.fgDim)
                    }
                    Spacer(minLength: 0)
                    Text(timeAgo(from: entry.timestamp))
                        .font(.system(size: 9))
                        .foregroundStyle(MuxyTheme.fgDim)
                }
                .padding(.vertical, 3)
            }
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
    private func statusIcon(_ status: PipelineOverallStatus) -> some View {
        switch status {
        case .idle:
            Image(systemName: "circle.dotted")
                .font(.system(size: 13))
                .foregroundStyle(MuxyTheme.fgDim)
        case .running:
            ProgressView()
                .controlSize(.small)
                .scaleEffect(0.7)
        case .passed:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 13))
                .foregroundStyle(.green)
        case .failed:
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 13))
                .foregroundStyle(.red)
        }
    }

    @ViewBuilder
    private func stepIcon(_ status: PipelineStepStatus) -> some View {
        switch status {
        case .waiting:
            Image(systemName: "circle")
                .font(.system(size: 9))
                .foregroundStyle(MuxyTheme.fgDim.opacity(0.4))
        case .running:
            ProgressView()
                .controlSize(.small)
                .scaleEffect(0.5)
        case .passed:
            Image(systemName: "checkmark")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.green)
        case .failed:
            Image(systemName: "xmark")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.red)
        case .skipped:
            Image(systemName: "minus")
                .font(.system(size: 9))
                .foregroundStyle(MuxyTheme.fgDim)
        }
    }

    private func timeAgo(from date: Date) -> String {
        let interval = -date.timeIntervalSinceNow
        guard interval > 0 else { return "just now" }
        switch interval {
        case ..<60: return "\(Int(interval))s ago"
        case ..<3600: return "\(Int(interval / 60))m ago"
        case ..<86400: return "\(Int(interval / 3600))h ago"
        default: return "\(Int(interval / 86400))d ago"
        }
    }
}
