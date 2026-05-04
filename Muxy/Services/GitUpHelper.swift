import AppKit
import Foundation

enum GitUpHelper {
    static func openRepository(at path: String) {
        let fm = FileManager.default
        var isDirectory: ObjCBool = false
        guard fm.fileExists(atPath: path, isDirectory: &isDirectory), isDirectory.boolValue else {
            alert(message: "Directory not found", info: "The path \"\(path)\" does not exist or is not a directory.")
            return
        }

        let openURL = URL(fileURLWithPath: "/usr/bin/open")

        func tryOpen(appName: String) -> Bool {
            let process = Process()
            process.executableURL = openURL
            process.arguments = ["-a", appName, path]
            do {
                try process.run()
                process.waitUntilExit()
                return process.terminationStatus == 0
            } catch {
                return false
            }
        }

        if tryOpen(appName: "GitUp") { return }
        if tryOpen(appName: "Tower") { return }

        alert(
            message: "Git GUI Not Found",
            info: "Install GitUp (recommended) or Tower to open repositories from Muxy."
        )
    }

    private static func alert(message: String, info: String) {
        let alert = NSAlert()
        alert.messageText = message
        alert.informativeText = info
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}
