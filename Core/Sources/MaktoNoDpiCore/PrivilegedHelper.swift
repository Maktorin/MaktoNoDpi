import Foundation

/// Root-owned helper + `sudoers` drop-in that lets the app perform its two
/// privileged operations (QUIC pf-block on connect, pf-reload on disconnect)
/// **without a password prompt** after a single one-time install.
///
/// Why this instead of an `SMAppService` privileged helper: the Apple-blessed
/// "authorize once, forever" daemon requires a Developer ID signature, which we
/// don't have for the direct unsigned distribution. A root-owned script plus a
/// scoped `NOPASSWD` sudoers rule achieves the same UX without signing.
///
/// Security model (the rule is a local privesc surface, so it is tightly scoped):
///  - The helper is owned `root:wheel`, mode `0755`, and lives in a `root`-owned
///    directory — neither the file nor its parent is user-writable, so malware
///    running as the user cannot rewrite what `sudo` will execute as root.
///  - The helper accepts only the verbs `connect` / `disconnect`; the pf rules
///    and hosts entries are **baked into the script**, never passed in from the
///    (unsigned, tamperable) app — so the worst a compromised app can do is run
///    connect/disconnect, not load an arbitrary firewall config as root.
///  - The sudoers drop-in grants `NOPASSWD` for that one fixed path only and is
///    syntax-validated with `visudo -c` before being kept.
public enum PrivilegedHelper {

    /// Bump whenever `scriptContents` changes; drives reinstall detection so an
    /// app update that ships a new helper re-prompts once to replace the stale one.
    public static let version = 1

    /// Fixed `root`-owned install location. Deliberately under `/Library` (root-owned,
    /// so a `mkdir` as root yields a root-owned dir) and with NO spaces — a space in
    /// the path would be a token separator in the sudoers command spec. Must NOT be
    /// the user's `~/Library/Application Support` (user-writable) nor `/usr/local`
    /// (Homebrew makes it user-writable → the helper could be replaced).
    public static let installDir = "/Library/MaktoNoDpi"
    public static let helperPath = installDir + "/quic-helper.sh"
    public static let sudoersPath = "/etc/sudoers.d/maktonodpi"

    private static let versionPrefix = "MAKTONODPI_HELPER_VERSION="

    /// The root helper script. Verbs: `connect` | `disconnect`. The pf rules and
    /// hosts block are embedded so no caller-supplied paths reach root.
    public static func scriptContents(pfRules: String, hostsMarker: String, hostsBlock: String) -> String {
        """
        #!/bin/sh
        # MaktoNoDpi privileged helper — QUIC pf-block + Discord/Telegram hosts.
        # \(versionPrefix)\(version)
        # Installed root:wheel 0755; invoked via a scoped NOPASSWD sudoers rule.
        case "$1" in
        connect)
          RULES="$(/usr/bin/mktemp /tmp/maktonodpi-pf.XXXXXX)"
          /bin/cat > "$RULES" <<'PFEOF'
        \(pfRules)
        PFEOF
          /sbin/pfctl -f "$RULES" 2>/dev/null
          /sbin/pfctl -E 2>/dev/null
          /bin/rm -f "$RULES"
          if ! /usr/bin/grep -q '\(hostsMarker)' /etc/hosts; then
            /bin/cat >> /etc/hosts <<'HOSTSEOF'
        \(hostsMarker)
        \(hostsBlock)
        HOSTSEOF
          fi
          ;;
        disconnect)
          /sbin/pfctl -f /etc/pf.conf 2>/dev/null
          ;;
        *)
          echo "usage: $0 connect|disconnect" >&2
          exit 2
          ;;
        esac
        exit 0
        """
    }

    /// The `sudoers` line granting passwordless exec of the installed helper to `user`.
    public static func sudoersContents(user: String) -> String {
        "\(user) ALL=(root) NOPASSWD: \(helperPath)\n"
    }

    /// Parse the embedded version from an installed helper's contents (nil if absent).
    public static func installedVersion(in contents: String) -> Int? {
        for line in contents.split(separator: "\n") {
            guard let r = line.range(of: versionPrefix) else { continue }
            return Int(line[r.upperBound...].trimmingCharacters(in: .whitespaces))
        }
        return nil
    }

    /// Whether (re)install is needed given the currently-installed helper contents
    /// (`nil` = not installed). True when missing or version-mismatched.
    public static func needsInstall(installedContents: String?) -> Bool {
        guard let contents = installedContents else { return true }
        return installedVersion(in: contents) != version
    }

    /// One-time privileged shell script (run via `osascript` → single admin prompt)
    /// that atomically installs the staged helper + sudoers with correct
    /// ownership/modes and validates the sudoers syntax, rolling back on failure.
    ///
    /// Single-line and `&&`-chained on purpose: AppleScript's `do shell script`
    /// string literal cannot span raw newlines, and any failed step must abort the
    /// install rather than leave a half-applied privileged state.
    public static func installScript(stagedHelperPath: String, stagedSudoersPath: String) -> String {
        [
            "/bin/mkdir -p '\(installDir)'",
            "/usr/sbin/chown root:wheel '\(installDir)'",
            "/bin/chmod 0755 '\(installDir)'",
            "/usr/bin/install -o root -g wheel -m 0755 '\(stagedHelperPath)' '\(helperPath)'",
            "/usr/bin/install -o root -g wheel -m 0440 '\(stagedSudoersPath)' '\(sudoersPath)'",
            "{ /usr/sbin/visudo -cf '\(sudoersPath)' || { /bin/rm -f '\(sudoersPath)'; exit 1; }; }"
        ].joined(separator: " && ")
    }
}
