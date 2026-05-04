import Foundation

enum ItemStatus: String, Codable {
    case active
    case partial
    case missing
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
    var detail: String?
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

struct AgentProfile: Identifiable, Equatable {
    let id: String
    let name: String
    let role: String
    let strengths: [String]
    let weaknesses: [String]
    let bestFor: String
    let skillPath: String?
}

struct InsightItem: Identifiable {
    let id: String
    let label: String
    let value: String
    var status: ItemStatus
    var agentProfile: AgentProfile?
}

let agentProfiles: [String: AgentProfile] = [
    "opencode": AgentProfile(
        id: "opencode",
        name: "OpenCode",
        role: "Primary builder — full feature dev, complex refactors, workflow architecture",
        strengths: [
            "Full feature development",
            "Complex refactoring",
            "Workflow architecture",
            "Multi-agent coordination",
            "System-level debugging",
        ],
        weaknesses: ["Can be verbose", "Heavy context usage"],
        bestFor: "New features, complex refactors, workflow setup, pipeline design",
        skillPath: "~/.claude/skills/opencode/SKILL.md"
    ),
    "claude-code": AgentProfile(
        id: "claude-code",
        name: "Claude Code",
        role: "Quick fixes, prototyping, documentation",
        strengths: ["Fast iteration", "Quick bug fixes", "Documentation", "Prototyping"],
        weaknesses: ["Less context-aware on large codebases"],
        bestFor: "Quick fixes, docs, prototyping, simple changes",
        skillPath: nil
    ),
    "hermes": AgentProfile(
        id: "hermes",
        name: "Hermes",
        role: "Exploratory coding, new patterns",
        strengths: ["Exploring new patterns", "Creative solutions", "Rapid prototyping"],
        weaknesses: ["May not follow existing conventions"],
        bestFor: "Prototypes, POCs, exploring new approaches",
        skillPath: nil
    ),
    "pi": AgentProfile(
        id: "pi",
        name: "Pi",
        role: "Multi-backend, rapid iteration, dependencies",
        strengths: ["Multi-backend work", "Dependency management", "Tooling", "Rapid iteration"],
        weaknesses: ["Less structured output"],
        bestFor: "Dependencies, tooling, multi-backend, chore tasks",
        skillPath: nil
    ),
]

struct TaskContextData: Codable {
    var taskType: String
    var taskDescription: String
    var recommendedSkills: [String]
    var lastUpdated: Date?
}

struct LastSessionData: Codable {
    var agent: String?
    var taskType: String?
    var taskDescription: String?
    var loadedSkills: [String]
    var status: String?
    var timestamp: Date?
}

struct ContextSuggestion: Identifiable, Equatable {
    let id: String
    let skillName: String
    let reason: String
    var severity: SuggestionSeverity
}

enum SuggestionSeverity: String, Codable {
    case missing
    case partial
    case optional
}

let taskTypeSkills: [String: [String]] = [
    "feature": ["agent-workflow", "opencode", "nova-command"],
    "fix": ["agent-workflow", "opencode"],
    "refactor": ["opencode", "agent-workflow"],
    "ui": ["atomic-ui-library", "opencode", "agent-workflow"],
    "docs": ["agent-workflow"],
    "chore": ["agent-workflow"],
    "hotfix": ["agent-workflow", "opencode"],
    "test": ["agent-workflow"],
]

let taskTypeLabels: [String: String] = [
    "feature": "Feature Development",
    "fix": "Bug Fix",
    "refactor": "Refactoring",
    "ui": "UI / Design",
    "docs": "Documentation",
    "chore": "Maintenance / Tooling",
    "hotfix": "Emergency Production Fix",
    "test": "Testing",
    "unknown": "Unknown Task",
]

@Observable
final class ProjectHealthState {
    var workflowItems: [WorkflowItem] = []
    var globalTools: [GlobalToolItem] = []
    var ciStatus: CIStatus?
    var piEvents: [PiExtensionEvent] = []
    var qualityScore: Int = 0
    var godFileCount: Int = 0
    var insights: [InsightItem] = []
    var selectedAgent: String?
    var currentTaskType: String = "unknown"
    var taskDescription: String = ""
    var contextSuggestions: [ContextSuggestion] = []
    var availableSkills: [String] = []
    var lastSession: LastSessionData?
    var testCount: Int = 0
    var testPassed: Int = 0

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()

