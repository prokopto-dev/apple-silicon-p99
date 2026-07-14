import P99Core
import SwiftUI

@MainActor
struct UninstallSheet: View {
    @Environment(InstallerModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var removeWrapper = true
    @State private var removeGame = false
    @State private var confirming = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Uninstall Project 1999")
                .font(.title2.bold())

            Toggle(isOn: $removeWrapper) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Delete the wrapper app (~1.1 GB)")
                    Text("/Applications/P99.app — safe to delete; can always be rebuilt.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .disabled(!model.status.isOK("wrapper"))

            Toggle(isOn: $removeGame) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Delete the game folder (~4.5 GB)")
                    Text("~/Games/EverQuest — contains your game files AND your characters' "
                         + "local settings (keybinds, UI layouts, chat logs). Only delete it if "
                         + "you're done with EverQuest on this Mac or have a copy elsewhere.")
                        .font(.caption)
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .disabled(!model.status.gameInstalled)

            Text("Kept either way: Homebrew, Command Line Tools, Rosetta 2, and the upx/cabextract "
                 + "helper tools (they're useful beyond this project — remove with "
                 + "“brew uninstall upx cabextract”).")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Button("Cancel") { dismiss() }
                Spacer()
                Button("Uninstall…", role: .destructive) { confirming = true }
                    .disabled(!removeWrapper && !removeGame)
            }
        }
        .padding(24)
        .frame(width: 480)
        .confirmationDialog(confirmTitle, isPresented: $confirming, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                dismiss()
                model.uninstall(removeWrapper: removeWrapper, removeGame: removeGame)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            if removeGame {
                Text("Deleting the game folder also deletes your keybinds, UI layouts, and chat logs. "
                     + "This can't be undone.")
            }
        }
    }

    private var confirmTitle: String {
        switch (removeWrapper, removeGame) {
        case (true, true):  "Delete the wrapper app AND the game folder?"
        case (true, false): "Delete the wrapper app?"
        default:            "Delete the game folder?"
        }
    }
}
