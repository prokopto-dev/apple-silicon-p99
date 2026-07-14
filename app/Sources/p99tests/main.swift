// Test runner: swift run --package-path app p99tests   (or `make test`)

import Foundation

// Line-buffer stdout even when piped (CI): otherwise a hang swallows all
// progress output and the logs can't show which test wedged.
setvbuf(stdout, nil, _IOLBF, 0)

// Watchdog: a healthy run finishes in seconds. If anything wedges (the CI
// coverage run has stalled here), fail loudly after 3 minutes — naming the
// last assertion that completed — instead of hanging until cancelled.
Thread.detachNewThread {
    Thread.sleep(forTimeInterval: 180)
    let msg = "WATCHDOG: p99tests still running after 180s — hung after "
            + "\(T.passed + T.failed) assertions; last completed: '\(T.lastLabel)'. Failing.\n"
    FileHandle.standardError.write(Data(msg.utf8))
    exit(2)
}

runOutputParserTests()
runP99StatusTests()
runStepsTests()
runAppUpdatesTests()
await runScriptRunnerTests()
T.finish()
