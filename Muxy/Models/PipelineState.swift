import Foundation
import Yams

struct PipelineStep: Identifiable {
    let id: String
    let name: String
    let kind: StepKind
    let orderIndex: Int
    let dependsOn: [String]
    var severity: StepSeverity
    var status: StepStatus
    var evidence: String?
    var detectedAt: Date?
}

enum StepKind: String {
    case plan
    case sentruxBaseline = "sentrux-baseline"
    case implement
    case qualityGate = "quality-gate"
    case graphifyUpdate = "graphify-update"
    case test
    case review
    case approval
    case pr
    case hookPreCommit = "hook-pre-commit"
    case hookPrePush = "hook-pre-push"
    case unknown
}

enum StepSeverity: String {
    case critical
    case warning
    case info
}

enum StepStatus: String {
    case followed
    case skipped
    case pending
}

struct WorkflowDef: Identifiable {
    let id: String
    let name: String
    let filePath: String
    var steps: [PipelineStep]
    var dependencyViolations: [String] = []

    var violationCount: Int {
        steps.count(where: { $0.status == .skipped }) + dependencyViolations.count
    }
}

struct PipelineRunRecord: Codable, Identifiable {
    var id: String { "\(workflowName)-\(date.timeIntervalSince1970)" }
    let date: Date
    let workflowName: String
    let stepResults: [StepResultRecord]
}

struct StepResultRecord: Codable {
    let stepID: String
    let name: String
    let status: String
    let severity: String
    let evidence: String
}

@Observable
final class PipelineState: @unchecked Sendable {
    var workflows: [WorkflowDef] = []
    var activeWorkflowID: String?
    var toolValidationPassed: Bool?
    var toolValidationDetail: String?
    var lastRun: Date?
    var history: [PipelineRunRecord] = []

    @ObservationIgnored private var watcher: GitDirectoryWatcher?
    @ObservationIgnored private var remoteChangeObserver: NSObjectProtocol?
    private var watchedProjectPath: String?

    var activeWorkflow: WorkflowDef? {
        guard let id = activeWorkflowID else { return workflows.first }
        return workflows.first { $0.id == id }
    }

    var allFollowed: Bool {
        guard let wf = activeWorkflow else { return false }
        return wf.steps.allSatisfy { $0.status == .followed } && wf.dependencyViolations.isEmpty
    }

    var skippedCount: Int {
        guard let wf = activeWorkflow else { return 0 }
        return wf.steps.count(where: { $0.status == .skipped })
    }

    var violationCount: Int {
        guard let wf = activeWorkflow else { return 0 }
        return wf.violationCount
    }

    func refresh(projectPath: String) {
        installWatcher(projectPath: projectPath)
        observeRemoteChanges(projectPath: projectPath)
        lastRun = Date()
        loadWorkflows(projectPath: projectPath)
        detectStepCompliance(projectPath: projectPath)
        checkDependencyViolations()
        runToolValidation(projectPath: projectPath)
        saveHistory(projectPath: projectPath)
        loadHistory(projectPath: projectPath)
    }

    // MARK: - Workflow Loading

