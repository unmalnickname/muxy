import Foundation

enum ItemStatus: String, Codable {
    case installed
    case missing
    case needsAction
}

enum CIStatusType: String, Codable {
    case passed
    case failed
    case running
    case unknown
}

struct WorkflowItem: Identifiable {
    let id: String
    let name: String
    let relativePath: String
    let description: String
    var status: ItemStatus
    var action: String?
}

struct GlobalToolItem: Identifiable {
    let id: String
    let name: String
    var installed: Bool
    var version: String?
    var location: String?
    var installHint: String?
}

struct CIStatus {
    var branch: String
    var lastRunAgo: String?
    var status: CIStatusType
    var url: String?
}

struct PiExtensionEvent: Identifiable {
    let id = UUID()
    let timestamp: Date
    let event: String
    let result: String
}

@Observable
final class ProjectHealthState {
    var workflowItems: [WorkflowItem] = []
    var globalTools: [GlobalToolItem] = []
    var ciStatus: CIStatus?
    var piEvents: [PiExtensionEvent] = []
    var qualityScore: Int = 0
    var godFileCount: Int = 0
    var testCount: Int = 0
    var testPassed: Int = 0

    nonisolated(unsafe) private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()

    func refresh(projectPath: String) {
        refreshWorkflowConfigs(projectPath: projectPath)
        refreshGlobalTools()
        refreshCI(projectPath: projectPath)
        refreshPiHistory()
        refreshQuality(projectPath: projectPath)
    }

    private func refreshWorkflowConfigs(projectPath: String) {
        let fm = FileManager.default
        let checks: [(String, String, String, String?)] = [
            ("githooks", ".githooks", "Pre-commit lint + pre-push gate", nil),
            ("sentrux", ".sentrux", "Architectural quality gates", nil),
            ("archon", ".archon", "AI workflow definitions", nil),
            ("graphify", ".graphify", "Knowledge graph tracking", "graphify scan . --quiet"),
            ("gitleaks", ".gitleaks.toml", "Secret scanning", nil),
            ("doppler", ".doppler.yaml", "Secrets management", "doppler setup"),
        ]
        let clickablePaths: [String: String] = [
            ".githooks": ".githooks",
            ".sentrux": ".sentrux/rules.toml",
            ".archon": ".archon/config.yaml",
            ".graphify": ".graphify/config.yaml",
            ".gitleaks.toml": ".gitleaks.toml",
            ".doppler.yaml": ".doppler.yaml",
        ]
        workflowItems = checks.map { id, path, desc, action in
            let exists = fm.fileExists(atPath: (projectPath as NSString).appendingPathComponent(path))
            return WorkflowItem(
                id: id,
                name: path,
                relativePath: clickablePaths[path] ?? path,
                description: desc,
                status: exists ? .installed : .missing,
                action: action
            )
        }
    }

    private func refreshGlobalTools() {
        let tools: [(String, String, String?)] = [
            ("pi", "pi --version 2>&1", "npm install -g @mariozechner/pi-coding-agent"),
            ("sentrux", "sentrux --version 2>&1", "curl -fsSL https://raw.githubusercontent.com/sentrux/sentrux/main/install.sh | sh"),
            ("swiftlint", "swiftlint version 2>&1", "brew install swiftlint"),
            ("swiftformat", "swiftformat --version 2>&1", "brew install swiftformat"),
            ("gh", "gh --version 2>&1 | head -1", "brew install gh"),
        ]
        globalTools = tools.map { name, checkCmd, hint in
            let task = Process()
            task.launchPath = "/bin/bash"
            task.arguments = ["-c", checkCmd]
            let out = Pipe()
            task.standardOutput = out
            task.standardError = out
            do {
                try task.run()
                task.waitUntilExit()
                let data = out.fileHandleForReading.readDataToEndOfFile()
                let version = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
                let installed = task.terminationStatus == 0 && !(version?.isEmpty ?? true)
                let location = installed ? which(name) : nil
                return GlobalToolItem(
                    id: name,
                    name: name,
                    installed: installed,
                    version: version,
                    location: location,
                    installHint: installed ? nil : hint
                )
            } catch {
                return GlobalToolItem(id: name, name: name, installed: false, installHint: hint)
            }
        }
    }

    private func refreshCI(projectPath: String) {
        let task = Process()
        task.launchPath = "/bin/bash"
        task.arguments = ["-c", "cd '\(projectPath)' 2>/dev/null && gh run list --limit 1 --json conclusion,headBranch,createdAt,url 2>&1"]
        let out = Pipe()
        task.standardOutput = out
        task.standardError = out
        do {
            try task.run()
            task.waitUntilExit()
            let data = out.fileHandleForReading.readDataToEndOfFile()
            let text = String(data: data, encoding: .utf8) ?? ""
            if let json = try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? [[String: Any]],
               let first = json.first
            {
                let branch = first["headBranch"] as? String ?? "unknown"
                let conclusion = first["conclusion"] as? String ?? "unknown"
                let url = first["url"] as? String
                let createdAt = first["createdAt"] as? String ?? ""
                let ago = timeAgo(from: createdAt)
                let statusType: CIStatusType = switch conclusion {
                case "success": .passed
                case "failure": .failed
                case "cancelled": .unknown
                default: .running
                }
                ciStatus = CIStatus(branch: branch, lastRunAgo: ago, status: statusType, url: url)
            } else {
                ciStatus = CIStatus(branch: "—", lastRunAgo: nil, status: .unknown)
            }
        } catch {
            ciStatus = CIStatus(branch: "—", lastRunAgo: nil, status: .unknown)
        }
    }

    private func refreshPiHistory() {
        let logPath = NSString(string: "~/.pi/agent/agent-workflow.log").expandingTildeInPath
        guard let logData = try? String(contentsOfFile: logPath, encoding: .utf8) else {
            piEvents = []
            return
        }
        let lines = logData.components(separatedBy: .newlines).filter { !$0.isEmpty }
        piEvents = lines.compactMap { line in
            let parts = line.components(separatedBy: " — ")
            guard parts.count >= 2 else { return nil }
            let event = parts[0].trimmingCharacters(in: .whitespaces)
            let result = parts[1].trimmingCharacters(in: .whitespaces)
            return PiExtensionEvent(timestamp: Date(), event: event, result: result)
        }
    }

    private func refreshQuality(projectPath: String) {
        let baselinePath = (projectPath as NSString).appendingPathComponent(".sentrux/baseline.json")
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: baselinePath)),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            qualityScore = 0
            godFileCount = 0
            return
        }
        if let score = json["quality_signal"] as? Double {
            qualityScore = Int(score * 10000)
        }
        godFileCount = json["god_file_count"] as? Int ?? 0
    }

    private func which(_ tool: String) -> String? {
        let task = Process()
        task.launchPath = "/usr/bin/which"
        task.arguments = [tool]
        let out = Pipe()
        task.standardOutput = out
        try? task.run()
        task.waitUntilExit()
        let data = out.fileHandleForReading.readDataToEndOfFile()
        let path = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        return path?.isEmpty == false ? path : nil
    }

    private func timeAgo(from isoString: String) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let date = f.date(from: isoString) ?? ISO8601DateFormatter().date(from: isoString) else { return "" }
        let interval = -date.timeIntervalSinceNow
        switch interval {
        case ..<60: return "\(Int(interval))s ago"
        case ..<3600: return "\(Int(interval / 60))m ago"
        case ..<86400: return "\(Int(interval / 3600))h ago"
        default: return "\(Int(interval / 86400))d ago"
        }
    }
}