    nonisolated(unsafe) private static let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    nonisolated(unsafe) private static let isoFormatterSimple: ISO8601DateFormatter = .init()

    private static let logDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    private static let maxPiLogSize = 1_048_576

    func refresh(projectPath: String) {
        refreshWorkflowConfigs(projectPath: projectPath)
        refreshGlobalTools()
        refreshCI(projectPath: projectPath)
        refreshPiHistory()
        refreshQuality(projectPath: projectPath)
        refreshStackDetection(projectPath: projectPath)
        refreshBranchConvention(projectPath: projectPath)
        refreshTaskContext(projectPath: projectPath)
    }

    func selectAgent(_ name: String, projectPath: String) {
        selectedAgent = name
        let dir = (projectPath as NSString).appendingPathComponent(".muxy")
        try? FileManager.default.createDirectory(at: URL(fileURLWithPath: dir), withIntermediateDirectories: true)
        try? "\(name)\n".write(toFile: (dir as NSString).appendingPathComponent("agent-preference"), atomically: true, encoding: .utf8)
        // Refresh gap detection with new agent
        contextSuggestions = detectContextGaps(taskType: currentTaskType, available: availableSkills)
    }

    func clearAgent(projectPath: String) {
        selectedAgent = nil
        let path = (projectPath as NSString).appendingPathComponent(".muxy/agent-preference")
        try? FileManager.default.removeItem(atPath: path)
    }

    // MARK: - Workflow Configs (Deep Validation)

    func refreshWorkflowConfigs(projectPath: String) {
        let fm = FileManager.default
        struct CheckDef {
            let id: String
            let path: String
            let desc: String
            let action: String?
        }
        let checks = [
            CheckDef(id: "githooks", path: ".githooks", desc: "Pre-commit lint + pre-push gate", action: nil),
            CheckDef(id: "sentrux", path: ".sentrux", desc: "Architectural quality gates", action: nil),
            CheckDef(id: "archon", path: ".archon", desc: "AI workflow definitions", action: nil),
            CheckDef(id: "graphify", path: ".graphify", desc: "Knowledge graph tracking", action: nil),
            CheckDef(id: "gitleaks", path: ".gitleaks.toml", desc: "Secret scanning", action: nil),
            CheckDef(id: "doppler", path: ".doppler.yaml", desc: "Secrets management", action: "doppler setup"),
        ]
        let clickablePaths: [String: String] = [
            ".githooks": ".githooks",
            ".sentrux": ".sentrux/rules.toml",
            ".archon": ".archon/config.yaml",
            ".graphify": ".graphify/config.yaml",
            ".gitleaks.toml": ".gitleaks.toml",
            ".doppler.yaml": ".doppler.yaml",
        ]
        workflowItems = checks.map { check in
            let fullPath = (projectPath as NSString).appendingPathComponent(check.path)
            let exists = fm.fileExists(atPath: fullPath)
            let (status, detail) = deepValidate(check.id, projectPath: projectPath, exists: exists)
            return WorkflowItem(
                id: check.id,
                name: check.path,
                relativePath: clickablePaths[check.path] ?? check.path,
                description: check.desc,
                status: status,
                detail: detail,
                action: check.action
            )
        }
    }

    private func deepValidate(_ id: String, projectPath: String, exists: Bool) -> (ItemStatus, String?) {
        guard exists else { return (.missing, nil) }

        switch id {
        case "githooks":
            return validateHooks(projectPath)
        case "sentrux":
            return validateSentrux(projectPath)
        case "archon":
            return validateArchon(projectPath)
        case "graphify":
            return validateGraphify(projectPath)
        default:
            return (.active, nil)
        }
    }

