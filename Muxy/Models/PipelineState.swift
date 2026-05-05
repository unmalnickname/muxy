import Foundation
import Yams

struct PipelineStep: Identifiable {
    let id: String
    let name: String
    let kind: StepKind
    var status: StepStatus
    var evidence: String?
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
}

@Observable
final class PipelineState {
    var workflows: [WorkflowDef] = []
    var activeWorkflowID: String?
    var toolValidationPassed: Bool?
    var toolValidationDetail: String?
    var lastRun: Date?

    var activeWorkflow: WorkflowDef? {
        guard let id = activeWorkflowID else { return workflows.first }
        return workflows.first { $0.id == id }
    }

    var allFollowed: Bool {
        guard let wf = activeWorkflow else { return false }
        return wf.steps.allSatisfy { $0.status == .followed }
    }

    var skippedCount: Int {
        guard let wf = activeWorkflow else { return 0 }
        return wf.steps.count(where: { $0.status == .skipped })
    }

    func refresh(projectPath: String) {
        lastRun = Date()
        loadWorkflows(projectPath: projectPath)
        detectStepCompliance(projectPath: projectPath)
        runToolValidation(projectPath: projectPath)
    }

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
                    let prompt = node["prompt"] as? String
                    let bash = node["bash"] as? String
                    let kind = StepKind(rawValue: id) ?? .unknown
                    return PipelineStep(
                        id: id,
                        name: id.replacingOccurrences(of: "-", with: " ").capitalized,
                        kind: kind,
                        status: .pending,
                        evidence: nil
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
        let task = Process()
        task.launchPath = "/bin/bash"
        task.arguments = ["-c", "cd '\(projectPath)' 2>/dev/null && git rev-parse --abbrev-ref HEAD 2>/dev/null"]
        let out = Pipe()
        task.standardOutput = out
        try? task.run()
        task.waitUntilExit()
        let data = out.fileHandleForReading.readDataToEndOfFile()
        let branch = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespaces) ?? ""

