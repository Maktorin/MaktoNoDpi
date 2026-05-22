import XCTest
@testable import MaktoNoDpiCore

final class SettingsStoreTests: XCTestCase {
    func testDefaults() {
        let d = UserDefaults(suiteName: UUID().uuidString)!
        let s = SettingsStore(defaults: d)
        XCTAssertFalse(s.autoStart)
        XCTAssertFalse(s.autoConnect)
        XCTAssertEqual(s.selectedStrategy, "auto")
        XCTAssertNil(s.lastWorkingStrategy)
    }
    func testPersistLastWorking() {
        let d = UserDefaults(suiteName: UUID().uuidString)!
        var s = SettingsStore(defaults: d)
        s.lastWorkingStrategy = "split+disorder"
        XCTAssertEqual(SettingsStore(defaults: d).lastWorkingStrategy, "split+disorder")
    }
}
