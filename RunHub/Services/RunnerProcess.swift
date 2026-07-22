//
//  RunnerProcess.swift
//  RunHub
//
//  Spawns a runner's run.sh as an in-session child, streams its stdout through
//  the status parser, and tears down the whole process group on stop.
//

import Foundation

/// Abstraction over a supervised runner process so `RunnerManager` can inject a
/// fake in tests instead of spawning real processes.
@MainActor
protocol RunnerProcessing: AnyObject {
    var status: RunnerStatus { get }
    var onStatusChange: (@MainActor (RunnerStatus) -> Void)? { get set }
    func start()
    /// Interactive stop: signal the group, escalate to SIGKILL asynchronously
    /// (keeps the UI responsive).
    func stop()
    /// Quit-path stop: signal the group and BLOCK until it exits (bounded),
    /// force-killing if needed, so kill signals are delivered before the app exits.
    func stopImmediately()
}

@MainActor
final class RunnerProcess: RunnerProcessing {

    private(set) var status: RunnerStatus = .stopped {
        didSet { if status != oldValue { onStatusChange?(status) } }
    }
    var onStatusChange: (@MainActor (RunnerStatus) -> Void)?

    private let runScriptURL: URL
    private let workingDirectory: URL
    private var process: Process?
    private var readBuffer = Data()
    private var stopRequested = false

    init(runScriptURL: URL, workingDirectory: URL) {
        self.runScriptURL = runScriptURL
        self.workingDirectory = workingDirectory
    }

    func start() {
        guard process == nil else { return }   // idempotent: already running
        stopRequested = false
        readBuffer.removeAll(keepingCapacity: true)
        status = .starting

        let proc = Process()
        // Launch run.sh in a NEW session/process group (POSIX::setsid) so that
        // Runner.Listener / Runner.Worker descendants can be torn down as a group.
        // macOS ships no setsid(1), so perl's POSIX::setsid is the portable lever.
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        proc.arguments = ["-e", "use POSIX; POSIX::setsid(); exec(@ARGV) or die $!;",
                          runScriptURL.path]
        proc.currentDirectoryURL = workingDirectory
        // Hand the runner the user's login-shell environment. Without this it
        // inherits RunHub's sparse Finder/LaunchServices env (PATH=/usr/bin:...),
        // so job steps can't find Homebrew/nvm/rbenv tools - see
        // LoginShellEnvironment for the full rationale.
        proc.environment = LoginShellEnvironment.shared

        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = pipe
        // SHORTCUT: line-buffered Pipe read; upgrade to a PTY if run.sh block-buffers
        // off-TTY and status lag is observed in TS-002.
        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            Task { @MainActor in self?.ingest(data) }
        }
        proc.terminationHandler = { [weak self] finished in
            let code = finished.terminationStatus
            Task { @MainActor in self?.handleTermination(code: code) }
        }

        do {
            try proc.run()
            process = proc
        } catch {
            process = nil
            status = .failed(reason: "Could not launch run.sh: \(error.localizedDescription)")
        }
    }

    func stop() {
        stopRequested = true
        guard let proc = process, proc.isRunning else {
            process = nil
            status = .stopped
            return
        }
        // processIdentifier is the setsid group leader -> negative pid signals the
        // whole group (run.sh + Listener + Worker). SIGTERM first, then SIGKILL.
        let pgid = proc.processIdentifier
        kill(-pgid, SIGTERM)
        DispatchQueue.global().asyncAfter(deadline: .now() + 3) {
            kill(-pgid, SIGKILL)
        }
        process = nil
        status = .stopped
    }

    /// Quit-path teardown: send SIGTERM, wait (bounded) for the group to exit,
    /// then SIGKILL any survivors - all synchronously, so the signals are
    /// delivered before AppKit tears down the host process (no orphans).
    func stopImmediately() {
        stopRequested = true
        guard let proc = process, proc.isRunning else {
            process = nil
            status = .stopped
            return
        }
        let pgid = proc.processIdentifier
        kill(-pgid, SIGTERM)
        var waitedMs = 0
        while kill(-pgid, 0) == 0 && waitedMs < 2000 {
            usleep(50_000)   // 50ms
            waitedMs += 50
        }
        if kill(-pgid, 0) == 0 { kill(-pgid, SIGKILL) }
        process = nil
        status = .stopped
    }

    // MARK: Private

    private func ingest(_ data: Data) {
        readBuffer.append(data)
        while let newline = readBuffer.firstIndex(of: 0x0A) {
            let lineData = readBuffer.subdata(in: readBuffer.startIndex..<newline)
            readBuffer.removeSubrange(readBuffer.startIndex...newline)
            guard let line = String(data: lineData, encoding: .utf8) else { continue }
            apply(RunnerOutputParser.event(for: line))
        }
    }

    private func apply(_ event: RunnerStatusEvent?) {
        guard let event else { return }
        // Ignore late output after a requested stop.
        guard !stopRequested else { return }
        switch event {
        case .listening: status = .idle
        case .jobStarted(let job): status = .busy(job: job)
        case .jobCompleted: status = .idle
        }
    }

    private func handleTermination(code: Int32) {
        process = nil
        if stopRequested {
            status = .stopped
        } else {
            status = .failed(reason: "Runner exited unexpectedly (code \(code)).")
        }
    }
}