    private func loadWorkflows(projectPath: String) {
        let fm = FileManager.default
        let workflowsDir = (projectPath as NSString).appendingPathComponent(".archon/workflows")
        guard fm.fileExists(atPath: workflowsDir) else { return }

        do {
            let files = try fm.contentsOfDirectory(atPath: workflowsDir).filter { $0.hasSuffix(".yaml") }
            workflows = try files.compactMap { file -> WorkflowDef? in
                let path = (workflowsDir as NSString).appendingPathComponent(file)
                let data = try String(contentsOfFile: path, encoding: .utf8)
                guard let yaml = try Yams.load(yaml: data) as? [String: Any],
                      let nodes = yaml["nodes"] as? [[String: Any]]
                else { return nil }

                let name = file.replacingOccurrences(of: ".yaml", with: "").replacingOccurrences(of: "agent-", with: "")
                let steps: [PipelineStep] = nodes.enumerated().map { idx, node in
                    let id = node["id"] as? String ?? "step-\(idx)"
                    let dependsOn = node["depends_on"] as? [String] ?? []
                    let kind = StepKind(rawValue: id) ?? .unknown
                    return PipelineStep(
                        id: id,
                        name: id.replacingOccurrences(of: "-", with: " ").capitalized,
                        kind: kind,
                        orderIndex: idx,
                        dependsOn: dependsOn,
                        severity: .info,
                        status: .pending,
                        evidence: nil,
                        detectedAt: nil
                    )
                }

                return WorkflowDef(
                    id: file,
                    name: name,
                    filePath: ".archon/workflows/\(file)",
                    steps: steps
                )
            }
        } catch {}

        detectActiveWorkflow(projectPath: projectPath)
    }

    private func detectActiveWorkflow(projectPath: String) {
        let branch = shell("cd '\(projectPath)' 2>/dev/null && git rev-parse --abbrev-ref HEAD 2>/dev/null")
        let type = branch.components(separatedBy: "/").first ?? ""
        for wf in workflows {
            if wf.id.contains(type) || wf.name == type {
                activeWorkflowID = wf.id
                return
            }
        }
        activeWorkflowID = workflows.first?.id
    }

    // MARK: - Step Compliance

    private func detectStepCompliance(projectPath: String) {
        guard var wf = activeWorkflow else { return }

        for i in wf.steps.indices {
            var step = wf.steps[i]
            switch step.kind {
            case .hookPreCommit,
                 .plan:
                step = detectPreCommit(projectPath: projectPath, step: step)
            case .sentruxBaseline:
                step = detectSentruxBaseline(projectPath: projectPath, step: step)
            case .implement:
                step = detectImplementation(projectPath: projectPath, step: step)
            case .qualityGate:
                step = detectQualityGate(projectPath: projectPath, step: step)
            case .graphifyUpdate:
                step = detectGraphify(projectPath: projectPath, step: step)
            case .test:
                step = detectTests(projectPath: projectPath, step: step)
            case .review:
                step = detectReview(projectPath: projectPath, step: step)
            case .approval:
                step = detectApproval(projectPath: projectPath, step: step)
            case .pr:
                step = detectPR(projectPath: projectPath, step: step)
            case .hookPrePush:
                step = detectPrePush(projectPath: projectPath, step: step)
            case .unknown:
                step.status = .pending
            }
            step.detectedAt = Date()
            wf.steps[i] = step
        }

        assignSeverity(&wf)
        checkStepOrdering(projectPath: projectPath, wf: &wf)

        if let idx = workflows.firstIndex(where: { $0.id == wf.id }) {
            workflows[idx] = wf
        }
    }

    private func assignSeverity(_ wf: inout WorkflowDef) {
        for i in wf.steps.indices {
            switch wf.steps[i].kind {
            case .approval,
                 .pr:
                wf.steps[i].severity = .critical
            case .qualityGate,
                 .hookPreCommit,
                 .hookPrePush,
                 .test,
                 .sentruxBaseline:
                wf.steps[i].severity = .warning
            case .plan,
                 .implement,
                 .review,
                 .graphifyUpdate,
                 .unknown:
                wf.steps[i].severity = .info
            }
        }
    }

