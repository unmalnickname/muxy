import AppKit
import Foundation

@MainActor
final class IdleDetectionService {
    static let shared = IdleDetectionService()

    private var monitor: Any?
    private var timer: Timer?
    private var lastEventDate = Date()

    private init() {}

    func start() {
        let mask: NSEvent.EventTypeMask = [
            .keyDown, .leftMouseDown, .rightMouseDown,
            .otherMouseDown, .scrollWheel, .flagsChanged,
        ]
        monitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            self?.lastEventDate = Date()
            return event
        }

        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.checkIdle()
            }
        }
    }

    func stop() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
        timer?.invalidate()
        timer = nil
    }

    private var isEnabled: Bool {
        UserDefaults.standard.object(forKey: AttentionSettingsKeys.idleDetectionEnabled)
            .flatMap { $0 as? Bool }
            ?? AttentionSettingsKeys.defaultIdleDetectionEnabled
    }

    private var threshold: TimeInterval {
        UserDefaults.standard.attentionIdleThreshold()
    }

    private func checkIdle() {
        guard isEnabled else {
            AttentionState.shared.setIdle(false)
            return
        }

        let appIdle = Date().timeIntervalSince(lastEventDate)

        let systemIdle: TimeInterval = if let anyEvent = CGEventType(rawValue: UInt32.max) {
            CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: anyEvent)
        } else {
            appIdle
        }

        let isIdle = appIdle >= threshold && systemIdle >= threshold
        AttentionState.shared.setIdle(isIdle)
    }
}
