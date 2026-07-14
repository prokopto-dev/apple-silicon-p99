import Foundation

/// Finds the shell scripts the app drives. The scripts are the source of
/// truth for all install logic; the app only orchestrates them.
public enum ScriptLocator {
    /// Resolution order:
    /// 1. P99_SCRIPTS_DIR env var — dev loop against the repo checkout
    ///    (`P99_SCRIPTS_DIR=$PWD/../scripts swift run`).
    /// 2. scripts/ bundled into the .app's Resources by `make app`.
    /// 3. ../scripts relative to cwd — bare `swift run` from app/.
    public static var scriptsDirectory: URL {
        if let override = ProcessInfo.processInfo.environment["P99_SCRIPTS_DIR"] {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        if let bundled = Bundle.main.resourceURL?.appendingPathComponent("scripts", isDirectory: true),
           FileManager.default.fileExists(atPath: bundled.appendingPathComponent("status.sh").path) {
            return bundled
        }
        return URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("../scripts").standardizedFileURL
    }

    public static func script(_ name: String) -> URL {
        scriptsDirectory.appendingPathComponent(name)
    }
}
