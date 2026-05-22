import XCTest
@testable import MaktoNoDpiCore

final class PatternFilesTests: XCTestCase {
    func testQuicInitialIs256BytesWithLongHeader() {
        let buf = PatternFiles.fakeQuicInitial()
        XCTAssertEqual(buf.count, 256)
        XCTAssertEqual(buf[0], 0xc3)
        XCTAssertEqual(Array(buf[1...4]), [0,0,0,1])
        XCTAssertEqual(buf[5], 0x08)
    }
    func testTlsClientHelloHasHandshakeRecordAndSNI() {
        let sni = "www.google.com"
        let rec = PatternFiles.fakeTlsClientHello(sni: sni)
        XCTAssertEqual(rec[0], 0x16)
        XCTAssertEqual(rec[5], 0x01)
        let sniBytes = Array(sni.utf8)
        XCTAssertTrue(Array(rec).containsSubsequence(sniBytes))
    }
}

private extension Array where Element == UInt8 {
    func containsSubsequence(_ sub: [UInt8]) -> Bool {
        guard !sub.isEmpty, count >= sub.count else { return false }
        for i in 0...(count - sub.count) where Array(self[i..<i+sub.count]) == sub { return true }
        return false
    }
}
