import XCTest
@testable import MaktoNoDpiCore

final class HostsDataTests: XCTestCase {
    func testMarkerAndUrl() {
        XCTAssertEqual(HostsData.marker, "# MaktoNoDpi Discord/Telegram hosts")
        XCTAssertEqual(HostsData.url, "https://raw.githubusercontent.com/Flowseal/zapret-discord-youtube/main/.service/hosts")
    }
    func testFallbackHasVoiceEntries() {
        let data = HostsData.fallback()
        XCTAssertTrue(data.contains("104.25.158.178 russia10000.discord.media"))
        XCTAssertTrue(data.contains("104.25.158.178 finland10099.discord.media"))
        XCTAssertTrue(data.contains("149.154.167.220 t.me"))
        let voiceLines = data.split(separator: "\n").filter { $0.contains(".discord.media") }
        XCTAssertEqual(voiceLines.count, 2800)
    }
}
