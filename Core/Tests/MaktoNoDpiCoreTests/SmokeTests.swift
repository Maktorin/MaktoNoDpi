import XCTest
@testable import MaktoNoDpiCore

final class SmokeTests: XCTestCase {
    func testVersionExists() {
        XCTAssertFalse(MaktoNoDpiCore.version.isEmpty)
    }
}
