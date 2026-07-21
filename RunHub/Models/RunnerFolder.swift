//
//  RunnerFolder.swift
//  RunHub
//
//  Validates that a folder contains an already-configured self-hosted runner.
//

import Foundation

/// Outcome of validating a candidate runner folder.
enum RunnerFolderValidation {
    case valid(RunnerFolder)
    case invalid(reason: String)
}

/// A validated runner folder: canonical location, its `run.sh`, parsed config,
/// and whether it is installed as a launchd service.
struct RunnerFolder: Equatable {
    /// Symlink-resolved folder path - the stable identity used for dedup/storage.
    let canonicalURL: URL
    let runScriptURL: URL
    let config: RunnerConfig
    /// True when a `.service` file is present (runner installed via `svc.sh`).
    let isInstalledAsService: Bool

    /// Validate that `folderURL` contains a configured runner. Valid only when
    /// `config.sh`, `.runner`, and a regular, executable `run.sh` all exist.
    static func validate(at folderURL: URL) -> RunnerFolderValidation {
        let fm = FileManager.default
        let canonical = URL(fileURLWithPath: folderURL.path).resolvingSymlinksInPath()

        let configScript = canonical.appendingPathComponent("config.sh")
        let runnerFile = canonical.appendingPathComponent(".runner")
        let runScript = canonical.appendingPathComponent("run.sh")

        guard fm.fileExists(atPath: configScript.path) else {
            return .invalid(reason: "Not a runner folder: config.sh is missing.")
        }
        guard fm.fileExists(atPath: runnerFile.path) else {
            return .invalid(reason: "Not a runner folder: .runner is missing.")
        }

        // run.sh must be a REGULAR file (attributesOfItem does not follow symlinks,
        // so a symlink reports .typeSymbolicLink and is rejected here) and executable.
        guard let attrs = try? fm.attributesOfItem(atPath: runScript.path),
              (attrs[.type] as? FileAttributeType) == .typeRegular else {
            return .invalid(reason: "run.sh is missing or not a regular file.")
        }
        guard fm.isExecutableFile(atPath: runScript.path) else {
            return .invalid(reason: "run.sh is not executable.")
        }

        let config: RunnerConfig
        do {
            config = try RunnerConfig.load(from: runnerFile)
        } catch {
            return .invalid(reason: "Could not read .runner: \(error.localizedDescription)")
        }

        let isService = fm.fileExists(
            atPath: canonical.appendingPathComponent(".service").path)

        return .valid(RunnerFolder(
            canonicalURL: canonical,
            runScriptURL: runScript,
            config: config,
            isInstalledAsService: isService
        ))
    }
}