    private func validateHooks(_ projectPath: String) -> (ItemStatus, String?) {
        let fm = FileManager.default
        let hooksDir = (projectPath as NSString).appendingPathComponent(".githooks")

        // Check hooksPath is configured
        let hooksPath = runGit(["config", "core.hooksPath"], projectPath: projectPath)
        guard hooksPath == ".githooks" else {
            return (.partial, "Not active — run: git config core.hooksPath .githooks")
        }

        // Check pre-commit has exit 1 (hardened)
        let preCommitPath = (hooksDir as NSString).appendingPathComponent("pre-commit")
        guard fm.fileExists(atPath: preCommitPath),
              let content = try? String(contentsOfFile: preCommitPath, encoding: .utf8)
        else {
            return (.partial, "pre-commit hook missing")
        }

        if content.contains("exit 1"), !content.contains("|| true") {
            return (.active, "Active and hardened")
        } else if content.contains("|| true") {
            return (.partial, "Checks use '|| true' — may pass silently")
        } else {
            return (.partial, "No verification found in pre-commit")
        }
    }

    private func validateSentrux(_ projectPath: String) -> (ItemStatus, String?) {
        let fm = FileManager.default
        let rulesPath = (projectPath as NSString).appendingPathComponent(".sentrux/rules.toml")
        guard let rulesContent = try? String(contentsOfFile: rulesPath, encoding: .utf8) else {
            return (.partial, "rules.toml missing")
        }

        // Extract layer paths
        let lines = rulesContent.components(separatedBy: .newlines)
        let pathLines = lines.filter { $0.hasPrefix("paths") }

        // Check if paths reference real project dirs
        let projectDirs = scanTopDirs(projectPath).map { $0.lowercased() }
        let matchesReal = pathLines.contains { line in
            projectDirs.contains { dir in
                line.lowercased().contains(dir)
            }
        }

        // Check baseline age
        let baselinePath = (projectPath as NSString).appendingPathComponent(".sentrux/baseline.json")
        var baselineAge: String?
        if let attrs = try? fm.attributesOfItem(atPath: baselinePath),
           let modDate = attrs[.modificationDate] as? Date
        {
            let age = -modDate.timeIntervalSinceNow
            if age > 7 * 86400 {
                baselineAge = "Baseline \(Int(age / 86400))d old — run: sentrux gate --save ."
            }
        }

        if !matchesReal {
            return (.partial, "Layer paths don't match project structure")
        }
        if let age = baselineAge {
            return (.partial, age)
        }
        return (.active, "Paths match project, baseline fresh")
    }

    private func validateArchon(_ projectPath: String) -> (ItemStatus, String?) {
        let mcpDir = (projectPath as NSString).appendingPathComponent("mcp-servers")
        let files = ["graphify-mcp.py", "archon-mcp.py", "start-mcp.sh"]
        let fm = FileManager.default
        let missing = files.filter { !fm.fileExists(atPath: (mcpDir as NSString).appendingPathComponent($0)) }
        if missing.isEmpty {
            return (.active, "All MCP servers present")
        }
        return (.partial, "Missing: \(missing.joined(separator: ", "))")
    }

    private func validateGraphify(_ projectPath: String) -> (ItemStatus, String?) {
        let configPath = (projectPath as NSString).appendingPathComponent(".graphify/config.yaml")
        guard let configContent = try? String(contentsOfFile: configPath, encoding: .utf8) else {
            return (.partial, "Config missing")
        }

        // Check if config covers project's source extension
        let hasSwift = configContent.contains("*.swift")
        let hasTS = configContent.contains("*.ts")
        let hasDart = configContent.contains("*.dart")
        let hasRS = configContent.contains("*.rs")
        let hasPy = configContent.contains("*.py")

        if hasSwift || hasTS || hasDart || hasRS || hasPy {
            return (.active, "Covers project source files")
        }
        return (.partial, "May not cover this project's source files")
    }

