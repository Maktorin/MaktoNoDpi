import XCTest
@testable import MaktoNoDpiCore

final class PrivilegedRunnerTests: XCTestCase {
    func testBuildConnectScriptHasPfAndHostsGuard() {
        let script = PrivilegedRunner.buildConnectScript(
            pfConfPath: "/tmp/pf.conf",
            hostsAddFile: "/tmp/hosts-add.txt",
            hostsMarker: HostsData.marker
        )
        XCTAssertTrue(script.contains("pfctl -f /tmp/pf.conf"))
        XCTAssertTrue(script.contains("pfctl -E"))
        XCTAssertTrue(script.contains("grep -q")) // marker guard before appending hosts
        XCTAssertTrue(script.contains(HostsData.marker))
    }
    func testPfRulesContent() {
        let rules = PrivilegedRunner.pfQuicBlockRules
        XCTAssertTrue(rules.contains("block return out quick proto udp from any to any port 443"))
        XCTAssertTrue(rules.contains("port 19294:19344"))
        XCTAssertTrue(rules.contains("port 50000:50100"))
    }
    func testEscapingForOsascript() {
        // Double-quotes inside the shell script must be escaped for AppleScript string literal.
        let wrapped = PrivilegedRunner.osascriptArguments(forShellScript: "echo \"hi\"")
        XCTAssertEqual(wrapped[0], "-e")
        XCTAssertTrue(wrapped[1].contains("with administrator privileges"))
        XCTAssertFalse(wrapped[1].contains("echo \"hi\""))   // raw quotes must be escaped, not literal
    }
}
