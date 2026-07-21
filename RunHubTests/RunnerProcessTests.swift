//
//  RunnerProcessTests.swift
//  RunHubTests
//
//  Functional tests: spawn a fake run.sh, drive status from its stdout, and
//  prove stop() tears down the whole process group (including a grandchild).
//

import Testing
import Foundation
@testable import RunHub

@MainActor
final class StatusRecorder {
    private(set) var seen: [RunnerStatus] = []
    func record(_ s: RunnerStatus) { seen.append(s) }
    var sawBusy: Bool { seen.contains { if case .busy = $0 { return true }; return false } }
    var isFailed: Bool { if case .failed = seen.last { return true }; return false }
}

struct RunnerProcessTests {

    @Test func startDrivesStatusAndStopKillsProcessTree() async throws {
        let dir = try makeFixture(.busyCycle)
        defer { try? FileManager.default.removeItem(at: dir) }

        let proc = RunnerProcess(runScriptURL: dir.appendingPathComponent("run.sh"),
                                 workingDirectory: dir)
        let recorder = StatusRecorder()
        proc.onStatusChange = { recorder.record($0) }
        proc.start()

        // Idle -> Busy -> Idle as the fixture emits the standard lines.
        await waitUntil { recorder.sawBusy }
        await waitUntil { recorder.seen.last == .idle && recorder.sawBusy }
        #expect(recorder.sawBusy)
        #expect(recorder.seen.contains(.busy(job: "build-app")))

        // The grandchild the fixture spawned must be alive before stop().
        let grandchild = try readPID(dir.appendingPathComponent("grandchild.pid"))
        #expect(isAlive(grandchild))

        proc.stop()
        #expect(proc.status == .stopped)

        // Group kill must reap the grandchild too - no orphan.
        await waitUntil { !isAlive(grandchild) }
        #expect(!isAlive(grandchild))
    }

    @Test func stopImmediatelyTearsDownTreeSynchronously() async throws {
        let dir = try makeFixture(.busyCycle)
        defer { try? FileManager.default.removeItem(at: dir) }

        let proc = RunnerProcess(runScriptURL: dir.appendingPathComponent("run.sh"),
                                 workingDirectory: dir)
        proc.start()
        await waitUntil { (try? readPID(dir.appendingPathComponent("grandchild.pid"))) != nil }
        let grandchild = try readPID(dir.appendingPathComponent("grandchild.pid"))
        #expect(isAlive(grandchild))

        // stopImmediately() blocks until the group is gone (quit-path guarantee):
        // the grandchild must be dead by the time it returns, with no polling here.
        proc.stopImmediately()
        #expect(proc.status == .stopped)
        #expect(!isAlive(grandchild))
    }

    @Test func unexpectedExitBecomesFailedAndCanRestart() async throws {
        let dir = try makeFixture(.exitEarly)
        defer { try? FileManager.default.removeItem(at: dir) }

        let proc = RunnerProcess(runScriptURL: dir.appendingPathComponent("run.sh"),
                                 workingDirectory: dir)
        proc.start()

        await waitUntil { if case .failed = proc.status { return true }; return false }
        guard case .failed = proc.status else {
            Issue.record("expected .failed after unexpected exit, got \(proc.status)")
            return
        }

        // A subsequent start() must relaunch (not be a no-op stuck on .failed).
        proc.start()
        #expect(proc.status == .starting)
        proc.stop()
    }

    @Test func unlaunchableRunScriptFails() async throws {
        let dir = try makeFixture(.busyCycle)
        defer { try? FileManager.default.removeItem(at: dir) }

        let proc = RunnerProcess(runScriptURL: dir.appendingPathComponent("does-not-exist.sh"),
                                 workingDirectory: dir)
        proc.start()
        await waitUntil { if case .failed = proc.status { return true }; return false }
        #expect({ if case .failed = proc.status { return true }; return false }())
    }

    // MARK: Helpers

    private enum FixtureKind { case busyCycle, exitEarly }

    private func makeFixture(_ kind: FixtureKind) throws -> URL {
        let fm = FileManager.default
        let dir = fm.temporaryDirectory.appendingPathComponent("runhub-proc-\(UUID().uuidString)")
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)

        let script: String
        switch kind {
        case .busyCycle:
            script = """
            #!/bin/bash
            sleep 120 &
            echo $! > grandchild.pid
            echo "2026-07-21 00:00:00Z: Listening for Jobs"
            sleep 0.3
            echo "2026-07-21 00:00:01Z: Running job: build-app"
            sleep 0.3
            echo "2026-07-21 00:00:02Z: Job build-app completed with result: Succeeded"
            sleep 120
            """
        case .exitEarly:
            script = """
            #!/bin/bash
            echo "2026-07-21 00:00:00Z: Listening for Jobs"
            sleep 0.2
            exit 0
            """
        }

        let runSh = dir.appendingPathComponent("run.sh")
        try script.write(to: runSh, atomically: true, encoding: .utf8)
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: runSh.path)
        return dir
    }

    private func readPID(_ url: URL) throws -> pid_t {
        let text = try String(contentsOf: url, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let value = Int32(text) else {
            throw NSError(domain: "test", code: 1)
        }
        return value
    }

    private func isAlive(_ pid: pid_t) -> Bool { kill(pid, 0) == 0 }

    private func waitUntil(timeout: Duration = .seconds(8),
                           _ condition: @MainActor () -> Bool) async {
        let clock = ContinuousClock()
        let start = clock.now
        while !condition() {
            if clock.now - start > timeout { return }
            try? await Task.sleep(for: .milliseconds(20))
        }
    }
}