    // MARK: - Stack Detection

    func refreshStackDetection(projectPath: String) {
        var results: [InsightItem] = []

        // Detect stack
        let fm = FileManager.default
        let hasXcode = fm.fileExists(atPath: (projectPath as NSString).appendingPathComponent("Package.swift"))
        let hasXcodeproj = ls(projectPath, "*.xcodeproj") || ls(projectPath, "*.xcworkspace")
        let hasCargo = fm.fileExists(atPath: (projectPath as NSString).appendingPathComponent("Cargo.toml"))
        let hasNode = fm.fileExists(atPath: (projectPath as NSString).appendingPathComponent("package.json"))
        let hasFlutter = fm.fileExists(atPath: (projectPath as NSString).appendingPathComponent("pubspec.yaml"))
        let hasPython = fm.fileExists(atPath: (projectPath as NSString).appendingPathComponent("pyproject.toml"))

        let stackLabel = if hasXcodeproj || hasXcode {
            "Swift / macOS App"
        } else if hasCargo { "Rust"
        } else if hasNode { "Node / TypeScript"
        } else if hasFlutter { "Flutter / Dart"
        } else if hasPython { "Python"
        } else { "Unknown" }

        results.append(InsightItem(id: "stack", label: "Stack", value: stackLabel, status: .active))

        // Recommended agent based on stack
        let recommendedAgent = switch stackLabel {
        case "Swift / macOS App": "opencode"
        case "Rust": "opencode"
        case "Node / TypeScript": "opencode"
        case "Flutter / Dart": "claude-code"
        case "Python": "pi"
        default: "opencode"
        }
        let profile = agentProfiles[recommendedAgent]
        results.append(InsightItem(
            id: "agent", label: "Recommended Agent",
            value: "\(recommendedAgent) (\(stackLabel))",
            status: .active, agentProfile: profile
        ))

        // User-selected agent from .muxy/agent-preference
        let prefPath = (projectPath as NSString).appendingPathComponent(".muxy/agent-preference")
        if let prefData = try? String(contentsOfFile: prefPath, encoding: .utf8),
           let chosen = prefData.trimmingCharacters(in: .whitespacesAndNewlines).components(separatedBy: .newlines).first,
           !chosen.isEmpty
        {
            selectedAgent = chosen
            let chosenProfile = agentProfiles[chosen]
            let matches = chosen == recommendedAgent
            results.append(InsightItem(
                id: "selected-agent", label: "Selected Agent",
                value: chosen,
                status: matches ? .active : .partial,
                agentProfile: chosenProfile
            ))
        } else {
            selectedAgent = nil
        }

        // Current agent from branch
        let branch = runGit(["branch", "--show-current"], projectPath: projectPath)
        if !branch.isEmpty, branch != "main", branch != "master" {
            if let match = branch.firstMatch(of: #/^[^/]+/([^/]+)/#) {
                let currentAgent = String(match.1)
                let sameAgent = currentAgent.lowercased() == recommendedAgent.lowercased()
                results.append(InsightItem(
                    id: "current-agent",
                    label: "Current Agent",
                    value: "\(currentAgent) on \(branch)",
                    status: sameAgent ? .active : .partial
                ))
            }
        }

        // Check Sentrux layers vs project dirs
        let rulesPath = (projectPath as NSString).appendingPathComponent(".sentrux/rules.toml")
        if let rulesContent = try? String(contentsOfFile: rulesPath, encoding: .utf8) {
            let pathLines = rulesContent.components(separatedBy: .newlines).filter { $0.hasPrefix("paths") }
            let dirNames = pathLines.compactMap { line -> String? in
                guard let start = line.range(of: "\""),
                      let end = line[start.upperBound...].range(of: "\"")
                else { return nil }
                return String(line[start.upperBound ..< end.lowerBound])
            }
            let value = dirNames.isEmpty ? "No layers defined" : dirNames.prefix(4).joined(separator: ", ")
            results.append(InsightItem(id: "layers", label: "Sentrux Layers", value: value, status: dirNames.isEmpty ? .partial : .active))
        }

        // Check hooks hardening
        let preCommitPath = (projectPath as NSString).appendingPathComponent(".githooks/pre-commit")
        let hooksActive = runGit(["config", "core.hooksPath"], projectPath: projectPath) == ".githooks"
        if hooksActive, let content = try? String(contentsOfFile: preCommitPath, encoding: .utf8) {
            let hardened = content.contains("exit 1")
            let status: ItemStatus = hardened ? .active : .partial
            results.append(InsightItem(
                id: "hooks",
                label: "Hooks",
                value: hardened ? "Hardened (exit 1)" : "Permissive (|| true)",
                status: status
            ))
        }

        insights = results
    }

