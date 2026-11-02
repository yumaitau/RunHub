//
//  LoginShellEnvironmentTests.swift
//  RunHubTests
//
//  Verify environment parsing and the background capture used during app launch.
//

import Testing
@testable import RunHub

struct LoginShellEnvironmentTests {

    @Test func environmentCanBeReadFromLaunchBackgroundTask() async {
        let environment = await Task.detached(priority: .utility) {
            LoginShellEnvironment.shared
        }.value
        #expect(environment["PATH"] != nil)
    }

    @Test func parsesNulDelimitedRecords() {
        let input = "PATH=/opt/homebrew/bin:/usr/bin\u{0}HOME=/Users/josh\u{0}"
        let env = LoginShellEnvironment.parse(input)
        #expect(env["PATH"] == "/opt/homebrew/bin:/usr/bin")
        #expect(env["HOME"] == "/Users/josh")
    }

    @Test func keepsEqualsSignsInsideValues() {
        // A value may contain '=' (e.g. a base64 token); split on the FIRST '=' only.
        let env = LoginShellEnvironment.parse("TOKEN=a=b=c\u{0}")
        #expect(env["TOKEN"] == "a=b=c")
    }

    @Test func skipsMalformedRecordsIncludingTrailingEmpty() {
        // "NOEQUALS" has no '='; the final NUL leaves an empty trailing record.
        let env = LoginShellEnvironment.parse("NOEQUALS\u{0}GOOD=1\u{0}")
        #expect(env["GOOD"] == "1")
        #expect(env["NOEQUALS"] == nil)
        #expect(env.count == 1)
    }

    @Test func emptyInputYieldsEmptyDictionary() {
        #expect(LoginShellEnvironment.parse("").isEmpty)
    }
}