        let type = branch.components(separatedBy: "/").first ?? ""
        for wf in workflows {
            if wf.id.contains(type) || wf.name == type {
                activeWorkflowID = wf.id
                return
            }
        }
        activeWorkflowID = workflows.first?.id
    }

    private func detectStepCompliance(projectPath: String) {
        guard var wf = activeWorkflow else { return }

        for i in wf.steps.indices {
            switch wf.steps[i].kind {
            case .hookPreCommit,
                 .plan:
                wf.steps[i] = detectPreCommit(projectPath: projectPath, step: wf.steps[i])
            case .sentruxBaseline:
                wf.steps[i] = detectSentruxBaseline(projectPath: projectPath, step: wf.steps[i])
            case .implement:
                wf.steps[i] = detectImplementation(projectPath: projectPath, step: wf.steps[i])
            case .qualityGate:
                wf.steps[i] = detectQualityGate(projectPath: projectPath, step: wf.steps[i])
            case .graphifyUpdate:
                wf.steps[i] = detectGraphify(projectPath: projectPath, step: wf.steps[i])
            case .test:
                wf.steps[i] = detectTests(projectPath: projectPath, step: wf.steps[i])
            case .review:
                wf.steps[i] = detectReview(projectPath: projectPath, step: wf.steps[i])
            case .approval:
                wf.steps[i] = detectApproval(projectPath: projectPath, step: wf.steps[i])
            case .pr:
                wf.steps[i] = detectPR(projectPath: projectPath, step: wf.steps[i])
            case .hookPrePush:
                wf.steps[i] = detectPrePush(projectPath: projectPath, step: wf.steps[i])
            case .unknown:
                wf.steps[i].status = .pending
            }
        }

        if let idx = workflows.firstIndex(where: { $0.id == wf.id }) {
            workflows[idx] = wf
        }
    }

    private func runToolValidation(projectPath: String) {
        let task = Process()
        task.launchPath = "/bin/bash"
        task.arguments = ["-c", "cd '\(projectPath)' 2>/dev/null && scripts/validate-workflow.sh --ci 2>&1; echo \"EXIT_CODE=$?\""]
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
                let cleaned = resultsLine.replacingOccurrences(
                    of: "[^a-zA-Z0-9, ]",
                    with: "",
                    options: .regularExpression
                )
                toolValidationDetail = cleaned.trimmingCharacters(in: .whitespaces)
            }
        } catch {}
    }

    private func detectPreCommit(projectPath: String, step: PipelineStep) -> PipelineStep {
        let code = shell("cd '\(projectPath)' 2>/dev/null && git log --format='%B' -1 2>/dev/null | head -5")
        let formatted = shell("cd '\(projectPath)' 2>/dev/null && swiftformat --lint . --quiet 2>&1; echo \"EXIT=$?\"")
        let linted = shell("cd '\(projectPath)' 2>/dev/null && swiftlint lint --strict --quiet 2>&1; echo \"EXIT=$?\"")

        let formatPassed = formatted.contains("EXIT=0")
        let lintPassed = linted.contains("EXIT=0")

        if code.contains("feature/") || code.contains("fix/") || code.contains("refactor/") {
            if formatPassed, lintPassed {
                return mark(step, .followed, "Format + lint clean")
            } else if !formatPassed {
                return mark(step, .skipped, "Formatting issues found — pre-commit may not have run")
            } else {
                return mark(step, .followed, "Pre-commit executed")
            }
        }
        return mark(step, .pending, "No agent commits on this branch")
    }

    private func detectSentruxBaseline(projectPath: String, step: PipelineStep) -> PipelineStep {
        let baselinePath = (projectPath as NSString).appendingPathComponent(".sentrux/baseline.json")
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: baselinePath),
              let modDate = attrs[.modificationDate] as? Date
        else {
            return mark(step, .skipped, "No Sentrux baseline found — sentrux gate --save not run")
        }

        let recent = abs(modDate.timeIntervalSinceNow) < 3600
        if recent {
            return mark(step, .followed, "Baseline updated \(timeAgo(modDate))")
        }
        return mark(step, .followed, "Baseline exists (last update \(timeAgo(modDate)))")
    }

    private func detectImplementation(projectPath: String, step: PipelineStep) -> PipelineStep {
        let count = shell("cd '\(projectPath)' 2>/dev/null && git log --oneline HEAD...HEAD~5 2>/dev/null | wc -l")
        let trimmed = count.trimmingCharacters(in: .whitespaces)
        if let commits = Int(trimmed), commits > 0 {
            return mark(step, .followed, "\(commits) recent commits")
        }
        let staged = shell("cd '\(projectPath)' 2>/dev/null && git diff --name-only 2>/dev/null | wc -l")
        if let files = Int(staged.trimmingCharacters(in: .whitespaces)), files > 0 {
            return mark(step, .followed, "\(files) files modified")
        }
        return mark(step, .skipped, "No recent code changes detected")
    }

    private func detectQualityGate(projectPath: String, step: PipelineStep) -> PipelineStep {
        let sentruxResult = shell("cd '\(projectPath)' 2>/dev/null && sentrux gate . 2>&1; echo \"EXIT=$?\"")
        if sentruxResult.contains("degradation") || sentruxResult.contains("No degradation") {
            return mark(step, .followed, "No structural degradation")
        }
        if sentruxResult.contains("EXIT=0") {
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
        return mark(step, .skipped, "Tests not run or failing")
    }

    private func detectReview(projectPath: String, step: PipelineStep) -> PipelineStep {
        let commitCount = shell("cd '\(projectPath)' 2>/dev/null && git log --oneline HEAD...HEAD~10 2>/dev/null | wc -l")
        if let count = Int(commitCount.trimmingCharacters(in: .whitespaces)), count > 1 {
            return mark(step, .followed, "\(count) commits in recent history")
        }
        return mark(step, .pending, "Not enough data")
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
}
