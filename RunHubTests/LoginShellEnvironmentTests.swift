//
//  LoginShellEnvironmentTests.swift
//  RunHubTests
//
//  Pins the contract for LoginShellEnvironment.parse: the NUL-delimited `env -0`
//  parser. RED until parse() is implemented.
//

import Testing
@testable import RunHub

struct LoginShellEnvironmentTests {

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
