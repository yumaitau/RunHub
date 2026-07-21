//
//  RunnerManagerTests.swift
//  RunHubTests
//
//  Covers the coordinator: add/dedup/reject, intent-vs-shutdown split,
//  auto-resume, and remove. Uses an injected validator + fake process so no
//  real folders or processes are touched.
//

import Testing
import Foundation
@testable import RunHub

@MainActor
final class FakeProcess: RunnerProcessing {
    private(set) var status: RunnerStatus = .stopped {
        didSet { onStatusChange?(status) }
    }
    var onStatusChange: (@MainActor (RunnerStatus) -> Void)?
    private(set) var startCount = 0

    func start() { startCount += 1; status = .idle }
    func stop() { status = .stopped }
    func stopImmediately() { status = .stopped }
    func simulateBusy(_ job: String) { status = .busy(job: job) }
}

@MainActor
struct RunnerManagerTests {

    @Test func addValidPersistsAndCreatesStoppedItem() {
        let (mgr, url) = makeManager()
        defer { try? FileManager.default.removeItem(at: url) }

        mgr.add(folderURL: URL(fileURLWithPath: "/tmp/r1"))
        #expect(mgr.runners.count == 1)
        #expect(mgr.runners[0].status == .stopped)
        #expect(RunnerStore(fileURL: url).load().count == 1)
    }

    @Test func nonRunnerFolderIsRejected() {
        let (mgr, url) = makeManager(validate: { _ in .invalid(reason: "not a runner") })
        defer { try? FileManager.default.removeItem(at: url) }

        mgr.add(folderURL: URL(fileURLWithPath: "/tmp/bad"))
        #expect(mgr.runners.isEmpty)
        #expect(mgr.lastMessage != nil)
    }

    @Test func addDedupsByCanonicalPath() {
        let canonical = URL(fileURLWithPath: "/tmp/real")
        let (mgr, url) = makeManager(validate: { _ in .valid(Self.dummyFolder(canonical)) })
        defer { try? FileManager.default.removeItem(at: url) }

        mgr.add(folderURL: URL(fileURLWithPath: "/tmp/real"))
        mgr.add(folderURL: URL(fileURLWithPath: "/tmp/symlink-to-real"))
        #expect(mgr.runners.count == 1)
    }

    @Test func startSetsIntentAndIsIdempotent_stopClearsIntent() {
        let (mgr, url) = makeManager()
        defer { try? FileManager.default.removeItem(at: url) }

        mgr.add(folderURL: URL(fileURLWithPath: "/tmp/r1"))
        mgr.start(mgr.runners[0])
        #expect(mgr.runners[0].stored.desiredRunning == true)
        #expect(isActive(mgr.runners[0].status))

        let fake = mgr.runners[0].process as? FakeProcess
        mgr.start(mgr.runners[0])   // already running -> no-op
        #expect(fake?.startCount == 1)

        mgr.stop(mgr.runners[0])
        #expect(mgr.runners[0].stored.desiredRunning == false)
        #expect(mgr.runners[0].status == .stopped)
    }

    @Test func stopAllProcessesPreservesIntentAndResumeRestarts() {
        let (mgr, url) = makeManager()
        defer { try? FileManager.default.removeItem(at: url) }

        mgr.add(folderURL: URL(fileURLWithPath: "/tmp/r1"))
        mgr.add(folderURL: URL(fileURLWithPath: "/tmp/r2"))
        mgr.start(mgr.runners[0])   // r1 running + intent; r2 left stopped

        mgr.stopAllProcesses()      // quit path: stop processes, keep intent
        #expect(mgr.runners[0].stored.desiredRunning == true)
        #expect(mgr.runners[0].status == .stopped)
        mgr.stopAllProcesses()      // calling twice is safe

        mgr.resumeDesiredRunning()
        #expect(isActive(mgr.runners[0].status))     // r1 restarted
        #expect(mgr.runners[1].status == .stopped)   // r2 stays stopped
    }

