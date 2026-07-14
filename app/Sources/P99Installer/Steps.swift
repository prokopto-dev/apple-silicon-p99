import Foundation

/// One script invocation shown as a step in the progress UI.
struct StepRun: Identifiable, Equatable {
    let title: String
    let script: String
    var arguments: [String] = []
    var id: String { script + arguments.joined() }
}

/// Where the user's proprietary EverQuest Titanium files come from.
enum SourceChoice: Equatable {
    case existing          // GAME_DIR already has eqgame.exe
    case folder(URL)       // a Titanium install folder to copy
    case isos([URL])       // disc images for the original Windows installer
}

/// Parsed output of scripts/status.sh (TSV: key<TAB>ok|missing|n/a|Vnn).
struct P99Status: Equatable {
    var values: [String: String] = [:]

    init() {}
    init(tsv: String) {
        for line in tsv.split(separator: "\n") {
            let parts = line.split(separator: "\t", maxSplits: 1)
            if parts.count == 2 { values[String(parts[0])] = String(parts[1]) }
        }
    }

    func value(_ key: String) -> String { values[key] ?? "?" }
    func isOK(_ key: String) -> Bool {
        let v = value(key)
        if key == "p99files" { return v.hasPrefix("V") }
        return v == "ok"
    }
    func isDone(_ key: String) -> Bool { isOK(key) || value(key) == "n/a" }

    var gameInstalled: Bool { isOK("game") }
    var brewInstalled: Bool { isOK("brew") }

    /// Everything a playable install needs (n/a counts: rosetta on Intel,
    /// game-dependent checks resolve once the game exists).
    static let requiredKeys = ["clt", "rosetta", "brew", "tools", "wrapper", "engine",
                               "prefix", "fonts", "game", "fix_dsetup", "fix_dpvs", "fix_ini"]
    var fullyInstalled: Bool {
        !values.isEmpty && Self.requiredKeys.allSatisfy { isDone($0) } && gameInstalled
    }
    var anythingInstalled: Bool { isOK("wrapper") || gameInstalled }
}

enum Steps {
    static func install(source: SourceChoice) -> [StepRun] {
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
}
