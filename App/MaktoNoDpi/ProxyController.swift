import Foundation
import Network
import SwiftUI
import MaktoNoDpiCore

/// Bridges the Core `ProxyEngine` actor to SwiftUI.
///
/// Constructs the real engine with system-backed runners and the wiring closures
/// described in Task 5.2. All `@Sendable` closures capture only `Sendable` values
/// (paths, a settings snapshot) — never `self` — so they are safe to hand to the
/// actor under strict concurrency.
@MainActor
final class ProxyController: ObservableObject {
    @Published var phase: ProxyPhase = .disconnected
    @Published var log: [LogEntry] = []

    private let engine: ProxyEngine
    private let settings: SettingsStore
    /// Active services snapshot captured at the last connect, used for teardown.
    private var eventTask: Task<Void, Never>?

    /// Resolved bundled tpws path (read-only, may be translocated) for fallbacks.
    private let bundledTpwsPath: String
    private let supportDirPath: String

    init() {
        let settings = SettingsStore()
        self.settings = settings

        // Resolve the bundled tpws (Contents/Resources/bin/tpws). Fall back to the
        // BinaryManager-installed copy under Application Support if the bundle lookup
        // fails (e.g. running outside a packaged .app).
        let supportDir = ProxyController.applicationSupportDir()
        self.supportDirPath = supportDir.path
        let installedTpws = "\(supportDir.path)/bin/tpws"
        let bundled = Bundle.main.path(forResource: "tpws", ofType: nil, inDirectory: "bin")
            ?? installedTpws
        self.bundledTpwsPath = bundled

        // Snapshot Sendable values for the wiring closures (no self capture).
        // Capture the SettingsStore itself (Sendable, reads live from UserDefaults)
        // so custom domains edited in Settings are picked up on the next connect.
        let supportPath = supportDir.path
        let bundledPath = bundled
        let settingsForFiles = settings
        let hostsMarker = HostsData.marker
        let hostsFallback = HostsData.fallback()
        let pfRules = PrivilegedRunner.pfQuicBlockRules

        let commandRunner = SystemCommandRunner()

        // prepareFiles: install binary, write lists + pattern files, return listsDir.
        let prepareFiles: @Sendable () async throws -> String = {
            let mgr = BinaryManager(bundledTpws: bundledPath, supportDir: supportPath)
            try mgr.installBundledBinary()
            let listsDir = try mgr.ensureHostLists(
                customInclude: settingsForFiles.customIncludeDomains,
                customExclude: settingsForFiles.customExcludeDomains
            )
            try mgr.ensurePatternFiles()
            return listsDir
        }

        // activeServices: enumerate via networksetup; [] on error.
        let activeServices: @Sendable () async -> [String] = {
            (try? await NetworkServices.active(using: SystemCommandRunner())) ?? []
        }

        // portProbe: TCP connect to 127.0.0.1:port with a short timeout.
        let portProbe: @Sendable (Int) async -> Bool = { port in
            await ProxyController.probeTCP(host: "127.0.0.1", port: port, timeout: 2.0)
        }

        // elevate: write the pf-conf + hosts-add temp files, build the batched
        // privileged script and run it (single admin prompt).
        let elevate: @Sendable (String) async throws -> Void = { _ in
            let tmp = FileManager.default.temporaryDirectory
            let pfConfPath = tmp.appendingPathComponent("maktonodpi-pf.conf").path
            let hostsAddPath = tmp.appendingPathComponent("maktonodpi-hosts-add.txt").path

            try pfRules.write(toFile: pfConfPath, atomically: true, encoding: .utf8)
            let hostsBlock = hostsMarker + "\n" + hostsFallback + "\n"
            try hostsBlock.write(toFile: hostsAddPath, atomically: true, encoding: .utf8)

            let script = PrivilegedRunner.buildConnectScript(
                pfConfPath: pfConfPath,
                hostsAddFile: hostsAddPath,
                hostsMarker: hostsMarker
            )
            _ = try await PrivilegedRunner(runner: SystemCommandRunner()).run(shellScript: script)
        }

        self.engine = ProxyEngine(
            strategies: Strategies.darwin(listsDir: "\(supportPath)/lists"),
            processRunner: SystemProcessRunner(),
            commandRunner: commandRunner,
            tester: ConnectivityTester(runner: commandRunner),
            settings: settings,
            activeServices: activeServices,
            portProbe: portProbe,
            elevate: elevate,
            prepareFiles: prepareFiles,
            tpwsPath: installedTpws,
            socksPort: 1080,
            stepDelay: .seconds(2)
        )

        startConsumingEvents()
    }

    // MARK: - Public API

    func connect() async {
        do {
            _ = try await engine.connect()
        } catch {
            phase = .error(.allStrategiesFailed, message: "\(error)")
        }
    }

    func stop() async {
        await engine.stop()
        // Close the QUIC-teardown gap: ProxyEngine.stop() cannot reload pf without
        // elevation, so reload /etc/pf.conf via a privileged script here.
        await ProxyController.teardownPf()
    }

    // MARK: - Event consumption

    private func startConsumingEvents() {
        let stream = engine.events
        eventTask = Task { [weak self] in
            for await event in stream {
                guard let self else { return }
                await self.handle(event)
            }
        }
    }

    private func handle(_ event: ProxyEngine.LogEvent) {
        switch event {
        case .log(let entry):
            log.append(entry)
            if log.count > 100 { log.removeFirst(log.count - 100) }
        case .phase(let p):
            phase = p
        }
    }

    // MARK: - Helpers

    static func applicationSupportDir() -> URL {
        let base = (try? FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )) ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent("MaktoNoDpi", isDirectory: true)
    }

    /// Reload /etc/pf.conf to drop the QUIC block. Best-effort; one admin prompt.
    private static func teardownPf() async {
        let script = "/sbin/pfctl -f /etc/pf.conf 2>/dev/null; exit 0"
        _ = try? await PrivilegedRunner(runner: SystemCommandRunner()).run(shellScript: script)
    }

    /// Open a TCP connection to verify a port is listening, with a timeout.
    static func probeTCP(host: String, port: Int, timeout: TimeInterval) async -> Bool {
        guard let nwPort = NWEndpoint.Port(rawValue: UInt16(port)) else { return false }
        let endpoint = NWEndpoint.hostPort(host: NWEndpoint.Host(host), port: nwPort)
        let params = NWParameters.tcp
        let connection = NWConnection(to: endpoint, using: params)

        return await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            let resolved = ManagedAtomicFlag()
            let queue = DispatchQueue(label: "com.makto.nodpi.portprobe")

            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    if resolved.tryResolve() {
                        connection.cancel()
                        continuation.resume(returning: true)
                    }
                case .failed, .cancelled:
                    if resolved.tryResolve() {
                        connection.cancel()
                        continuation.resume(returning: false)
                    }
                default:
                    break
                }
            }
            connection.start(queue: queue)

            queue.asyncAfter(deadline: .now() + timeout) {
                if resolved.tryResolve() {
                    connection.cancel()
                    continuation.resume(returning: false)
                }
            }
        }
    }
}

/// Minimal one-shot resolution guard so the port probe resumes its continuation
/// exactly once across the success/failure/timeout paths.
private final class ManagedAtomicFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var resolved = false
    func tryResolve() -> Bool {
        lock.lock(); defer { lock.unlock() }
        if resolved { return false }
        resolved = true
        return true
    }
}
