//
//  GitHubEnrichment.swift
//  RunHub
//
//  Optional, additive enrichment via the `gh` CLI: authoritative online/busy
//  state for repo- and org-level runners. Any failure returns nil - it never
//  blocks local flows.
//

import Foundation

/// Authoritative status for a runner, as GitHub sees it.
struct RunnerEnrichment: Equatable, Sendable {
    let isOnline: Bool
    let isBusy: Bool
}

/// Nonisolated so it can run off the main actor (it does blocking Process I/O).
nonisolated final class GitHubEnrichment {

    /// Runs `gh <args>` and returns stdout, or throws on failure.
    typealias CommandRunner = ([String]) throws -> Data

    private let run: CommandRunner

    init(run: @escaping CommandRunner = GitHubEnrichment.defaultRunner) {
        self.run = run
    }

    /// True when `gh` is installed and authenticated.
    func isAvailable() -> Bool {
        (try? run(["auth", "status"])) != nil
    }

    /// Fetch authoritative status for `runnerName`. Returns nil for enterprise/
    /// unknown registrations, or when `gh` is unavailable/fails.
    func enrich(registration: RunnerRegistration, runnerName: String) -> RunnerEnrichment? {
        let apiPath: String
        switch registration {
        case .repo(let owner, let repo):
            apiPath = "repos/\(owner)/\(repo)/actions/runners?per_page=100"
        case .org(let org):
            apiPath = "orgs/\(org)/actions/runners?per_page=100"
        case .enterprise, .unknown:
            return nil
        }
        guard let data = try? run(["api", apiPath]) else { return nil }
        return Self.parse(data, runnerName: runnerName)
    }

    // MARK: Parsing

    private struct APIRunner: Decodable {
        let name: String
        let status: String
        let busy: Bool
    }
    private struct APIResponse: Decodable {
        let runners: [APIRunner]
    }

    static func parse(_ data: Data, runnerName: String) -> RunnerEnrichment? {
        let decoder = JSONDecoder()
        let matches: (APIRunner) -> Bool = { $0.name == runnerName }

        if let response = try? decoder.decode(APIResponse.self, from: data),
           let match = response.runners.first(where: matches) {
            return RunnerEnrichment(isOnline: match.status == "online", isBusy: match.busy)
        }
        // Fallback: a bare array of runner objects.
        if let array = try? decoder.decode([APIRunner].self, from: data),
           let match = array.first(where: matches) {
            return RunnerEnrichment(isOnline: match.status == "online", isBusy: match.busy)
        }
        return nil
    }

    // MARK: Default gh invocation

    static func defaultRunner(_ args: [String]) throws -> Data {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["gh"] + args
        let stdout = Pipe()
        process.standardOutput = stdout
        process.standardError = Pipe()
        try process.run()
        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw NSError(domain: "gh", code: Int(process.terminationStatus))
        }
        return data
    }
}
