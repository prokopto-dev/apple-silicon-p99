import P99Core
import SwiftUI
import Observation

enum Phase: Equatable {
    case status        // main screen: checklist + actions
    case homebrewGate  // brew missing: hand off to Terminal, poll until present
    case sourcePicker  // where are the Titanium files?
    case run(RunKind)  // a script pipeline is running (or just finished/failed)
}

enum RunKind: Equatable {
    case install, update, uninstall, launch, performance, fexSetup

    var title: String {
        switch self {
        case .install:     "Installing Project 1999"
        case .update:      "Updating P99 files"
        case .uninstall:   "Uninstalling"
        case .launch:      "Launching Project 1999"
        case .performance: "Applying performance settings"
        case .fexSetup:    "Setting up the FEX stack (experimental)"
        }
    }
}

enum RunState: Equatable {
    case running
    case success
    case failure(String)
}

@Observable @MainActor
final class InstallerModel {
    var phase: Phase = .status
    var status = P99Status()
    var statusLoaded = false

    /// The V58 dsetup.dll swap (Mac fix 1). Default on. The off switch exists
    /// for the day P99 ships a DLL update that supersedes the V58 workaround —
    /// staff have said that's coming — so users of an old installer build can
    /// keep updating without the script downgrading the new DLL. Persisted.
    static let dsetupFixKey = "applyDsetupFix"
    var applyDsetupFix: Bool = UserDefaults.standard.object(forKey: dsetupFixKey) as? Bool ?? true {
        didSet { UserDefaults.standard.set(applyDsetupFix, forKey: Self.dsetupFixKey) }
    }
    private var waivedKeys: Set<String> { applyDsetupFix ? [] : ["fix_dsetup"] }
    /// fullyInstalled, but honoring user-disabled optional fixes.
    var readyToPlay: Bool { status.fullyInstalled(waiving: waivedKeys) }

    // MARK: - Engine stack (experimental FEX slot; see docs/EXPERIMENTAL-FEX.md)

    /// Which engine stack Apply targets and Play then launches: "rosetta"
    /// (supported) or "fex" (experimental, side-by-side wrapper). Selecting
    /// fex pins the renderer back to wined3d — the bundled alt-renderer DLL
    /// sets are only proven against the Rosetta engine. Persisted.
    static let stackKey = "stackChoice"
    var stackChoice: String = UserDefaults.standard.string(forKey: stackKey) ?? "rosetta" {
        didSet {
            UserDefaults.standard.set(stackChoice, forKey: Self.stackKey)
            if stackChoice == "fex" { rendererChoice = "wined3d" }
        }
    }

    /// The FEX option is selectable only once its wrapper+engine exist;
    /// setup is offered only while an engine tarball is pinned but not built.
    var fexSelectable: Bool { status.fexInstalled }
    var fexSetupPossible: Bool { status.fexEnginePinned && !status.fexInstalled }

    /// One-time FEX stack setup: builds the side-by-side wrapper, links the
    /// shared game folder in, records the stack, and smoke-tests the engine.
    func setUpFex() {
        startRun(.fexSetup, steps: Steps.fexSetup(), extraEnv: Steps.fexSetupEnv())
    }

    // MARK: - Performance settings (opt-in, reversible; see docs/PERFORMANCE.md)

    /// Graphics renderer: "wined3d" (stock) or "d9vk" (D3D9 → Vulkan → Metal,
    /// smoother on newer Apple Silicon). Applied by 60-renderer.sh, which restores
    /// the stock renderer cleanly when set back to wined3d. Persisted.
    static let rendererKey = "rendererChoice"
    var rendererChoice: String = UserDefaults.standard.string(forKey: rendererKey) ?? "wined3d" {
        didSet { UserDefaults.standard.set(rendererChoice, forKey: Self.rendererKey) }
    }

    /// Apply the "smoother" eqclient.ini profile (lower particle load, capped
    /// effects). Applied/reverted surgically by 35-perf-ini.sh — never touches
    /// resolution or keybinds. Persisted.
    static let smootherINIKey = "smootherINI"
    var smootherINI: Bool = UserDefaults.standard.bool(forKey: smootherINIKey) {
        didSet { UserDefaults.standard.set(smootherINI, forKey: Self.smootherINIKey) }
    }

