//
//  RunHubApp.swift
//  RunHub
//
//  Created by Josh Luongo on 21/7/2026.
//

import SwiftUI
import AppKit
import Combine

@main
struct RunHubApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // The UI lives in an NSStatusItem + NSPopover managed by AppDelegate, so
        // the app needs no visible SwiftUI window. MenuBarExtra is intentionally
        // NOT used: its label is not reactive, so the status icon could not switch
        // between the Active and Inactive images.
        Settings { EmptyView() }
    }
}

/// Owns the status item (with a dynamic Active/Inactive icon), the popover that
/// hosts the SwiftUI panel, and app termination (the busy-quit confirmation).
final class AppDelegate: NSObject, NSApplicationDelegate {
    let manager = RunnerManager.shared
    private let updater = AppUpdater()

    private var statusItem: NSStatusItem?
    private let popover = NSPopover()
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Pre-warm the login-shell environment capture off the main thread so the
        // first runner launch (incl. launch-time auto-resume below) never blocks
        // the UI on shell startup.
        Task.detached(priority: .utility) { _ = LoginShellEnvironment.shared }

        // Establish a visible presence before initialising menu content, which
        // queries Service Management. Newer macOS versions manage invisible
        // background apps separately from apps with a menu bar icon.
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.target = self
        item.button?.action = #selector(togglePopover(_:))
        statusItem = item
        updateIcon(busy: isAnyBusy(manager.runners))

        popover.behavior = .transient
        popover.contentViewController = NSHostingController(
            rootView: MenuContentView(manager: manager, updater: updater))

        // Keep the menu bar icon in sync with runner status.
        manager.$runners
            .receive(on: RunLoop.main)
            .sink { [weak self] runners in
                self?.updateIcon(busy: self?.isAnyBusy(runners) ?? false)
            }
            .store(in: &cancellables)

        manager.resumeDesiredRunning()
        updater.start()
    }

    /// True when any runner is actively running a job (Busy).
    private func isAnyBusy(_ runners: [RunnerManager.Item]) -> Bool {
        runners.contains { if case .busy = $0.status { return true }; return false }
    }

    /// Swap the status-item image: Active while a job is running, else Inactive.
    private func updateIcon(busy: Bool) {
        let image = NSImage(named: busy ? "Active" : "Inactive")
        image?.isTemplate = true
        statusItem?.button?.image = image
    }

    @objc private func togglePopover(_ sender: NSStatusBarButton) {
        if popover.isShown {
            popover.performClose(sender)
        } else {
            popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard manager.hasRunningJob else { return .terminateNow }
        let alert = NSAlert()
        alert.messageText = "Stop running jobs?"
        alert.informativeText =
            "A runner is currently running a job. Quitting RunHub will stop it."
        alert.addButton(withTitle: "Quit and Stop")
        alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn ? .terminateNow : .terminateCancel
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Stop processes without clearing desiredRunning, so auto-resume is preserved.
        manager.stopAllProcesses()
    }
}
