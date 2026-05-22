import XCTest
@testable import MaktoNoDpiCore

final class CommandRunnerTests: XCTestCase {
    func testEchoReturnsStdoutAndZeroStatus() async throws {
        let r = SystemCommandRunner()
        let result = try await r.run("/bin/echo", ["hello"])
        XCTAssertEqual(result.status, 0)
        XCTAssertEqual(result.stdout.trimmingCharacters(in: .whitespacesAndNewlines), "hello")
    }
    func testNonzeroStatus() async throws {
        let r = SystemCommandRunner()
        let result = try await r.run("/bin/sh", ["-c", "exit 3"])
        XCTAssertEqual(result.status, 3)
    }
}
