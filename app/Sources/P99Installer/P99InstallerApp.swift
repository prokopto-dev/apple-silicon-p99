import SwiftUI

// NOTE: must be @main in a non-main.swift file so SwiftPM compiles the target
// with -parse-as-library (a top-level main.swift would break the @main attribute).
@main
struct P99InstallerApp: App {
    @State private var model = InstallerModel()

    init() {
        // Hidden debug hook: `P99Installer --selftest` verifies script
        // location, the runner, and status parsing without opening a window.
        if CommandLine.arguments.contains("--selftest") {
            let dir = ScriptLocator.scriptsDirectory
            print("scripts dir: \(dir.path)")
            let semaphore = DispatchSemaphore(value: 0)
            // Detached: a plain Task would inherit the main actor, which the
            // semaphore below is blocking — instant deadlock.
            Task.detached {
                do {
                    let tsv = try await ScriptRunner.capture(script: ScriptLocator.script("status.sh"))
                    let status = P99Status(tsv: tsv)
                    for key in P99Status.requiredKeys + ["p99files"] {
                        print("\(key): \(status.value(key)) done=\(status.isDone(key))")
                    }
                    print("fullyInstalled=\(status.fullyInstalled) anythingInstalled=\(status.anythingInstalled)")
                    try await Self.selftestStreaming()
                    print("SELFTEST OK")
                    exit(0)
                } catch {
                    print("SELFTEST FAILED: \(error)")
                    exit(1) // nonzero so CI fails the build
                }
            }
            semaphore.wait() // parked until one of the exits above fires
        }
    }

    /// Exercises ScriptRunner streaming (incl. \r-delimited curl-style
    /// progress) and OutputParser classification against a synthetic script.
    /// nonisolated: App conformance makes members @MainActor by default, and
    /// the selftest's semaphore is blocking the main thread.
    nonisolated static func selftestStreaming() async throws {
        let script = """
        source ./config.sh
        say "hello world"
        printf '#########                       45.3%%\\r'
        printf '###############################  100.0%%\\r'
        warn "a warning"
        echo "raw tool output"
        die "boom"
        """
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("p99-selftest.sh")
        try script.write(to: url, atomically: true, encoding: .utf8)
        // Run from the scripts dir so `source ./config.sh` resolves.
        let copy = ScriptLocator.script("p99-selftest-tmp.sh")
        try? FileManager.default.removeItem(at: copy)
        try FileManager.default.copyItem(at: url, to: copy)
        defer { try? FileManager.default.removeItem(at: copy) }

        var events: [String] = []
        var failed = false
        do {
            for try await line in ScriptRunner().stream(script: copy) {
                switch OutputParser.parse(line) {
                case .say(let s):     events.append("say:\(s)")
                case .warn(let s):    events.append("warn:\(s)")
                case .error(let s):   events.append("error:\(s)")
                case .percent(let p): events.append("pct:\(p)")
                case .raw(let s):     events.append("raw:\(s)")
                }
            }
        } catch is ScriptFailure {
            failed = true
        }
        print("stream events: \(events)")
        let expected = ["say:hello world", "pct:45.3", "pct:100.0",
                        "warn:a warning", "raw:raw tool output", "error:boom"]
        guard events == expected, failed else {
            throw ScriptFailure(script: "selftest-stream (expected \(expected), failed=\(failed))",
                                exitCode: -1)
        }
    }

    var body: some Scene {
        WindowGroup("P99 Installer") {
            ContentView()
                .environment(model)
        }
        .windowResizability(.contentSize)
    }
}

struct ContentView: View {
    @Environment(InstallerModel.self) private var model

    var body: some View {
        Group {
            switch model.phase {
            case .status:       StatusView()
            case .homebrewGate: HomebrewGateView()
            case .sourcePicker: SourcePickerView()
            case .run:          RunView()
            }
        }
        .frame(width: 680, height: 540)
        .task { await model.refreshStatus() }
    }
}
