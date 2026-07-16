import P99Core
import SwiftUI

// @MainActor on every view struct (not just body): older SDKs (Xcode 15)
// only isolate `body`, so helper properties touching the model won't compile
// there without it.
@MainActor
struct StatusView: View {
    @Environment(InstallerModel.self) private var model
    @State private var showUninstall = false
    @State private var showAppUpdates = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if model.statusLoaded {
                checklist
            } else {
                Spacer()
                SwiftUI.ProgressView("Checking what's already installed…")
                Spacer()
            }
            Divider()
            footer
        }
        .sheet(isPresented: $showUninstall) { UninstallSheet() }
        .sheet(isPresented: $showAppUpdates) { AppUpdatesSheet() }
    }

    private var header: some View {
        VStack(spacing: 6) {
            if InstallerModel.isFEXBeta {
                Label("FEX RUNTIME BETA", systemImage: "testtube.2")
                    .font(.caption.bold())
                    .foregroundStyle(.orange)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(.orange.opacity(0.12), in: Capsule())
            }
            Text("Project 1999 for Mac")
                .font(.largeTitle.bold())
            Text("Sets up classic EverQuest (Project 1999) on your Mac — Apple Silicon included. "
                 + "Safe to re-run any time: finished steps are detected and skipped.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Text("The app never asks for your password. If Homebrew or Rosetta are needed, "
                 + "macOS and Homebrew's own installers do the asking. "
                 + "Installer v\(InstallerModel.appVersion).")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            if InstallerModel.isFEXBeta {
                Text("Experimental build channel. It currently retains the supported "
                     + "Rosetta runtime while the native Wine/FEX backend is developed.")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
        }
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity)
    }

    private var checklist: some View {
        ScrollView {
            VStack(spacing: 14) {
                CheckGroup(title: "Prerequisites", rows: [
                    ("Apple Command Line Tools", model.status.value("clt")),
                    ("Rosetta 2", model.status.value("rosetta")),
                    ("Homebrew", model.status.value("brew")),
                    ("Helper tools (upx, cabextract)", model.status.value("tools")),
                ])
                CheckGroup(title: "P99 wrapper app", rows: [
                    ("Wrapper (/Applications/P99.app)", model.status.value("wrapper")),
                    ("Wine engine", model.status.value("engine")),
                    ("Wine prefix", model.status.value("prefix")),
                    ("MS core fonts", model.status.value("fonts")),
                ])
                CheckGroup(title: "Game files", rows: [
                    ("EverQuest Titanium", model.status.value("game")),
                    ("P99 patch files", model.status.value("p99files")),
                ])
                CheckGroup(title: "Mac fixes", rows: [
                    ("dsetup.dll (V58 build)",
                     model.applyDsetupFix ? model.status.value("fix_dsetup") : "skipped"),
                    ("dpvs.dll unpacked", model.status.value("fix_dpvs")),
                    ("eqclient.ini applied", model.status.value("fix_ini")),
                ])
                settingsBox
            }
            .padding(16)
        }
    }

    private var settingsBox: some View {
        @Bindable var model = model
        return GroupBox("Settings") {
            Toggle(isOn: $model.applyDsetupFix) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Anti-cheat compatibility fix (V58 dsetup.dll)")
                    Text("Leave this on. Turn it off only when P99's patch notes announce a "
                         + "new anti-cheat DLL that replaces the V58 workaround — then run "
                         + "Check for Updates so the new DLL is kept.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 6)
        }
    }

    private var footer: some View {
        HStack {
            Button("Uninstall…") { showUninstall = true }
                .disabled(!model.status.anythingInstalled)
            Button("Installer Updates…") { showAppUpdates = true }
                .help("Check for a newer version of this installer app")
            Button {
                Task { await model.refreshStatus() }
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise").labelStyle(.iconOnly)
            }
            .help("Re-check what's installed")
            Spacer()
            if model.readyToPlay {
                Button("Update Game Files") { model.update() }
                    .help("Fetch the newest P99 patch files and re-apply the Mac fixes")
                Button("Play") { model.play() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
            } else {
                Button(model.status.anythingInstalled ? "Continue Install" : "Install") {
                    model.beginInstall()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(!model.statusLoaded)
            }
        }
        .padding(14)
    }
}

private struct CheckGroup: View {
    let title: String
    let rows: [(String, String)]

    var body: some View {
        GroupBox(title) {
            VStack(spacing: 6) {
                ForEach(rows, id: \.0) { row in
                    HStack {
                        Text(row.0)
                        Spacer()
                        stateBadge(row.1)
                    }
                }
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 6)
        }
    }

    @ViewBuilder
    private func stateBadge(_ value: String) -> some View {
        switch value {
        case "ok":
            Label("Done", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case "missing":
            Label("Not yet", systemImage: "circle.dotted")
                .foregroundStyle(.secondary)
        case "n/a":
            Label("Not needed", systemImage: "minus.circle")
                .foregroundStyle(.tertiary)
        case "skipped":
            Label("Off (by choice)", systemImage: "hand.raised")
                .foregroundStyle(.orange)
        default: // p99files version, e.g. "V62" or "none"
            if value.hasPrefix("V") {
                Label(value, systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else {
                Label("Not yet", systemImage: "circle.dotted")
                    .foregroundStyle(.secondary)
            }
        }
    }
}
