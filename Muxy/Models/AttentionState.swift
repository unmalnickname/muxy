import SwiftUI

enum AttentionSettingsKeys {
    static let idleDetectionEnabled = "muxy.attention.idleDetectionEnabled"
    static let idleThreshold = "muxy.attention.idleThreshold"
    static let pulseSpeed = "muxy.attention.pulseSpeed"
    static let agentDuration = "muxy.attention.agentDuration"
    static let idleColor = "muxy.attention.idleColor"
    static let agentColor = "muxy.attention.agentColor"

    static let defaultIdleDetectionEnabled = true
    static let defaultIdleThreshold: TimeInterval = 300
    static let defaultPulseSpeed: TimeInterval = 2.0
    static let defaultAgentDuration: TimeInterval = 10
    static let defaultIdleColor = "#FF9500"
    static let defaultAgentColor = "#00CCCC"
}

extension UserDefaults {
    func attentionIdleThreshold() -> TimeInterval {
        guard let raw = string(forKey: AttentionSettingsKeys.idleThreshold),
              let minutes = Double(raw.split(separator: " ").first ?? "5")
        else { return AttentionSettingsKeys.defaultIdleThreshold }
        return minutes * 60
    }

    func attentionPulseSpeed() -> TimeInterval {
        let raw = string(forKey: AttentionSettingsKeys.pulseSpeed)
        switch raw {
        case "slow": return 4.0
        case "fast": return 1.0
        default: return AttentionSettingsKeys.defaultPulseSpeed
        }
    }

    func attentionIdleColor() -> Color {
        if let hex = string(forKey: AttentionSettingsKeys.idleColor),
           let color = Color(hex: hex)
        { return color }
        return Color(hex: AttentionSettingsKeys.defaultIdleColor) ?? .orange
    }

    func attentionAgentDuration() -> TimeInterval {
        guard let raw = string(forKey: AttentionSettingsKeys.agentDuration),
              let seconds = Double(raw.split(separator: " ").first ?? "10")
        else { return AttentionSettingsKeys.defaultAgentDuration }
        return seconds
    }

    func attentionAgentColor() -> Color {
        if let hex = string(forKey: AttentionSettingsKeys.agentColor),
           let color = Color(hex: hex)
        { return color }
        return Color(hex: AttentionSettingsKeys.defaultAgentColor) ?? .cyan
    }
}

@MainActor
@Observable
final class AttentionState {
    static let shared = AttentionState()

    private(set) var isIdle = false
    private(set) var agentCompletionDate: Date?
    private(set) var settingsVersion = 0

    private var agentDuration: TimeInterval {
        UserDefaults.standard.attentionAgentDuration()
    }

    var alertColor: Color? {
        _ = settingsVersion
        _ = agentDuration
        if let agentCompletionDate, Date().timeIntervalSince(agentCompletionDate) < agentDuration {
            return UserDefaults.standard.attentionAgentColor()
        }
        if isIdle {
            return UserDefaults.standard.attentionIdleColor()
        }
        return nil
    }

    var pulseDuration: TimeInterval {
        _ = settingsVersion
        return UserDefaults.standard.attentionPulseSpeed()
    }

    var hasAlert: Bool { alertColor != nil }

    func reloadSettings() {
        settingsVersion += 1
    }

    func setIdle(_ idle: Bool) {
        guard idle != isIdle else { return }
        isIdle = idle
    }

    func agentCompleted() {
        agentCompletionDate = Date()
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(agentDuration))
            guard let date = agentCompletionDate,
                  Date().timeIntervalSince(date) >= agentDuration
            else { return }
            agentCompletionDate = nil
        }
    }

    func resetForTesting() {
        isIdle = false
        agentCompletionDate = nil
        settingsVersion = 0
    }
}
