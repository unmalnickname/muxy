import MuxyShared
import SwiftUI

enum PulseSpeedOption: String, CaseIterable, Identifiable {
    case slow = "Slow"
    case normal = "Normal"
    case fast = "Fast"

    var id: String { rawValue }
}

enum IdleThresholdOption: String, CaseIterable, Identifiable {
    case oneMin = "1 min"
    case twoMin = "2 min"
    case fiveMin = "5 min"
    case tenMin = "10 min"
    case fifteenMin = "15 min"

    var id: String { rawValue }

    var minutes: Double {
        switch self {
        case .oneMin: 1
        case .twoMin: 2
        case .fiveMin: 5
        case .tenMin: 10
        case .fifteenMin: 15
        }
    }
}

enum AgentDurationOption: String, CaseIterable, Identifiable {
    case fiveSec = "5 sec"
    case tenSec = "10 sec"
    case fifteenSec = "15 sec"
    case thirtySec = "30 sec"

    var id: String { rawValue }

    var seconds: Double {
        switch self {
        case .fiveSec: 5
        case .tenSec: 10
        case .fifteenSec: 15
        case .thirtySec: 30
        }
    }
}

struct AttentionSettingsView: View {
    @AppStorage(AttentionSettingsKeys.idleDetectionEnabled) private var idleDetectionEnabled = true
    @AppStorage(AttentionSettingsKeys.idleThreshold) private var idleThresholdRaw = IdleThresholdOption.fiveMin.rawValue
    @AppStorage(AttentionSettingsKeys.pulseSpeed) private var pulseSpeedRaw = "normal"
    @AppStorage(AttentionSettingsKeys.agentDuration) private var agentDurationRaw = AgentDurationOption.tenSec.rawValue
    @AppStorage(AttentionSettingsKeys.idleColor) private var idleColorHex = AttentionSettingsKeys.defaultIdleColor
    @AppStorage(AttentionSettingsKeys.agentColor) private var agentColorHex = AttentionSettingsKeys.defaultAgentColor

    @State private var showIdleColorPicker = false
    @State private var showAgentColorPicker = false

    var body: some View {
        SettingsContainer {
            SettingsSection("Attention Pulse", footer: "Pulsing glow on the active project row when idle or agent completes.") {
                SettingsToggleRow(label: "Idle Detection", isOn: $idleDetectionEnabled)
                    .onChange(of: idleDetectionEnabled) { _, _ in
                        AttentionState.shared.reloadSettings()
                    }
            }

            SettingsSection("Timing") {
                SettingsPickerRow<IdleThresholdOption>(
                    label: "Idle Threshold",
                    selection: $idleThresholdRaw,
                    width: 120
                )
                .onChange(of: idleThresholdRaw) { _, _ in
                    AttentionState.shared.reloadSettings()
                }

                SettingsPickerRow<PulseSpeedOption>(
                    label: "Pulse Speed",
                    selection: $pulseSpeedRaw,
                    width: 120
                )
                .onChange(of: pulseSpeedRaw) { _, _ in
                    AttentionState.shared.reloadSettings()
                }

                SettingsPickerRow<AgentDurationOption>(
                    label: "Agent Glow Duration",
                    selection: $agentDurationRaw,
                    width: 120
                )
                .onChange(of: agentDurationRaw) { _, _ in
                    AttentionState.shared.reloadSettings()
                }
            }

            SettingsSection("Colors") {
                colorRow(label: "Idle Color", hex: $idleColorHex, showPicker: $showIdleColorPicker)

                colorRow(label: "Agent Color", hex: $agentColorHex, showPicker: $showAgentColorPicker)
            }
        }
        .onChange(of: idleColorHex) { _, _ in AttentionState.shared.reloadSettings() }
        .onChange(of: agentColorHex) { _, _ in AttentionState.shared.reloadSettings() }
    }

    private func colorRow(label: String, hex: Binding<String>, showPicker: Binding<Bool>) -> some View {
        SettingsRow(label) {
            HStack(spacing: 8) {
                Circle()
                    .fill(Color(hex: hex.wrappedValue) ?? .gray)
                    .frame(width: 16, height: 16)

                Button(hex.wrappedValue) {
                    showPicker.wrappedValue = true
                }
                .buttonStyle(.plain)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(MuxyTheme.fgMuted)
                .popover(isPresented: showPicker) {
                    AttentionColorPicker(selectedHex: hex.wrappedValue) { newHex in
                        hex.wrappedValue = newHex
                    }
                }
            }
        }
    }
}

private struct AttentionColorPicker: View {
    let selectedHex: String
    let onSelect: (String) -> Void

    private let columns = Array(repeating: GridItem(.fixed(24), spacing: 8), count: 6)

    private var allSwatches: [ProjectIconColor.Swatch] {
        let defaults: [ProjectIconColor.Swatch] = [
            .init(id: "orange", name: "Orange", hex: "#FF9500"),
            .init(id: "cyan", name: "Cyan", hex: "#00CCCC"),
        ]
        return defaults + ProjectIconColor.palette.filter { s in
            s.id != "orange" && s.id != "cyan" && s.id != "teal"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Pick a Color")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(MuxyTheme.fg)

            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(allSwatches) { swatch in
                    swatchButton(swatch)
                }
            }
        }
        .padding(12)
        .frame(width: 216)
    }

    private func swatchButton(_ swatch: ProjectIconColor.Swatch) -> some View {
        let isSelected = swatch.hex.caseInsensitiveCompare(selectedHex) == .orderedSame
        let color = Color(hex: swatch.hex) ?? .gray
        return Button {
            onSelect(swatch.hex)
        } label: {
            ZStack {
                Circle()
                    .fill(color)
                    .frame(width: 22, height: 22)
                if isSelected {
                    Circle()
                        .strokeBorder(.white, lineWidth: 2)
                        .frame(width: 18, height: 18)
                }
            }
            .frame(width: 24, height: 24)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(swatch.name)
    }
}
