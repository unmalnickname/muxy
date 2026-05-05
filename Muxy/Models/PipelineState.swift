import Foundation

@Observable
final class PipelineState {
    var validationPassed: Bool?
    var validationDetail: String?
    var validationOutput: String?
    var lastRun: Date?

    func refresh(projectPath: String) {
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
            lastRun = Date()
            validationOutput = output

            if let exitLine = output.components(separatedBy: .newlines).last(where: { $0.hasPrefix("EXIT_CODE=") }) {
                let code = exitLine.replacingOccurrences(of: "EXIT_CODE=", with: "").trimmingCharacters(in: .whitespaces)
                validationPassed = code == "0"
            } else {
                validationPassed = task.terminationStatus == 0
            }

            let lines = output.components(separatedBy: .newlines)
            if let resultsLine = lines.last(where: { $0.contains("passed") || $0.contains("Results") }) {
                let cleaned = resultsLine.replacingOccurrences(
                    of: "[^a-zA-Z0-9, ]",
                    with: "",
                    options: .regularExpression
                )
                validationDetail = cleaned.trimmingCharacters(in: .whitespaces)
            }
        } catch {
            validationPassed = nil
            validationDetail = nil
            validationOutput = nil
        }
    }
}
