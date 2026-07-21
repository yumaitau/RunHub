//
//  RunnerRowView.swift
//  RunHub
//
//  One row in the runner overview: status badge, name/repo, current job, and
//  Start/Stop plus Remove controls.
//

import SwiftUI

struct RunnerRowView: View {
    let item: RunnerManager.Item
    @ObservedObject var manager: RunnerManager

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(badgeColor)
                .frame(width: 9, height: 9)

            VStack(alignment: .leading, spacing: 1) {
                Text(item.stored.name)
                Text(registrationText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if case .busy(let job) = item.status {
                    Text("Running: \(job)")
                        .font(.caption)
                        .foregroundStyle(.blue)
                }
                if case .failed(let reason) = item.status {
                    Text(reason)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                if let enrichment = item.enrichment {
                    Text(enrichmentText(enrichment))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            if isRunning {
                Button("Stop") { manager.stop(item) }
            } else {
                Button("Start") { manager.start(item) }
            }

            Button {
                manager.remove(item)
            } label: {
                Image(systemName: "trash")
            }
            .help("Remove from RunHub (does not delete files or deregister)")
        }
        .padding(.vertical, 2)
    }

    private var isRunning: Bool { item.status.isActive }

    private var badgeColor: Color {
        switch item.status {
        case .stopped: return .gray
        case .starting: return .yellow
        case .idle: return .green
        case .busy: return .blue
        case .failed: return .red
        }
    }

    private func enrichmentText(_ enrichment: RunnerEnrichment) -> String {
        guard enrichment.isOnline else { return "GitHub: offline" }
        return enrichment.isBusy ? "GitHub: online, busy" : "GitHub: online"
    }

    private var registrationText: String {
        switch item.stored.registration {
        case .repo(let owner, let repo): return "\(owner)/\(repo)"
        case .org(let org): return org
        case .enterprise(let name): return "enterprise: \(name)"
        case .unknown: return "unknown"
        }
    }
}