    @Test func explicitStopAllThenResumeRestartsNothing() {
        let (mgr, url) = makeManager()
        defer { try? FileManager.default.removeItem(at: url) }

        mgr.add(folderURL: URL(fileURLWithPath: "/tmp/r1"))
        mgr.start(mgr.runners[0])
        mgr.stopAll()               // explicit: intent false for all
        mgr.resumeDesiredRunning()
        #expect(mgr.runners[0].status == .stopped)
    }

    @Test func hasRunningJobReflectsBusy() {
        let (mgr, url) = makeManager()
        defer { try? FileManager.default.removeItem(at: url) }

        mgr.add(folderURL: URL(fileURLWithPath: "/tmp/r1"))
        mgr.start(mgr.runners[0])
        #expect(mgr.hasRunningJob == false)
        (mgr.runners[0].process as? FakeProcess)?.simulateBusy("job1")
        #expect(mgr.hasRunningJob == true)
    }

    @Test func removeStopsUntracksAndKeepsStore() {
        let (mgr, url) = makeManager()
        defer { try? FileManager.default.removeItem(at: url) }

        mgr.add(folderURL: URL(fileURLWithPath: "/tmp/r1"))
        mgr.start(mgr.runners[0])
        let fake = mgr.runners[0].process as? FakeProcess
        mgr.remove(mgr.runners[0])
        #expect(mgr.runners.isEmpty)
        #expect(fake?.status == .stopped)
        #expect(RunnerStore(fileURL: url).load().isEmpty)
    }

    @Test func statusPropagatesWhenStoredPathDiffersFromValidatedCanonical() {
        // Regression: onStatusChange must key updates by the item's own id, not a
        // re-derived canonical path. When the stored path and the validator's
        // canonical path differ (path normalization), status must still propagate.
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("mgr-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        RunnerStore(fileURL: url).add(StoredRunner(folderPath: "/tmp/stored-path", name: "r",
                                                   registration: .unknown, desiredRunning: false))

        let mgr = RunnerManager(
            store: RunnerStore(fileURL: url),
            validate: { _ in .valid(RunnerManagerTests.dummyFolder(
                URL(fileURLWithPath: "/private/tmp/canonical-path"))) },
            processFactory: { _ in FakeProcess() },
            enrichmentProvider: { _, _ in nil })

        mgr.start(mgr.runners[0])
        #expect(isActive(mgr.runners[0].status))
    }

    @Test func refreshEnrichmentUpdatesItems() async {
        let (mgr, url) = makeManager(enrich: { _, _ in RunnerEnrichment(isOnline: true, isBusy: false) })
        defer { try? FileManager.default.removeItem(at: url) }

        mgr.add(folderURL: URL(fileURLWithPath: "/tmp/r1"))
        #expect(mgr.runners[0].enrichment == nil)
        await mgr.refreshEnrichment()
        #expect(mgr.runners[0].enrichment == RunnerEnrichment(isOnline: true, isBusy: false))
    }

    // MARK: Helpers

    private func isActive(_ status: RunnerStatus) -> Bool { status.isActive }

    private static func dummyFolder(_ url: URL) -> RunnerFolder {
        RunnerFolder(
            canonicalURL: url,
            runScriptURL: url.appendingPathComponent("run.sh"),
            config: RunnerConfig(name: url.lastPathComponent,
                                 gitHubUrl: "https://github.com/octo/hello"),
            isInstalledAsService: false)
    }

    private func makeManager(
        validate: @escaping @MainActor (URL) -> RunnerFolderValidation
            = { .valid(RunnerManagerTests.dummyFolder($0)) },
        enrich: @escaping @Sendable (RunnerRegistration, String) async -> RunnerEnrichment?
            = { _, _ in nil }
    ) -> (RunnerManager, URL) {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("mgr-\(UUID().uuidString).json")
        let mgr = RunnerManager(store: RunnerStore(fileURL: url),
                                validate: validate,
                                processFactory: { _ in FakeProcess() },
                                enrichmentProvider: enrich)
        return (mgr, url)
    }
}
