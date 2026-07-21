//
//  RunnerConfig.swift
//  RunHub
//
//  Decodes a runner folder's `.runner` file and classifies its registration level.
//

import Foundation

/// Registration level of a self-hosted runner, derived from its `.runner` `gitHubUrl`.
///
/// Only `.repo` and `.org` are enriched via the GitHub API (Task 8); `.enterprise`
/// and `.unknown` fall back to local-only status.
enum RunnerRegistration: Codable, Equatable, Sendable {
    case repo(owner: String, repo: String)
    case org(String)
    case enterprise(String)
    case unknown

    /// Derive the registration from a runner's `gitHubUrl`
    /// (e.g. `https://github.com/owner/repo`, `.../org`, `.../enterprises/name`).
    init(gitHubUrl: String) {
        guard let url = URL(string: gitHubUrl) else {
            self = .unknown
            return
        }
        let parts = url.pathComponents.filter { $0 != "/" && !$0.isEmpty }
        if parts.count >= 2, parts[0].lowercased() == "enterprises" {
            self = .enterprise(parts[1])
        } else if parts.count >= 2 {
            self = .repo(owner: parts[0], repo: parts[1])
        } else if parts.count == 1 {
            self = .org(parts[0])
        } else {
            self = .unknown
        }
    }
}

/// The subset of a runner folder's `.runner` JSON that RunHub needs.
///
/// Decoded leniently: only `agentName` and `gitHubUrl` are read; other keys
/// (agentId, poolId, serverUrl, workFolder, ...) are ignored.
struct RunnerConfig: Decodable, Equatable {
    let name: String
    let gitHubUrl: String

    private enum CodingKeys: String, CodingKey {
        case agentName
        case gitHubUrl
    }

    init(name: String, gitHubUrl: String) {
        self.name = name
        self.gitHubUrl = gitHubUrl
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.name = try container.decode(String.self, forKey: .agentName)
        self.gitHubUrl = try container.decode(String.self, forKey: .gitHubUrl)
    }

    /// Registration level derived from `gitHubUrl`.
    var registration: RunnerRegistration {
        RunnerRegistration(gitHubUrl: gitHubUrl)
    }

    /// Parse the `.runner` JSON file at `runnerFileURL`.
    static func load(from runnerFileURL: URL) throws -> RunnerConfig {
        let data = try Data(contentsOf: runnerFileURL)
        return try JSONDecoder().decode(RunnerConfig.self, from: data)
    }
}
