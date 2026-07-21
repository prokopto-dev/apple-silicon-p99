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

    /// Renderer swap + eqclient.ini perf keys. Both scripts read their mode from
    /// the environment (P99_RENDERER / P99_APPLY_PERF), so this same list applies
    /// or reverts the settings depending on the current toggles.
    public static func performance() -> [StepRun] {
        [StepRun(title: "Set the graphics renderer", script: "60-renderer.sh"),
         StepRun(title: "Apply EQ graphics settings", script: "35-perf-ini.sh")]
    }
}
