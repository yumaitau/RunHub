//
//  LoginItemTests.swift
//  RunHubTests
//
//  Unit-tests the pure status->enabled mapping via an injected status provider.
//  The register/unregister side effects need a real app bundle and are covered
//  by E2E TS-007.
//

import Testing
import ServiceManagement
@testable import RunHub

@MainActor
struct LoginItemTests {

    @Test func isEnabledOnlyWhenStatusIsEnabled() {
        #expect(LoginItem(statusProvider: { .enabled }).isEnabled == true)
        #expect(LoginItem(statusProvider: { .notRegistered }).isEnabled == false)
        #expect(LoginItem(statusProvider: { .requiresApproval }).isEnabled == false)
    }
}
