import Foundation

public struct PrivilegedRunner: Sendable {
    private let runner: CommandRunner
    public init(runner: CommandRunner) { self.runner = runner }

    public static let pfQuicBlockRules = [
        "block return out quick proto udp from any to any port 443",
        "block return out quick proto udp from any to any port 19294:19344",
        "block return out quick proto udp from any to any port 50000:50100"
    ].joined(separator: "\n")

    /// Builds the combined privileged shell script for a connection.
    public static func buildConnectScript(pfConfPath: String, hostsAddFile: String, hostsMarker: String) -> String {
        return [
            "/sbin/pfctl -f \(pfConfPath) 2>/dev/null",
            "/sbin/pfctl -E 2>/dev/null",
            "if ! grep -q '\(hostsMarker)' /etc/hosts; then /bin/cat \(hostsAddFile) >> /etc/hosts; fi",
            "exit 0"
        ].joined(separator: "; ")
    }

    /// AppleScript-escape a shell script and wrap it for `do shell script ... with administrator privileges`.
    public static func osascriptArguments(forShellScript shell: String) -> [String] {
        let escaped = shell.replacingOccurrences(of: "\\", with: "\\\\")
                           .replacingOccurrences(of: "\"", with: "\\\"")
        return ["-e", "do shell script \"\(escaped)\" with administrator privileges"]
    }

    /// Run a privileged shell script (single password prompt).
    public func run(shellScript: String) async throws -> CommandResult {
        try await runner.run("/usr/bin/osascript", Self.osascriptArguments(forShellScript: shellScript))
    }
}
