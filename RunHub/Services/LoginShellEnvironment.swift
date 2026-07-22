//
//  LoginShellEnvironment.swift
//  RunHub
//
//  A menu-bar app launched from Finder/login-item inherits the sparse
//  LaunchServices environment (PATH=/usr/bin:/bin:/usr/sbin:/sbin), so a runner
//  we spawn - and its job steps - cannot find Homebrew/nvm/rbenv tools the way
//  they do from a terminal. The GitHub runner's own .env/.path files load fine
//  (they resolve relative to the runner binary), but they only carry what is
//  explicitly written in them; everything the user's login shell exports is
//  gone.
//
//  This captures the user's login+interactive shell environment ONCE (reading
//  stdout only, so the shell's startup noise on stderr - gitstatus, setopt
//  monitor, ... - is discarded) and hands it to the runner as its environment,
//  making a RunHub-launched runner behave like a terminal-launched one.
//
//  Why capture-once instead of wrapping run.sh in `$SHELL -ilc`: an interactive
//  shell enables job-control/monitor mode, which would fight RunHub's
//  kill(-pgid) process-group teardown, and its stderr noise would pollute the
//  status-parser stream. Capturing once sidesteps both.
//

import Foundation

enum LoginShellEnvironment {

    /// The captured login-shell environment, computed once and cached. Falls
    /// back to the current process environment if capture yields no PATH, so a
    /// capture failure degrades to today's behaviour rather than an empty env.
    static let shared: [String: String] = capture()

    /// Parse the NUL-delimited output of `env -0` into an environment dictionary.
    ///
    /// `env -0` emits one `KEY=VALUE` record per variable, each terminated by a
    /// NUL byte (`\0`). NUL-delimiting (rather than newline) is deliberate: a
    /// value may itself contain newlines, so only NUL is a safe record separator.
    /// Each record is split on the FIRST `=` only (values like base64 tokens
    /// legally contain `=`); records with no `=` - including the empty trailing
    /// record the final NUL leaves - are skipped.
    static func parse(_ env0Output: String) -> [String: String] {
        var env: [String: String] = [:]
        for record in env0Output.split(separator: "\u{0}") {
            guard let eq = record.firstIndex(of: "="), eq != record.startIndex else { continue }
            env[String(record[..<eq])] = String(record[record.index(after: eq)...])
        }
        return env
    }

    // MARK: Capture (implemented)

    private static func capture() -> [String: String] {
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: shell)
        // -i -l: interactive login shell, so it sources the same profile files a
        // Terminal does (.zprofile, .zshrc, ...) and picks up PATH set in either.
        // `command env -0` bypasses any `env` alias/function; -0 NUL-delimits.
        proc.arguments = ["-ilc", "command env -0"]

        let out = Pipe()
        proc.standardOutput = out
        proc.standardError = FileHandle.nullDevice   // discard interactive-shell noise

        do {
            try proc.run()
            let data = out.fileHandleForReading.readDataToEndOfFile()
            proc.waitUntilExit()
            let parsed = parse(String(decoding: data, as: UTF8.self))
            // Only trust a capture that actually produced a PATH.
            if parsed["PATH"] != nil { return parsed }
        } catch {
            // fall through to the safe fallback
        }
        return ProcessInfo.processInfo.environment
    }
}
