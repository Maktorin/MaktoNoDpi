import Foundation

public struct ConnectivityTester: Sendable {
    private let runner: CommandRunner
    public init(runner: CommandRunner) { self.runner = runner }

    public static func isSuccess(curlOutput: String) -> Bool {
        guard let code = Int(curlOutput.trimmingCharacters(in: .whitespacesAndNewlines)) else { return false }
        return code > 0 && code < 500
    }

    func single(port: Int, timeoutSec: Int, url: String) async -> Bool {
        let args = ["--socks5-hostname", "127.0.0.1:\(port)", "--connect-timeout", "\(timeoutSec)",
                    "-s", "-o", "/dev/null", "-w", "%{http_code}", url]
        guard let r = try? await runner.run("/usr/bin/curl", args) else { return false }
        return Self.isSuccess(curlOutput: r.stdout)
    }

    public func testProxy(port: Int = 1080, timeoutSec: Int = 8) async -> Bool {
        async let yt = single(port: port, timeoutSec: timeoutSec, url: "https://www.youtube.com/")
        async let api = single(port: port, timeoutSec: timeoutSec, url: "https://discord.com/api/v10/gateway")
        async let cdn = single(port: port, timeoutSec: timeoutSec, url: "https://cdn.discordapp.com/")
        var (ytOk, apiOk, cdnOk) = await (yt, api, cdn)
        if ytOk && apiOk && cdnOk { return true }
        if !ytOk { ytOk = await single(port: port, timeoutSec: timeoutSec, url: "https://i.ytimg.com/vi/dQw4w9WgXcQ/hqdefault.jpg"); if !ytOk { return false } }
        var dcOk = apiOk || cdnOk
        if !dcOk {
            let media = await single(port: port, timeoutSec: timeoutSec, url: "https://media.discordapp.net/")
            let gw = await single(port: port, timeoutSec: timeoutSec, url: "https://gateway.discord.gg/")
            dcOk = media || gw
        }
        return dcOk
    }
}
