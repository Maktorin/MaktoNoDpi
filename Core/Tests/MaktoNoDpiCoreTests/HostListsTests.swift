import XCTest
@testable import MaktoNoDpiCore

final class HostListsTests: XCTestCase {
    func testGeneralContainsDiscordAndCloudflareNotYouTube() {
        let g = HostLists.general
        XCTAssertTrue(g.contains("discord.com"))
        XCTAssertTrue(g.contains("cloudflare-ech.com"))
        XCTAssertFalse(g.contains("youtube.com"))
    }
    func testGoogleContainsYouTube() {
        XCTAssertTrue(HostLists.google.contains("youtube.com"))
        XCTAssertTrue(HostLists.google.contains("googlevideo.com"))
    }
    func testIpsetAllValue() {
        XCTAssertEqual(HostLists.ipsetAll, "203.0.113.113/32")
    }
    func testListAllIsGeneralPlusGooglePlusDiscord() {
        let expected = HostLists.general + "\n" + HostLists.google + "\n" + HostLists.discord
        XCTAssertEqual(HostLists.listAll(customInclude: []), expected)
    }
    func testCustomIncludeAppendsToGeneral() {
        let all = HostLists.listAll(customInclude: ["example.org"])
        XCTAssertTrue(all.contains("example.org"))
    }
}
