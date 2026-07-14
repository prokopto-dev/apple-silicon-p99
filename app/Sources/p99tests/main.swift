// Test runner: swift run --package-path app p99tests   (or `make test`)

import Foundation

// Watchdog: a healthy run finishes in seconds. If anything wedges (CI stalled
// repeatedly in the instrumented coverage run before the pipe EOF fix), fail
// loudly after 3 minutes instead of hanging the pipeline until cancelled.
Thread.detachNewThread {
    Thread.sleep(forTimeInterval: 180)
    FileHandle.standardError.write(Data("WATCHDOG: p99tests still running after 180s — a stream never finished. Failing.\n".utf8))
    exit(2)
}

runOutputParserTests()
runP99StatusTests()
runStepsTests()
runAppUpdatesTests()
await runScriptRunnerTests()
T.finish()
