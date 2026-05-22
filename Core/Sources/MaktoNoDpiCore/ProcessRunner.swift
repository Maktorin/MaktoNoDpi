import Foundation

/// A running child process (tpws). The handle can be killed and reports termination.
public protocol RunningProcess: AnyObject, Sendable {
    var isRunning: Bool { get }
    func kill()
    func onTerminate(_ handler: @escaping @Sendable (Int32) -> Void)
}

public protocol ProcessRunner: Sendable {
    func spawn(_ launchPath: String, _ args: [String]) throws -> RunningProcess
}

public final class SystemProcessRunner: ProcessRunner {
    public init() {}
    public func spawn(_ launchPath: String, _ args: [String]) throws -> RunningProcess {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: launchPath)
        p.arguments = args
        p.standardOutput = Pipe(); p.standardError = Pipe()
        let handle = SystemRunningProcess(process: p)
        try p.run()
        return handle
    }
}

final class SystemRunningProcess: RunningProcess, @unchecked Sendable {
    private let process: Process
    init(process: Process) { self.process = process }
    var isRunning: Bool { process.isRunning }
    func kill() { if process.isRunning { process.terminate() } }
    func onTerminate(_ handler: @escaping @Sendable (Int32) -> Void) {
        process.terminationHandler = { p in handler(p.terminationStatus) }
    }
}