    // MARK: - Branch Convention

    func refreshBranchConvention(projectPath: String) {
        let branch = runGit(["branch", "--show-current"], projectPath: projectPath)
        guard !branch.isEmpty else { return }

        let item = if branch == "main" || branch == "master" {
            WorkflowItem(
                id: "branch",
                name: "Branch: \(branch)",
                relativePath: "",
                description: "Current git branch",
                status: .partial,
                detail: "On \(branch) — create feature branches: feature/opencode/desc"
            )
        } else if branch == "develop" {
            WorkflowItem(
                id: "branch",
                name: "Branch: \(branch)",
                relativePath: "",
                description: "Current git branch",
                status: .partial,
                detail: "On develop — create feature branches"
            )
        } else if branch.range(of: #"^(feature|fix|refactor|chore|docs|test|hotfix)/[a-z0-9._-]+/.+"#, options: .regularExpression) != nil {
            WorkflowItem(
                id: "branch",
                name: "Branch: \(branch)",
                relativePath: "",
                description: "Current git branch",
                status: .active,
                detail: "Following branch convention"
            )
        } else {
            WorkflowItem(
                id: "branch",
                name: "Branch: \(branch)",
                relativePath: "",
                description: "Current git branch",
                status: .partial,
                detail: "Doesn't follow {type}/{agent}/{desc} pattern"
            )
        }
        // Insert before other workflow items
        workflowItems.insert(item, at: 0)
    }

    // MARK: - Task Context

    func refreshTaskContext(projectPath: String) {
        let muxyDir = (projectPath as NSString).appendingPathComponent(".muxy")

        // Read task context
        let contextPath = (muxyDir as NSString).appendingPathComponent("task-context.json")
        if let data = try? Data(contentsOf: URL(fileURLWithPath: contextPath)),
           let ctx = try? JSONDecoder().decode(TaskContextData.self, from: data)
        {
            currentTaskType = ctx.taskType
            taskDescription = ctx.taskDescription
        } else {
            // Auto-detect from branch
            let branch = runGit(["branch", "--show-current"], projectPath: projectPath)
            currentTaskType = detectTaskType(from: branch)
            taskDescription = ""
        }

        // Read last session
        let sessionPath = (muxyDir as NSString).appendingPathComponent("last-session.json")
        if let data = try? Data(contentsOf: URL(fileURLWithPath: sessionPath)),
           let session = try? JSONDecoder().decode(LastSessionData.self, from: data)
        {
            lastSession = session
        } else {
            lastSession = nil
        }

        // Scan available skills
        availableSkills = scanAvailableSkills()

        // Detect gaps
        contextSuggestions = detectContextGaps(taskType: currentTaskType, available: availableSkills)
    }

    func detectTaskType(from branch: String) -> String {
        if branch.isEmpty || branch == "main" || branch == "master" || branch == "develop" {
            return "unknown"
        }
        // Extract type from feature/opencode/desc
        let parts = branch.components(separatedBy: "/")
        let validTypes = ["feature", "fix", "refactor", "chore", "docs", "hotfix", "test"]
        if let first = parts.first, validTypes.contains(first) {
            return first
        }
        return "unknown"
    }

