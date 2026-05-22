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
}

extension FakeCommandRunner {
    func setResponder(_ r: @escaping @Sendable (String, [String]) -> CommandResult) { self.responder = r }
}
