//
//  RunnerManager.swift
//  RunHub
//
//  Central coordinator the UI binds to. Merges persisted runners with live
//  process status and exposes add/remove, start/stop, all-runner variants,
//  auto-resume, and a process-only stop-all for the quit path.
//

import Foundation
import Combine

@MainActor
final class RunnerManager: ObservableObject {

    /// One adopted runner: its persisted record, live status, and (when running)
    /// its supervising process.
    struct Item: Identifiable {
        var stored: StoredRunner
        var status: RunnerStatus
        var process: RunnerProcessing?
        /// Authoritative GitHub status (when `gh` enrichment is available), else nil.
        var enrichment: RunnerEnrichment?
        var id: String { stored.folderPath }
    }

    /// Shared instance so the App (menu bar label) and the AppDelegate
    /// (termination handling) observe the same manager.
    static let shared = RunnerManager()

    @Published private(set) var runners: [Item] = []
    /// Last user-facing message (rejection, already-added, service warning).
    @Published var lastMessage: String?

    private let store: RunnerStore
    private let validate: @MainActor (URL) -> RunnerFolderValidation
    private let processFactory: @MainActor (RunnerFolder) -> RunnerProcessing
    private let enrichmentProvider: @Sendable (RunnerRegistration, String) async -> RunnerEnrichment?

    init(store: RunnerStore = .defaultStore(),
         validate: @escaping @MainActor (URL) -> RunnerFolderValidation
            = { RunnerFolder.validate(at: $0) },
         processFactory: @escaping @MainActor (RunnerFolder) -> RunnerProcessing
            = { RunnerProcess(runScriptURL: $0.runScriptURL, workingDirectory: $0.canonicalURL) },
         enrichmentProvider: @escaping @Sendable (RunnerRegistration, String) async -> RunnerEnrichment?
            = { registration, name in
                // Run the blocking gh call off the main actor.
                await Task.detached {
                    GitHubEnrichment().enrich(registration: registration, runnerName: name)
                }.value
            }) {
        self.store = store
        self.validate = validate
        self.processFactory = processFactory
        self.enrichmentProvider = enrichmentProvider
        self.runners = store.load().map {
            Item(stored: $0, status: .stopped, process: nil)
        }
    }

    var hasRunningJob: Bool {
        runners.contains { if case .busy = $0.status { return true }; return false }
    }

    // MARK: Adoption

    func add(folderURL: URL) {
        switch validate(folderURL) {
        case .invalid(let reason):
            lastMessage = reason
        case .valid(let folder):
            let path = folder.canonicalURL.path
            guard !runners.contains(where: { $0.stored.folderPath == path }) else {
                lastMessage = "\(folder.config.name) is already added."
                return
            }
            let stored = StoredRunner(folderPath: path,
                                      name: folder.config.name,
                                      registration: folder.config.registration,
                                      desiredRunning: false)
            store.add(stored)
            runners.append(Item(stored: stored, status: .stopped, process: nil))
            if folder.isInstalledAsService {
                lastMessage = "\(folder.config.name) is installed as a launchd service. " +
                    "Run 'svc.sh uninstall' so RunHub can supervise it in-session."
            }
        }
    }

    func remove(_ item: Item) {
        guard let index = runners.firstIndex(where: { $0.id == item.id }) else { return }
        runners[index].process?.stop()
        store.remove(folderPath: item.stored.folderPath)
        runners.remove(at: index)
    }

    // MARK: Lifecycle (explicit user actions set intent)

    func start(_ item: Item) {
        setDesiredRunning(item.id, true)
        launch(item.id)
    }

    func stop(_ item: Item) {
        setDesiredRunning(item.id, false)
        guard let index = runners.firstIndex(where: { $0.id == item.id }) else { return }
        runners[index].process?.stop()
    }

    func startAll() { runners.forEach { start($0) } }
    func stopAll() { runners.forEach { stop($0) } }

    /// Quit path: stop every running process WITHOUT changing `desiredRunning`,
    /// so auto-resume still reflects user intent. Safe to call repeatedly.
    func stopAllProcesses() {
        for index in runners.indices {
            runners[index].process?.stopImmediately()
        }
    }

    /// Refresh authoritative GitHub status for every runner (additive; no-op when
    /// `gh` is unavailable or the registration is enterprise/unknown).
    func refreshEnrichment() async {
        for item in runners {
            if let result = await enrichmentProvider(item.stored.registration, item.stored.name) {
                applyEnrichment(id: item.id, result)
            }
        }
    }

    /// Launch-time auto-resume: start only runners the user left running.
    func resumeDesiredRunning() {
        for item in runners where item.stored.desiredRunning {
            launch(item.id)
        }
    }

    // MARK: Private

    private func setDesiredRunning(_ id: String, _ value: Bool) {
        guard let index = runners.firstIndex(where: { $0.id == id }) else { return }
        runners[index].stored.desiredRunning = value
        store.setDesiredRunning(folderPath: id, value)
    }

    private func launch(_ id: String) {
        guard let index = runners.firstIndex(where: { $0.id == id }) else { return }
        // Idempotent: already running -> no-op.
        if runners[index].process != nil, runners[index].status.isActive { return }

        // Revalidate the canonical folder before every launch so a swapped or
        // removed run.sh fails closed rather than executing.
        switch validate(URL(fileURLWithPath: runners[index].stored.folderPath)) {
        case .invalid(let reason):
            runners[index].status = .failed(reason: reason)
        case .valid(let folder):
            let process = processFactory(folder)
            // Key status updates by the item's own id, NOT a re-derived canonical
            // path (path normalization can differ and silently drop updates).
            process.onStatusChange = { [weak self] status in
                self?.updateStatus(id: id, status)
            }
            runners[index].process = process
            process.start()
        }
    }

    private func updateStatus(id: String, _ status: RunnerStatus) {
        guard let index = runners.firstIndex(where: { $0.id == id }) else { return }
        runners[index].status = status
    }

    private func applyEnrichment(id: String, _ enrichment: RunnerEnrichment) {
        guard let index = runners.firstIndex(where: { $0.id == id }) else { return }
        runners[index].enrichment = enrichment
    }

}
