import Foundation
import Testing

@testable import Muxy

@Suite("ProjectHealthState")
struct ProjectHealthStateTests {
    private let state = ProjectHealthState()

    // MARK: - timeAgo

    @Test("timeAgo returns empty string for unparseable input")
    func timeAgoUnparseable() {
        #expect(state.timeAgo(from: "") == "")
        #expect(state.timeAgo(from: "not-a-date") == "")
        #expect(state.timeAgo(from: "garbage") == "")
    }

    @Test("timeAgo returns just now for future dates")
    func timeAgoFutureDate() {
        let futureISO = "2029-01-01T00:00:00Z"
        #expect(state.timeAgo(from: futureISO) == "just now")
    }

    @Test("timeAgo formats seconds")
    func timeAgoSeconds() {
        let past = ISO8601DateFormatter().string(from: Date().addingTimeInterval(-15))
        let result = state.timeAgo(from: past)
        #expect(result.hasSuffix("s ago"))
    }

    @Test("timeAgo formats minutes")
    func timeAgoMinutes() {
        let past = ISO8601DateFormatter().string(from: Date().addingTimeInterval(-300))
        let result = state.timeAgo(from: past)
        #expect(result == "5m ago")
    }

    @Test("timeAgo formats hours")
    func timeAgoHours() {
        let past = ISO8601DateFormatter().string(from: Date().addingTimeInterval(-7200))
        let result = state.timeAgo(from: past)
        #expect(result == "2h ago")
    }

    @Test("timeAgo formats days")
    func timeAgoDays() {
        let past = ISO8601DateFormatter().string(from: Date().addingTimeInterval(-172800))
        let result = state.timeAgo(from: past)
        #expect(result == "2d ago")
    }

    @Test("timeAgo handles ISO date with fractional seconds")
    func timeAgoFractionalISO() {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let past = formatter.string(from: Date().addingTimeInterval(-120))
        let result = state.timeAgo(from: past)
        #expect(result == "2m ago")
    }

    // MARK: - parsePiTimestamp

    @Test("parsePiTimestamp extracts date from bracketed format")
    func parsePiTimestampBracketed() {
        let date = ProjectHealthState.parsePiTimestamp("[2026-01-15 10:30:00]")
        #expect(date != nil)
        if let date {
            let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
            #expect(components.year == 2026)
            #expect(components.month == 1)
            #expect(components.day == 15)
            #expect(components.hour == 10)
            #expect(components.minute == 30)
        }
    }

    @Test("parsePiTimestamp extracts date from plain format")
    func parsePiTimestampPlain() {
        let date = ProjectHealthState.parsePiTimestamp("2026-06-20 14:45:00")
        #expect(date != nil)
        if let date {
            let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
            #expect(components.year == 2026)
            #expect(components.month == 6)
            #expect(components.day == 20)
            #expect(components.hour == 14)
            #expect(components.minute == 45)
        }
    }

    @Test("parsePiTimestamp returns nil for non-date strings")
    func parsePiTimestampNonDate() {
        #expect(ProjectHealthState.parsePiTimestamp("event completed") == nil)
        #expect(ProjectHealthState.parsePiTimestamp("") == nil)
        #expect(ProjectHealthState.parsePiTimestamp("task finished") == nil)
    }

    @Test("parsePiTimestamp trims whitespace")
    func parsePiTimestampTrims() {
        let date = ProjectHealthState.parsePiTimestamp("  [2026-03-10 08:00:00]  ")
        #expect(date != nil)
    }

    // MARK: - refreshWorkflowConfigs (temp directory)

    @Test("refreshWorkflowConfigs detects installed files")
    func workflowConfigsDetectsInstalled() {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("muxy-test-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: tempDir.appendingPathComponent(".gitleaks.toml").path, contents: Data())

        state.refreshWorkflowConfigs(projectPath: tempDir.path)

        let gitleaks = state.workflowItems.first { $0.id == "gitleaks" }
        #expect(gitleaks != nil)
        #expect(gitleaks?.status == .installed)

        let githooks = state.workflowItems.first { $0.id == "githooks" }
        #expect(githooks != nil)
        #expect(githooks?.status == .missing)

        try? FileManager.default.removeItem(at: tempDir)
    }

    @Test("refreshWorkflowConfigs marks all missing when project empty")
    func workflowConfigsAllMissing() {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("muxy-test-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        state.refreshWorkflowConfigs(projectPath: tempDir.path)

        for item in state.workflowItems {
            #expect(item.status == .missing)
        }

        try? FileManager.default.removeItem(at: tempDir)
    }

    // MARK: - refreshQuality (baseline.json)

    @Test("refreshQuality returns zero when no baseline.json")
    func qualityNoBaseline() {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("muxy-test-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        state.refreshQuality(projectPath: tempDir.path)
        #expect(state.qualityScore == 0)
        #expect(state.godFileCount == 0)

        try? FileManager.default.removeItem(at: tempDir)
    }

    @Test("refreshQuality parses baseline.json correctly")
    func qualityWithBaseline() {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("muxy-test-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let baseline: [String: Any] = ["quality_signal": 0.85, "god_file_count": 3]
        let data = try! JSONSerialization.data(withJSONObject: baseline)
        let sentruxDir = tempDir.appendingPathComponent(".sentrux")
        try? FileManager.default.createDirectory(at: sentruxDir, withIntermediateDirectories: true)
        try? data.write(to: sentruxDir.appendingPathComponent("baseline.json"))

        state.refreshQuality(projectPath: tempDir.path)
        #expect(state.qualityScore == 8500)
        #expect(state.godFileCount == 3)

        try? FileManager.default.removeItem(at: tempDir)
    }

    // MARK: - refreshPiHistory (parsePiTimestamp covers parsing; file tests are
    // handled by parsePiTimestamp tests to avoid real filesystem conflicts)

    @Test("refreshPiHistory returns empty when log missing")
    func piHistoryNoLog() {
        state.refreshPiHistory()
        #expect(state.piEvents.isEmpty)
    }

    @Test("refreshPiHistory resets events on each call")
    func piHistoryResets() {
        state.refreshPiHistory()
        let firstCount = state.piEvents.count
        state.refreshPiHistory()
        #expect(state.piEvents.count == firstCount)
    }
}
