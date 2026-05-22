import Foundation

/// Abstraction over the connectivity probe so tests can script deterministic outcomes.
public protocol ConnectivityProbing: Sendable {
    func testProxy(port: Int, timeoutSec: Int) async -> Bool
}

extension ConnectivityTester: ConnectivityProbing {}

/// Orchestrates the strategy-iteration loop ported from the darwin path of
/// `startProxy`/`stopProxy` (docs/reference/electron-main.js:2109-2523).
///
/// All side-effecting primitives are injected so tests run with no real tpws,
/// no real networking and no real privileged operations:
///  - `processRunner`  spawns tpws (fake returns an always-running handle in tests)
///  - `commandRunner`  drives SystemConfig (proxy/DNS) — no-op fake in tests
///  - `tester`         the connectivity probe (scripted in tests)
///  - `activeServices` returns the active network services
///  - `portProbe`      checks tpws is listening on the SOCKS port
///  - `elevate`        runs the batched privileged script (no-op in tests)
///  - `prepareFiles`   writes host lists / pattern files, returns the lists dir
public actor ProxyEngine {
    public enum LogEvent: Sendable {
        case log(LogEntry)
        case phase(ProxyPhase)
    }

    private let strategies: [Strategy]
    private let processRunner: ProcessRunner
    private let systemConfig: SystemConfig
    private let tester: ConnectivityProbing
    private let settings: SettingsStore
    private let activeServices: @Sendable () async -> [String]
    private let portProbe: @Sendable (Int) async -> Bool
    private let elevate: @Sendable (String) async throws -> Void
    private let prepareFiles: @Sendable () async throws -> String
    private let tpwsPath: String
    private let socksPort: Int
    /// Inter-step delay (tpws warm-up). Defaults to 0 so unit tests run instantly;
    /// the app passes a real value (~2s) to match the Electron behaviour.
    private let stepDelay: Duration

    private var current: RunningProcess?
    private var phase: ProxyPhase = .disconnected

    private let continuation: AsyncStream<LogEvent>.Continuation
    /// Stream of log/phase events for UI binding. Optional to consume.
    public nonisolated let events: AsyncStream<LogEvent>

    public init(
        strategies: [Strategy],
        processRunner: ProcessRunner,
        commandRunner: CommandRunner,
        tester: ConnectivityProbing,
        settings: SettingsStore,
        activeServices: @escaping @Sendable () async -> [String],
        portProbe: @escaping @Sendable (Int) async -> Bool,
        elevate: @escaping @Sendable (String) async throws -> Void,
        prepareFiles: @escaping @Sendable () async throws -> String,
        tpwsPath: String = "/usr/local/bin/tpws",
        socksPort: Int = 1080,
        stepDelay: Duration = .zero
    ) {
        self.strategies = strategies
        self.processRunner = processRunner
        self.systemConfig = SystemConfig(runner: commandRunner)
        self.tester = tester
        self.settings = settings
        self.activeServices = activeServices
        self.portProbe = portProbe
        self.elevate = elevate
        self.prepareFiles = prepareFiles
        self.tpwsPath = tpwsPath
        self.socksPort = socksPort
        self.stepDelay = stepDelay

        var cont: AsyncStream<LogEvent>.Continuation!
        self.events = AsyncStream { cont = $0 }
        self.continuation = cont
    }

    // MARK: - Logging / phase

    private func log(_ type: LogType, _ message: String) {
        continuation.yield(.log(LogEntry(type: type, message: message)))
    }

    private func setPhase(_ p: ProxyPhase) {
        phase = p
        continuation.yield(.phase(p))
    }

    // MARK: - Strategy ordering

    /// Mirrors the selection logic from startProxy:
    /// - explicit `selectedStrategy` (not "auto") matching a name → just that one
    /// - else `lastWorkingStrategy` matching → that one first, then the rest
    /// - else all strategies in order
    private func orderedStrategies() -> [Strategy] {
        let selected = settings.selectedStrategy
        if selected != "auto", let pick = strategies.first(where: { $0.name == selected }) {
            return [pick]
        }
        if let last = settings.lastWorkingStrategy,
           let lastWorking = strategies.first(where: { $0.name == last }) {
            let rest = strategies.filter { $0.name != last }
            return [lastWorking] + rest
        }
        return strategies
    }

    // MARK: - Connect

    public func connect() async throws -> ProxyPhase {
        log(.info, "Начало подключения...")

        let listsDir = try await prepareFiles()
        log(.info, "Списки подготовлены: \(listsDir)")

        let services = await activeServices()
        if services.isEmpty {
            let phase = ProxyPhase.error(.networkUnavailable, message: "Не обнаружено активных сетевых подключений")
            setPhase(phase)
            log(.error, "Не обнаружено активных сетевых подключений")
            return phase
        }

        // Batched privileged step (clean DNS, QUIC block, hosts) — one prompt.
        do {
            try await elevate(listsDir)
        } catch {
            let phase = ProxyPhase.error(.networkUnavailable, message: "Не удалось применить системные настройки")
            setPhase(phase)
            log(.error, "Не удалось применить системные настройки: \(error)")
            return phase
        }

        // Clean DNS (1.1.1.1 / 8.8.8.8) to avoid ISP DNS poisoning for Discord
        // (electron-main.js:2159). restoreDns() in stop() reverts this.
        await systemConfig.setCleanDns(services: services)
        log(.info, "DNS установлен на 1.1.1.1 / 8.8.8.8 (защита от подмены)")

        let ordered = orderedStrategies()
        let total = ordered.count
        log(.info, "Начинаю перебор \(total) стратегий...")

        for (i, strategy) in ordered.enumerated() {
            setPhase(.searching(StrategyProgress(current: i + 1, total: total, name: strategy.name)))
            log(.info, "[\(i + 1)/\(total)] Тестирование: \(strategy.name)")

            killCurrent()

            // Spawn tpws.
            let proc: RunningProcess
            do {
                proc = try processRunner.spawn(tpwsPath, strategy.args)
            } catch {
                log(.warning, "\(strategy.name): не удалось запустить — \(error)")
                continue
            }
            current = proc

            // Wait for tpws to start listening.
            if stepDelay > .zero { try? await Task.sleep(for: stepDelay) }

            if !proc.isRunning {
                log(.warning, "\(strategy.name): процесс не запустился")
                killCurrent()
                continue
            }

            // Verify tpws is listening on the SOCKS port.
            if !(await portProbe(socksPort)) {
                log(.warning, "\(strategy.name): порт \(socksPort) не доступен")
                killCurrent()
                continue
            }

            // Route system traffic through tpws.
            await systemConfig.enableProxy(port: socksPort, services: services)

            // Verify the bypass actually works.
            let works = await tester.testProxy(port: socksPort, timeoutSec: 10)
            if works {
                settings.lastWorkingStrategy = strategy.name
                let phase = ProxyPhase.connected(strategy: strategy.name, since: Date())
                setPhase(phase)
                log(.success, "Стратегия \(strategy.name) работает!")
                return phase
            } else {
                log(.warning, "\(strategy.name): не прошла проверку соединения")
                await systemConfig.disableProxy(services: services)
                killCurrent()
                continue
            }
        }

        let phase = ProxyPhase.error(.allStrategiesFailed,
                                     message: "Ни одна стратегия не сработала. Попробуйте позже или обратитесь в поддержку")
        setPhase(phase)
        log(.error, "Все \(total) стратегий не сработали")
        return phase
    }

    // MARK: - Stop

    public func stop() async {
        let services = await activeServices()
        await systemConfig.disableProxy(services: services)
        await systemConfig.restoreDns(services: services)
        await systemConfig.flushDnsCache()
        killCurrent()
        setPhase(.disconnected)
        log(.info, "Отключено пользователем")
    }

    // MARK: - Helpers

    private func killCurrent() {
        current?.kill()
        current = nil
    }
}
