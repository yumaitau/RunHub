//
//  RunnerStatus.swift
//  RunHub
//
//  The live status of a supervised runner and a pure parser that maps
//  run.sh stdout lines to status-transition events.
//

import Foundation

/// Live status of a supervised runner.
enum RunnerStatus: Equatable {
    case stopped
    case starting
    /// Online and listening for jobs (no job running).
    case idle
    /// Actively running a job of the given name.
    case busy(job: String)
    /// The runner process exited unexpectedly.
    case failed(reason: String)
}

extension RunnerStatus {
    /// True when the runner is starting, online-idle, or running a job.
    var isActive: Bool {
        switch self {
        case .starting, .idle, .busy: return true
        case .stopped, .failed: return false
        }
    }
}

/// A transition signalled by a line of runner output.
enum RunnerStatusEvent: Equatable {
    case listening
    case jobStarted(String)
    case jobCompleted
}

/// Pure mapping from a single stdout line to a status event.
///
/// Lines are timestamp-prefixed, so matching is tolerant (contains / prefix),
/// not exact. Non-status lines return `nil` (no transition).
enum RunnerOutputParser {
    static func event(for line: String) -> RunnerStatusEvent? {
        if line.contains("Listening for Jobs") {
            return .listening
        }
        if let range = line.range(of: "Running job: ") {
            let job = line[range.upperBound...]
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return .jobStarted(job)
        }
        if line.contains("Job ") && line.contains(" completed with result:") {
            return .jobCompleted
        }
        return nil
    }
}
