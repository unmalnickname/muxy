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
final class ProjectHealthState: @unchecked Sendable {
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
    var lastRefresh: Date?
    var isLoading = false

    private struct RefreshResult {
        let workflowItems: [WorkflowItem]
        let globalTools: [GlobalToolItem]
        let ciStatus: CIStatus?
        let piEvents: [PiExtensionEvent]
        let qualityScore: Int
        let godFileCount: Int
        let validationPassed: Bool?
        let validationDetail: String?
    }

    func refresh(projectPath: String, includeSlow: Bool = true) {
        lastRefresh = Date()
        isLoading = true
        let slow = includeSlow
        Task.detached { [weak self] in
            let result = Self.computeAll(projectPath: projectPath, includeSlow: slow)
            await MainActor.run {
                guard let self else { return }
                self.workflowItems = result.workflowItems
                self.globalTools = result.globalTools
                self.ciStatus = result.ciStatus
                self.piEvents = result.piEvents
                self.qualityScore = result.qualityScore
                self.godFileCount = result.godFileCount
                self.validationPassed = result.validationPassed
                self.validationDetail = result.validationDetail
                self.isLoading = false
            }
        }
    }

    func forceRefresh(projectPath: String) {
        refresh(projectPath: projectPath)
    }

    private static func computeAll(projectPath: String, includeSlow: Bool) -> RefreshResult {
        let workflowItems = refreshWorkflowConfigsStatic(projectPath: projectPath)
        let globalTools = includeSlow ? probeGlobalTools() : []
        let piEvents = includeSlow ? refreshPiHistoryStatic() : []
        let (qualityScore, godFileCount) = refreshQualityStatic(projectPath: projectPath)

        var ciStatus: CIStatus?
        var validationPassed: Bool?
        var validationDetail: String?

        if includeSlow {
            ciStatus = refreshCIStatic(projectPath: projectPath)
            let validation = runValidationStatic(projectPath: projectPath)
            validationPassed = validation.passed
            validationDetail = validation.detail
        }

        return RefreshResult(
            workflowItems: workflowItems,
            globalTools: globalTools,
            ciStatus: ciStatus,
            piEvents: piEvents,
            qualityScore: qualityScore,
            godFileCount: godFileCount,
            validationPassed: validationPassed,
            validationDetail: validationDetail
        )
    }

    private static func refreshWorkflowConfigsStatic(projectPath: String) -> [WorkflowItem] {
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
        return checks.map { check in
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

    private static func probeGlobalTools() -> [GlobalToolItem] {
        struct ToolDef {
            let name: String
            let checkArgs: [String]
            let hint: String?
        }
        let tools = [
            ToolDef(name: "swiftformat", checkArgs: ["--version"], hint: "brew install swiftformat"),
            ToolDef(name: "swiftlint", checkArgs: ["version"], hint: "brew install swiftlint"),
            ToolDef(name: "gitleaks", checkArgs: ["version"], hint: "brew install gitleaks"),
            ToolDef(
                name: "sentrux",
                checkArgs: ["--version"],
                hint: "curl -fsSL https://raw.githubusercontent.com/sentrux/sentrux/main/install.sh | sh"
            ),
            ToolDef(name: "graphify", checkArgs: ["--help"], hint: "pip install graphifyy"),
            ToolDef(name: "gh", checkArgs: ["--version"], hint: "brew install gh"),
        ]
        return tools.map { tool in
            let result = ShellRunner.runTool(tool.name, arguments: tool.checkArgs)
            return GlobalToolItem(
                id: tool.name,
                name: tool.name,
                installed: result.installed,
                version: result.version,
                location: result.installed ? GitProcessRunner.resolveExecutable(tool.name) : nil,
                installHint: result.installed ? nil : tool.hint
            )
        }
    }

    private static func refreshCIStatic(projectPath: String) -> CIStatus {
        let result = ShellRunner.run("gh run list --limit 1 --json conclusion,headBranch,createdAt,url 2>&1", workingDirectory: projectPath)
        let text = result.output
        if let json = try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? [[String: Any]],
           let first = json.first
        {
            let branch = first["headBranch"] as? String ?? "unknown"
            let conclusion = first["conclusion"] as? String ?? "unknown"
            let url = first["url"] as? String
            let createdAt = first["createdAt"] as? String ?? ""
            let ago = Date.timeAgo(fromISO: createdAt)
            let statusType: CIStatusType = switch conclusion {
            case "success": .passed
            case "failure": .failed
            case "cancelled": .unknown
            default: .running
            }
            return CIStatus(branch: branch, lastRunAgo: ago, status: statusType, url: url)
        }
        return CIStatus(branch: "—", lastRunAgo: nil, status: .unknown)
    }

    private static func refreshPiHistoryStatic() -> [PiExtensionEvent] {
        let logPath = NSString(string: "~/.pi/agent/agent-workflow.log").expandingTildeInPath
        guard let logData = try? String(contentsOfFile: logPath, encoding: .utf8) else {
            return []
        }
        let lines = logData.components(separatedBy: .newlines).filter { !$0.isEmpty }
        return lines.compactMap { line in
            let parts = line.components(separatedBy: " — ")
            guard parts.count >= 2 else { return nil }
            let event = parts[0].trimmingCharacters(in: .whitespaces)
            let result = parts[1].trimmingCharacters(in: .whitespaces)
            return PiExtensionEvent(timestamp: Date(), event: event, result: result)
        }
    }

    private static func refreshQualityStatic(projectPath: String) -> (qualityScore: Int, godFileCount: Int) {
        let baselinePath = (projectPath as NSString).appendingPathComponent(".sentrux/baseline.json")
        if let data = try? Data(contentsOf: URL(fileURLWithPath: baselinePath)),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        {
            let score = (json["quality_signal"] as? Double).map { Int($0 * 10000) } ?? 0
            let godFiles = json["god_file_count"] as? Int ?? 0
            return (score, godFiles)
        }
        return (0, 0)
    }

    private static func runValidationStatic(projectPath: String) -> (passed: Bool?, detail: String?) {
        let validateScript = Bundle.main.path(forResource: "validate-workflow", ofType: "sh", inDirectory: "Scripts")
            ?? (Bundle.main.bundlePath as NSString).appendingPathComponent("Contents/Resources/Scripts/validate-workflow.sh")
        guard FileManager.default.fileExists(atPath: validateScript) else {
            return (nil, "validate-workflow.sh not bundled")
        }

        let result = ShellRunner.run("'\(validateScript)' --ci 2>&1", workingDirectory: projectPath)
        let passed = result.exitCode == 0
        var detail: String?
        if let resultsLine = result.output.components(separatedBy: .newlines).last(where: { $0.contains("passed") }) {
            detail = resultsLine.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return (passed, detail)
    }
}
