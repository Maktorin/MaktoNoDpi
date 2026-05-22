import SwiftUI
import MaktoNoDpiCore

struct ContentView: View {
    @ObservedObject var controller: ProxyController

    var body: some View {
        VStack(spacing: 16) {
            Text("MaktoNoDpi")
                .font(.title2.bold())

            statusPill

            Button(action: primaryAction) {
                Text(buttonTitle)
                    .frame(maxWidth: .infinity)
            }
            .controlSize(.large)
            .buttonStyle(.borderedProminent)
            .disabled(isSearching)

            Divider()

            logList
        }
        .padding()
        .frame(width: 420, height: 460)
    }

    // MARK: - Status pill

    private var statusPill: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(statusColor)
                .frame(width: 10, height: 10)
            Text(statusText)
                .font(.callout)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(statusColor.opacity(0.12), in: Capsule())
    }

    private var statusColor: Color {
        switch controller.phase {
        case .disconnected: return .secondary
        case .searching: return .orange
        case .connected: return .green
        case .error: return .red
        }
    }

    private var statusText: String {
        switch controller.phase {
        case .disconnected:
            return "Отключено"
        case .searching(let progress):
            if let p = progress {
                return "Поиск стратегии [\(p.current)/\(p.total)]: \(p.name)"
            }
            return "Поиск рабочей стратегии..."
        case .connected(let strategy, let since):
            return "Подключено: \(strategy) (с \(Self.timeFormatter.string(from: since)))"
        case .error(_, let message):
            return "Ошибка: \(message)"
        }
    }

    // MARK: - Button

    private var isSearching: Bool {
        if case .searching = controller.phase { return true }
        return false
    }

    private var isConnected: Bool {
        if case .connected = controller.phase { return true }
        return false
    }

    private var buttonTitle: String {
        if isSearching { return "Подключение..." }
        return isConnected ? "Отключить" : "Подключить"
    }

    private func primaryAction() {
        Task {
            if isConnected {
                await controller.stop()
            } else {
                await controller.connect()
            }
        }
    }

    // MARK: - Log

    private var logList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(controller.log.enumerated()), id: \.offset) { index, entry in
                        HStack(alignment: .top, spacing: 6) {
                            Text(Self.timeFormatter.string(from: entry.timestamp))
                                .font(.system(.caption2, design: .monospaced))
                                .foregroundStyle(.secondary)
                            Text(entry.message)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(color(for: entry.type))
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .id(index)
                    }
                }
                .padding(8)
            }
            .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
            .onChange(of: controller.log.count) { _ in
                if let last = controller.log.indices.last {
                    withAnimation { proxy.scrollTo(last, anchor: .bottom) }
                }
            }
        }
    }

    private func color(for type: LogType) -> Color {
        switch type {
        case .info: return .primary
        case .success: return .green
        case .warning: return .orange
        case .error: return .red
        }
    }

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()
}
