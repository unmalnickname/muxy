import AppKit

@MainActor
enum ProjectOpenService {
    static func openProject(
        appState: AppState,
        projectStore: ProjectStore,
        worktreeStore: WorktreeStore
    ) {
        let alert = NSAlert()
        alert.messageText = "New Project"
        alert.informativeText = "Enter a name for the project:"
        alert.addButton(withTitle: "Create")
        alert.addButton(withTitle: "Cancel")

        let textField = NSTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 22))
        textField.placeholderString = "Project name"
        alert.accessoryView = textField
        alert.window.initialFirstResponder = textField

        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let rawName = textField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rawName.isEmpty else {
            let err = NSAlert()
            err.messageText = "Invalid project name"
            err.informativeText = "Project name cannot be empty."
            err.runModal()
            return
        }

        let sanitized = rawName
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
        guard !sanitized.isEmpty else {
            let err = NSAlert()
            err.messageText = "Invalid project name"
            err.informativeText = "Project name contains only invalid characters."
            err.runModal()
            return
        }

        let projectsDir = URL.homeDirectory.appendingPathComponent("Muxy", isDirectory: true)
        let projectURL = projectsDir.appendingPathComponent(sanitized, isDirectory: true)

        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: projectURL.path, isDirectory: &isDirectory)

        if exists {
            guard isDirectory.boolValue else {
                let err = NSAlert()
                err.messageText = "Cannot create project"
                err.informativeText = "A file already exists at that path."
                err.runModal()
                return
            }
        } else {
            do {
                try FileManager.default.createDirectory(at: projectsDir, withIntermediateDirectories: true)
                try FileManager.default.createDirectory(at: projectURL, withIntermediateDirectories: false)
            } catch {
                let err = NSAlert()
                err.messageText = "Failed to create project directory"
                err.informativeText = error.localizedDescription
                err.runModal()
                return
            }
        }

        let project = Project(
            name: sanitized,
            path: projectURL.path(percentEncoded: false),
            sortOrder: projectStore.projects.count
        )
        projectStore.add(project)
        worktreeStore.ensurePrimary(for: project)
        guard let primary = worktreeStore.primary(for: project.id) else { return }
        appState.selectProject(project, worktree: primary)
    }
}
