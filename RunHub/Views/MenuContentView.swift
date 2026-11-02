//
//  MenuContentView.swift
//  RunHub
//
//  The menu bar panel: runner list (or empty state), add-by-folder, all-runner
//  controls, and an overflow menu (version, GitHub link, launch-at-login, quit).
//

import SwiftUI
import AppKit

struct MenuContentView: View {
    @ObservedObject var manager: RunnerManager
    @ObservedObject var updater: AppUpdater
    @StateObject private var loginItem = LoginItem()

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Self-Hosted Runners")
                .font(.headline)

            if manager.runners.isEmpty {
                Text("No runners - use Add Runner to adopt a configured runner folder.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.vertical, 6)
            } else {
                ForEach(manager.runners) { item in
                    RunnerRowView(item: item, manager: manager)
                }
            }

            if let message = manager.lastMessage {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider()

            HStack {
                Button("Add Runner") { addRunner() }
                Spacer()
                Button("Start All") { manager.startAll() }
                    .disabled(manager.runners.isEmpty)
                Button("Stop All") { manager.stopAll() }
                    .disabled(manager.runners.isEmpty)
            }

            Divider()

            if updater.updateAvailable {
                Button("Update Available…") { updater.checkForUpdates() }
                    .disabled(!updater.canCheckForUpdates)
            }

            HStack(alignment: .center) {
                Text("RunHub \(appVersion)")
                    .font(.caption)
                    .bold()
                    .opacity(0.75)
                Spacer()
                Menu {
                    Link("View on GitHub", destination: projectURL)
                    Button("Check for Updates…") { updater.checkForUpdates() }
                        .disabled(!updater.canCheckForUpdates)
                    Toggle("Automatically Check for Updates", isOn: Binding(
                        get: { updater.automaticallyChecksForUpdates },
                        set: { updater.setAutomaticallyChecksForUpdates($0) }))
                    Toggle("Automatically Download Updates", isOn: Binding(
                        get: { updater.automaticallyDownloadsUpdates },
                        set: { updater.setAutomaticallyDownloadsUpdates($0) }))
                        .disabled(!updater.automaticallyChecksForUpdates)
                    Divider()
                    Toggle("Launch RunHub at login", isOn: Binding(
                        get: { loginItem.isEnabled },
                        set: { setLaunchAtLogin($0) }))
                    if loginItem.requiresApproval {
                        Button("Approve Launch at Login…") { loginItem.openLoginItemsSettings() }
                        Button("Cancel Launch at Login Request") { setLaunchAtLogin(false) }
                    } else {
                        Button("Login Items Settings…") { loginItem.openLoginItemsSettings() }
                    }
                    Divider()
                    Button("Quit RunHub") { NSApp.terminate(nil) }
                } label: {
                    Image(systemName: "ellipsis")
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .accessibilityLabel("More options")
            }
        }
        .padding(12)
        .frame(width: 340)
        .onAppear { loginItem.refresh() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            loginItem.refresh()
        }
        .task { await manager.refreshEnrichment() }
    }

    /// Marketing version shown in the overflow menu, read from the app bundle
    /// (CFBundleShortVersionString == MARKETING_VERSION, e.g. "1.0.1").
    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
    }

    /// The project's GitHub page, opened from the overflow menu.
    private let projectURL = URL(string: "https://github.com/yumaitau/RunHub")!

    private func addRunner() {
        manager.lastMessage = nil
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Add Runner"
        panel.message = "Select a configured self-hosted runner folder."
        if panel.runModal() == .OK, let url = panel.url {
            manager.add(folderURL: url)
        }
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        manager.lastMessage = nil
        do {
            if enabled { try loginItem.enable() } else { try loginItem.disable() }
        } catch {
            manager.lastMessage = "Launch-at-login change failed: \(error.localizedDescription)"
        }
    }
}
