import XCTest
@testable import MaktoNoDpiCore

final class StrategiesTests: XCTestCase {
    let dir = "/tmp/lists"

    func testCountMatchesReference() {
        XCTAssertEqual(Strategies.darwin(listsDir: dir).count, 52)
    }
    func testFirstTierStrategyArgsExact() {
        let s = Strategies.darwin(listsDir: dir).first { $0.name == "multi:disorder+tlsrec" }!
        XCTAssertEqual(s.args, [
            "--port","1080","--socks",
            "--hostlist=\(dir)/list-all.txt","--hostlist-exclude=\(dir)/list-exclude.txt",
            "--filter-l7=tls","--split-pos=1,midsld","--disorder","--tlsrec=sni",
            "--new",
            "--hostlist=\(dir)/list-all.txt","--hostlist-exclude=\(dir)/list-exclude.txt",
            "--filter-l7=http","--hostcase","--methodeol","--split-pos=1","--disorder"
        ])
    }
    func testBasicSplitDisorder() {
        let s = Strategies.darwin(listsDir: dir).first { $0.name == "split+disorder" }!
        XCTAssertEqual(s.args, ["--port","1080","--socks","--split-pos=1","--disorder","--hostcase",
            "--hostlist=\(dir)/list-all.txt","--hostlist-exclude=\(dir)/list-exclude.txt"])
    }
    func testAllNamesUnique() {
        let names = Strategies.darwin(listsDir: dir).map { $0.name }
        XCTAssertEqual(names.count, Set(names).count)
    }
}
