import XCTest
@testable import MaktoNoDpiCore

final class PrivilegedHelperTests: XCTestCase {

    // MARK: - scriptContents

    func testScriptEmbedsParsableVersionMarker() {
        let s = PrivilegedHelper.scriptContents(pfRules: "RULE", hostsMarker: "# MARK", hostsBlock: "1.2.3.4 x")
        XCTAssertEqual(PrivilegedHelper.installedVersion(in: s), PrivilegedHelper.version)
    }

    func testConnectBranchLoadsPfRulesEnablesPfAndGuardsHosts() {
        let s = PrivilegedHelper.scriptContents(pfRules: "block-rule-X", hostsMarker: "# MARKER", hostsBlock: "9.9.9.9 host")
        XCTAssertTrue(s.contains("connect)"), "missing connect verb")
        XCTAssertTrue(s.contains("block-rule-X"), "pf rules not embedded")
        XCTAssertTrue(s.contains("pfctl -f"), "pf rules not loaded")
        XCTAssertTrue(s.contains("pfctl -E"), "pf not enabled")
        XCTAssertTrue(s.contains("# MARKER"), "hosts marker not embedded")
        XCTAssertTrue(s.contains("9.9.9.9 host"), "hosts block not embedded")
        XCTAssertTrue(s.contains("grep"), "hosts append not guarded by grep marker check")
    }

    func testDisconnectBranchReloadsDefaultPf() {
        let s = PrivilegedHelper.scriptContents(pfRules: "R", hostsMarker: "# M", hostsBlock: "h")
        XCTAssertTrue(s.contains("disconnect)"), "missing disconnect verb")
        XCTAssertTrue(s.contains("pfctl -f /etc/pf.conf"), "disconnect must reload default pf to drop QUIC block")
    }

    func testScriptRejectsUnknownVerb() {
        let s = PrivilegedHelper.scriptContents(pfRules: "R", hostsMarker: "# M", hostsBlock: "h")
        // A usage/error path for anything other than connect/disconnect.
        XCTAssertTrue(s.contains("usage") || s.contains("exit 2"), "unknown verb must not silently succeed")
    }

    func testGeneratedScriptIsValidShell() throws {
        // Guards heredoc-terminator placement: Swift's multiline literal strips
        // leading indentation, and an indented `PFEOF`/`HOSTSEOF` would break the
        // heredoc. Validate the real generated script with `sh -n`.
        let s = PrivilegedHelper.scriptContents(
            pfRules: PrivilegedRunner.pfQuicBlockRules,
            hostsMarker: "# MaktoNoDpi hosts",
            hostsBlock: "1.2.3.4 example.com\n5.6.7.8 other.com"
        )
        let path = NSTemporaryDirectory() + "maktonodpi-helper-test-\(UUID().uuidString).sh"
        try s.write(toFile: path, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(atPath: path) }

        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = ["-n", path]
        let err = Pipe(); p.standardError = err
        try p.run(); p.waitUntilExit()
        let msg = String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        XCTAssertEqual(p.terminationStatus, 0, "sh -n rejected the generated helper:\n\(msg)")
    }

    // MARK: - sudoersContents

    func testSudoersGrantsPasswordlessHelperToUser() {
        let line = PrivilegedHelper.sudoersContents(user: "maktorin")
        XCTAssertEqual(line, "maktorin ALL=(root) NOPASSWD: \(PrivilegedHelper.helperPath)\n")
    }

    // MARK: - installedVersion

    func testInstalledVersionNilWhenMarkerAbsent() {
        XCTAssertNil(PrivilegedHelper.installedVersion(in: "#!/bin/sh\necho hi\n"))
    }

    // MARK: - needsInstall

    func testNeedsInstallWhenNotInstalled() {
        XCTAssertTrue(PrivilegedHelper.needsInstall(installedContents: nil))
    }

    func testNeedsInstallWhenVersionMismatched() {
        let stale = "# MAKTONODPI_HELPER_VERSION=0\n"
        XCTAssertTrue(PrivilegedHelper.needsInstall(installedContents: stale))
    }

    func testNoInstallWhenCurrentVersionPresent() {
        let current = PrivilegedHelper.scriptContents(pfRules: "R", hostsMarker: "# M", hostsBlock: "h")
        XCTAssertFalse(PrivilegedHelper.needsInstall(installedContents: current))
    }

    // MARK: - installScript

    func testInstallScriptPlacesHelperRootOwnedNonWritable() {
        let s = PrivilegedHelper.installScript(stagedHelperPath: "/tmp/h.sh", stagedSudoersPath: "/tmp/s")
        XCTAssertTrue(s.contains(PrivilegedHelper.installDir), "must create the fixed install dir")
        XCTAssertTrue(s.contains("root:wheel"), "helper must be owned root:wheel")
        XCTAssertTrue(s.contains("0755"), "helper must be 0755 (not user-writable)")
        XCTAssertTrue(s.contains(PrivilegedHelper.helperPath), "must install to fixed helper path")
        XCTAssertTrue(s.contains("/tmp/h.sh"), "must read the staged helper")
    }

    func testInstallScriptInstallsSudoersAndValidates() {
        let s = PrivilegedHelper.installScript(stagedHelperPath: "/tmp/h.sh", stagedSudoersPath: "/tmp/s")
        XCTAssertTrue(s.contains(PrivilegedHelper.sudoersPath), "must install sudoers drop-in")
        XCTAssertTrue(s.contains("0440"), "sudoers must be 0440")
        XCTAssertTrue(s.contains("visudo -c"), "sudoers must be syntax-validated")
        XCTAssertTrue(s.contains("rm"), "must roll back sudoers on validation failure")
    }
}
