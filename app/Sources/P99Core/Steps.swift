import Foundation

/// One script invocation shown as a step in the progress UI.
public struct StepRun: Identifiable, Equatable {
    public init(title: String, script: String, arguments: [String] = []) {
        self.title = title
        self.script = script
        self.arguments = arguments
    }
    public let title: String
    public let script: String
    public var arguments: [String]
    public var id: String { script + arguments.joined() }
}

/// Where the user's proprietary EverQuest Titanium files come from.
public enum SourceChoice: Equatable {
    case existing          // GAME_DIR already has eqgame.exe
    case folder(URL)       // a Titanium install folder to copy
    case isos([URL])       // disc images for the original Windows installer
}

/// Parsed output of scripts/status.sh (TSV: key<TAB>ok|missing|n/a|Vnn).
public struct P99Status: Equatable {
    var values: [String: String] = [:]

    public init() {}
    public init(tsv: String) {
        for line in tsv.split(separator: "\n") {
            let parts = line.split(separator: "\t", maxSplits: 1)
            if parts.count == 2 { values[String(parts[0])] = String(parts[1]) }
        }
    }

    public func value(_ key: String) -> String { values[key] ?? "?" }
    public func isOK(_ key: String) -> Bool {
        let v = value(key)
        if key == "p99files" { return v.hasPrefix("V") }
        return v == "ok"
    }
    public func isDone(_ key: String) -> Bool { isOK(key) || value(key) == "n/a" }

    public var gameInstalled: Bool { isOK("game") }
    public var brewInstalled: Bool { isOK("brew") }

    // MARK: Experimental FEX stack (informational — never gates readiness)

    /// Which stack Play launches (scripts/70-stack.sh marker). Old status.sh
    /// output has no "stack" key; default to rosetta so upgrades stay sane.
    public var activeStack: String { values["stack"] ?? "rosetta" }
    /// Whether a FEX engine tarball is pinned at all — the master gate.
    public var fexEnginePinned: Bool { isOK("fex_pinned") }
    /// Whether the FEX wrapper + engine are actually installed.
    public var fexInstalled: Bool { isOK("fex_engine") }
    /// Last 75-fex-smoke.sh result: pass | fail | never | n/a.
    public var fexSmoke: String { values["fex_smoke"] ?? "n/a" }

    /// Everything a playable install needs (n/a counts: rosetta on Intel,
    /// game-dependent checks resolve once the game exists).
    public static let requiredKeys = ["clt", "rosetta", "brew", "tools", "wrapper", "engine",
                               "prefix", "fonts", "game", "fix_dsetup", "fix_dpvs", "fix_ini"]
    public var fullyInstalled: Bool { fullyInstalled(waiving: []) }

    /// `waiving` lets the app treat user-disabled optional fixes (e.g. the
    /// V58 dsetup swap once P99 ships its own fixed DLL) as satisfied.
    /// The game itself can never be waived.
    public func fullyInstalled(waiving waived: Set<String>) -> Bool {
        !values.isEmpty
            && Self.requiredKeys.allSatisfy { isDone($0) || waived.contains($0) }
            && gameInstalled
    }
    public var anythingInstalled: Bool { isOK("wrapper") || gameInstalled }
}

public enum Steps {
    public static func install(source: SourceChoice) -> [StepRun] {
        var steps: [StepRun] = [
            StepRun(title: "Check prerequisites", script: "00-prereqs.sh"),
            StepRun(title: "Build the P99 wrapper app", script: "10-build-wrapper.sh"),
        ]
        switch source {
        case .existing:
            steps.append(StepRun(title: "Install game files + P99 patch", script: "20-install-game.sh"))
        case .folder(let url):
            steps.append(StepRun(title: "Copy game files + P99 patch", script: "20-install-game.sh",
                                 arguments: [url.path]))
        case .isos(let urls):
            steps.append(StepRun(title: "Run the Titanium installer", script: "15-install-from-media.sh",
                                 arguments: urls.map(\.path)))
            steps.append(StepRun(title: "Apply the P99 patch files", script: "20-install-game.sh"))
        }
        steps.append(StepRun(title: "Apply the Mac fixes", script: "30-apply-mac-fixes.sh"))
        return steps
    }

    /// Stack switch + renderer swap + eqclient.ini perf keys. All three scripts
    /// read their mode from the environment (P99_STACK / P99_RENDERER /
    /// P99_APPLY_PERF), so this same list applies or reverts the settings
    /// depending on the current toggles. The stack is recorded first so the
    /// renderer applies inside the wrapper future launches will actually use.
    public static func performance() -> [StepRun] {
        [StepRun(title: "Set the engine stack", script: "70-stack.sh"),
         StepRun(title: "Set the graphics renderer", script: "60-renderer.sh"),
         StepRun(title: "Apply EQ graphics settings", script: "35-perf-ini.sh")]
    }

    /// One-time setup of the experimental FEX stack (side-by-side wrapper;
    /// the supported P99.app is never touched). All steps run with the
    /// fexSetupEnv() overlay so the scripts target the FEX wrapper. Assumes
    /// the game itself is already installed (its folder is shared).
    public static func fexSetup() -> [StepRun] {
        [StepRun(title: "Build the FEX wrapper app", script: "10-build-wrapper.sh"),
         StepRun(title: "Link game files into the FEX wrapper", script: "20-install-game.sh"),
         StepRun(title: "Switch the active stack to FEX", script: "70-stack.sh"),
         StepRun(title: "Run the FEX smoke tests", script: "75-fex-smoke.sh")]
    }

    public static func fexSetupEnv() -> [String: String] { ["P99_STACK": "fex"] }

    /// The environment the Performance panel's choices translate to — the single
    /// place the UI-to-script contract lives (docs/PERFORMANCE.md documents the
    /// same variables for terminal users). Empty string = "leave off"; every
    /// script treats an empty variable as unset. The INI patcher runs in apply
    /// mode whenever any INI-backed choice is on, and in revert mode otherwise,
    /// so turning the last toggle off cleans the keys back out.
    public static func performanceEnv(stack: String, renderer: String, smoother: Bool,
                                      indirectMaps: Bool, fpsCap: String,
                                      rendererDebug: Bool, fpsOverlay: Bool) -> [String: String] {
        let applyINI = smoother || !fpsCap.isEmpty
        return ["P99_STACK": stack,
                "P99_RENDERER": renderer,
                "P99_APPLY_PERF": applyINI ? "1" : "0",
                "P99_PERF_PROFILE": smoother ? "smoother" : "",
                "EQ_FPS_CAP": fpsCap,
                "P99_DXVK_INDIRECT_MAPS": indirectMaps ? "1" : "",
                "P99_RENDERER_DEBUG": rendererDebug ? "1" : "",
                "P99_DXVK_HUD": fpsOverlay ? "fps,frametimes" : ""]
    }
}
