//
//  RunnerStore.swift
//  RunHub
//
//  Persists the list of adopted runners across launches.
//

import Foundation

/// A persisted adopted runner. `folderPath` is the canonical (symlink-resolved)
/// path and the dedup/identity key. `desiredRunning` records user intent (set by
/// explicit Start/Stop) and is what auto-resume reads on launch.
struct StoredRunner: Codable, Equatable, Identifiable {
    let folderPath: String
    let name: String
    let registration: RunnerRegistration
    var desiredRunning: Bool

    var id: String { folderPath }
}

/// Codable JSON persistence for the adopted-runner list.
final class RunnerStore {
    private let fileURL: URL

    init(fileURL: URL) {
        self.fileURL = fileURL
    }

    /// Store rooted at `Application Support/RunHub/runners.json`.
    static func defaultStore() -> RunnerStore {
        let base = FileManager.default.urls(for: .applicationSupportDirectory,
                                            in: .userDomainMask)[0]
        return RunnerStore(fileURL: base.appendingPathComponent("RunHub/runners.json"))
    }

    func load() -> [StoredRunner] {
        guard let data = try? Data(contentsOf: fileURL),
              let runners = try? JSONDecoder().decode([StoredRunner].self, from: data) else {
            return []
        }
        return runners
    }

    func save(_ runners: [StoredRunner]) {
        let dir = fileURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        guard let data = try? JSONEncoder().encode(runners) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    /// Add a runner, deduplicating by canonical `folderPath`.
    func add(_ runner: StoredRunner) {
        var all = load()
        guard !all.contains(where: { $0.folderPath == runner.folderPath }) else { return }
        all.append(runner)
        save(all)
    }

    func remove(folderPath: String) {
        save(load().filter { $0.folderPath != folderPath })
    }

    func setDesiredRunning(folderPath: String, _ value: Bool) {
        var all = load()
        guard let index = all.firstIndex(where: { $0.folderPath == folderPath }) else { return }
        all[index].desiredRunning = value
        save(all)
    }
}
