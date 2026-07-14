import Foundation

struct ScriptFailure: Error, LocalizedError {
    let script: String
    let exitCode: Int32
    var errorDescription: String? { "\(script) exited with code \(exitCode)" }
}

/// Runs one bash script, streaming its merged stdout+stderr line by line.
/// Lines are split on both \n and \r so curl --progress-bar updates
/// (carriage-return-delimited) arrive as individual chunks.
final class ScriptRunner: @unchecked Sendable {
    private let process = Process()

    /// Environment for script children. Finder-launched apps get a bare PATH
    /// that lacks Homebrew's bin dirs, so prepend them (setup.sh does the
    /// equivalent with `brew shellenv` — the GUI bypasses setup.sh).
    static func environment(extra: [String: String] = [:]) -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        var path = env["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"
        for dir in ["/usr/local/bin", "/opt/homebrew/bin"]
        where !path.split(separator: ":").contains(Substring(dir)) {
            path = dir + ":" + path
        }
        env["PATH"] = path
        env.merge(extra) { _, new in new }
        return env
    }

    /// One-shot helper: run a script to completion and return its stdout.
    /// Used for the fast, read-only status.sh.
    static func capture(script: URL, arguments: [String] = []) async throws -> String {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/bash")
        p.arguments = [script.path] + arguments
        p.currentDirectoryURL = script.deletingLastPathComponent()
        p.environment = environment()
        p.standardInput = FileHandle.nullDevice
        let out = Pipe()
        p.standardOutput = out
        p.standardError = Pipe()
        return try await withCheckedThrowingContinuation { cont in
            DispatchQueue.global().async {
                do {
                    try p.run()
                    let data = out.fileHandleForReading.readDataToEndOfFile()
                    p.waitUntilExit()
                    guard p.terminationStatus == 0 else {
                        throw ScriptFailure(script: script.lastPathComponent,
                                            exitCode: p.terminationStatus)
                    }
                    cont.resume(returning: String(data: data, encoding: .utf8) ?? "")
                } catch {
                    cont.resume(throwing: error)
                }
            }
        }
    }

    func stream(script: URL, arguments: [String] = [],
                extraEnv: [String: String] = [:]) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let p = process
            p.executableURL = URL(fileURLWithPath: "/bin/bash")
            p.arguments = [script.path] + arguments
            p.currentDirectoryURL = script.deletingLastPathComponent()
            p.environment = Self.environment(extra: extraEnv)
            p.standardInput = FileHandle.nullDevice
            let pipe = Pipe()
            p.standardOutput = pipe
            p.standardError = pipe

            let lock = NSLock()
            var buffer = Data()

            func drain(_ incoming: Data) -> [String] {
                lock.lock(); defer { lock.unlock() }
                buffer.append(incoming)
                var lines: [String] = []
                while let brk = buffer.firstIndex(where: { $0 == 0x0A || $0 == 0x0D }) {
                    let chunk = buffer.subdata(in: buffer.startIndex..<brk)
                    buffer.removeSubrange(buffer.startIndex...brk)
                    if let s = String(data: chunk, encoding: .utf8), !s.isEmpty {
                        lines.append(s)
                    }
                }
                return lines
            }

            pipe.fileHandleForReading.readabilityHandler = { fh in
                let data = fh.availableData
                guard !data.isEmpty else { fh.readabilityHandler = nil; return }
                for line in drain(data) { continuation.yield(line) }
            }

            p.terminationHandler = { proc in
                pipe.fileHandleForReading.readabilityHandler = nil
                // After SIGTERM, orphaned children (e.g. curl) can hold the
                // pipe's write end open indefinitely — skip the final read.
                if proc.terminationReason != .uncaughtSignal,
                   let rest = try? pipe.fileHandleForReading.readToEnd(), !rest.isEmpty {
                    for line in drain(rest) { continuation.yield(line) }
                }
                lock.lock()
                let tail = String(data: buffer, encoding: .utf8) ?? ""
                buffer.removeAll()
                lock.unlock()
                if !tail.isEmpty { continuation.yield(tail) }

                if proc.terminationReason == .uncaughtSignal {
                    continuation.finish(throwing: CancellationError())
                } else if proc.terminationStatus == 0 {
                    continuation.finish()
                } else {
                    continuation.finish(throwing: ScriptFailure(script: script.lastPathComponent,
                                                                exitCode: proc.terminationStatus))
                }
            }

            do {
                try p.run()
            } catch {
                continuation.finish(throwing: error)
            }
        }
    }

    /// SIGTERM the script. Every script is idempotent, so a cancelled run is
    /// safe: re-running resumes where it left off. (An in-flight curl child
    /// may linger until its download completes — harmless.)
    func terminate() {
        if process.isRunning { process.terminate() }
    }
}
