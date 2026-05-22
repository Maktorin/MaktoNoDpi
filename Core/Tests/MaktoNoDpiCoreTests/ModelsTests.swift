import XCTest
@testable import MaktoNoDpiCore

final class ModelsTests: XCTestCase {
    func testErrorCodesMatchElectron() {
        XCTAssertEqual(ProxyError.allStrategiesFailed.rawValue, "ALL_STRATEGIES_FAILED")
        XCTAssertEqual(ProxyError.noBinary.rawValue, "NO_BINARY")
        XCTAssertEqual(ProxyError.networkUnavailable.rawValue, "NETWORK_UNAVAILABLE")
    }
}
