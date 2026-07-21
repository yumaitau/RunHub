//
//  MenuContentView.swift
//  RunHub
//
//  The menu bar panel: runner list (or empty state), add-by-folder, all-runner
//  controls, launch-at-login toggle, and quit.
//

import SwiftUI
import AppKit

struct MenuContentView: View {
    @ObservedObject var manager: RunnerManager
    @State private var loginItem = LoginItem()
    @State private var launchAtLogin = false

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

            Toggle("Launch RunHub at login", isOn: $launchAtLogin)
                .onChange(of: launchAtLogin) { _, newValue in setLaunchAtLogin(newValue) }

            Divider()

            Button("Quit RunHub") { NSApp.terminate(nil) }
        }
        .padding(12)
        .frame(width: 340)
        .onAppear { launchAtLogin = loginItem.isEnabled }
        .task { await manager.refreshEnrichment() }
    }

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
        do {
            if enabled { try loginItem.enable() } else { try loginItem.disable() }
        } catch {
            manager.lastMessage = "Launch-at-login change failed: \(error.localizedDescription)"
            launchAtLogin = loginItem.isEnabled
        }
    }
}
