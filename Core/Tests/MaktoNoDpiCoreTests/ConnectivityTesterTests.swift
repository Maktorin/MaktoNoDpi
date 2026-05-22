import XCTest
@testable import MaktoNoDpiCore

final class ConnectivityTesterTests: XCTestCase {
    func testParseHttpCodeSuccessRange() {
        XCTAssertTrue(ConnectivityTester.isSuccess(curlOutput: "200"))
        XCTAssertTrue(ConnectivityTester.isSuccess(curlOutput: "301"))
        XCTAssertFalse(ConnectivityTester.isSuccess(curlOutput: "000"))
        XCTAssertFalse(ConnectivityTester.isSuccess(curlOutput: "503"))
    }
    func testProxyTestPassesWhenAllPrimaryEndpointsReturn200() async {
        let fake = FakeCommandRunner()
        await fake.setResponder { _, _ in CommandResult(status: 0, stdout: "200", stderr: "") }
        let t = ConnectivityTester(runner: fake)
        let ok = await t.testProxy(port: 1080, timeoutSec: 5)
        XCTAssertTrue(ok)
    }

    // MARK: - classify (code + latency parsing)

    func testClassifyHealthy() {
        let r = ConnectivityTester.classify(curlOutput: "200 0.042000")
        XCTAssertEqual(r.state, .ok)
        XCTAssertEqual(r.latencyMs, 42)
    }
    func testClassifyDegradedWhenSlow() {
        let r = ConnectivityTester.classify(curlOutput: "200 0.350")
        XCTAssertEqual(r.state, .degraded)
        XCTAssertEqual(r.latencyMs, 350)
    }
    func testClassifyDownOnZeroCode() {
        let r = ConnectivityTester.classify(curlOutput: "000 0.000000")
        XCTAssertEqual(r.state, .down)
        XCTAssertEqual(r.latencyMs, 0)
    }
    func testClassifyDownOnServerError() {
        XCTAssertEqual(ConnectivityTester.classify(curlOutput: "503 0.1").state, .down)
    }
    func testClassifyDownOnGarbage() {
        let r = ConnectivityTester.classify(curlOutput: "curl: (7) failed")
        XCTAssertEqual(r.state, .down)
        XCTAssertNil(r.latencyMs)
    }
    func testClassifyTrimsWhitespace() {
        let r = ConnectivityTester.classify(curlOutput: "  301 0.075\n")
        XCTAssertEqual(r.state, .ok)
        XCTAssertEqual(r.latencyMs, 75)
    }

    // MARK: - testServices (per-service status)

    func testServicesReturnsAllThreeInOrder() async {
        let fake = FakeCommandRunner()
        await fake.setResponder { _, args in
            // distinguish by URL (last arg): give each a distinct latency
            let url = args.last ?? ""
            if url.contains("youtube")  { return CommandResult(status: 0, stdout: "200 0.042", stderr: "") }
            if url.contains("discord")  { return CommandResult(status: 0, stdout: "200 0.038", stderr: "") }
            return CommandResult(status: 0, stdout: "200 0.360", stderr: "") // telegram → slow
        }
        let t = ConnectivityTester(runner: fake)
        let result = await t.testServices(port: 1080, timeoutSec: 5)
        XCTAssertEqual(result.map(\.service), [.youtube, .discord, .telegram])
        XCTAssertEqual(result[0].state, .ok)
        XCTAssertEqual(result[0].latencyMs, 42)
        XCTAssertEqual(result[2].state, .degraded)   // telegram slow → degraded
    }
}

extension FakeCommandRunner {
    func setResponder(_ r: @escaping @Sendable (String, [String]) -> CommandResult) { self.responder = r }
}
