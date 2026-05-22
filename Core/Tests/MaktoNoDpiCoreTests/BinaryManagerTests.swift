import XCTest
@testable import MaktoNoDpiCore

final class BinaryManagerTests: XCTestCase {
    func testInstallCopiesBundledBinaryAndChmod() throws {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        let bundled = tmp.appendingPathComponent("tpws-bundled")
        try Data([0x7f, 0x45, 0x4c, 0x46]).write(to: bundled)   // dummy
        let supportDir = tmp.appendingPathComponent("support")
        let mgr = BinaryManager(bundledTpws: bundled.path, supportDir: supportDir.path)
        let installed = try mgr.installBundledBinary()
        XCTAssertTrue(FileManager.default.fileExists(atPath: installed))
        let perms = try FileManager.default.attributesOfItem(atPath: installed)[.posixPermissions] as? NSNumber
        XCTAssertEqual(perms?.int16Value, 0o755)
    }
    func testWritesAllListFiles() throws {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let mgr = BinaryManager(bundledTpws: "/dev/null", supportDir: tmp.path)
        let listsDir = try mgr.ensureHostLists(customInclude: [], customExclude: [])
        for f in ["list-general.txt","list-google.txt","list-discord.txt","list-exclude.txt","ipset-exclude.txt","ipset-all.txt","list-all.txt"] {
            XCTAssertTrue(FileManager.default.fileExists(atPath: "\(listsDir)/\(f)"), "missing \(f)")
        }
    }
}
