import XCTest
@testable import MaktoNoDpiCore

final class NetworkServicesTests: XCTestCase {
    func testParseListDropsHeader() {
        let raw = """
        An asterisk (*) denotes that a network service is disabled.
        Wi-Fi
        Thunderbolt Bridge
        """
        XCTAssertEqual(NetworkServices.parseServiceList(raw), ["Wi-Fi", "Thunderbolt Bridge"])
    }
    func testActiveDetectsIPv4() {
        XCTAssertTrue(NetworkServices.infoIndicatesActive("IP address: 192.168.1.5\nSubnet mask: 255.255.255.0"))
        XCTAssertFalse(NetworkServices.infoIndicatesActive("IP address: \n"))
    }
}
