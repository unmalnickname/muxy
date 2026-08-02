import Foundation

@Observable
final class ProjectMonitorCoordinator: @unchecked Sendable {
    let pipeline = PipelineState()
    let health = ProjectHealthState()

    var isAutoRefreshing = false
    var lastAutoRefresh: Date?

    @ObservationIgnored private var watcher: GitDirectoryWatcher?
    @ObservationIgnored private var remoteChangeObserver: NSObjectProtocol?
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var activeProjectPath: String?

    private let refreshInterval: TimeInterval = 30

    func startMonitoring(projectPath: String) {
        guard activeProjectPath != projectPath else { return }
        stopMonitoring()
        activeProjectPath = projectPath

        // TODO: Re-enable monitoring after fixing freeze
        // installWatcher(projectPath: projectPath)
        // observeRemoteChanges(projectPath: projectPath)
        // startTimer()
        // refreshAll(includeSlow: false)
    }

    func stopMonitoring() {
        watcher = nil
        if let observer = remoteChangeObserver {
            NotificationCenter.default.removeObserver(observer)
            remoteChangeObserver = nil
        }
        stopTimer()
        activeProjectPath = nil
    }

    func refreshAll(includeSlow: Bool = true) {
        guard let path = activeProjectPath else { return }
        if includeSlow {
            pipeline.refresh(projectPath: path)
        }
        health.refresh(projectPath: path, includeSlow: includeSlow)
        lastAutoRefresh = Date()
    }

    func refreshPipeline() {
        // TODO: re-enable after fixing freeze
        // guard let path = activeProjectPath else { return }
        // pipeline.refresh(projectPath: path)
        // lastAutoRefresh = Date()
    }

    func refreshHealth() {
        // TODO: re-enable after fixing freeze
        // guard let path = activeProjectPath else { return }
        // health.forceRefresh(projectPath: path)
        // lastAutoRefresh = Date()
    }

    private func installWatcher(projectPath: String) {
        watcher = GitDirectoryWatcher(directoryPath: projectPath) { [weak self] in
            Task { @MainActor [weak self] in
                self?.refreshAll(includeSlow: false)
            }
        }
    }

    private func observeRemoteChanges(projectPath: String) {
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
                self?.refreshAll(includeSlow: false)
            }
        }
    }

    private func startTimer() {
        stopTimer()
        isAutoRefreshing = true
        timer = Timer.scheduledTimer(withTimeInterval: refreshInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refreshAll(includeSlow: false)
            }
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
        isAutoRefreshing = false
    }

    deinit {
        stopMonitoring()
    }
}
