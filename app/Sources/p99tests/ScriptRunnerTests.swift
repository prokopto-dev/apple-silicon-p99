import Foundation
import P99Core

/// Writes a bash fixture script and returns its URL.
private func fixture(_ body: String) throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("p99-test-\(UUID().uuidString).sh")
    try body.write(to: url, atomically: true, encoding: .utf8)
    return url
}

func runScriptRunnerTests() async {
    do {
        // \n and \r both delimit lines (curl progress arrives \r-delimited).
        let mixed = try fixture("""
        echo "line one"
        printf 'progress 10%%\\rprogress 90%%\\r'
        echo "line two"
        """)
        defer { try? FileManager.default.removeItem(at: mixed) }
        var lines: [String] = []
        for try await line in ScriptRunner().stream(script: mixed) { lines.append(line) }
        T.equal(lines, ["line one", "progress 10%", "progress 90%", "line two"],
                "stream splits on \\n and \\r")

        // stderr merges into the same stream (scripts warn/die on stderr).
        let stderrScript = try fixture("""
        echo "to stdout"
        echo "to stderr" >&2
        """)
        defer { try? FileManager.default.removeItem(at: stderrScript) }
        lines = []
        for try await line in ScriptRunner().stream(script: stderrScript) { lines.append(line) }
        T.expect(lines.contains("to stdout") && lines.contains("to stderr"),
                 "stderr merged into stream")

        // Nonzero exit throws ScriptFailure after delivering output.
        let failing = try fixture("""
        echo "ERROR: boom" >&2
        exit 3
        """)
        defer { try? FileManager.default.removeItem(at: failing) }
        lines = []
        var failure: ScriptFailure?
        do {
            for try await line in ScriptRunner().stream(script: failing) { lines.append(line) }
        } catch let e as ScriptFailure {
            failure = e
        }
        T.expect(lines.contains("ERROR: boom"), "failing script output delivered")
        T.equal(failure?.exitCode ?? -99, 3, "exit code propagated in ScriptFailure")

        // terminate() ends the stream with CancellationError, not ScriptFailure.
        let sleeper = try fixture("""
        echo "started"
        sleep 30
        echo "never reached"
        """)
        defer { try? FileManager.default.removeItem(at: sleeper) }
        let runner = ScriptRunner()
        lines = []
        var cancelled = false
        do {
            for try await line in runner.stream(script: sleeper) {
                lines.append(line)
                if line == "started" { runner.terminate() }
            }
        } catch is CancellationError {
            cancelled = true
        }
        T.equal(lines, ["started"], "no output after terminate")
        T.expect(cancelled, "terminate surfaces as CancellationError")

        // capture(): stdout on success, throws on failure.
        let ok = try fixture("echo hello")
        defer { try? FileManager.default.removeItem(at: ok) }
        let out = try await ScriptRunner.capture(script: ok)
        T.equal(out, "hello\n", "capture returns stdout")

        let bad = try fixture("exit 7")
        defer { try? FileManager.default.removeItem(at: bad) }
        var captureThrew = false
        do { _ = try await ScriptRunner.capture(script: bad) }
        catch is ScriptFailure { captureThrew = true }
        catch {}
        T.expect(captureThrew, "capture throws ScriptFailure on nonzero exit")
    } catch {
        T.expect(false, "unexpected error in ScriptRunner tests: \(error)")
    }

    // Finder-launched apps get a bare PATH; the runner must add brew dirs.
    let env = ScriptRunner.environment(extra: ["P99_TEST": "1"])
    let path = env["PATH"] ?? ""
    T.expect(path.contains("/opt/homebrew/bin") && path.contains("/usr/local/bin"),
             "brew dirs prepended to PATH")
    T.equal(env["P99_TEST"] ?? "", "1", "extra env merged")

    // The Performance panel routes its choices to the scripts through this same
    // extraEnv channel (see InstallerModel.applyPerformance).
    let perfEnv = ScriptRunner.environment(extra: ["P99_RENDERER": "d9vk",
                                                   "P99_APPLY_PERF": "1",
                                                   "P99_PERF_PROFILE": "smoother"])
    T.equal(perfEnv["P99_RENDERER"] ?? "", "d9vk", "renderer env merged")
    T.equal(perfEnv["P99_APPLY_PERF"] ?? "", "1", "apply-perf env merged")
    T.equal(perfEnv["P99_PERF_PROFILE"] ?? "", "smoother", "perf-profile env merged")
}
