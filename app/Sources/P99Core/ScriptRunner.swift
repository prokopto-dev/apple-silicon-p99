import Foundation

public struct ScriptFailure: Error, LocalizedError {
    public init(script: String, exitCode: Int32) {
        self.script = script
        self.exitCode = exitCode
    }
    public let script: String
    public let exitCode: Int32
    public var errorDescription: String? { "\(script) exited with code \(exitCode)" }
}

/// Runs one bash script, streaming its merged stdout+stderr line by line.
/// Lines are split on both \n and \r so curl --progress-bar updates
/// (carriage-return-delimited) arrive as individual chunks.
public final class ScriptRunner: @unchecked Sendable {
    public init() {}
    private let process = Process()

    /// Environment for script children. Finder-launched apps get a bare PATH
    /// that lacks Homebrew's bin dirs, so prepend them (setup.sh does the
    /// equivalent with `brew shellenv` — the GUI bypasses setup.sh).
    public static func environment(extra: [String: String] = [:]) -> [String: String] {
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
    public static func capture(script: URL, arguments: [String] = []) async throws -> String {
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
                    try? out.fileHandleForWriting.close() // see stream(): EOF guarantee
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

    public func stream(script: URL, arguments: [String] = [],
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

            // All reading happens through the readabilityHandler; the stream
            // finishes only once BOTH pipe EOF and process termination have
            // been observed. Never mix readToEnd() with a readabilityHandler:
            // for fast-exiting processes the handler machinery may already
            // have slurped the fd when terminationHandler cancels it, and a
            // readToEnd() there reads nothing — silently losing all output
            // (caught by p99tests on the faster CI runners).
            let lock = NSLock()
            var buffer = Data()
            var sawEOF = false
            var exitState: (status: Int32, signaled: Bool)?

            // Callers must hold `lock` for both helpers.
            func drain(_ incoming: Data) -> [String] {
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
            func finishIfComplete() {
                guard sawEOF, let exit = exitState else { return }
                if exit.signaled {
                    continuation.finish(throwing: CancellationError())
                } else if exit.status == 0 {
                    continuation.finish()
                } else {
                    continuation.finish(throwing: ScriptFailure(script: script.lastPathComponent,
                                                                exitCode: exit.status))
                }
            }

            // Dedicated blocking reader thread instead of readabilityHandler:
            // the GCD-callback machinery hung intermittently on cold
            // instrumented starts (CI watchdog: frozen entering the first
            // stream, zero lines delivered). A plain blocking read loop has
            // no callback semantics to race — data or EOF, nothing else.
            let readHandle = pipe.fileHandleForReading
            Thread.detachNewThread {
                // POSIX read, not FileHandle.availableData: read() returns 0
                // at EOF and -1 after the cancel path closes the fd — no
                // ObjC exceptions to dodge.
                let fd = readHandle.fileDescriptor
                var chunk = [UInt8](repeating: 0, count: 65536)
                while true {
                    let n = read(fd, &chunk, chunk.count)
                    if n <= 0 { break }
                    lock.lock()
                    let lines = drain(Data(bytes: chunk, count: n))
                    lock.unlock()
                    for line in lines { continuation.yield(line) }
                }
                lock.lock()
                let tail = String(data: buffer, encoding: .utf8) ?? ""
                buffer.removeAll()
                sawEOF = true
                if !tail.isEmpty { continuation.yield(tail) }
                finishIfComplete()
                lock.unlock()
            }

            p.terminationHandler = { proc in
                lock.lock()
                let signaled = proc.terminationReason == .uncaughtSignal
                exitState = (proc.terminationStatus, signaled)
                if signaled {
                    // SIGTERM (user cancel): orphaned children (e.g. curl) can
                    // hold the pipe open indefinitely — don't wait for EOF.
                    // Closing the read end also unblocks the reader thread.
                    sawEOF = true
                    try? readHandle.close()
                }
                finishIfComplete()
                lock.unlock()
            }

            do {
                try p.run()
                // Close our reference to the write end. The child owns its
                // dup; without this, whether EOF ever reaches the reader
                // depends on Foundation closing it for us — which differs
                // across macOS versions (macOS 15 CI runners stalled here).
                try? pipe.fileHandleForWriting.close()
            } catch {
                continuation.finish(throwing: error)
            }
        }
    }

    /// SIGTERM the script. Every script is idempotent, so a cancelled run is
    /// safe: re-running resumes where it left off. (An in-flight curl child
    /// may linger until its download completes — harmless.)
    public func terminate() {
        if process.isRunning { process.terminate() }
    }
}
