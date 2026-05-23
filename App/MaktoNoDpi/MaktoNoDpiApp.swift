import AppKit
import SwiftUI
import MaktoNoDpiCore

@main
struct MaktoNoDpiApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var controller = ProxyController()
    @StateObject private var updater = UpdaterController()

    var body: some Scene {
        MenuBarExtra {
            ContentView(controller: controller, updater: updater)
        } label: {
            Image(systemName: menuBarSymbol)
                .onAppear { appDelegate.attach(controller: controller) }
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
        }
    }

    /// Menu-bar glyph reflecting the current connection phase (template-rendered).
    private var menuBarSymbol: String {
        switch controller.phase {
        case .connected:    return "shield.lefthalf.filled"
        case .searching:    return "shield.righthalf.filled"
        case .error:        return "exclamationmark.shield"
        case .disconnected: return "shield.slash"
        }
    }
}

/// Owns the app lifecycle hooks. The menu-bar presence is now the SwiftUI
/// `MenuBarExtra` scene; this delegate only handles launch/quit/signal cleanup
/// and the one-time controller wiring (login item + auto-connect).
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var controller: ProxyController?
    private var signalSources: [DispatchSourceSignal] = []

    /// Called once the SwiftUI scene has constructed the shared controller.
    func attach(controller: ProxyController) {
        guard self.controller == nil else { return }
        self.controller = controller

        let settings = SettingsStore()

        // Apply the saved launch-at-login setting (electron-main.js:3061-3062).
        LoginItem.setEnabled(settings.autoStart)

        // Auto-connect ~1.5s after launch when enabled (electron-main.js:3066-3070).
        if settings.autoConnect {
            Task {
                try? await Task.sleep(for: .milliseconds(1500))
                await controller.connect()
            }
        }
    }

    // MARK: - Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Clear stale proxy/DNS settings left over from a previous crash
        // (electron-main.js:3034-3036).
        EmergencyCleanup.run()
        installSignalHandlers()
    }

    func applicationWillTerminate(_ notification: Notification) {
        EmergencyCleanup.run()
    }

    /// Install SIGTERM/SIGINT handlers via GCD (dispatched to the main queue, so
    /// the handler body is not constrained to async-signal-safe calls).
    private func installSignalHandlers() {
        for sig in [SIGTERM, SIGINT] {
            // Ignore default disposition so the dispatch source receives it.
            signal(sig, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: sig, queue: .main)
            source.setEventHandler {
                EmergencyCleanup.run()
                exit(0)
            }
            source.resume()
            signalSources.append(source)
        }
    }
}

/// Synchronous best-effort teardown for quit/crash/signal paths. Uses blocking
/// `Process` calls (terminate/signal handlers cannot await). Each step is
/// independent and swallows its own errors.
enum EmergencyCleanup {
    static func run() {
        let services = activeServices()
        for svc in services {
            // Disable system SOCKS proxy.
            shell("/usr/sbin/networksetup", ["-setsocksfirewallproxystate", svc, "off"])
            // Restore DNS to automatic (best-effort).
            shell("/usr/sbin/networksetup", ["-setdnsservers", svc, "Empty"])
        }
        // Drop the QUIC block via the passwordless helper. Unlike a bare `pfctl`
        // (which needs root and silently failed here), this now actually succeeds
        // on the quit/crash path once the helper is installed; a no-op otherwise.
        shell("/usr/bin/sudo", ["-n", PrivilegedHelper.helperPath, "disconnect"])
        // Kill any lingering tpws child.
        shell("/usr/bin/pkill", ["-f", "tpws"])
    }

    /// Synchronous network-service enumeration. Falls back to an empty list on
    /// any failure rather than blocking the quit path indefinitely.
    private static func activeServices() -> [String] {
        guard let raw = capture("/usr/sbin/networksetup", ["-listallnetworkservices"]) else {
            return []
        }
        let all = raw.split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("An asterisk") }
        // Probe each for an IPv4 address; keep those that look active.
        var active: [String] = []
        for svc in all {
            if let info = capture("/usr/sbin/networksetup", ["-getinfo", svc]),
               info.range(of: #"IP address:\s*\d+\.\d+\.\d+\.\d+"#, options: .regularExpression) != nil {
                active.append(svc)
            }
        }
        return active.isEmpty ? all : active
    }

    @discardableResult
    private static func shell(_ launchPath: String, _ args: [String]) -> Int32 {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: launchPath)
        p.arguments = args
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        do {
            try p.run()
            p.waitUntilExit()
            return p.terminationStatus
        } catch {
            return -1
        }
    }

    private static func capture(_ launchPath: String, _ args: [String]) -> String? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: launchPath)
        p.arguments = args
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = FileHandle.nullDevice
        do {
            try p.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            p.waitUntilExit()
            return String(data: data, encoding: .utf8)
        } catch {
            return nil
        }
    }
}
