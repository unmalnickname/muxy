import Foundation

enum PipelineStepStatus: String, Codable {
    case waiting
    case running
    case passed
    case failed
    case skipped
}

enum PipelineOverallStatus: String, Codable {
    case idle
    case running
    case passed
    case failed
}

struct PipelineStep: Identifiable, Codable {
    let id: String
    let name: String
    var status: PipelineStepStatus
    var duration: TimeInterval?
}

struct PipelineRun: Identifiable, Codable {
    var id: String { "\(hookType)-\(startedAt ?? Date())" }
    var hookType: String
    var overallStatus: PipelineOverallStatus
    var steps: [PipelineStep]
    var startedAt: Date?
    var finishedAt: Date?
}

struct PipelineHistoryEntry: Codable, Identifiable {
    let id: String
    let hookType: String
    let result: String
    let timestamp: Date
    let stepCount: Int
    let passedCount: Int
    let duration: TimeInterval?
}

@Observable
final class PipelineState {
    var currentRun: PipelineRun?
    var history: [PipelineHistoryEntry] = []
    var isLive: Bool = false

    private let statusPath = ".muxy/hook-status.json"
    private let historyPath = ".muxy/pipeline-history.json"
    private var timer: Timer?

    func startPolling(projectPath: String) {
        stopPolling()
        refresh(projectPath: projectPath)
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.refresh(projectPath: projectPath)
        }
    }

    func stopPolling() {
        timer?.invalidate()
        timer = nil
    }

    func refresh(projectPath: String) {
        let fullPath = (projectPath as NSString).appendingPathComponent(statusPath)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: fullPath)),
              let run = try? decoder.decode(PipelineRun.self, from: data)
        else {
            currentRun = nil
            isLive = false
            return
        }
        currentRun = run
        isLive = run.overallStatus == .running

        // Read history
        let histPath = (projectPath as NSString).appendingPathComponent(historyPath)
        if let histData = try? Data(contentsOf: URL(fileURLWithPath: histPath)),
           let hist = try? decoder.decode([PipelineHistoryEntry].self, from: histData)
        {
            history = hist
        }
    }

    deinit {
        stopPolling()
    }
}
