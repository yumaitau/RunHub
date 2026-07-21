//
//  GitHubEnrichmentTests.swift
//  RunHubTests
//
//  Covers gh endpoint selection (repo vs org), busy parsing, and graceful
//  degradation, using an injected command runner (no real gh invocation).
//

import Testing
import Foundation
@testable import RunHub

@MainActor
struct GitHubEnrichmentTests {

    @Test func repoRegistrationHitsReposEndpoint() {
        var captured: [String] = []
        let service = GitHubEnrichment(run: { args in
            captured = args
            return Data("{\"runners\":[]}".utf8)
        })
        _ = service.enrich(registration: .repo(owner: "octo", repo: "hello"), runnerName: "r1")
        #expect(captured.contains { $0.contains("repos/octo/hello/actions/runners") })
    }

    @Test func orgRegistrationHitsOrgsEndpoint() {
        var captured: [String] = []
        let service = GitHubEnrichment(run: { args in
            captured = args
            return Data("{\"runners\":[]}".utf8)
        })
        _ = service.enrich(registration: .org("acme"), runnerName: "r1")
        #expect(captured.contains { $0.contains("orgs/acme/actions/runners") })
    }

    @Test func parsesMatchingRunnerStatusAndBusy() {
        let json = "{\"total_count\":1,\"runners\":[" +
            "{\"id\":1,\"name\":\"other\",\"os\":\"macos\",\"status\":\"offline\",\"busy\":false}," +
            "{\"id\":2,\"name\":\"r1\",\"os\":\"macos\",\"status\":\"online\",\"busy\":true}]}"
        let service = GitHubEnrichment(run: { _ in Data(json.utf8) })
        let result = service.enrich(registration: .repo(owner: "o", repo: "p"), runnerName: "r1")
        #expect(result == RunnerEnrichment(isOnline: true, isBusy: true))
    }

    @Test func enterpriseRegistrationReturnsNil() {
        let service = GitHubEnrichment(run: { _ in Data("{}".utf8) })
        #expect(service.enrich(registration: .enterprise("e"), runnerName: "r1") == nil)
    }

    @Test func failingGhReturnsNil() {
        let service = GitHubEnrichment(run: { _ in throw NSError(domain: "gh", code: 1) })
        #expect(service.enrich(registration: .repo(owner: "o", repo: "p"), runnerName: "r1") == nil)
    }
}
