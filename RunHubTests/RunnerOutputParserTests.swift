//
//  RunnerOutputParserTests.swift
//  RunHubTests
//
//  Covers mapping run.sh stdout lines to status-transition events.
//

import Testing
@testable import RunHub

struct RunnerOutputParserTests {

    @Test func listeningLineMapsToListening() {
        #expect(RunnerOutputParser.event(for: "2026-07-21 10:00:00Z: Listening for Jobs")
                == .listening)
    }

    @Test func runningJobLineMapsToJobStartedWithName() {
        #expect(RunnerOutputParser.event(for: "2026-07-21 10:00:00Z: Running job: build-app")
                == .jobStarted("build-app"))
    }

    @Test func completedLineMapsToJobCompleted() {
        #expect(RunnerOutputParser.event(
            for: "2026-07-21 10:00:00Z: Job build-app completed with result: Succeeded")
                == .jobCompleted)
    }

    @Test func unrelatedLineMapsToNil() {
        #expect(RunnerOutputParser.event(for: "2026-07-21 10:00:00Z: Connected to GitHub") == nil)
    }
}
