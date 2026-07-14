import SwiftUI

struct StatusView: View {
    @Environment(InstallerModel.self) private var model
    @State private var showUninstall = false

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
    }

    private var header: some View {
        VStack(spacing: 6) {
            Text("Project 1999 for Mac")
                .font(.largeTitle.bold())
            Text("Sets up classic EverQuest (Project 1999) on your Mac — Apple Silicon included. "
                 + "Safe to re-run any time: finished steps are detected and skipped.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Text("The app never asks for your password. If Homebrew or Rosetta are needed, "
                 + "macOS and Homebrew's own installers do the asking.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
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
                    ("dsetup.dll (V58 build)", model.status.value("fix_dsetup")),
                    ("dpvs.dll unpacked", model.status.value("fix_dpvs")),
                    ("eqclient.ini applied", model.status.value("fix_ini")),
                ])
            }
            .padding(16)
        }
    }

    private var footer: some View {
        HStack {
            Button("Uninstall…") { showUninstall = true }
                .disabled(!model.status.anythingInstalled)
            Button {
                Task { await model.refreshStatus() }
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise").labelStyle(.iconOnly)
            }
            .help("Re-check what's installed")
            Spacer()
            if model.status.fullyInstalled {
                Button("Check for Updates") { model.update() }
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
