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
    case install, update, uninstall, launch

    var title: String {
        switch self {
        case .install:   "Installing Project 1999"
        case .update:    "Updating P99 files"
        case .uninstall: "Uninstalling"
        case .launch:    "Launching Project 1999"
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

    /// Build-time distribution channel stamped by the Makefile. The FEX beta
    /// uses a separate bundle identifier, so its preferences cannot leak into
    /// the stable installer even though both apps share this source code.
    static var buildChannel: String {
        Bundle.main.object(forInfoDictionaryKey: "P99BuildChannel") as? String ?? "stable"
    }
    static var isFEXBeta: Bool { buildChannel == "fex-beta" }

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

    // MARK: - Installer app updates

    enum AppUpdateState: Equatable {
        case idle, checking, upToDate
        case available([AppRelease])
        case failed(String)
    }
    var appUpdateState: AppUpdateState = .idle

    /// Version stamped into the bundle by `make app` (from CHANGELOG.md).
    static var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
    }

    /// Asks GitHub for newer installer releases; each release's notes are its
    /// CHANGELOG section, so the sheet can show everything the user missed.
    func checkAppUpdates() async {
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
        startRun(.update, steps: [StepRun(title: "Download + apply newest P99 files", script: "50-update.sh")])
    }

    func play() {
        startRun(.launch, steps: [StepRun(title: "Launch Project 1999", script: "40-launch.sh")])
    }

    func uninstall(removeWrapper: Bool, removeGame: Bool) {
        startRun(.uninstall,
                 steps: [StepRun(title: "Remove selected components", script: "90-uninstall.sh")],
                 extraEnv: ["P99_NONINTERACTIVE": "1",
                            "P99_REMOVE_WRAPPER": removeWrapper ? "1" : "0",
                            "P99_REMOVE_GAMEDIR": removeGame ? "1" : "0"])
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