    private func checkStepOrdering(projectPath: String, wf: inout WorkflowDef) {
        let commits = shell("cd '\(projectPath)' 2>/dev/null && git log --format='%H %ct' -20 2>/dev/null")
        let commitLines = commits.components(separatedBy: .newlines).filter { !$0.isEmpty }
        guard commitLines.count >= 2 else { return }

        let timestamps = commitLines.compactMap { line -> TimeInterval? in
            Double(line.split(separator: " ").last.map(String.init) ?? "")
        }

        let followedSteps = wf.steps.enumerated().filter { $0.element.status == .followed }
        for i in 1 ..< followedSteps.count {
            let prev = followedSteps[i - 1]
            let curr = followedSteps[i]
            if prev.offset > curr.offset {
                wf.steps[curr.offset].severity = .warning
                if let ev = wf.steps[curr.offset].evidence {
                    wf.steps[curr.offset].evidence = "\(ev) [ran before \(prev.element.name)]"
                }
            }
        }
    }

    private func checkDependencyViolations() {
        guard let wf = activeWorkflow else { return }
        var violations: [String] = []

        for step in wf.steps where step.status == .followed {
            for depID in step.dependsOn {
                if let dep = wf.steps.first(where: { $0.id == depID }),
                   dep.status != .followed
                {
                    violations.append("\(step.name) depends on \(dep.name) but \(dep.name) was \(dep.status.rawValue)")
                }
            }
        }

        if let idx = workflows.firstIndex(where: { $0.id == wf.id }) {
            workflows[idx].dependencyViolations = violations
        }
    }

    // MARK: - Tool Validation

    private func runToolValidation(projectPath: String) {
        let validateScript = Bundle.main.path(forResource: "validate-workflow", ofType: "sh", inDirectory: "Scripts")
            ?? (Bundle.main.bundlePath as NSString).appendingPathComponent("Contents/Resources/Scripts/validate-workflow.sh")
        guard FileManager.default.fileExists(atPath: validateScript) else {
            toolValidationPassed = nil
            toolValidationDetail = "validate-workflow.sh not bundled"
            return
        }

        let task = Process()
        task.launchPath = "/bin/bash"
        task.arguments = ["-c", "cd '\(projectPath)' 2>/dev/null && '\(validateScript)' --ci 2>&1; echo \"EXIT_CODE=$?\""]
        let out = Pipe()
        task.standardOutput = out
        task.standardError = out
        do {
            try task.run()
            task.waitUntilExit()
            let data = out.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""

            if let exitLine = output.components(separatedBy: .newlines).last(where: { $0.hasPrefix("EXIT_CODE=") }) {
                let code = exitLine.replacingOccurrences(of: "EXIT_CODE=", with: "").trimmingCharacters(in: .whitespaces)
                toolValidationPassed = code == "0"
            } else {
                toolValidationPassed = task.terminationStatus == 0
            }

            if let resultsLine = output.components(separatedBy: .newlines)
                .last(where: { $0.contains("passed") || $0.contains("Results") })
            {
                let cleaned = resultsLine.replacingOccurrences(of: "[^a-zA-Z0-9, ]", with: "", options: .regularExpression)
                toolValidationDetail = cleaned.trimmingCharacters(in: .whitespaces)
            }
        } catch {
            toolValidationPassed = nil
            toolValidationDetail = "validation failed: \(error.localizedDescription)"
        }
    }

    // MARK: - Per-Step Detection

    private func detectPreCommit(projectPath: String, step: PipelineStep) -> PipelineStep {
        let code = shell("cd '\(projectPath)' 2>/dev/null && git log --format='%B' -1 2>/dev/null | head -5")
        let formatted = shell("cd '\(projectPath)' 2>/dev/null && swiftformat --lint . --quiet 2>&1; echo \"EXIT=$?\"")
        let linted = shell("cd '\(projectPath)' 2>/dev/null && swiftlint lint --strict --quiet 2>&1; echo \"EXIT=$?\"")

        let formatPassed = formatted.contains("EXIT=0")
        let lintPassed = linted.contains("EXIT=0")

        if code.contains("feature/") || code.contains("fix/") || code.contains("refactor/") {
            if formatPassed, lintPassed {
                return mark(step, .followed, "Format + lint clean")
            } else if !formatPassed, !lintPassed {
                return mark(step, .skipped, "Format and lint issues — pre-commit did not run")
            } else if !formatPassed {
                return mark(step, .skipped, "swiftformat issues found — pre-commit may not have run")
            } else {
                return mark(step, .followed, "Pre-commit executed (lint warnings)")
            }
        }
        return mark(step, .pending, "No agent commits on this branch")
    }

