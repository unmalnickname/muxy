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
                    validationSection
                        .padding(.horizontal, 10)
                    if let output = state.validationOutput {
                        sectionSpacer
                        outputSection(output)
                            .padding(.horizontal, 10)
                    }
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
            Image(systemName: "arrow.triangle.branch")
                .font(.system(size: 13))
                .foregroundStyle(MuxyTheme.accent)
            Text("Pipeline")
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
            HStack(spacing: 8) {
                Image(systemName: "checkmark.shield.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(validationColor)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Workflow Validation")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(MuxyTheme.fgDim)
                    if let passed = state.validationPassed {
                        Text(passed ? "All checks passed" : "Issues detected")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(passed ? .green : .red)
                        if let detail = state.validationDetail {
                            Text(detail)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(MuxyTheme.fgDim)
                                .padding(.top, 2)
                        }
                        if let lastRun = state.lastRun {
                            Text(timeAgo(lastRun))
                                .font(.system(size: 10))
                                .foregroundStyle(MuxyTheme.fgDim)
                                .padding(.top, 2)
                        }
                    } else {
                        Text("Not yet validated")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(MuxyTheme.fgMuted)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, 4)
        }
    }

    private func outputSection(_ output: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            sectionHeader("Output")
            ScrollView([.horizontal, .vertical]) {
                Text(output)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(MuxyTheme.fgDim)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(height: 200)
            .background(MuxyTheme.bg.opacity(0.5))
            .cornerRadius(4)
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(MuxyTheme.border, lineWidth: 1))
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.system(size: 10, weight: .bold))
            .tracking(0.5)
            .foregroundStyle(MuxyTheme.fgDim)
            .padding(.bottom, 4)
    }

    private var validationColor: Color {
        guard let passed = state.validationPassed else { return MuxyTheme.fgDim }
        return passed ? .green : .red
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
