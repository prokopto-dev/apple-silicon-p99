import P99Core
import SwiftUI

/// Updates for the installer app itself. Lists every release the user is
/// missing, each with its changelog notes (the release pipeline makes GitHub
/// Release bodies == CHANGELOG.md sections, so this is authoritative), and —
/// for same-major releases — downloads, verifies, and installs the new app
/// in place, relaunching into it. Major-version jumps route to the release
/// page instead. Pops up automatically at launch when something new exists
/// (InstallerModel.autoCheckAppUpdates); "Skip This Version" quiets that
/// popup for one release without hiding the manual button.
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
            footer
        }
        .padding(20)
        .frame(width: 560, height: 460)
        .task {
            // The launch-time auto-check may already have found releases —
            // don't refetch over it, and never clobber a download in flight.
            switch model.appUpdateState {
            case .idle, .upToDate, .failed: await model.checkAppUpdates()
            default: break
            }
        }
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
                Label("Couldn't update", systemImage: "wifi.exclamationmark")
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
            releaseList(releases)
            if !model.latestIsAutoInstallable, releases.first != nil {
                Text(majorUpdateHint(releases))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        case .downloading(let releases, let progress):
            if let latest = releases.first {
                Text("Downloading \(latest.tag)…")
                    .font(.callout)
            }
            if let progress {
                SwiftUI.ProgressView(value: progress, total: 1)
            } else {
                SwiftUI.ProgressView()
                    .frame(maxWidth: .infinity)
            }
            releaseList(releases)
        case .staged(let releases, _):
            if let latest = releases.first {
                Label("\(latest.tag) is downloaded and verified.", systemImage: "checkmark.seal.fill")
                    .font(.headline)
                    .foregroundStyle(.green)
                Text("Restart & Update quits the installer, swaps in the new version, "
                     + "and reopens it — takes a few seconds.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            releaseList(releases)
        }
    }

    private var footer: some View {
        HStack {
            Button("Close") { dismiss() }
            if case .available = model.appUpdateState {
                Button("Skip This Version") {
                    model.skipAvailableUpdate()
                    dismiss()
                }
                .help("Stop the launch popup for this release — the Installer Updates… "
                      + "button still shows it")
            }
            Spacer()
            switch model.appUpdateState {
            case .available(let releases):
                if let latest = releases.first {
                    if model.latestIsAutoInstallable {
                        Button("Download & Install \(latest.tag)") {
                            Task { await model.downloadAndStageUpdate() }
                        }
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.defaultAction)
                    } else {
                        Button("Open Download Page for \(latest.tag)") {
                            NSWorkspace.shared.open(latest.url)
                        }
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.defaultAction)
                    }
                }
            case .staged:
                Button("Restart & Update") { model.installStagedUpdate() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            default:
                EmptyView()
            }
        }
    }

    /// Why the newest release can't be one-click installed.
    private func majorUpdateHint(_ releases: [AppRelease]) -> String {
        guard let latest = releases.first else { return "" }
        if !InstallerModel.canSelfInstall {
            return "This build isn't running from an installed app bundle, so it can't "
                 + "replace itself — use the download page."
        }
        if latest.downloadURL == nil {
            return "This release has no downloadable app archive yet — use the download page."
        }
        return "\(latest.tag) is a major update, so it's a fresh download from the "
             + "release page rather than an in-place update."
    }

    @ViewBuilder
    private func releaseList(_ releases: [AppRelease]) -> some View {
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

    /// Light markdown cleanup so raw changelog text reads well in a Text view.
    private func cleaned(_ notes: String) -> String {
        notes
            .replacingOccurrences(of: "### ", with: "")
            .replacingOccurrences(of: "**", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
