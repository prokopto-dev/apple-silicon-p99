import P99Core
import SwiftUI

/// "Check for updates" for the installer app itself. Lists every release the
/// user is missing, each with its changelog notes (the release pipeline makes
/// GitHub Release bodies == CHANGELOG.md sections, so this is authoritative).
@MainActor
struct AppUpdatesSheet: View {
    @Environment(InstallerModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Installer Updates")
                    .font(.title2.bold())
                Spacer()
                Text("you have v\(InstallerModel.appVersion)")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            content
            HStack {
                Button("Close") { dismiss() }
                Spacer()
                if case .available(let releases) = model.appUpdateState,
                   let latest = releases.first {
                    Button("Open Download Page for \(latest.tag)") {
                        NSWorkspace.shared.open(latest.url)
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding(20)
        .frame(width: 560, height: 460)
        .task { await model.checkAppUpdates() }
    }

    @ViewBuilder
    private var content: some View {
        switch model.appUpdateState {
        case .idle, .checking:
            Spacer()
            HStack {
                Spacer()
                SwiftUI.ProgressView("Checking GitHub for newer releases…")
                Spacer()
            }
            Spacer()
        case .upToDate:
            Spacer()
            HStack {
                Spacer()
                Label("You're on the latest installer.", systemImage: "checkmark.seal.fill")
                    .font(.headline)
                    .foregroundStyle(.green)
                Spacer()
            }
            Spacer()
        case .failed(let message):
            Spacer()
            VStack(spacing: 6) {
                Label("Couldn't check for updates", systemImage: "wifi.exclamationmark")
                    .font(.headline)
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Button("Try Again") { Task { await model.checkAppUpdates() } }
            }
            .frame(maxWidth: .infinity)
            Spacer()
        case .available(let releases):
            Text("\(releases.count) newer release\(releases.count == 1 ? "" : "s") since your version — what you're missing:")
                .font(.callout)
                .foregroundStyle(.secondary)
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(releases) { release in
                        GroupBox {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(release.tag)
                                    .font(.headline)
                                Text(cleaned(release.notes))
                                    .font(.callout)
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .padding(6)
                        }
                    }
                }
            }
        }
    }

    /// Light markdown cleanup so raw changelog text reads well in a Text view.
    private func cleaned(_ notes: String) -> String {
        notes
            .replacingOccurrences(of: "### ", with: "")
            .replacingOccurrences(of: "**", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
