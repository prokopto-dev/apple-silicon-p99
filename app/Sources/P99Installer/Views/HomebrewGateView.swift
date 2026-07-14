import SwiftUI

/// Shown when Homebrew is missing. Its installer needs a real terminal and
/// asks for the user's macOS password itself — this app must never handle
/// that password, so the install is handed off to Terminal.app and the gate
/// polls until brew appears.
@MainActor
struct HomebrewGateView: View {
    @Environment(InstallerModel.self) private var model
    @State private var opened = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            VStack(spacing: 14) {
                Image(systemName: "cup.and.saucer.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(.tint)
                Text("One thing needs a Terminal window")
                    .font(.title2.bold())
                Text("Homebrew (the standard Mac package manager) is needed for two small "
                     + "helper tools. Its installer asks for your macOS login password, and "
                     + "for your safety it does that itself, in Terminal — this app never "
                     + "sees your password.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 70)
                Button("Install Homebrew in Terminal") {
                    model.openHomebrewInstaller()
                    opened = true
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                if opened {
                    HStack(spacing: 8) {
                        SwiftUI.ProgressView().controlSize(.small)
                        Text("Waiting for Homebrew to finish — the install continues here automatically.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 6)
                }
            }
            Spacer()
            Divider()
            HStack {
                Button("Back") { model.backToStatus() }
                Spacer()
                Text("Already have Homebrew? It wasn't found on this Mac — installing it again is safe.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding(14)
        }
        .task { await model.pollHomebrew() }
    }
}