    func scanAvailableSkills() -> [String] {
        let skillsPath = NSString(string: "~/.claude/skills").expandingTildeInPath
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(atPath: skillsPath) else { return [] }
        var isDir: ObjCBool = false
        return contents.filter { item in
            let full = (skillsPath as NSString).appendingPathComponent(item)
            return fm.fileExists(atPath: full, isDirectory: &isDir) && isDir.boolValue
        }.sorted()
    }

    func detectContextGaps(taskType: String, available: [String]) -> [ContextSuggestion] {
        guard taskType != "unknown" else {
            let suggestion = ContextSuggestion(
                id: "no-task",
                skillName: "Set a task type",
                reason: "Task type unknown — cannot suggest context",
                severity: .optional
            )
            return [suggestion]
        }

        let needed = taskTypeSkills[taskType] ?? []
        var suggestions: [ContextSuggestion] = []

        for skill in needed {
            if available.contains(skill) {
                suggestions.append(ContextSuggestion(
                    id: "has-\(skill)", skillName: skill,
                    reason: "Recommended for \(taskTypeLabels[taskType] ?? taskType) tasks",
                    severity: .optional
                ))
            } else {
                suggestions.append(ContextSuggestion(
                    id: "missing-\(skill)", skillName: skill,
                    reason: "Not installed — consider creating this skill",
                    severity: .missing
                ))
            }
        }

        // Check for agent-specific context
        if let agent = selectedAgent {
            let agentSkill = "\(agent)"
            if !available.contains(agentSkill), agentSkill != "opencode" {
                suggestions.append(ContextSuggestion(
                    id: "missing-agent-\(agent)", skillName: agent,
                    reason: "No skill for selected agent \(agent)",
                    severity: .partial
                ))
            }
        }

        // Check for task-specific gaps
        if taskType == "ui" || taskType == "feature" {
            if !available.contains("atomic-ui-library") {
                suggestions.append(ContextSuggestion(
                    id: "missing-ui", skillName: "atomic-ui-library",
                    reason: "UI task without component library context",
                    severity: .missing
                ))
            }
        }

        return suggestions
    }

    func applyContext(taskType: String, description: String, skills: [String], projectPath: String) {
        currentTaskType = taskType
        taskDescription = description

        let muxyDir = (projectPath as NSString).appendingPathComponent(".muxy")
        try? FileManager.default.createDirectory(at: URL(fileURLWithPath: muxyDir), withIntermediateDirectories: true)

        let ctx = TaskContextData(
            taskType: taskType,
            taskDescription: description,
            recommendedSkills: skills,
            lastUpdated: Date()
        )
        let path = (muxyDir as NSString).appendingPathComponent("task-context.json")
        if let data = try? JSONEncoder().encode(ctx) {
            try? data.write(to: URL(fileURLWithPath: path))
        }

        // Refresh suggestions with new context
        contextSuggestions = detectContextGaps(taskType: taskType, available: availableSkills)
    }

    // MARK: - Global Tools

