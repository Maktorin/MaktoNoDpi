import Foundation

public struct Strategy: Equatable, Sendable {
    public let name: String
    public let args: [String]
    public init(name: String, args: [String]) { self.name = name; self.args = args }
}

public enum LogType: String, Sendable { case info, success, warning, error }

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
