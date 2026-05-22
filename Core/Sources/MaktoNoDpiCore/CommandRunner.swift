import Foundation

public struct CommandResult: Sendable { public let status: Int32; public let stdout: String; public let stderr: String }

public protocol CommandRunner: Sendable {
    func run(_ launchPath: String, _ args: [String]) async throws -> CommandResult
}

public struct SystemCommandRunner: CommandRunner {
    public init() {}
    public func run(_ launchPath: String, _ args: [String]) async throws -> CommandResult {
        try await withCheckedThrowingContinuation { cont in
            let p = Process()
            p.executableURL = URL(fileURLWithPath: launchPath)
            p.arguments = args
            let out = Pipe(); let err = Pipe()
            p.standardOutput = out; p.standardError = err
            p.terminationHandler = { proc in
                let o = String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                let e = String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                cont.resume(returning: CommandResult(status: proc.terminationStatus, stdout: o, stderr: e))
            }
            do { try p.run() } catch { cont.resume(throwing: error) }
        }
    }
}
