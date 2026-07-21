//
//  RunnerFolderTests.swift
//  RunHubTests
//
//  Covers RunnerConfig registration parsing and RunnerFolder validation.
//

import Testing
import Foundation
@testable import RunHub

struct RunnerFolderTests {

    // MARK: Registration parsing

    @Test func repoUrlParsesToRepo() {
        #expect(RunnerRegistration(gitHubUrl: "https://github.com/octo/hello")
                == .repo(owner: "octo", repo: "hello"))
    }

    @Test func orgUrlParsesToOrg() {
        #expect(RunnerRegistration(gitHubUrl: "https://github.com/my-org") == .org("my-org"))
    }

    @Test func enterpriseUrlParsesToEnterprise() {
        #expect(RunnerRegistration(gitHubUrl: "https://github.com/enterprises/acme")
                == .enterprise("acme"))
    }

    // MARK: Folder validation

    @Test func validFolderValidates() throws {
        let dir = try makeRunnerFolder()
        defer { try? FileManager.default.removeItem(at: dir) }

        guard case .valid(let folder) = RunnerFolder.validate(at: dir) else {
            Issue.record("expected valid folder")
            return
        }
        #expect(folder.config.name == "runner-1")
        #expect(folder.config.registration == .repo(owner: "octo", repo: "hello"))
        #expect(folder.isInstalledAsService == false)
    }

    @Test func missingRunShIsRejected() throws {
        let dir = try makeRunnerFolder(includeRunSh: false)
        defer { try? FileManager.default.removeItem(at: dir) }
        #expect(isInvalid(RunnerFolder.validate(at: dir)))
    }

    @Test func nonExecutableRunShIsRejected() throws {
        let dir = try makeRunnerFolder(runShExecutable: false)
        defer { try? FileManager.default.removeItem(at: dir) }
        #expect(isInvalid(RunnerFolder.validate(at: dir)))
    }

    @Test func missingConfigShIsRejected() throws {
        let dir = try makeRunnerFolder(includeConfigSh: false)
        defer { try? FileManager.default.removeItem(at: dir) }
        #expect(isInvalid(RunnerFolder.validate(at: dir)))
    }

    @Test func symlinkedRunShIsRejected() throws {
        let dir = try makeRunnerFolder(includeRunSh: false)
        defer { try? FileManager.default.removeItem(at: dir) }

        // Create a real executable elsewhere in the folder, then symlink run.sh to it.
        let fm = FileManager.default
        let target = dir.appendingPathComponent("real-run.sh")
        try "#!/bin/bash\necho hi\n".write(to: target, atomically: true, encoding: .utf8)
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: target.path)
        try fm.createSymbolicLink(at: dir.appendingPathComponent("run.sh"),
                                  withDestinationURL: target)

        #expect(isInvalid(RunnerFolder.validate(at: dir)))
    }

    @Test func serviceFileIsDetected() throws {
        let dir = try makeRunnerFolder(includeService: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        guard case .valid(let folder) = RunnerFolder.validate(at: dir) else {
            Issue.record("expected valid folder")
            return
        }
        #expect(folder.isInstalledAsService == true)
    }

    // MARK: Helpers

    private func isInvalid(_ result: RunnerFolderValidation) -> Bool {
        if case .invalid = result { return true }
        return false
    }

    private func makeRunnerFolder(
        gitHubUrl: String = "https://github.com/octo/hello",
        name: String = "runner-1",
        includeConfigSh: Bool = true,
        includeRunSh: Bool = true,
        runShExecutable: Bool = true,
        includeService: Bool = false
    ) throws -> URL {
        let fm = FileManager.default
        let dir = fm.temporaryDirectory.appendingPathComponent("runhub-test-\(UUID().uuidString)")
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)

        if includeConfigSh {
            try "#!/bin/bash\n".write(to: dir.appendingPathComponent("config.sh"),
                                      atomically: true, encoding: .utf8)
        }

        let runnerJSON = "{\"agentId\":1,\"agentName\":\"\(name)\"," +
            "\"gitHubUrl\":\"\(gitHubUrl)\",\"workFolder\":\"_work\"}"
        try runnerJSON.write(to: dir.appendingPathComponent(".runner"),
                             atomically: true, encoding: .utf8)

        if includeRunSh {
            let runSh = dir.appendingPathComponent("run.sh")
            try "#!/bin/bash\necho hi\n".write(to: runSh, atomically: true, encoding: .utf8)
            try fm.setAttributes([.posixPermissions: runShExecutable ? 0o755 : 0o644],
                                 ofItemAtPath: runSh.path)
        }

        if includeService {
            try "actions.runner.octo-hello.runner-1"
                .write(to: dir.appendingPathComponent(".service"),
                       atomically: true, encoding: .utf8)
        }

        return dir
    }
}
