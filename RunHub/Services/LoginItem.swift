//
//  LoginItem.swift
//  RunHub
//
//  Keep the launch-at-login control in sync with macOS approval and registration.
//

import Foundation
import ServiceManagement
import Combine

@MainActor
final class LoginItem: ObservableObject {

    @Published private(set) var status: SMAppService.Status
    private let statusProvider: () -> SMAppService.Status
    private let register: () throws -> Void
    private let unregister: () throws -> Void
    private let openSettings: () -> Void

    init(statusProvider: @escaping () -> SMAppService.Status = { SMAppService.mainApp.status },
         register: @escaping () throws -> Void = { try SMAppService.mainApp.register() },
         unregister: @escaping () throws -> Void = { try SMAppService.mainApp.unregister() },
         openSettings: @escaping () -> Void = { SMAppService.openSystemSettingsLoginItems() }) {
        self.statusProvider = statusProvider
        self.register = register
        self.unregister = unregister
        self.openSettings = openSettings
        self.status = statusProvider()
    }

    /// True only when the app is registered and enabled as a login item.
    var isEnabled: Bool {
        status == .enabled
    }

    var requiresApproval: Bool {
        status == .requiresApproval
    }

    /// Reading system state must never register or unregister the app.
    func refresh() {
        status = statusProvider()
    }

    func openLoginItemsSettings() {
        openSettings()
    }

    func enable() throws {
        refresh()
        guard !isEnabled else { return }
        // A disabled or pending item is already registered. macOS requires the
        // user to approve it in Settings; registering again cannot grant consent.
        if requiresApproval {
            openSettings()
            return
        }

        do {
            try register()
        } catch {
            refresh()
            guard requiresApproval else { throw error }
        }
        refresh()
        if requiresApproval {
            openSettings()
        } else if !isEnabled {
            throw RegistrationError.notEnabled
        }
    }

    func disable() throws {
        defer { refresh() }
        try unregister()
    }

    private enum RegistrationError: LocalizedError {
        case notEnabled

        var errorDescription: String? {
            "macOS has not enabled RunHub at login. Move RunHub to Applications and try again."
        }
    }
}
