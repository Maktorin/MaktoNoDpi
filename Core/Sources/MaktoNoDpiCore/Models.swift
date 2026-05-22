import Foundation

public struct Strategy: Equatable, Sendable {
    public let name: String
    public let args: [String]
    public init(name: String, args: [String]) { self.name = name; self.args = args }
}

public enum LogType: String, Sendable { case info, success, warning, error }

/// The monitored flagship services shown on the dashboard.
public enum ServiceID: String, CaseIterable, Sendable {
    case youtube, discord, telegram
}

/// Reachability of one monitored service through the proxy, with measured latency.
public struct ServiceStatus: Equatable, Sendable {
    public enum State: String, Sendable {
        case unknown   // not connected / not yet tested
        case ok        // reachable, healthy latency
        case degraded  // reachable but slow
        case down      // unreachable through the proxy
    }
    public let service: ServiceID
    public let state: State
    public let latencyMs: Int?
    public init(service: ServiceID, state: State, latencyMs: Int? = nil) {
        self.service = service; self.state = state; self.latencyMs = latencyMs
    }
}

public struct LogEntry: Equatable, Sendable {
    public let type: LogType
    public let message: String
    public let timestamp: Date
    public init(type: LogType, message: String, timestamp: Date = Date()) {
        self.type = type; self.message = message; self.timestamp = timestamp
    }
}

public struct StrategyProgress: Equatable, Sendable {
    public let current: Int
    public let total: Int
    public let name: String
    public init(current: Int, total: Int, name: String) { self.current = current; self.total = total; self.name = name }
}

public enum ProxyError: String, Error, Sendable {
    case alreadyRunning = "ALREADY_RUNNING"
    case downloadFailed = "DOWNLOAD_FAILED"
    case noBinary = "NO_BINARY"
    case networkUnavailable = "NETWORK_UNAVAILABLE"
    case allStrategiesFailed = "ALL_STRATEGIES_FAILED"
    case processCrashed = "PROCESS_CRASHED"
}

public enum ProxyPhase: Equatable, Sendable {
    case disconnected
    case searching(StrategyProgress?)
    case connected(strategy: String, since: Date)
    case error(ProxyError, message: String)
}
