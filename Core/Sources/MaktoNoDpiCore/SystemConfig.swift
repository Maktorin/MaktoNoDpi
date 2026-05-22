import Foundation

public actor SystemConfig {
    private let runner: CommandRunner
    private let setup = "/usr/sbin/networksetup"
    private var originalDns: [String: String] = [:]
    public init(runner: CommandRunner) { self.runner = runner }

    public func enableProxy(port: Int, services: [String]) async {
        for s in services {
            _ = try? await runner.run(setup, ["-setsocksfirewallproxy", s, "127.0.0.1", "\(port)"])
            _ = try? await runner.run(setup, ["-setsocksfirewallproxystate", s, "on"])
        }
    }
    public func disableProxy(services: [String]) async {
        for s in services { _ = try? await runner.run(setup, ["-setsocksfirewallproxystate", s, "off"]) }
    }
    public func setCleanDns(services: [String]) async {
        for s in services {
            let info = (try? await runner.run(setup, ["-getdnsservers", s]))?.stdout ?? ""
            originalDns[s] = info
            _ = try? await runner.run(setup, ["-setdnsservers", s, "1.1.1.1", "8.8.8.8", "1.0.0.1", "8.8.4.4"])
        }
    }
    public func restoreDns(services: [String]) async {
        let all = Set(originalDns.keys).union(services)
        for s in all {
            let orig = originalDns[s] ?? ""
            if !orig.isEmpty && !orig.contains("aren't any") && !orig.contains("Error") {
                let servers = orig.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
                _ = try? await runner.run(setup, ["-setdnsservers", s] + servers)
            } else {
                _ = try? await runner.run(setup, ["-setdnsservers", s, "Empty"])
            }
        }
        originalDns.removeAll()
    }
    public func flushDnsCache() async {
        _ = try? await runner.run("/usr/bin/dscacheutil", ["-flushcache"])
        _ = try? await runner.run("/usr/bin/killall", ["-HUP", "mDNSResponder"])
    }
}
