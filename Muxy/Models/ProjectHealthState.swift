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
    var validationPassed: Bool?
    var validationDetail: String?

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
        runValidation(projectPath: projectPath)
    }

    private func runValidation(projectPath: String) {
        let task = Process()
        task.launchPath = "/bin/bash"
        task.arguments = ["-c", "cd '\(projectPath)' 2>/dev/null && scripts/validate-workflow.sh --ci 2>&1"]
        let out = Pipe()
        task.standardOutput = out
        task.standardError = out
        do {
            try task.run()
            task.waitUntilExit()
            let data = out.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""
            validationPassed = task.terminationStatus == 0
            if let resultsLine = output.components(separatedBy: .newlines).last(where: { $0.contains("passed") }) {
                validationDetail = resultsLine.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        } catch {
            validationPassed = nil
            validationDetail = nil
        }
    }

    private func refreshWorkflowConfigs(projectPath: String) {
        let fm = FileManager.default
        struct CheckDef {
            let id: String
            let path: String
            let desc: String
            let action: String?
        }
        let checks = [
            CheckDef(id: "checks", path: "scripts/checks.sh", desc: "Format, lint, build, test pipeline", action: nil),
            CheckDef(
                id: "validate",
                path: "scripts/validate-workflow.sh",
                desc: "Workflow tooling self-validation",
                action: "scripts/validate-workflow.sh --ci"
            ),
            CheckDef(id: "githooks", path: ".githooks", desc: "Pre-commit lint + pre-push gate", action: nil),
            CheckDef(id: "sentrux", path: ".sentrux", desc: "Architectural quality gates", action: nil),
            CheckDef(id: "archon", path: ".archon", desc: "AI workflow definitions", action: nil),
            CheckDef(id: "graphify", path: ".graphify", desc: "Knowledge graph tracking", action: "graphify update ."),
            CheckDef(id: "gitleaks", path: ".gitleaks.toml", desc: "Secret scanning", action: nil),
            CheckDef(id: "doppler", path: ".doppler.yaml", desc: "Secrets management", action: "doppler setup"),
        ]
        let clickablePaths: [String: String] = [
            "scripts/checks.sh": "scripts/checks.sh",
            "scripts/validate-workflow.sh": "scripts/validate-workflow.sh",
            ".githooks": ".githooks",
            ".sentrux": ".sentrux/rules.toml",
            ".archon": ".archon/config.yaml",
            ".graphify": ".graphify/config.yaml",
            ".gitleaks.toml": ".gitleaks.toml",
            ".doppler.yaml": ".doppler.yaml",
        ]
        workflowItems = checks.map { check in
            let exists = fm.fileExists(atPath: (projectPath as NSString).appendingPathComponent(check.path))
            return WorkflowItem(
                id: check.id,
                name: check.path,
                relativePath: clickablePaths[check.path] ?? check.path,
                description: check.desc,
                status: exists ? .installed : .missing,
                action: check.action
            )
        }
    }

    private func refreshGlobalTools() {
        struct ToolDef {
            let name: String
            let checkCmd: String
            let hint: String?
        }
        let tools = [
            ToolDef(name: "swiftformat", checkCmd: "swiftformat --version 2>&1", hint: "brew install swiftformat"),
            ToolDef(name: "swiftlint", checkCmd: "swiftlint version 2>&1", hint: "brew install swiftlint"),
            ToolDef(name: "gitleaks", checkCmd: "gitleaks version 2>&1", hint: "brew install gitleaks"),
            ToolDef(
                name: "sentrux",
                checkCmd: "sentrux --version 2>&1",
                hint: "curl -fsSL https://raw.githubusercontent.com/sentrux/sentrux/main/install.sh | sh"
            ),
            ToolDef(name: "graphify", checkCmd: "graphify --help 2>&1 | head -1", hint: "pip install graphifyy"),
            ToolDef(name: "gh", checkCmd: "gh --version 2>&1 | head -1", hint: "brew install gh"),
        ]
        globalTools = tools.map { tool in
            let task = Process()
            task.launchPath = "/bin/bash"
            task.arguments = ["-c", tool.checkCmd]
            let out = Pipe()
            task.standardOutput = out
            task.standardError = out
            do {
                try task.run()
                task.waitUntilExit()
                let data = out.fileHandleForReading.readDataToEndOfFile()
                let version = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
                let installed = task.terminationStatus == 0 && !(version?.isEmpty ?? true)
                let location = installed ? which(tool.name) : nil
                return GlobalToolItem(
                    id: tool.name,
                    name: tool.name,
                    installed: installed,
                    version: version,
                    location: location,
                    installHint: installed ? nil : tool.hint
                )
            } catch {
                return GlobalToolItem(id: tool.name, name: tool.name, installed: false, installHint: tool.hint)
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
        if let data = try? Data(contentsOf: URL(fileURLWithPath: baselinePath)),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        {
            if let score = json["quality_signal"] as? Double {
                qualityScore = Int(score * 10000)
            }
            godFileCount = json["god_file_count"] as? Int ?? 0
        }
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
