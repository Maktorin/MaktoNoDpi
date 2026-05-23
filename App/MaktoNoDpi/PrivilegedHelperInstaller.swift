import Foundation
import MaktoNoDpiCore

/// App-side orchestration for the root-owned privileged helper (see
/// `PrivilegedHelper` in Core for the security model). Installs the helper +
/// `sudoers` rule on first use (one admin prompt) and afterwards drives the
/// privileged connect/disconnect through passwordless `sudo`.
enum PrivilegedHelperInstaller {

    enum HelperError: LocalizedError {
        case installFailed(Int32)
        case verifyFailed
        var errorDescription: String? {
            switch self {
            case .installFailed(let s): return "Не удалось установить служебный компонент (код \(s))"
            case .verifyFailed:         return "Служебный компонент установлен, но не прошёл проверку"
            }
        }
    }

    /// Contents of the currently-installed helper, or nil if absent/unreadable.
    private static func installedContents() -> String? {
        try? String(contentsOfFile: PrivilegedHelper.helperPath, encoding: .utf8)
    }

    /// Ensure the helper + sudoers rule are installed at the current version.
    /// Triggers exactly one admin prompt when (re)install is needed; no-op when
    /// already current. Throws if the user cancels or install/validation fails.
    static func ensureInstalled(pfRules: String, hostsMarker: String, hostsBlock: String) async throws {
        guard PrivilegedHelper.needsInstall(installedContents: installedContents()) else { return }

        let helper = PrivilegedHelper.scriptContents(pfRules: pfRules, hostsMarker: hostsMarker, hostsBlock: hostsBlock)
        let sudoers = PrivilegedHelper.sudoersContents(user: NSUserName())

        // Stage into the per-user temp dir (mode 0700), then let root install with
        // the correct ownership/modes — no caller-supplied path reaches the final
        // privileged location.
        let tmp = FileManager.default.temporaryDirectory
        let stagedHelper = tmp.appendingPathComponent("maktonodpi-helper.stage").path
        let stagedSudoers = tmp.appendingPathComponent("maktonodpi-sudoers.stage").path
        try helper.write(toFile: stagedHelper, atomically: true, encoding: .utf8)
        try sudoers.write(toFile: stagedSudoers, atomically: true, encoding: .utf8)
        defer {
            try? FileManager.default.removeItem(atPath: stagedHelper)
            try? FileManager.default.removeItem(atPath: stagedSudoers)
        }

        let script = PrivilegedHelper.installScript(stagedHelperPath: stagedHelper, stagedSudoersPath: stagedSudoers)
        let result = try await PrivilegedRunner(runner: SystemCommandRunner()).run(shellScript: script)
        guard result.status == 0 else { throw HelperError.installFailed(result.status) }
        guard !PrivilegedHelper.needsInstall(installedContents: installedContents()) else {
            throw HelperError.verifyFailed
        }
    }

    /// Run a helper verb (`connect`/`disconnect`) via passwordless sudo.
    /// Returns false on any failure (e.g. rule missing). Never prompts (`-n`).
    @discardableResult
    static func run(_ verb: String) async -> Bool {
        let r = try? await SystemCommandRunner().run("/usr/bin/sudo", ["-n", PrivilegedHelper.helperPath, verb])
        return (r?.status ?? -1) == 0
    }
}
