import Foundation

/// Minimal test harness: `test("name") { expect(...) }`, then `finish()` exits non-zero on failure.
private var failures: [String] = []
private var currentTest = ""
private var testCount = 0

func test(_ name: String, _ body: () throws -> Void) {
    currentTest = name
    testCount += 1
    let before = failures.count
    do { try body() } catch { failures.append("\(name): threw \(error)") }
    print(failures.count == before ? "  ✓ \(name)" : "  ✗ \(name)")
}

func expect(_ condition: @autoclosure () -> Bool, _ message: @autoclosure () -> String = "",
            file: StaticString = #fileID, line: UInt = #line) {
    if !condition() { failures.append("\(currentTest) (\(file):\(line)) \(message())") }
}

func expectEqual<T: Equatable>(_ a: T, _ b: T, file: StaticString = #fileID, line: UInt = #line) {
    expect(a == b, "expected \(b), got \(a)", file: file, line: line)
}

func expectClose(_ a: Float, _ b: Float, tolerance: Float = 1e-3,
                 file: StaticString = #fileID, line: UInt = #line) {
    expect(abs(a - b) <= tolerance, "expected \(b) ± \(tolerance), got \(a)", file: file, line: line)
}

func section(_ name: String) { print(name) }

func finish() -> Never {
    print("")
    if failures.isEmpty {
        print("All \(testCount) tests passed.")
        exit(0)
    }
    print("\(failures.count) failure(s) in \(testCount) tests:")
    for f in failures { print("  - \(f)") }
    exit(1)
}
