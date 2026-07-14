import Foundation

public enum OutputEvent: Equatable {
    case say(String)      // "==> " green status line from config.sh say()
    case warn(String)     // "WARN: " from warn()
    case error(String)    // "ERROR: " from die()
    case percent(Double)  // curl --progress-bar chunk ("####   45.3%")
    case raw(String)      // anything else (external tool output)
}

/// Classifies script output. The scripts' say/warn/die helpers in config.sh
/// give them a de-facto machine protocol; nothing script-side changes for the GUI.
public enum OutputParser {
    private static let ansi = #/\u{1B}\[[0-9;]*[A-Za-z]/#
    private static let progress = #/^[#\s.]*([0-9]+(?:\.[0-9]+)?)%\s*$/#

    public static func stripANSI(_ s: String) -> String {
        s.replacing(ansi, with: "")
    }

    public static func parse(_ line: String) -> OutputEvent {
        let clean = stripANSI(line).trimmingCharacters(in: .whitespaces)
        if clean.hasPrefix("==> ")   { return .say(String(clean.dropFirst(4))) }
        if clean.hasPrefix("WARN: ") { return .warn(String(clean.dropFirst(6))) }
        if clean.hasPrefix("ERROR: "){ return .error(String(clean.dropFirst(7))) }
        if let m = clean.wholeMatch(of: progress), let p = Double(m.1) {
            return .percent(min(p, 100))
        }
        return .raw(clean)
    }
}