    /// Frame-rate cap (eqclient.ini MaxFPS/MaxBGFPS via 35-perf-ini.sh): "" = off,
    /// otherwise the cap as a string ("30"/"60"). Persisted.
    static let fpsCapKey = "fpsCap"
    var fpsCap: String = UserDefaults.standard.string(forKey: fpsCapKey) ?? "" {
        didSet { UserDefaults.standard.set(fpsCap, forKey: Self.fpsCapKey) }
    }

    /// d9vk experiment: route D3D9 buffer locks through DXVK-owned memory instead
    /// of directly-mapped Vulkan memory (dxvk-p99.conf in the wrapper's drive_c),
    /// sidestepping the WoW64 32-bit map penalty at the cost of some CPU copying.
    /// Only takes effect when the d9vk renderer is applied. Persisted.
    static let indirectMapsKey = "indirectMaps"
    var indirectMaps: Bool = UserDefaults.standard.bool(forKey: indirectMapsKey) {
        didSet { UserDefaults.standard.set(indirectMaps, forKey: Self.indirectMapsKey) }
    }

    /// d9vk diagnostics: verbose DXVK/MoltenVK logs (P99_RENDERER_DEBUG) and the
    /// in-game FPS overlay (P99_DXVK_HUD). Both only take effect under d9vk and
    /// are removed whenever the renderer is re-applied without them. Persisted.
    static let rendererDebugKey = "rendererDebug"
    var rendererDebug: Bool = UserDefaults.standard.bool(forKey: rendererDebugKey) {
        didSet { UserDefaults.standard.set(rendererDebug, forKey: Self.rendererDebugKey) }
    }
    static let fpsOverlayKey = "fpsOverlay"
    var fpsOverlay: Bool = UserDefaults.standard.bool(forKey: fpsOverlayKey) {
        didSet { UserDefaults.standard.set(fpsOverlay, forKey: Self.fpsOverlayKey) }
    }

    /// Display scaling (55-wrapper.sh, both renderers, both stacks): "" leaves
    /// the wrapper's shipped behavior, "off" renders at 1x and lets macOS scale
    /// the window up (the wined3d fill-rate win), "on" forces Retina-scale
    /// rendering. Fully reversible — "" restores the exact shipped state.
    /// Persisted.
    static let hidpiChoiceKey = "hidpiChoice"
    var hidpiChoice: String = UserDefaults.standard.string(forKey: hidpiChoiceKey) ?? "" {
        didSet { UserDefaults.standard.set(hidpiChoice, forKey: Self.hidpiChoiceKey) }
    }

    /// Apple's Metal performance HUD (55-wrapper.sh) — frametimes on any
    /// renderer, including the stock wined3d path that has no DXVK HUD.
    /// Diagnostics, not a performance setting. Persisted.
    static let metalHudKey = "metalHud"
    var metalHud: Bool = UserDefaults.standard.bool(forKey: metalHudKey) {
        didSet { UserDefaults.standard.set(metalHud, forKey: Self.metalHudKey) }
    }

    /// wined3d registry tuning (65-wined3d.sh; stock renderer only — the env
    /// contract blanks these under d9vk). Empty string = wine's own default.
    /// csmt: ""/"off"/"serialize"; maxGL: ""/"2.1"/"4.1"; vram: ""/"512"/"1024".
    /// Persisted.
    static let wined3dCsmtKey = "wined3dCsmt"
    var wined3dCsmt: String = UserDefaults.standard.string(forKey: wined3dCsmtKey) ?? "" {
        didSet { UserDefaults.standard.set(wined3dCsmt, forKey: Self.wined3dCsmtKey) }
    }
    static let wined3dMaxGLKey = "wined3dMaxGL"
    var wined3dMaxGL: String = UserDefaults.standard.string(forKey: wined3dMaxGLKey) ?? "" {
        didSet { UserDefaults.standard.set(wined3dMaxGL, forKey: Self.wined3dMaxGLKey) }
    }
    static let wined3dVramKey = "wined3dVram"
    var wined3dVram: String = UserDefaults.standard.string(forKey: wined3dVramKey) ?? "" {
        didSet { UserDefaults.standard.set(wined3dVram, forKey: Self.wined3dVramKey) }
    }

    // MARK: - Installer app updates

