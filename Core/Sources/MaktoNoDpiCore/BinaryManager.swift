import Foundation

public struct BinaryManager: Sendable {
    let bundledTpws: String
    let supportDir: String
    public init(bundledTpws: String, supportDir: String) { self.bundledTpws = bundledTpws; self.supportDir = supportDir }

    var binDir: String { "\(supportDir)/bin" }
    public var installedTpwsPath: String { "\(binDir)/tpws" }
    public var listsDir: String { "\(supportDir)/lists" }

    public func installBundledBinary() throws -> String {
        try FileManager.default.createDirectory(atPath: binDir, withIntermediateDirectories: true)
        if FileManager.default.fileExists(atPath: installedTpwsPath) { try? FileManager.default.removeItem(atPath: installedTpwsPath) }
        try FileManager.default.copyItem(atPath: bundledTpws, toPath: installedTpwsPath)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: installedTpwsPath)
        return installedTpwsPath
    }

    @discardableResult
    public func ensureHostLists(customInclude: [String], customExclude: [String]) throws -> String {
        try FileManager.default.createDirectory(atPath: listsDir, withIntermediateDirectories: true)
        func write(_ name: String, _ content: String) throws { try content.write(toFile: "\(listsDir)/\(name)", atomically: true, encoding: .utf8) }
        let general = customInclude.isEmpty ? HostLists.general : HostLists.general + "\n" + customInclude.joined(separator: "\n")
        let exclude = customExclude.isEmpty ? HostLists.exclude : HostLists.exclude + "\n" + customExclude.joined(separator: "\n")
        try write("list-general.txt", general)
        try write("list-google.txt", HostLists.google)
        try write("list-discord.txt", HostLists.discord)
        try write("list-exclude.txt", exclude)
        try write("ipset-exclude.txt", HostLists.ipsetExclude)
        try write("ipset-all.txt", HostLists.ipsetAll)
        try write("list-all.txt", general + "\n" + HostLists.google + "\n" + HostLists.discord)
        return listsDir
    }

    public func ensurePatternFiles() throws {
        try FileManager.default.createDirectory(atPath: binDir, withIntermediateDirectories: true)
        let quic = "\(binDir)/quic_initial_www_google_com.bin"
        if !FileManager.default.fileExists(atPath: quic) {
            try Data(PatternFiles.fakeQuicInitial()).write(to: URL(fileURLWithPath: quic))
        }
        for (file, sni) in [("tls_clienthello_www_google_com.bin","www.google.com"),
                            ("tls_clienthello_4pda_to.bin","4pda.to"),
                            ("tls_clienthello_max_ru.bin","max.ru")] {
            let p = "\(binDir)/\(file)"
            if !FileManager.default.fileExists(atPath: p) {
                try Data(PatternFiles.fakeTlsClientHello(sni: sni)).write(to: URL(fileURLWithPath: p))
            }
        }
    }

    /// Best-effort network refresh of tpws from latest zapret release. No-ops on any failure.
    public func updateFromNetwork() async { /* best-effort; see docs/reference/electron-main.js:1281-1468 */ }
}
