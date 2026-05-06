import Foundation
import Testing

@Suite("Architecture Lint")
struct MuxyArchitectureLint {
    @Test("project directories exist")
    func test_project_structure_exists() {
        let testPath = #filePath
        let basePath = (testPath as NSString).deletingLastPathComponent
            .replacingOccurrences(of: "Tests/MuxyTests/Lint", with: "")

        let required = ["Muxy", "MuxyShared", "MuxyServer", "GhosttyKit"]
        for dir in required {
            let path = (basePath as NSString).appendingPathComponent(dir)
            #expect(FileManager.default.fileExists(atPath: path))
        }
    }

    @Test("required config files exist")
    func test_required_config_files_exist() {
        let testPath = #filePath
        let basePath = (testPath as NSString).deletingLastPathComponent
            .replacingOccurrences(of: "Tests/MuxyTests/Lint", with: "")

        let configs = [".swiftformat", ".swiftlint.yml", ".sentrux/rules.toml", ".archon/config.yaml"]
        for config in configs {
            let path = (basePath as NSString).appendingPathComponent(config)
            #expect(FileManager.default.fileExists(atPath: path), "Missing: \(config)")
        }
    }

    @Test("no debug prints in production")
    func test_no_debug_print_in_production() {
        let testPath = #filePath
        let basePath = (testPath as NSString).deletingLastPathComponent
            .replacingOccurrences(of: "Tests/MuxyTests/Lint", with: "Muxy")

        let sources = (try? FileManager.default.contentsOfDirectory(atPath: basePath))?
            .filter { $0.hasSuffix(".swift") }
            .map { (basePath as NSString).appendingPathComponent($0) } ?? []

        for path in sources {
            let content = try? String(contentsOfFile: path, encoding: .utf8)
            #expect(!(content?.contains("print(\"DEBUG") ?? false), "DEBUG print in \((path as NSString).lastPathComponent)")
        }
    }
}