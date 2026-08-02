import Foundation

struct ShellResult {
    let output: String
    let exitCode: Int32
}

enum ShellRunner {
    private static var bashPath: String {
        GitProcessRunner.resolveExecutable("bash") ?? "/usr/bin/env"
    }

    static func run(
        _ command: String,
        workingDirectory: String? = nil,
        timeout: TimeInterval = 30
    ) -> ShellResult {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: bashPath)
        task.arguments = ["-c", command]

        if let dir = workingDirectory {
            task.currentDirectoryURL = URL(fileURLWithPath: dir)
        }

        let out = Pipe()
        task.standardOutput = out
        task.standardError = out

        do {
            try task.run()
        } catch {
            return ShellResult(output: "launch failed: \(error.localizedDescription)", exitCode: -1)
        }

        task.waitUntilExit()
        let data = out.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return ShellResult(output: output, exitCode: task.terminationStatus)
    }

    @discardableResult
    static func runAction(_ command: String, workingDirectory: String? = nil) -> Bool {
        run(command, workingDirectory: workingDirectory).exitCode == 0
    }

    static func runWithOutput(
        _ command: String,
        workingDirectory: String? = nil
    ) -> String {
        let result = run(command, workingDirectory: workingDirectory)
        return result.exitCode == 0 ? "OK" : "Failed: \(result.output.prefix(200))"
    }

    static func runTool(_ name: String, arguments: [String]) -> (installed: Bool, version: String?) {
        guard let path = GitProcessRunner.resolveExecutable(name) else {
            return (installed: false, version: nil)
        }
        let task = Process()
        task.executableURL = URL(fileURLWithPath: path)
        task.arguments = arguments
        let out = Pipe()
        task.standardOutput = out
        task.standardError = out
        do {
            try task.run()
            task.waitUntilExit()
            let data = out.fileHandleForReading.readDataToEndOfFile()
            let version = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            let installed = task.terminationStatus == 0 && !(version?.isEmpty ?? true)
            return (installed: installed, version: version)
        } catch {
            return (installed: false, version: nil)
        }
    }
}
