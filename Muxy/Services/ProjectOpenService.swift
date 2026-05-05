import AppKit

@MainActor
enum ProjectOpenService {
    static func openProject(
        appState: AppState,
        projectStore: ProjectStore,
        worktreeStore: WorktreeStore
    ) {
        let alert = NSAlert()
        alert.messageText = "Add Project"
        alert.informativeText = "Enter a name, git URL, or leave empty to browse:"
        alert.addButton(withTitle: "Add")
        alert.addButton(withTitle: "Browse…")
        alert.addButton(withTitle: "Cancel")

        let textField = NSTextField(frame: NSRect(x: 0, y: 0, width: 280, height: 22))
        textField.placeholderString = "Project name or git URL (e.g. git@github.com:user/repo.git)"
        alert.accessoryView = textField
        alert.window.initialFirstResponder = textField

        guard let window = NSApp.keyWindow ?? NSApp.mainWindow else { return }
        let response = alert.runModal()

        if response == .alertFirstButtonReturn {
            let rawInput = textField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if rawInput.isEmpty {
                browseAndAdd(appState: appState, projectStore: projectStore, worktreeStore: worktreeStore)
            } else if isGitURL(rawInput) {
                cloneAndAdd(rawInput, appState: appState, projectStore: projectStore, worktreeStore: worktreeStore)
            } else {
                createNamedProject(rawInput, appState: appState, projectStore: projectStore, worktreeStore: worktreeStore)
            }
        } else if response == .alertSecondButtonReturn {
            browseAndAdd(appState: appState, projectStore: projectStore, worktreeStore: worktreeStore)
        }
    }

    private static func isGitURL(_ input: String) -> Bool {
        input.hasPrefix("https://") || input.hasPrefix("git@") || input.hasPrefix("http://") || input.hasSuffix(".git")
    }

    private static func cloneAndAdd(
        _ url: String,
        appState: AppState,
        projectStore: ProjectStore,
        worktreeStore: WorktreeStore
    ) {
        let nameStr: String = if let parsed = URL(string: url)?.deletingPathExtension().lastPathComponent, !parsed.isEmpty {
            parsed
        } else if let last = url.split(separator: "/").last {
            last.split(separator: ".").first.map(String.init) ?? String(last)
        } else {
            "cloned-project"
        }

        let projectsDir = URL.homeDirectory.appendingPathComponent("Muxy", isDirectory: true)
        let projectURL = projectsDir.appendingPathComponent(nameStr, isDirectory: true)

        let progressAlert = NSAlert()
        progressAlert.messageText = "Cloning \(nameStr)…"
        progressAlert.informativeText = "Cloning repository, please wait…"
        progressAlert.addButton(withTitle: "Cancel")
        let indicator = NSProgressIndicator(frame: NSRect(x: 0, y: 0, width: 280, height: 16))
        indicator.style = .spinning
        indicator.startAnimation(nil)
        progressAlert.accessoryView = indicator

        Task {
            let task = Process()
            task.launchPath = "/usr/bin/git"
            task.arguments = ["clone", url, projectURL.path]
            let out = Pipe()
            task.standardOutput = out
            task.standardError = out
            try? task.run()

            await MainActor.run {
                NSApp.abortModal()
                progressAlert.window.orderOut(nil)
            }

            task.waitUntilExit()

            let success = task.terminationStatus == 0
            await MainActor.run {
                if success {
                    addProject(
                        name: nameStr,
                        path: projectURL.path,
                        appState: appState,
                        projectStore: projectStore,
                        worktreeStore: worktreeStore
                    )
                } else {
                    let data = out.fileHandleForReading.readDataToEndOfFile()
                    let output = String(data: data, encoding: .utf8) ?? "Unknown error"
                    let errorAlert = NSAlert()
                    errorAlert.messageText = "Clone Failed"
                    errorAlert.informativeText = output
                    errorAlert.addButton(withTitle: "OK")
                    errorAlert.runModal()
                }
            }
        }

        guard let window = NSApp.keyWindow ?? NSApp.mainWindow else { return }
        progressAlert.beginSheetModal(for: window) { _ in }
    }

    private static func createNamedProject(
        _ name: String,
        appState: AppState,
        projectStore: ProjectStore,
        worktreeStore: WorktreeStore
    ) {
        let projectsDir = URL.homeDirectory.appendingPathComponent("Muxy", isDirectory: true)
        let projectURL = projectsDir.appendingPathComponent(name, isDirectory: true)

        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: projectURL.path, isDirectory: &isDirectory)

        if exists {
            guard isDirectory.boolValue else {
                let errorAlert = NSAlert()
                errorAlert.messageText = "Cannot create project"
                errorAlert.informativeText = "A file already exists at the path."
                errorAlert.runModal()
                return
            }
        } else {
            do {
                try FileManager.default.createDirectory(at: projectsDir, withIntermediateDirectories: true)
                try FileManager.default.createDirectory(at: projectURL, withIntermediateDirectories: false)
            } catch {
                let errorAlert = NSAlert()
                errorAlert.messageText = "Failed to create project directory"
                errorAlert.informativeText = error.localizedDescription
                errorAlert.runModal()
                return
            }
        }

        addProject(name: name, path: projectURL.path, appState: appState, projectStore: projectStore, worktreeStore: worktreeStore)
    }

    private static func browseAndAdd(
        appState: AppState,
        projectStore: ProjectStore,
        worktreeStore: WorktreeStore
    ) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.message = "Select a project folder or git repository"
        guard panel.runModal() == .OK, let url = panel.url else { return }

        let folderName = url.lastPathComponent
        addProject(
            name: folderName,
            path: url.path(percentEncoded: false),
            appState: appState,
            projectStore: projectStore,
            worktreeStore: worktreeStore
        )
    }

    private static func addProject(
        name: String,
        path: String,
        appState: AppState,
        projectStore: ProjectStore,
        worktreeStore: WorktreeStore
    ) {
        let project = Project(
            name: name,
            path: path,
            sortOrder: projectStore.projects.count
        )
        projectStore.add(project)
        worktreeStore.ensurePrimary(for: project)
        guard let primary = worktreeStore.primary(for: project.id) else { return }
        appState.selectProject(project, worktree: primary)
    }
}
