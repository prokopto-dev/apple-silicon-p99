import Foundation

// Minimal test harness. Deliberately homegrown: Apple's Command Line Tools
// ship neither XCTest nor swift-testing (both are Xcode components), and this
// repo promises to build with CLT alone — a swift-testing dependency would
// drag in swift-syntax and minutes of macro compilation for no gain at this
// scale.
enum T {
    static var passed = 0
    static var failed = 0
    static var lastLabel = "(none)" // for the watchdog's hang diagnostic

    static func expect(_ condition: @autoclosure () -> Bool, _ label: String,
                       file: StaticString = #file, line: UInt = #line) {
        lastLabel = label
        if condition() {
            passed += 1
        } else {
            failed += 1
            let name = ("\(file)" as NSString).lastPathComponent
            print("FAIL: \(label)  [\(name):\(line)]")
        }
    }

    static func equal<V: Equatable>(_ actual: V, _ expected: V, _ label: String,
                                    file: StaticString = #file, line: UInt = #line) {
        lastLabel = label
        if actual == expected {
            passed += 1
        } else {
            failed += 1
            let name = ("\(file)" as NSString).lastPathComponent
            print("FAIL: \(label)  [\(name):\(line)]")
            print("      expected: \(expected)")
            print("      actual:   \(actual)")
        }
    }

    static func finish() -> Never {
        print(failed == 0 ? "OK — \(passed) assertions passed"
                          : "FAILED — \(failed) of \(passed + failed) assertions failed")
        exit(failed == 0 ? 0 : 1)
    }
}
