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

    private var statusItem: NSStatusItem?
    private let popover = NSPopover()
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(
            rootView: MenuContentView(manager: manager))

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.target = self
        item.button?.action = #selector(togglePopover(_:))
        statusItem = item
        updateIcon(active: isAnyActive(manager.runners))

        // Keep the menu bar icon in sync with runner status.
        manager.$runners
            .receive(on: RunLoop.main)
            .sink { [weak self] runners in
                self?.updateIcon(active: self?.isAnyActive(runners) ?? false)
            }
            .store(in: &cancellables)

        manager.resumeDesiredRunning()
    }

    private func isAnyActive(_ runners: [RunnerManager.Item]) -> Bool {
        runners.contains { $0.status.isActive }
    }

    /// Swap the status-item image between the Active and Inactive template assets.
    private func updateIcon(active: Bool) {
        let image = NSImage(named: active ? "Active" : "Inactive")
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
