import SwiftUI
import MaktoNoDpiCore

/// View-model bridging the value-type `SettingsStore` (UserDefaults-backed) to
/// SwiftUI bindings, and the `SMAppService` login item.
@MainActor
final class SettingsViewModel: ObservableObject {
    private let store = SettingsStore()

    @Published var autoStart: Bool {
        didSet {
            LoginItem.setEnabled(autoStart)
            store.autoStart = autoStart
        }
    }
    @Published var autoConnect: Bool {
        didSet { store.autoConnect = autoConnect }
    }
    @Published var selectedStrategy: String {
        didSet { store.selectedStrategy = selectedStrategy }
    }
    @Published var includeText: String {
        didSet { store.customIncludeDomains = SettingsViewModel.parseLines(includeText) }
    }
    @Published var excludeText: String {
        didSet { store.customExcludeDomains = SettingsViewModel.parseLines(excludeText) }
    }

    /// "auto" plus all strategy names.
    let strategyNames: [String] = ["auto"] + Strategies.darwin(listsDir: "").map { $0.name }

    init() {
        self.autoStart = LoginItem.isEnabled
        self.autoConnect = store.autoConnect
        self.selectedStrategy = store.selectedStrategy
        self.includeText = store.customIncludeDomains.joined(separator: "\n")
        self.excludeText = store.customExcludeDomains.joined(separator: "\n")
    }

    private static func parseLines(_ text: String) -> [String] {
        text.split(whereSeparator: { $0.isNewline })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }
}

struct SettingsView: View {
    @StateObject private var model = SettingsViewModel()

    var body: some View {
        Form {
            Section("Запуск") {
                Toggle("Запускать при входе в систему", isOn: $model.autoStart)
                Toggle("Подключаться автоматически при запуске", isOn: $model.autoConnect)
            }

            Section("Стратегия") {
                Picker("Стратегия обхода", selection: $model.selectedStrategy) {
                    ForEach(model.strategyNames, id: \.self) { name in
                        Text(name).tag(name)
                    }
                }
                .pickerStyle(.menu)
            }

            Section("Свои домены (по одному в строке)") {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Включить")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextEditor(text: $model.includeText)
                        .font(.system(.body, design: .monospaced))
                        .frame(minHeight: 70)
                        .border(Color.secondary.opacity(0.3))
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("Исключить")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextEditor(text: $model.excludeText)
                        .font(.system(.body, design: .monospaced))
                        .frame(minHeight: 70)
                        .border(Color.secondary.opacity(0.3))
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 460, height: 520)
    }
}