    private func detectSentruxBaseline(projectPath: String, step: PipelineStep) -> PipelineStep {
        let baselinePath = (projectPath as NSString).appendingPathComponent(".sentrux/baseline.json")
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: baselinePath),
              let modDate = attrs[.modificationDate] as? Date
        else {
            return mark(step, .skipped, "No Sentrux baseline — sentrux gate --save not run")
        }

        if abs(modDate.timeIntervalSinceNow) < 3600 {
            return mark(step, .followed, "Baseline updated \(timeAgo(modDate))")
        }
        let score = readQualityScore(baselinePath: baselinePath)
        return mark(step, .followed, "Baseline score: \(score) (updated \(timeAgo(modDate)))")
    }

    private func readQualityScore(baselinePath: String) -> Int {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: baselinePath)),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let score = json["quality_signal"] as? Double
        else { return 0 }
        return Int(score * 10000)
    }

    private func detectImplementation(projectPath: String, step: PipelineStep) -> PipelineStep {
        let log = shell("cd '\(projectPath)' 2>/dev/null && git log --oneline -5 2>/dev/null")
        let lines = log.components(separatedBy: .newlines).filter { !$0.isEmpty }
        if !lines.isEmpty {
            let snippets = lines.prefix(3).map { String($0.prefix(60)) }.joined(separator: "\n")
            return mark(step, .followed, "\(lines.count) recent commits:\n\(snippets)")
        }
        let staged = shell("cd '\(projectPath)' 2>/dev/null && git diff --name-only 2>/dev/null | wc -l")
        if let files = Int(staged.trimmingCharacters(in: .whitespaces)), files > 0 {
            return mark(step, .followed, "\(files) files modified (uncommitted)")
        }
        return mark(step, .skipped, "No recent code changes detected")
    }

    private func detectQualityGate(projectPath: String, step: PipelineStep) -> PipelineStep {
        let result = shell("cd '\(projectPath)' 2>/dev/null && sentrux gate . 2>&1; echo \"EXIT=$?\"")
        if result.contains("No degradation") {
            return mark(step, .followed, "No structural degradation detected")
        }
        if result.contains("EXIT=0") {
            return mark(step, .followed, "Quality gate passed")
        }
        return mark(step, .skipped, "sentrux gate not run or failed")
    }

    private func detectGraphify(projectPath: String, step: PipelineStep) -> PipelineStep {
        let outDir = (projectPath as NSString).appendingPathComponent("graphify-out")
        if FileManager.default.fileExists(atPath: "\(outDir)/graph.json") {
            return mark(step, .followed, "Knowledge graph exists")
        }
        return mark(step, .skipped, "graphify update not run")
    }

    private func detectTests(projectPath: String, step: PipelineStep) -> PipelineStep {
        let result = shell("cd '\(projectPath)' 2>/dev/null && swift test 2>&1 | tail -3; echo \"EXIT=$?\"")
        if result.contains("passed"), !result.contains("failed") {
            return mark(step, .followed, "All tests passed")
        }
        if result.contains("EXIT=0") {
            return mark(step, .followed, "Tests executed")
        }
        if result.contains("failed") {
            return mark(step, .skipped, "Tests failed or not run")
        }
        return mark(step, .pending, "Test status unknown")
    }

    private func detectReview(projectPath: String, step: PipelineStep) -> PipelineStep {
        let commitCount = shell("cd '\(projectPath)' 2>/dev/null && git log --oneline HEAD...HEAD~10 2>/dev/null | wc -l")
        if let count = Int(commitCount.trimmingCharacters(in: .whitespaces)), count > 1 {
            return mark(step, .followed, "\(count) commits in recent history")
        }
        return mark(step, .pending, "Single commit — no review iteration detected")
    }

    private func detectApproval(projectPath: String, step: PipelineStep) -> PipelineStep {
        mark(step, .pending, "Manual step — check PR status")
    }

    private func detectPR(projectPath: String, step: PipelineStep) -> PipelineStep {
        let result = shell("cd '\(projectPath)' 2>/dev/null && gh pr view --json state 2>/dev/null; echo \"EXIT=$?\"")
        if result.contains("MERGED") {
            return mark(step, .followed, "PR merged")
        }
        if result.contains("OPEN") {
            return mark(step, .followed, "PR open")
        }
        return mark(step, .pending, "No PR detected")
    }

    private func detectPrePush(projectPath: String, step: PipelineStep) -> PipelineStep {
        let branch = shell("cd '\(projectPath)' 2>/dev/null && git rev-parse --abbrev-ref HEAD 2>/dev/null")
        let remote = shell("cd '\(projectPath)' 2>/dev/null && git ls-remote --heads origin \(branch) 2>/dev/null | head -1")
        if !remote.isEmpty {
            return mark(step, .followed, "Branch pushed to remote")
        }
        return mark(step, .pending, "Branch not pushed yet")
    }

    // MARK: - History

    private func saveHistory(projectPath: String) {
        guard let wf = activeWorkflow else { return }
        let record = PipelineRunRecord(
            date: Date(),
            workflowName: wf.name,
            stepResults: wf.steps.map {
                StepResultRecord(
                    stepID: $0.id,
                    name: $0.name,
                    status: $0.status.rawValue,
                    severity: $0.severity.rawValue,
                    evidence: $0.evidence ?? ""
                )
            }
        )

        var all = history
        all.insert(record, at: 0)
        if all.count > 20 { all = Array(all.prefix(20)) }
        history = all

        if let data = try? JSONEncoder().encode(all) {
            let path = (projectPath as NSString).appendingPathComponent(".muxy/pipeline-history.json")
            try? FileManager.default.createDirectory(
                atPath: (path as NSString).deletingLastPathComponent,
                withIntermediateDirectories: true
            )
            try? data.write(to: URL(fileURLWithPath: path))
        }
    }

    private func loadHistory(projectPath: String) {
        let path = (projectPath as NSString).appendingPathComponent(".muxy/pipeline-history.json")
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
              let records = try? JSONDecoder().decode([PipelineRunRecord].self, from: data)
        else { return }
        history = records
    }

    // MARK: - Helpers

    private func mark(_ step: PipelineStep, _ status: StepStatus, _ evidence: String) -> PipelineStep {
        var s = step
        s.status = status
        s.evidence = evidence
        return s
    }

    private func shell(_ cmd: String) -> String {
        let task = Process()
        task.launchPath = "/bin/bash"
        task.arguments = ["-c", cmd]
        let out = Pipe()
        task.standardOutput = out
        task.standardError = out
        try? task.run()
        task.waitUntilExit()
        let data = out.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
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

    private func installWatcher(projectPath: String) {
        guard watchedProjectPath != projectPath else { return }
        watchedProjectPath = projectPath
        watcher = GitDirectoryWatcher(directoryPath: projectPath) { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.refresh(projectPath: projectPath)
            }
        }
    }

    private func observeRemoteChanges(projectPath: String) {
        guard watchedProjectPath != projectPath else { return }
        let path = projectPath
        remoteChangeObserver = NotificationCenter.default.addObserver(
            forName: .vcsRepoDidChange,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let notifiedPath = notification.userInfo?["repoPath"] as? String,
                  notifiedPath == path
            else { return }
            MainActor.assumeIsolated {
                self?.refresh(projectPath: path)
            }
        }
    }

    deinit {
        if let observer = remoteChangeObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }
}
