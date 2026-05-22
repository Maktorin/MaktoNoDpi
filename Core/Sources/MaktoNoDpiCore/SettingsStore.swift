import Foundation

public struct SettingsStore: @unchecked Sendable {
    private let defaults: UserDefaults
    public init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    public var autoStart: Bool { get { defaults.bool(forKey: "autoStart") } nonmutating set { defaults.set(newValue, forKey: "autoStart") } }
    public var autoConnect: Bool { get { defaults.bool(forKey: "autoConnect") } nonmutating set { defaults.set(newValue, forKey: "autoConnect") } }
    public var selectedStrategy: String { get { defaults.string(forKey: "selectedStrategy") ?? "auto" } nonmutating set { defaults.set(newValue, forKey: "selectedStrategy") } }
    public var lastWorkingStrategy: String? { get { defaults.string(forKey: "lastWorkingStrategy") } nonmutating set { defaults.set(newValue, forKey: "lastWorkingStrategy") } }
    public var customIncludeDomains: [String] { get { defaults.stringArray(forKey: "customIncludeDomains") ?? [] } nonmutating set { defaults.set(newValue, forKey: "customIncludeDomains") } }
    public var customExcludeDomains: [String] { get { defaults.stringArray(forKey: "customExcludeDomains") ?? [] } nonmutating set { defaults.set(newValue, forKey: "customExcludeDomains") } }
}
