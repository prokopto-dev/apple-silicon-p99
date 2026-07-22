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
        .task {
            // Launch-time update check: pop the updates sheet (changelog and
            // all) when a release the user hasn't skipped is available. Runs
            // once per launch — the model guards re-entry when this view
            // reappears after install/play runs.
            if await model.autoCheckAppUpdates() { showAppUpdates = true }
        }
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
                 + "macOS and Homebrew's own installers do the asking. "
                 + "Installer v\(InstallerModel.appVersion).")
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
                    ("dsetup.dll (V58 build)",
                     model.applyDsetupFix ? model.status.value("fix_dsetup") : "skipped"),
                    ("dpvs.dll unpacked", model.status.value("fix_dpvs")),
                    ("eqclient.ini applied", model.status.value("fix_ini")),
                ])
                settingsBox
                stackBox
                performanceBox
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

    private func caption(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    // The experimental post-Rosetta engine stack (docs/EXPERIMENTAL-FEX.md).
    // Hard-gated: the FEX option is selectable only once its engine is actually
    // installed, and setup is offered only while an engine tarball is pinned —
    // so on today's builds this box just explains what's coming. Both stacks
    // live side by side; the supported P99.app is never touched.
    private var stackBox: some View {
        @Bindable var model = model
        return GroupBox("Engine stack (experimental)") {
            VStack(alignment: .leading, spacing: 10) {
                Picker("Engine stack", selection: $model.stackChoice) {
                    Text("Rosetta 2 + WineCX (supported)").tag("rosetta")
                    Text("FEX native ARM64 (experimental)").tag("fex")
                        .selectionDisabled(!model.fexSelectable)
                }
                if !model.status.fexEnginePinned {
                    caption("Engine not yet available: no FEX engine build has been "
                            + "published, so this option is locked. It unlocks when the "
                            + "project releases one — or when you point FEX_ENGINE_URL and "
                            + "FEX_ENGINE_SHA256 at your own development build. Apple "
                            + "retires general-purpose Rosetta 2 after macOS 27; this "
                            + "stack is the escape route being built in the open.")
                } else if model.fexSetupPossible {
                    caption("A FEX engine is available but not installed. Setup builds a "
                            + "second wrapper (P99 FEX.app) beside your working install and "
                            + "smoke-tests the engine — the supported stack is not changed.")
                    HStack {
                        Spacer()
                        Button("Set Up FEX Stack…") { model.setUpFex() }
                            .disabled(!model.readyToPlay)
                            .help(model.readyToPlay
                                  ? "Builds the side-by-side FEX wrapper and runs the smoke tests"
                                  : "Finish installing the game first — the FEX wrapper links to it")
                    }
                } else {
                    HStack {
                        Text("FEX wrapper + engine")
                        Spacer()
                        Label("Installed", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    }
                    HStack {
                        Text("Engine smoke tests")
                        Spacer()
                        smokeBadge(model.status.fexSmoke)
                    }
                    HStack {
                        Text("Stack Play launches now")
                        Spacer()
                        Text(model.status.activeStack == "fex"
                             ? "FEX (experimental)" : "Rosetta (supported)")
                            .foregroundStyle(.secondary)
                    }
                    caption("Pick a stack and press Apply in the Performance panel — Play "
                            + "then launches that wrapper. Both stacks stay installed, so "
                            + "you can switch back and forth freely to compare.")
                }
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 6)
        }
    }

    @ViewBuilder
    private func smokeBadge(_ value: String) -> some View {
        switch value {
        case "pass":
            Label("Passed", systemImage: "checkmark.seal.fill").foregroundStyle(.green)
        case "fail":
            Label("Failed", systemImage: "xmark.seal").foregroundStyle(.orange)
        default: // "never" (not run yet) or "n/a"
            Label("Not run yet", systemImage: "circle.dotted").foregroundStyle(.secondary)
        }
    }

    // Opt-in, reversible tuning for stutter on newer Apple Silicon. Full guide:
    // docs/PERFORMANCE.md (every control names the script + variable it maps to
    // there, so terminal users get the identical behavior). Apply runs the
    // scripts; toggles alone change nothing until Apply is pressed (these edit
    // the wine prefix / eqclient.ini, which must be done with the game closed).
    private var performanceBox: some View {
        @Bindable var model = model
        return GroupBox("Performance") {
            VStack(alignment: .leading, spacing: 10) {
                Group {
                    Picker("Graphics renderer", selection: $model.rendererChoice) {
                        Text("Stock (wined3d)").tag("wined3d")
                        Text("D9VK — Vulkan/Metal (experimental)").tag("d9vk")
                    }
                    .disabled(model.stackChoice == "fex")
                    if model.stackChoice == "fex" {
                        caption("Renderer choices are Rosetta-stack only for now: the bundled "
                                + "D9VK/DXMT libraries and their MoltenVK pairing are x86_64 "
                                + "builds, unverified under the FEX engine. The FEX stack runs "
                                + "the stock wined3d renderer.")
                    } else {
                        caption("D9VK skips the deprecated OpenGL path and can be much smoother "
                                + "on newer chips — but on some machines it is much slower "
                                + "(single-digit FPS has been reported). If that happens, switch "
                                + "back to Stock and Apply; it restores the original renderer "
                                + "and changes nothing else.")
                    }
                    if model.rendererChoice == "d9vk" {
                        Toggle(isOn: $model.indirectMaps) {
                            Text("Indirect buffer maps (experiment)")
                        }
                        caption("If D9VK is still slow, try this: it keeps the game's "
                                + "geometry updates out of the one code path this stack "
                                + "makes expensive, at the cost of some extra CPU copying.")
                    }
                    // wined3d registry tuning: stock renderer only — under d9vk
                    // the whole wined3d DLL is replaced, so these values would
                    // silently do nothing there (Steps.performanceEnv blanks
                    // them too, and 65-wined3d.sh refuses to set them; hiding
                    // the controls is the same convention as the d9vk-only
                    // toggles above). Valid on both engine stacks: the registry
                    // lives in each stack's own prefix.
                    if model.rendererChoice == "wined3d" {
                        Picker("Command stream (CSMT)", selection: $model.wined3dCsmt) {
                            Text("Wine default (on)").tag("")
                            Text("Off — pacing experiment").tag("off")
                            Text("Serialize (debug only)").tag("serialize")
                        }
                        Picker("OpenGL version cap", selection: $model.wined3dMaxGL) {
                            Text("Wine default").tag("")
                            Text("2.1 (legacy context)").tag("2.1")
                            Text("4.1 (macOS core max)").tag("4.1")
                        }
                        Picker("Reported video memory", selection: $model.wined3dVram) {
                            Text("Wine default").tag("")
                            Text("512 MB").tag("512")
                            Text("1 GB").tag("1024")
                        }
                        caption("Stock-renderer fine-tuning (wine registry, experimental). "
                                + "Wine's own defaults are the verified baseline — change "
                                + "one at a time and measure with the Metal HUD below. "
                                + "\"Wine default\" everywhere restores exactly the stock "
                                + "behavior.")
                    }
                }
                Divider()
                Group {
                    Picker("Display scaling", selection: $model.hidpiChoice) {
                        Text("System default").tag("")
                        Text("1× — smoother, less heat").tag("off")
                        Text("Retina — crisper text").tag("on")
                    }
                    caption("1× renders a quarter of the pixels and lets macOS scale the "
                            + "window up — the biggest fill-rate cut available on the "
                            + "stock renderer, where every pixel crosses Apple's "
                            + "deprecated OpenGL layer. UI text gets slightly softer; "
                            + "the 3D world barely changes (2005 textures have no extra "
                            + "detail to lose). Applies on every renderer and stack, "
                            + "never touches EQ's own settings, and is fully reversible "
                            + "— try both and keep what you prefer.")
                }
                Divider()
                Group {
                    Toggle(isOn: $model.smootherINI) {
                        Text("Smoother visuals (lower particle load)")
                    }
                    Picker("Frame-rate cap", selection: $model.fpsCap) {
                        Text("Off").tag("")
                        Text("30 FPS").tag("30")
                        Text("60 FPS").tag("60")
                    }
                    caption("EverQuest's own settings (eqclient.ini): fewer particles and "
                            + "a steadier frame cap. Never changes your resolution or "
                            + "keybinds, and is fully reversible.")
                }
                DisclosureGroup("Diagnostics") {
                    VStack(alignment: .leading, spacing: 10) {
                        Toggle(isOn: $model.metalHud) {
                            Text("Metal performance HUD")
                        }
                        caption("Apple's built-in overlay (top right: FPS, frame "
                                + "times, GPU time) — works on any renderer, so it's "
                                + "the way to measure the stock wined3d path, which "
                                + "has no other overlay. macOS 13+. Unconfirmed over "
                                + "the OpenGL compatibility layer on this stack; if "
                                + "it doesn't appear, nothing else is affected.")
                        if model.rendererChoice == "d9vk" {
                            Toggle(isOn: $model.fpsOverlay) {
                                Text("Show DXVK FPS overlay in-game")
                            }
                            Toggle(isOn: $model.rendererDebug) {
                                Text("Verbose renderer logs (for bug reports)")
                            }
                            caption("D9VK-only diagnostics. The logs name exactly "
                                    + "which components loaded — attach them if you "
                                    + "report a slow or broken D9VK run.")
                        }
                    }
                    .padding(.top, 6)
                }
                .font(.callout)
                HStack {
                    Text("Close EverQuest before applying.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    Spacer()
                    Button("Apply Performance Settings") { model.applyPerformance() }
                        .disabled(!model.readyToPlay)
                        .help(model.readyToPlay ? "Runs the renderer + graphics scripts"
                                                : "Finish installing before tuning performance")
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
