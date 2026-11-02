//
//  LoginItemTests.swift
//  RunHubTests
//
//  Exercise login-item transitions without changing the Mac's login items.
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
        #expect(LoginItem(statusProvider: { .notFound }).isEnabled == false)
    }

    @Test func registrationRequiringApprovalOpensSettings() throws {
        var status: SMAppService.Status = .notRegistered
        var settingsOpened = false
        let item = LoginItem(statusProvider: { status }, register: {
            status = .requiresApproval
        }, openSettings: { settingsOpened = true })

        try item.enable()

        #expect(!item.isEnabled)
        #expect(item.requiresApproval)
        #expect(settingsOpened)
    }

    @Test func pendingApprovalDoesNotRegisterAgain() throws {
        var registrations = 0
        var settingsOpened = false
        let item = LoginItem(statusProvider: { .requiresApproval }, register: {
            registrations += 1
        }, openSettings: { settingsOpened = true })

        try item.enable()

        #expect(registrations == 0)
        #expect(settingsOpened)
    }

    @Test func enablingAnEnabledItemDoesNotRegisterAgain() throws {
        var registrations = 0
        let item = LoginItem(statusProvider: { .enabled }, register: { registrations += 1 })
        try item.enable()
        #expect(registrations == 0)
        #expect(item.isEnabled)
    }

    @Test func refreshReflectsExternalChangesWithoutWritingRegistration() {
        var status: SMAppService.Status = .enabled
        var writes = 0
        let item = LoginItem(statusProvider: { status }, register: { writes += 1 },
                             unregister: { writes += 1 })

        status = .requiresApproval
        item.refresh()
        #expect(!item.isEnabled)
        #expect(item.requiresApproval)

        status = .enabled
        item.refresh()
        #expect(item.isEnabled)
        #expect(!item.requiresApproval)
        #expect(writes == 0)
    }

    private enum TestError: Error { case failed }

    @Test func failedRegistrationRefreshesStatusAndPropagatesError() {
        let item = LoginItem(statusProvider: { .notRegistered }, register: { throw TestError.failed })
        #expect(throws: TestError.failed) { try item.enable() }
        #expect(!item.isEnabled)
    }

    @Test func approvalRequiredAfterRegistrationErrorStillOpensSettings() throws {
        var status: SMAppService.Status = .notRegistered
        var settingsOpened = false
        let item = LoginItem(statusProvider: { status }, register: {
            status = .requiresApproval
            throw TestError.failed
        }, openSettings: { settingsOpened = true })
        try item.enable()
        #expect(item.requiresApproval)
        #expect(settingsOpened)
    }

    @Test func successfulRegistrationRefreshesEnabledState() throws {
        var status: SMAppService.Status = .notRegistered
        let item = LoginItem(statusProvider: { status }, register: { status = .enabled })
        try item.enable()
        #expect(item.isEnabled)
    }

    @Test func registrationWithoutEnabledStatusReportsFailure() {
        let item = LoginItem(statusProvider: { .notRegistered }, register: {})
        #expect(throws: (any Error).self) { try item.enable() }
        #expect(!item.isEnabled)
    }

    @Test func missingRegistrationCanBeRegisteredAgain() throws {
        var status: SMAppService.Status = .notFound
        let item = LoginItem(statusProvider: { status }, register: { status = .enabled })
        try item.enable()
        #expect(item.isEnabled)
    }

    @Test func disablingPendingApprovalUnregisters() throws {
        var status: SMAppService.Status = .requiresApproval
        let item = LoginItem(statusProvider: { status }, unregister: { status = .notRegistered })
        try item.disable()
        #expect(!item.requiresApproval)
        #expect(!item.isEnabled)
    }

    @Test func failedUnregistrationPreservesEnabledState() {
        let item = LoginItem(statusProvider: { .enabled }, unregister: { throw TestError.failed })
        #expect(throws: TestError.failed) { try item.disable() }
        #expect(item.isEnabled)
    }
}
