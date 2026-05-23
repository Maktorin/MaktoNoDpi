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

    // MARK: - Per-service status + latency (dashboard)

    /// Representative endpoint pinged for each flagship service.
    static let serviceURL: [ServiceID: String] = [
        .youtube:  "https://www.youtube.com/",
        .discord:  "https://discord.com/api/v10/gateway",
        .telegram: "https://web.telegram.org/",
    ]

    /// Latency at or above this (ms) downgrades a reachable service to `.degraded`.
    public static let degradedThresholdMs = 300

    /// Parse curl `-w "%{http_code} %{time_total}"` output into a state + latency.
    /// `time_total` is seconds (curl always emits a `.` decimal); converted to ms.
    public static func classify(curlOutput: String,
                                degradedThresholdMs: Int = degradedThresholdMs) -> (state: ServiceStatus.State, latencyMs: Int?) {
        let parts = curlOutput.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: " ")
        guard let code = Int(parts.first ?? "") else { return (.down, nil) }
        let latencyMs: Int? = parts.count > 1 ? Double(parts[1]).map { Int(($0 * 1000).rounded()) } : nil
        guard code > 0 && code < 500 else { return (.down, latencyMs) }
        if let ms = latencyMs, ms >= degradedThresholdMs { return (.degraded, ms) }
        return (.ok, latencyMs)
    }

    private func probeService(_ id: ServiceID, port: Int, timeoutSec: Int) async -> ServiceStatus {
        let url = Self.serviceURL[id] ?? ""
        let args = ["--socks5-hostname", "127.0.0.1:\(port)", "--connect-timeout", "\(timeoutSec)",
                    "-s", "-o", "/dev/null", "-w", "%{http_code} %{time_total}", url]
        guard let r = try? await runner.run("/usr/bin/curl", args) else {
            return ServiceStatus(service: id, state: .down, latencyMs: nil)
        }
        let (state, ms) = Self.classify(curlOutput: r.stdout)
        return ServiceStatus(service: id, state: state, latencyMs: ms)
    }

    /// Probe all flagship services concurrently; results returned in `ServiceID.allCases` order.
    public func testServices(port: Int = 1080, timeoutSec: Int = 8) async -> [ServiceStatus] {
        async let yt = probeService(.youtube, port: port, timeoutSec: timeoutSec)
        async let dc = probeService(.discord, port: port, timeoutSec: timeoutSec)
        async let tg = probeService(.telegram, port: port, timeoutSec: timeoutSec)
        return await [yt, dc, tg]
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
