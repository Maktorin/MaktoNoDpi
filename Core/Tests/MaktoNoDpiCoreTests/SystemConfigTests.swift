import XCTest
@testable import MaktoNoDpiCore

actor FakeCommandRunner: CommandRunner {
    private(set) var calls: [(String, [String])] = []
    var responder: (@Sendable (String, [String]) -> CommandResult)?
    func run(_ launchPath: String, _ args: [String]) async throws -> CommandResult {
        calls.append((launchPath, args))
        return responder?(launchPath, args) ?? CommandResult(status: 0, stdout: "", stderr: "")
    }
    func recorded() -> [(String, [String])] { calls }
}

final class SystemConfigTests: XCTestCase {
    func testEnableProxyIssuesSetAndStateOnPerService() async throws {
        let fake = FakeCommandRunner()
        let cfg = SystemConfig(runner: fake)
        await cfg.enableProxy(port: 1080, services: ["Wi-Fi"])
        let calls = await fake.recorded()
        XCTAssertTrue(calls.contains { $0.1 == ["-setsocksfirewallproxy","Wi-Fi","127.0.0.1","1080"] })
        XCTAssertTrue(calls.contains { $0.1 == ["-setsocksfirewallproxystate","Wi-Fi","on"] })
    }
    func testDisableProxyTurnsStateOff() async throws {
        let fake = FakeCommandRunner()
        let cfg = SystemConfig(runner: fake)
        await cfg.disableProxy(services: ["Wi-Fi"])
        let calls = await fake.recorded()
        XCTAssertTrue(calls.contains { $0.1 == ["-setsocksfirewallproxystate","Wi-Fi","off"] })
    }
}
