//
//  RunnerStoreTests.swift
//  RunHubTests
//
//  Covers persistence of adopted runners (round-trip, dedup, remove, intent flag).
//

import Testing
import Foundation
@testable import RunHub

struct RunnerStoreTests {

    @Test func addPersistsAndReloadsAllFields() {
        let url = tempFile()
        defer { try? FileManager.default.removeItem(at: url) }

        let store = RunnerStore(fileURL: url)
        let runner = StoredRunner(folderPath: "/tmp/r1", name: "r1",
                                  registration: .repo(owner: "octo", repo: "hello"),
                                  desiredRunning: true)
        store.add(runner)

        // A fresh instance reading the same file returns the runner intact.
        let reloaded = RunnerStore(fileURL: url).load()
        #expect(reloaded == [runner])
    }

    @Test func addIsIdempotentByFolderPath() {
        let url = tempFile()
        defer { try? FileManager.default.removeItem(at: url) }

        let store = RunnerStore(fileURL: url)
        let runner = StoredRunner(folderPath: "/tmp/r1", name: "r1",
                                  registration: .org("acme"), desiredRunning: false)
        store.add(runner)
        store.add(runner)
        #expect(store.load().count == 1)
    }

    @Test func removeDropsTheRunner() {
        let url = tempFile()
        defer { try? FileManager.default.removeItem(at: url) }

        let store = RunnerStore(fileURL: url)
        store.add(StoredRunner(folderPath: "/tmp/r1", name: "r1",
                               registration: .unknown, desiredRunning: false))
        store.remove(folderPath: "/tmp/r1")
        #expect(store.load().isEmpty)
    }

    @Test func setDesiredRunningPersistsIntent() {
        let url = tempFile()
        defer { try? FileManager.default.removeItem(at: url) }

        let store = RunnerStore(fileURL: url)
        store.add(StoredRunner(folderPath: "/tmp/r1", name: "r1",
                               registration: .unknown, desiredRunning: false))
        store.setDesiredRunning(folderPath: "/tmp/r1", true)
        #expect(store.load().first?.desiredRunning == true)
    }

    private func tempFile() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("runhub-store-\(UUID().uuidString).json")
    }
}
