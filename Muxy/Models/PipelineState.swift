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
    var isLoading = false

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

    private struct RefreshResult {
        let workflows: [WorkflowDef]
        let activeWorkflowID: String?
        let toolValidationPassed: Bool?
        let toolValidationDetail: String?
        let history: [PipelineRunRecord]
    }

    func refresh(projectPath: String) {
        lastRun = Date()
        isLoading = true
        let path = projectPath
        Task.detached { [weak self] in
            let result = Self.computeAll(projectPath: path)
            await MainActor.run {
                guard let self else { return }
                self.workflows = result.workflows
                self.activeWorkflowID = result.activeWorkflowID
                self.toolValidationPassed = result.toolValidationPassed
                self.toolValidationDetail = result.toolValidationDetail
                self.history = result.history
                self.isLoading = false
            }
        }
    }

    // MARK: - Compute

    private static func computeAll(projectPath: String) -> RefreshResult {
        var wf = loadWorkflowsStatic(projectPath: projectPath)
        let activeID = wf?.id
        if let w = wf {
            wf = detectStepComplianceStatic(projectPath: projectPath, wf: w)
            wf = checkDependencyViolationsStatic(wf: w)
        }
        let validation = runToolValidationStatic(projectPath: projectPath)
        var hist = loadHistoryStatic(projectPath: projectPath)
        if let w = wf {
            let record = PipelineRunRecord(
                date: Date(),
                workflowName: w.name,
                stepResults: w.steps.map {
                    StepResultRecord(
                        stepID: $0.id,
                        name: $0.name,
                        status: $0.status.rawValue,
                        severity: $0.severity.rawValue,
                        evidence: $0.evidence ?? ""
                    )
                }
            )
            hist.insert(record, at: 0)
            if hist.count > 20 { hist = Array(hist.prefix(20)) }
            saveHistoryStatic(history: hist, projectPath: projectPath)
        }
        return RefreshResult(
            workflows: wf.map { [$0] } ?? [],
            activeWorkflowID: activeID,
            toolValidationPassed: validation.passed,
            toolValidationDetail: validation.detail,
            history: hist
        )
    }

    // MARK: - Workflow Loading

    private static func loadWorkflowsStatic(projectPath: String) -> WorkflowDef? {
        let fm = FileManager.default
        let workflowsDir = (projectPath as NSString).appendingPathComponent(".archon/workflows")
        guard fm.fileExists(atPath: workflowsDir) else { return nil }

        var workflows: [WorkflowDef] = []
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
        } catch {
            print("[PipelineState] Failed to load workflows from \(workflowsDir): \(error)")
        }

        let branch = ShellRunner.run("git rev-parse --abbrev-ref HEAD", workingDirectory: projectPath).output
        let type = branch.components(separatedBy: "/").first ?? ""
        for wf in workflows {
            if wf.id.contains(type) || wf.name == type {
                return wf
            }
        }
        return workflows.first
    }

    // MARK: - Step Compliance

    private static func detectStepComplianceStatic(projectPath: String, wf inputWf: WorkflowDef) -> WorkflowDef {
        var wf = inputWf
        for i in wf.steps.indices {
            var step = wf.steps[i]
            switch step.kind {
            case .hookPreCommit, .plan:
                step = detectPreCommitStatic(projectPath: projectPath, step: step)
            case .sentruxBaseline:
                step = detectSentruxBaselineStatic(projectPath: projectPath, step: step)
            case .implement:
                step = detectImplementationStatic(projectPath: projectPath, step: step)
            case .qualityGate:
                step = detectQualityGateStatic(projectPath: projectPath, step: step)
            case .graphifyUpdate:
                step = detectGraphifyStatic(projectPath: projectPath, step: step)
            case .test:
                step = detectTestsStatic(projectPath: projectPath, step: step)
            case .review:
                step = detectReviewStatic(projectPath: projectPath, step: step)
            case .approval:
                step = detectApprovalStatic(projectPath: projectPath, step: step)
            case .pr:
                step = detectPRStatic(projectPath: projectPath, step: step)
            case .hookPrePush:
                step = detectPrePushStatic(projectPath: projectPath, step: step)
            case .unknown:
                step.status = .pending
            }
            step.detectedAt = Date()
            wf.steps[i] = step
        }
        assignSeverityStatic(&wf)
        checkStepOrderingStatic(projectPath: projectPath, wf: &wf)
        return wf
    }

    private static func assignSeverityStatic(_ wf: inout WorkflowDef) {
        for i in wf.steps.indices {
            switch wf.steps[i].kind {
            case .approval, .pr:
                wf.steps[i].severity = .critical
            case .qualityGate, .hookPreCommit, .hookPrePush, .test, .sentruxBaseline:
                wf.steps[i].severity = .warning
            case .plan, .implement, .review, .graphifyUpdate, .unknown:
                wf.steps[i].severity = .info
            }
        }
    }

    private static func checkStepOrderingStatic(projectPath: String, wf: inout WorkflowDef) {
        let commits = ShellRunner.run("git log --format='%H %ct' -20", workingDirectory: projectPath).output
        let commitLines = commits.components(separatedBy: .newlines).filter { !$0.isEmpty }
        guard commitLines.count >= 2 else { return }
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

    private static func checkDependencyViolationsStatic(wf inputWf: WorkflowDef) -> WorkflowDef {
        var wf = inputWf
        var violations: [String] = []
        for step in wf.steps where step.status == .followed {
            for depID in step.dependsOn {
                if let dep = wf.steps.first(where: { $0.id == depID }), dep.status != .followed {
                    violations.append("\(step.name) depends on \(dep.name) but \(dep.name) was \(dep.status.rawValue)")
                }
            }
        }
        wf.dependencyViolations = violations
        return wf
    }

    // MARK: - Tool Validation

    private static func runToolValidationStatic(projectPath: String) -> (passed: Bool?, detail: String?) {
        let validateScript = Bundle.main.path(forResource: "validate-workflow", ofType: "sh", inDirectory: "Scripts")
            ?? (Bundle.main.bundlePath as NSString).appendingPathComponent("Contents/Resources/Scripts/validate-workflow.sh")
        guard FileManager.default.fileExists(atPath: validateScript) else {
            return (nil, "validate-workflow.sh not bundled")
        }
        let result = ShellRunner.run("'\(validateScript)' --ci 2>&1; echo \"EXIT_CODE=$?\"", workingDirectory: projectPath)
        var passed: Bool?
        var detail: String?
        if let exitLine = result.output.components(separatedBy: .newlines).last(where: { $0.hasPrefix("EXIT_CODE=") }) {
            let code = exitLine.replacingOccurrences(of: "EXIT_CODE=", with: "").trimmingCharacters(in: .whitespaces)
            passed = code == "0"
        } else {
            passed = result.exitCode == 0
        }
        if let resultsLine = result.output.components(separatedBy: .newlines)
            .last(where: { $0.contains("passed") || $0.contains("Results") })
        {
            let cleaned = resultsLine.replacingOccurrences(of: "[^a-zA-Z0-9, ]", with: "", options: .regularExpression)
            detail = cleaned.trimmingCharacters(in: .whitespaces)
        }
        return (passed, detail)
    }

    // MARK: - Per-Step Detection

    private static func detectPreCommitStatic(projectPath: String, step: PipelineStep) -> PipelineStep {
        let code = ShellRunner.run("git log --format='%B' -1 | head -5", workingDirectory: projectPath).output
        let formatted = ShellRunner.run("swiftformat --lint . --quiet 2>&1; echo \"EXIT=$?\"", workingDirectory: projectPath).output
        let linted = ShellRunner.run("swiftlint lint --strict --quiet 2>&1; echo \"EXIT=$?\"", workingDirectory: projectPath).output
        let formatPassed = formatted.contains("EXIT=0")
        let lintPassed = linted.contains("EXIT=0")
        if code.contains("feature/") || code.contains("fix/") || code.contains("refactor/") {
            if formatPassed, lintPassed {
                return markStatic(step, .followed, "Format + lint clean")
            } else if !formatPassed, !lintPassed {
                return markStatic(step, .skipped, "Format and lint issues — pre-commit did not run")
            } else if !formatPassed {
                return markStatic(step, .skipped, "swiftformat issues found — pre-commit may not have run")
            } else {
                return markStatic(step, .followed, "Pre-commit executed (lint warnings)")
            }
        }
        return markStatic(step, .pending, "No agent commits on this branch")
    }

    private static func detectSentruxBaselineStatic(projectPath: String, step: PipelineStep) -> PipelineStep {
        let baselinePath = (projectPath as NSString).appendingPathComponent(".sentrux/baseline.json")
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: baselinePath),
              let modDate = attrs[.modificationDate] as? Date
        else {
            return markStatic(step, .skipped, "No Sentrux baseline — sentrux gate --save not run")
        }
        if abs(modDate.timeIntervalSinceNow) < 3600 {
            return markStatic(step, .followed, "Baseline updated \(Date.timeAgo(since: modDate))")
        }
        let score = readQualityScoreStatic(baselinePath: baselinePath)
        return markStatic(step, .followed, "Baseline score: \(score) (updated \(Date.timeAgo(since: modDate)))")
    }

    private static func readQualityScoreStatic(baselinePath: String) -> Int {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: baselinePath)),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let score = json["quality_signal"] as? Double
        else { return 0 }
        return Int(score * 10000)
    }

    private static func detectImplementationStatic(projectPath: String, step: PipelineStep) -> PipelineStep {
        let log = ShellRunner.run("git log --oneline -5", workingDirectory: projectPath).output
        let lines = log.components(separatedBy: .newlines).filter { !$0.isEmpty }
        if !lines.isEmpty {
            let snippets = lines.prefix(3).map { String($0.prefix(60)) }.joined(separator: "\n")
            return markStatic(step, .followed, "\(lines.count) recent commits:\n\(snippets)")
        }
        let staged = ShellRunner.run("git diff --name-only | wc -l", workingDirectory: projectPath).output
        if let files = Int(staged.trimmingCharacters(in: .whitespaces)), files > 0 {
            return markStatic(step, .followed, "\(files) files modified (uncommitted)")
        }
        return markStatic(step, .skipped, "No recent code changes detected")
    }

    private static func detectQualityGateStatic(projectPath: String, step: PipelineStep) -> PipelineStep {
        let result = ShellRunner.run("sentrux gate . 2>&1; echo \"EXIT=$?\"", workingDirectory: projectPath).output
        if result.contains("No degradation") {
            return markStatic(step, .followed, "No structural degradation detected")
        }
        if result.contains("EXIT=0") {
            return markStatic(step, .followed, "Quality gate passed")
        }
        return markStatic(step, .skipped, "sentrux gate not run or failed")
    }

    private static func detectGraphifyStatic(projectPath: String, step: PipelineStep) -> PipelineStep {
        let outDir = (projectPath as NSString).appendingPathComponent("graphify-out")
        if FileManager.default.fileExists(atPath: "\(outDir)/graph.json") {
            return markStatic(step, .followed, "Knowledge graph exists")
        }
        return markStatic(step, .skipped, "graphify update not run")
    }

    private static func detectTestsStatic(projectPath: String, step: PipelineStep) -> PipelineStep {
        let result = ShellRunner.run("swift test 2>&1 | tail -3; echo \"EXIT=$?\"", workingDirectory: projectPath).output
        if result.contains("passed"), !result.contains("failed") {
            return markStatic(step, .followed, "All tests passed")
        }
        if result.contains("EXIT=0") {
            return markStatic(step, .followed, "Tests executed")
        }
        if result.contains("failed") {
            return markStatic(step, .skipped, "Tests failed or not run")
        }
        return markStatic(step, .pending, "Test status unknown")
    }

    private static func detectReviewStatic(projectPath: String, step: PipelineStep) -> PipelineStep {
        let commitCount = ShellRunner.run("git log --oneline HEAD...HEAD~10 | wc -l", workingDirectory: projectPath).output
        if let count = Int(commitCount.trimmingCharacters(in: .whitespaces)), count > 1 {
            return markStatic(step, .followed, "\(count) commits in recent history")
        }
        return markStatic(step, .pending, "Single commit — no review iteration detected")
    }

    private static func detectApprovalStatic(projectPath: String, step: PipelineStep) -> PipelineStep {
        markStatic(step, .pending, "Manual step — check PR status")
    }

    private static func detectPRStatic(projectPath: String, step: PipelineStep) -> PipelineStep {
        let result = ShellRunner.run("gh pr view --json state 2>/dev/null; echo \"EXIT=$?\"", workingDirectory: projectPath).output
        if result.contains("MERGED") {
            return markStatic(step, .followed, "PR merged")
        }
        if result.contains("OPEN") {
            return markStatic(step, .followed, "PR open")
        }
        return markStatic(step, .pending, "No PR detected")
    }

    private static func detectPrePushStatic(projectPath: String, step: PipelineStep) -> PipelineStep {
        let branch = ShellRunner.run("git rev-parse --abbrev-ref HEAD", workingDirectory: projectPath).output
        let remote = ShellRunner.run("git ls-remote --heads origin \(branch) | head -1", workingDirectory: projectPath).output
        if !remote.isEmpty {
            return markStatic(step, .followed, "Branch pushed to remote")
        }
        return markStatic(step, .pending, "Branch not pushed yet")
    }

    // MARK: - History

    private static func saveHistoryStatic(history: [PipelineRunRecord], projectPath: String) {
        if let data = try? JSONEncoder().encode(history) {
            let path = (projectPath as NSString).appendingPathComponent(".muxy/pipeline-history.json")
            try? FileManager.default.createDirectory(
                atPath: (path as NSString).deletingLastPathComponent,
                withIntermediateDirectories: true
            )
            try? data.write(to: URL(fileURLWithPath: path))
        }
    }

    private static func loadHistoryStatic(projectPath: String) -> [PipelineRunRecord] {
        let path = (projectPath as NSString).appendingPathComponent(".muxy/pipeline-history.json")
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
              let records = try? JSONDecoder().decode([PipelineRunRecord].self, from: data)
        else { return [] }
        return records
    }

    // MARK: - Helpers

    private static func markStatic(_ step: PipelineStep, _ status: StepStatus, _ evidence: String) -> PipelineStep {
        var s = step
        s.status = status
        s.evidence = evidence
        return s
    }
}
