//
//  LoginItem.swift
//  RunHub
//
//  Thin wrapper over SMAppService.mainApp for the launch-at-login toggle.
//  The status->enabled mapping is injectable for unit testing; the register/
//  unregister side effects are verified via E2E (TS-007).
//

import Foundation
import ServiceManagement

@MainActor
final class LoginItem {

    private let statusProvider: () -> SMAppService.Status

    init(statusProvider: @escaping () -> SMAppService.Status = { SMAppService.mainApp.status }) {
        self.statusProvider = statusProvider
    }

    /// True only when the app is registered and enabled as a login item.
    var isEnabled: Bool {
        statusProvider() == .enabled
    }

    func enable() throws {
        try SMAppService.mainApp.register()
    }

    func disable() throws {
        try SMAppService.mainApp.unregister()
    }
}