    enum AppUpdateState: Equatable {
        case idle, checking, upToDate
        case available([AppRelease])
        case downloading([AppRelease], Double?)   // progress 0...1, nil = unknown
        case staged([AppRelease], URL)            // verified new .app, ready to swap in
        case failed(String)
    }
    var appUpdateState: AppUpdateState = .idle
    private var didAutoCheckUpdates = false

    /// Version stamped into the bundle by `make app` (from CHANGELOG.md).
    static var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
    }

    /// True when running as a real installed .app — the only shape the in-place
    /// swap can replace. `swift run` dev builds fall back to the release page.
    static var canSelfInstall: Bool { Bundle.main.bundleURL.pathExtension == "app" }

    /// Whether the newest missed release can be installed in place: same major
    /// version (AppUpdates.canAutoUpdate), a published zip asset, and a real
    /// .app bundle to replace.
    var latestIsAutoInstallable: Bool {
        guard case .available(let releases) = appUpdateState,
              let latest = releases.first else { return false }
        return Self.canSelfInstall && latest.downloadURL != nil
            && AppUpdates.canAutoUpdate(from: Self.appVersion, to: latest.version)
    }

    /// Asks GitHub for newer installer releases; each release's notes are its
    /// CHANGELOG section, so the sheet can show everything the user missed.
    func checkAppUpdates() async {
        switch appUpdateState {
        case .downloading, .staged: return   // never clobber an in-flight update
        default: break
        }
        appUpdateState = .checking
        do {
            var request = URLRequest(url: AppUpdates.releasesAPI)
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            let (data, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                throw ScriptFailure(script: "GitHub API", exitCode: Int32(http.statusCode))
            }
            let missed = AppUpdates.newer(than: Self.appVersion,
                                          in: try AppUpdates.releases(fromJSON: data))
            appUpdateState = missed.isEmpty ? .upToDate : .available(missed)
        } catch {
            appUpdateState = .failed(error.localizedDescription)
        }
    }

    /// Launch-time check behind the automatic "update available" popup. Runs
    /// once per app launch; returns true when the sheet should present itself
    /// (something newer exists that the user hasn't skipped).
    func autoCheckAppUpdates() async -> Bool {
        guard !didAutoCheckUpdates else { return false }
        didAutoCheckUpdates = true
        await checkAppUpdates()
        return shouldAutoPromptForUpdate
    }

    /// "Skip This Version" — remembered per tag, so the launch popup stays
    /// quiet for this release but returns for the next one. The manual
    /// Installer Updates… button always shows everything regardless.
    static let skippedUpdateKey = "skippedUpdateTag"
    var shouldAutoPromptForUpdate: Bool {
        guard case .available(let releases) = appUpdateState,
              let latest = releases.first else { return false }
        return latest.tag != UserDefaults.standard.string(forKey: Self.skippedUpdateKey)
    }
    func skipAvailableUpdate() {
        guard case .available(let releases) = appUpdateState,
              let latest = releases.first else { return }
        UserDefaults.standard.set(latest.tag, forKey: Self.skippedUpdateKey)
    }

    /// Downloads the newest release's zip with progress, then extracts and
    /// verifies it via 95-selfupdate.sh (stage mode): the staged bundle must
    /// carry exactly the advertised version. Ends in .staged — the swap only
    /// happens when the user confirms the restart.
    func downloadAndStageUpdate() async {
        guard case .available(let releases) = appUpdateState,
              let latest = releases.first,
              let asset = latest.downloadURL else { return }
        appUpdateState = .downloading(releases, nil)
        do {
            let work = FileManager.default.temporaryDirectory
                .appendingPathComponent("p99-selfupdate-\(latest.tag)")
            try? FileManager.default.removeItem(at: work)
            try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)

            let (bytes, response) = try await URLSession.shared.bytes(from: asset)
            if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                throw ScriptFailure(script: "GitHub download", exitCode: Int32(http.statusCode))
            }
            let expected = response.expectedContentLength
            var data = Data()
            if expected > 0 { data.reserveCapacity(Int(expected)) }
            var sinceReport = 0
            for try await byte in bytes {
                data.append(byte)
                sinceReport += 1
                if sinceReport >= 262_144 {   // update the bar every 256 KB
                    sinceReport = 0
                    appUpdateState = .downloading(
                        releases, expected > 0 ? Double(data.count) / Double(expected) : nil)
                }
            }
            let zip = work.appendingPathComponent(AppUpdates.zipAssetName)
            try data.write(to: zip)

            let out = try await ScriptRunner.capture(
                script: ScriptLocator.script("95-selfupdate.sh"),
                arguments: ["stage", zip.path, work.appendingPathComponent("staged").path])
            var fields: [String: String] = [:]
            for line in out.split(separator: "\n") {
                let parts = line.split(separator: "\t", maxSplits: 1)
                if parts.count == 2 { fields[String(parts[0])] = String(parts[1]) }
            }
            guard let appPath = fields["APP"], !appPath.isEmpty else {
                appUpdateState = .failed("the downloaded zip contained no app bundle")
                return
            }
            guard fields["VERSION"] == latest.versionString else {
                appUpdateState = .failed("downloaded app reports version "
                    + "\(fields["VERSION"] ?? "?") instead of \(latest.versionString)")
                return
            }
            appUpdateState = .staged(releases, URL(fileURLWithPath: appPath))
        } catch {
            appUpdateState = .failed(error.localizedDescription)
        }
    }

    /// Hands the staged bundle to a detached copy of 95-selfupdate.sh (swap
    /// mode) and quits: the helper waits for this process to exit, replaces
    /// the app in place, clears quarantine, and relaunches the new version.
    /// The helper must run from OUTSIDE the bundle it is about to replace.
    func installStagedUpdate() {
        guard case .staged(_, let stagedApp) = appUpdateState else { return }
        do {
            let helper = FileManager.default.temporaryDirectory
                .appendingPathComponent("p99-selfupdate.sh")
            try? FileManager.default.removeItem(at: helper)
            try FileManager.default.copyItem(at: ScriptLocator.script("95-selfupdate.sh"),
                                             to: helper)
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/bin/bash")
            p.arguments = [helper.path, "swap", stagedApp.path,
                           Bundle.main.bundleURL.path,
                           String(ProcessInfo.processInfo.processIdentifier)]
            p.standardInput = FileHandle.nullDevice
            p.standardOutput = FileHandle.nullDevice
            p.standardError = FileHandle.nullDevice
            try p.run()
            NSApplication.shared.terminate(nil)
        } catch {
            appUpdateState = .failed("could not start the update helper: "
                + error.localizedDescription)
        }
    }

    // Run-screen state
    var runKind: RunKind = .install
    var runState: RunState = .running
    var steps: [StepRun] = []
    var currentStep = 0
    var headline = ""
    var percent: Double?
    var logLines: [String] = []

    private var runner: ScriptRunner?
    private var runTask: Task<Void, Never>?

    // MARK: - Status

    func refreshStatus() async {
        do {
            let tsv = try await ScriptRunner.capture(script: ScriptLocator.script("status.sh"))
            status = P99Status(tsv: tsv)
        } catch {
            logLines.append("status.sh failed: \(error.localizedDescription)")
        }
        statusLoaded = true
    }

    // MARK: - Install flow

    /// Entry from the Install button. Routes through the Homebrew gate and
    /// source picker as needed; both loop back here when satisfied.
    func beginInstall() {
        guard status.brewInstalled else {
            phase = .homebrewGate
            return
        }
        if status.gameInstalled {
            startRun(.install, steps: Steps.install(source: .existing))
        } else {
            phase = .sourcePicker
        }
    }

    func install(source: SourceChoice) {
        startRun(.install, steps: Steps.install(source: source))
    }

    func update() {
        startRun(.update, steps: Steps.update())
    }

    func play() {
        startRun(.launch, steps: [StepRun(title: "Launch Project 1999", script: "40-launch.sh")])
    }

    /// Apply the current Performance panel choices. Both scripts read their mode
    /// from the environment, so the same run either applies or reverts depending
    /// on the toggles — no separate "revert" action needed. The choice→env
    /// mapping lives in Steps.performanceEnv (P99Core) so tests can pin it.
    func applyPerformance() {
        startRun(.performance,
                 steps: Steps.performance(),
                 extraEnv: Steps.performanceEnv(stack: stackChoice,
                                                renderer: rendererChoice,
                                                smoother: smootherINI,
                                                indirectMaps: indirectMaps,
                                                fpsCap: fpsCap,
                                                rendererDebug: rendererDebug,
                                                fpsOverlay: fpsOverlay,
                                                hidpi: hidpiChoice,
                                                metalHud: metalHud,
                                                wined3dCsmt: wined3dCsmt,
                                                wined3dMaxGL: wined3dMaxGL,
                                                wined3dVram: wined3dVram))
    }

    func uninstall(removeWrapper: Bool, removeGame: Bool, removeFex: Bool = false) {
        startRun(.uninstall,
                 steps: [StepRun(title: "Remove selected components", script: "90-uninstall.sh")],
                 extraEnv: ["P99_NONINTERACTIVE": "1",
                            "P99_REMOVE_WRAPPER": removeWrapper ? "1" : "0",
                            "P99_REMOVE_GAMEDIR": removeGame ? "1" : "0",
                            "P99_REMOVE_FEX_WRAPPER": removeFex ? "1" : "0"])
    }

    func cancelRun() {
        runTask?.cancel()
        runner?.terminate()
        backToStatus()
    }

    func backToStatus() {
        phase = .status
        Task { await refreshStatus() }
    }

    // MARK: - Homebrew gate

    /// Homebrew's installer is interactive and asks for the user's macOS
    /// password (sudo). The app must never see that password, so it hands the
    /// official install command to Terminal.app — a real tty — via a .command
    /// file, then polls status.sh until brew appears.
    func openHomebrewInstaller() {
        let script = """
        #!/bin/bash
        echo "This installs Homebrew, the Mac package manager (https://brew.sh)."
        echo "It will ask for your macOS login password — that prompt comes from"
        echo "Homebrew's own installer running in this Terminal window."
        echo "P99 Installer never sees your password."
        echo
        /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
        echo
        echo "Done — you can close this window. P99 Installer continues automatically."
        """
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("Install Homebrew.command")
        do {
            try script.write(to: url, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755],
                                                  ofItemAtPath: url.path)
            NSWorkspace.shared.open(url)
        } catch {
            logLines.append("could not stage Homebrew installer: \(error.localizedDescription)")
        }
    }

    /// Runs while the Homebrew gate is showing; auto-advances when brew lands.
    func pollHomebrew() async {
        while phase == .homebrewGate {
            await refreshStatus()
            if status.brewInstalled {
                beginInstall()
                return
            }
            try? await Task.sleep(for: .seconds(2))
        }
    }

    // MARK: - Pipeline runner

    private func startRun(_ kind: RunKind, steps: [StepRun], extraEnv: [String: String] = [:]) {
        runKind = kind
        self.steps = steps
        currentStep = 0
        headline = ""
        percent = nil
        logLines = []
        runState = .running
        phase = .run(kind)
        var env = extraEnv
        if !applyDsetupFix {
            // 30-apply-mac-fixes.sh and 50-update.sh honor this: keep the
            // dsetup.dll that the P99 patch shipped instead of the V58 swap.
            env["SKIP_DSETUP_FIX"] = "1"
        }
        runTask = Task { await runAll(extraEnv: env) }
    }

    private func runAll(extraEnv: [String: String]) async {
        var lastError: String?
        for (index, step) in steps.enumerated() {
            currentStep = index
            percent = nil
            headline = step.title
            let runner = ScriptRunner()
            self.runner = runner
            do {
                let stream = runner.stream(script: ScriptLocator.script(step.script),
                                           arguments: step.arguments,
                                           extraEnv: extraEnv)
                for try await line in stream {
                    if Task.isCancelled { return }
                    handle(line: line, lastError: &lastError)
                }
            } catch is CancellationError {
                return // user cancelled; cancelRun() already reset the phase
            } catch {
                if Task.isCancelled { return }
                let message = lastError ?? error.localizedDescription
                runState = .failure(message)
                await refreshStatus()
                return
            }
            if Task.isCancelled { return }
        }
        currentStep = steps.count
        runState = .success
        await refreshStatus()
    }

    private func handle(line: String, lastError: inout String?) {
        switch OutputParser.parse(line) {
        case .say(let s):
            headline = s
            percent = nil
            logLines.append("==> " + s)
        case .warn(let s):
            logLines.append("WARN: " + s)
        case .error(let s):
            lastError = s
            logLines.append("ERROR: " + s)
        case .percent(let p):
            percent = p
        case .raw(let s):
            if !s.isEmpty { logLines.append(s) }
        }
        if logLines.count > 2400 { logLines.removeFirst(400) }
    }
}
