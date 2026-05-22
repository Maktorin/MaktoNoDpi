import Foundation

public enum NetworkServices {
    public static func parseServiceList(_ raw: String) -> [String] {
        raw.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("An asterisk") }
    }
    public static func infoIndicatesActive(_ info: String) -> Bool {
        info.range(of: #"IP address:\s*\d+\.\d+\.\d+\.\d+"#, options: .regularExpression) != nil
    }
    /// Live enumeration using a CommandRunner (used by SystemConfig).
    public static func active(using runner: CommandRunner) async throws -> [String] {
        let list = try await runner.run("/usr/sbin/networksetup", ["-listallnetworkservices"])
        let all = parseServiceList(list.stdout)
        var active: [String] = []
        for svc in all {
            let info = try await runner.run("/usr/sbin/networksetup", ["-getinfo", svc])
            if infoIndicatesActive(info.stdout) { active.append(svc) }
        }
        return active.isEmpty ? all.filter { $0.range(of: #"(?i)wi-fi|ethernet|usb"#, options: .regularExpression) != nil } : active
    }
}
