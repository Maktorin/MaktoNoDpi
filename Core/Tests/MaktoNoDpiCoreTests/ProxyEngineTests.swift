import XCTest
@testable import MaktoNoDpiCore

/// A child process that is always "running" and whose kill/onTerminate are no-ops.
final class FakeRunningProcess: RunningProcess, @unchecked Sendable {
    var isRunning: Bool { true }
    func kill() {}
    func onTerminate(_ handler: @escaping @Sendable (Int32) -> Void) {}
}

/// A ProcessRunner that always returns an always-running fake process.
final class FakeProcessRunner: ProcessRunner, @unchecked Sendable {
    func spawn(_ launchPath: String, _ args: [String]) throws -> RunningProcess {
        FakeRunningProcess()
    }
}

/// A ConnectivityProbing fake that returns successive booleans from an injected array.
actor ScriptedTester: ConnectivityProbing {
    private let results: [Bool]
    private var index = 0
    init(results: [Bool]) { self.results = results }
    func testProxy(port: Int, timeoutSec: Int) async -> Bool {
        guard index < results.count else { return false }
        let r = results[index]
        index += 1
        return r
    }
}

final class ProxyEngineTests: XCTestCase {
    func testConnectsOnSecondStrategyAndPersistsLastWorking() async throws {
        let fakeProc = FakeProcessRunner()                 // always "running"
        let fakeCmd = FakeCommandRunner()                  // proxy/dns no-ops
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        var settings = SettingsStore(defaults: defaults)

        // ConnectivityTester fake: fail first probe, succeed second.
        let tester = ScriptedTester(results: [false, true])
        let engine = ProxyEngine(
            strategies: [Strategy(name: "A", args: []), Strategy(name: "B", args: [])],
            processRunner: fakeProc, commandRunner: fakeCmd,
            tester: tester, settings: settings,
            activeServices: { ["Wi-Fi"] }, portProbe: { _ in true },
            elevate: { _ in }, prepareFiles: { "/tmp/lists" }
        )
        let phase = try await engine.connect()
        guard case .connected(let strategy, _) = phase else { return XCTFail("not connected: \(phase)") }
        XCTAssertEqual(strategy, "B")
        XCTAssertEqual(SettingsStore(defaults: defaults).lastWorkingStrategy, "B")
    }

    func testAllStrategiesFailReturnsError() async throws {
        let engine = ProxyEngine(
            strategies: [Strategy(name: "A", args: [])],
            processRunner: FakeProcessRunner(), commandRunner: FakeCommandRunner(),
            tester: ScriptedTester(results: [false]), settings: SettingsStore(defaults: UserDefaults(suiteName: UUID().uuidString)!),
            activeServices: { ["Wi-Fi"] }, portProbe: { _ in true }, elevate: { _ in }, prepareFiles: { "/tmp/lists" }
        )
        let phase = try await engine.connect()
        guard case .error(let code, _) = phase else { return XCTFail("expected error") }
        XCTAssertEqual(code, .allStrategiesFailed)
    }
}