    private func refreshGlobalTools() {
        struct ToolDef {
            let name: String
            let checkCmd: String
            let hint: String?
        }
        let tools = [
            ToolDef(name: "pi", checkCmd: "pi --version 2>&1", hint: "npm install -g @mariozechner/pi-coding-agent"),
            ToolDef(
                name: "sentrux",
                checkCmd: "sentrux --version 2>&1",
                hint: "curl -fsSL https://raw.githubusercontent.com/sentrux/sentrux/main/install.sh | sh"
            ),
            ToolDef(name: "swiftlint", checkCmd: "swiftlint version 2>&1", hint: "brew install swiftlint"),
            ToolDef(name: "swiftformat", checkCmd: "swiftformat --version 2>&1", hint: "brew install swiftformat"),
            ToolDef(name: "gh", checkCmd: "gh --version 2>&1 | head -1", hint: "brew install gh"),
        ]
        globalTools = tools.map { tool in
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/bin/bash")
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

    // MARK: - CI Status

    private func refreshCI(projectPath: String) {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        task.arguments = ["gh", "run", "list", "--limit", "1", "--json", "conclusion,headBranch,createdAt,url"]
        task.currentDirectoryURL = URL(fileURLWithPath: projectPath)
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

    // MARK: - Pi History

    func refreshPiHistory() {
        let logPath = NSString(string: "~/.pi/agent/agent-workflow.log").expandingTildeInPath
        let logURL = URL(fileURLWithPath: logPath)
        guard let fileSize = try? logURL.resourceValues(forKeys: [.fileSizeKey]).fileSize,
              fileSize <= Self.maxPiLogSize,
              let logData = try? String(contentsOf: logURL, encoding: .utf8)
        else {
            piEvents = []
            return
        }
        let lines = logData.components(separatedBy: .newlines).filter { !$0.isEmpty }
        piEvents = lines.compactMap { line in
            let parts = line.components(separatedBy: " — ")
            guard parts.count >= 2 else { return nil }
            if let timestamp = Self.parsePiTimestamp(parts[0]) {
                let event = parts[1].trimmingCharacters(in: .whitespaces)
                let result = parts.count > 2 ? parts[2].trimmingCharacters(in: .whitespaces) : ""
                return PiExtensionEvent(timestamp: timestamp, event: event, result: result)
            }
            let event = parts[0].trimmingCharacters(in: .whitespaces)
            let result = parts[1].trimmingCharacters(in: .whitespaces)
            return PiExtensionEvent(timestamp: Date(), event: event, result: result)
        }
    }

    static func parsePiTimestamp(_ raw: String) -> Date? {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("["), trimmed.hasSuffix("]") {
            let inner = String(trimmed.dropFirst().dropLast())
            return logDateFormatter.date(from: inner)
        }
        return logDateFormatter.date(from: trimmed) ?? isoFormatterSimple.date(from: trimmed)
    }

    // MARK: - Quality

    func refreshQuality(projectPath: String) {
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

    // MARK: - Helpers

    private func runGit(_ args: [String], projectPath: String) -> String {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        task.arguments = args
        task.currentDirectoryURL = URL(fileURLWithPath: projectPath)
        let out = Pipe()
        task.standardOutput = out
        try? task.run()
        task.waitUntilExit()
        let data = out.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private func which(_ tool: String) -> String? {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        task.arguments = [tool]
        let out = Pipe()
        task.standardOutput = out
        try? task.run()
        task.waitUntilExit()
        let data = out.fileHandleForReading.readDataToEndOfFile()
        let path = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        return path?.isEmpty == false ? path : nil
    }

    private func scanTopDirs(_ projectPath: String) -> [String] {
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(atPath: projectPath) else { return [] }
        var isDir: ObjCBool = false
        return contents.filter { item in
            let full = (projectPath as NSString).appendingPathComponent(item)
            return fm.fileExists(atPath: full, isDirectory: &isDir) && isDir.boolValue && !item.hasPrefix(".")
        }
    }

    private func ls(_ projectPath: String, _ pattern: String) -> Bool {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/bash")
        task.arguments = ["-c", "ls \(pattern) 2>/dev/null | head -1"]
        task.currentDirectoryURL = URL(fileURLWithPath: projectPath)
        let out = Pipe()
        task.standardOutput = out
        try? task.run()
        task.waitUntilExit()
        let data = out.fileHandleForReading.readDataToEndOfFile()
        let result = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        return result?.isEmpty == false
    }

    func timeAgo(from isoString: String) -> String {
        guard let date = Self.isoFormatter.date(from: isoString) ?? Self.isoFormatterSimple.date(from: isoString) else { return "" }
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
