import SwiftUI
import AppKit
import MaktoNoDpiCore

struct ContentView: View {
    @ObservedObject var controller: ProxyController
    @ObservedObject var updater: UpdaterController
    @State private var showDetails = false
    @State private var now = Date()

    private let ticker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 14) {
            hero
            servicesSection
            primaryButton
            detailsSection
            footer
        }
        .padding(16)
        .frame(width: 420)
        .onReceive(ticker) { now = $0 }
    }

    // MARK: - Footer (Settings / Updates / Quit)

    private var footer: some View {
        HStack(spacing: 16) {
            footerButton("Настройки", "gearshape") { Self.openSettings() }
            footerButton("Обновления", "arrow.down.circle") { updater.checkForUpdates() }
            Spacer()
            footerButton("Выход", "power") { NSApplication.shared.terminate(nil) }
        }
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
    }

    private func footerButton(_ title: String, _ symbol: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol).labelStyle(.titleAndIcon)
        }
        .buttonStyle(.plain)
        .help(title)
    }

    /// Open the SwiftUI `Settings` scene from a menu-bar-only app (no app menu).
    /// macOS 13 renamed the selector to `showSettingsWindow:`; fall back to the
    /// pre-13 `showPreferencesWindow:` for safety.
    private static func openSettings() {
        NSApp.activate(ignoringOtherApps: true)
        let settingsSel = NSSelectorFromString("showSettingsWindow:")
        let prefsSel = NSSelectorFromString("showPreferencesWindow:")
        if NSApp.responds(to: settingsSel) {
            NSApp.sendAction(settingsSel, to: nil, from: nil)
        } else {
            NSApp.sendAction(prefsSel, to: nil, from: nil)
        }
    }

    // MARK: - Hero status

    private var hero: some View {
        HStack(spacing: 13) {
            ZStack {
                Circle().fill(heroTint.opacity(0.18)).frame(width: 38, height: 38)
                heroGlyph
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(heroTitle).font(.system(size: 15, weight: .semibold))
                Text(heroSubtitle).font(.system(size: 12)).foregroundStyle(.secondary)
                    .lineLimit(1).truncationMode(.middle)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16).padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(heroTint.opacity(0.13), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(heroTint.opacity(0.28), lineWidth: 0.5))
    }

    @ViewBuilder private var heroGlyph: some View {
        switch controller.phase {
        case .searching:
            ProgressView().controlSize(.small)
        case .connected:
            Image(systemName: "lock.shield.fill").font(.system(size: 19)).foregroundStyle(heroTint)
        case .error:
            Image(systemName: "exclamationmark.shield.fill").font(.system(size: 19)).foregroundStyle(heroTint)
        case .disconnected:
            Image(systemName: "shield.slash").font(.system(size: 18)).foregroundStyle(heroTint)
        }
    }

    private var heroTint: Color {
        switch controller.phase {
        case .disconnected: return .gray
        case .searching:    return .orange
        case .connected:    return .green
        case .error:        return .red
        }
    }

    private var heroTitle: String {
        switch controller.phase {
        case .disconnected:        return "Отключено"
        case .searching:           return "Подбор стратегии…"
        case .connected:           return "Соединение активно"
        case .error:               return "Ошибка подключения"
        }
    }

    private var heroSubtitle: String {
        switch controller.phase {
        case .disconnected:
            return "Нажмите «Подключить» для обхода"
        case .searching(let progress):
            if let p = progress { return "Проверка \(p.current) из \(p.total) · \(p.name)" }
            return "Поиск рабочей стратегии…"
        case .connected(let strategy, let since):
            return "Стратегия \(strategy) · \(uptime(since))"
        case .error(_, let message):
            return message
        }
    }

    // MARK: - Services

    private var servicesSection: some View {
        VStack(spacing: 8) {
            HStack {
                Text("СЕРВИСЫ").font(.system(size: 11, weight: .semibold))
                    .kerning(0.5).foregroundStyle(.secondary)
                Spacer()
                Button { Task { await controller.refreshServices() } } label: {
                    Image(systemName: "arrow.clockwise").font(.system(size: 11, weight: .semibold))
                }
                .buttonStyle(.borderless)
                .disabled(!controller.isConnected)
                .help("Обновить")
            }
            .padding(.horizontal, 4)

            VStack(spacing: 0) {
                ForEach(Array(controller.services.enumerated()), id: \.element.service) { index, status in
                    if index > 0 { Divider().padding(.leading, 54) }
                    ServiceRow(status: status)
                }
            }
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 11))
            .overlay(RoundedRectangle(cornerRadius: 11).strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5))
        }
    }

    // MARK: - Primary button

    @ViewBuilder private var primaryButton: some View {
        if isConnected {
            Button(action: primaryAction) { Text(buttonTitle).frame(maxWidth: .infinity) }
                .controlSize(.large).buttonStyle(.bordered).disabled(isSearching)
        } else {
            Button(action: primaryAction) { Text(buttonTitle).frame(maxWidth: .infinity) }
                .controlSize(.large).buttonStyle(.borderedProminent).disabled(isSearching)
        }
    }

    private var isSearching: Bool { if case .searching = controller.phase { return true }; return false }
    private var isConnected: Bool { controller.isConnected }

    private var buttonTitle: String {
        if isSearching { return "Подключение…" }
        return isConnected ? "Отключить" : "Подключить"
    }

    private func primaryAction() {
        Task {
            if isConnected { await controller.stop() } else { await controller.connect() }
        }
    }

    // MARK: - Details disclosure

    private var detailsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Divider()
            Button { withAnimation(.easeInOut(duration: 0.15)) { showDetails.toggle() } } label: {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .bold))
                        .rotationEffect(.degrees(showDetails ? 90 : 0))
                    Text("Подробности").font(.system(size: 12))
                    Spacer()
                }
                .foregroundStyle(.secondary)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.top, 10)

            if showDetails {
                techGrid.padding(.top, 12)
                logView.padding(.top, 12)
            }
        }
    }

    private var techGrid: some View {
        Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 7) {
            techRow("Стратегия", strategyName)
            techRow("Время сессии", sessionTime)
            techRow("SOCKS-порт", "127.0.0.1:1080")
            techRow("Интерфейс", isConnected ? controller.activeInterface : "—")
            techBadgeRow("DNS", "защищён", tint: isConnected ? .green : nil)
            techBadgeRow("QUIC-блок", "активен", tint: isConnected ? .blue : nil)
        }
        .font(.system(size: 12))
        .padding(.horizontal, 4)
    }

    private func techRow(_ label: String, _ value: String) -> some View {
        GridRow {
            Text(label).foregroundStyle(.secondary)
            Text(value).gridColumnAlignment(.trailing).frame(maxWidth: .infinity, alignment: .trailing)
                .monospacedDigit()
        }
    }

    /// A tech-grid row whose value is a tinted badge; a plain dash when `tint` is nil (disconnected).
    private func techBadgeRow(_ label: String, _ value: String, tint: Color?) -> some View {
        GridRow {
            Text(label).foregroundStyle(.secondary)
            Group {
                if let tint {
                    Text(value)
                        .font(.system(size: 11, weight: .medium))
                        .padding(.horizontal, 7).padding(.vertical, 2)
                        .background(tint.opacity(0.16), in: Capsule())
                        .foregroundStyle(tint)
                } else {
                    Text("—").monospacedDigit()
                }
            }
            .gridColumnAlignment(.trailing)
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }

    private var logView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 3) {
                    ForEach(Array(controller.log.enumerated()), id: \.offset) { index, entry in
                        HStack(alignment: .top, spacing: 6) {
                            Text(Self.time.string(from: entry.timestamp))
                                .foregroundStyle(.tertiary)
                            Text(entry.message)
                                .foregroundStyle(color(for: entry.type))
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .id(index)
                    }
                }
                .padding(9)
            }
            .frame(height: 110)
            .font(.system(size: 10.5, design: .monospaced))
            .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 7))
            .onChange(of: controller.log.count) { _ in
                if let last = controller.log.indices.last {
                    withAnimation { proxy.scrollTo(last, anchor: .bottom) }
                }
            }
        }
    }

    // MARK: - Derived values

    private var strategyName: String {
        if case .connected(let s, _) = controller.phase { return s }
        return "—"
    }
    private var sessionTime: String {
        if case .connected(_, let since) = controller.phase { return uptime(since, full: true) }
        return "—"
    }

    private func uptime(_ since: Date, full: Bool = false) -> String {
        let secs = max(0, Int(now.timeIntervalSince(since)))
        let h = secs / 3600, m = (secs % 3600) / 60, s = secs % 60
        if full { return String(format: "%02d:%02d:%02d", h, m, s) }
        if h > 0 { return "\(h) ч \(m) мин" }
        if m > 0 { return "\(m) мин" }
        return "\(s) с"
    }

    private func color(for type: LogType) -> Color {
        switch type {
        case .info:    return .primary
        case .success: return .green
        case .warning: return .orange
        case .error:   return .red
        }
    }

    private static let time: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "HH:mm:ss"; return f
    }()
}

// MARK: - Service row

private struct ServiceRow: View {
    let status: ServiceStatus

    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 8).fill(meta.tint.opacity(0.13))
                .frame(width: 30, height: 30)
                .overlay(
                    Image(meta.asset).resizable().renderingMode(.template)
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 17, height: 17)
                        .foregroundStyle(meta.tint)
                )
            VStack(alignment: .leading, spacing: 1.5) {
                Text(meta.name).font(.system(size: 13.5, weight: .medium))
                Text(meta.subtitle).font(.system(size: 11)).foregroundStyle(.tertiary)
            }
            Spacer(minLength: 8)
            Text(latencyText).font(.system(size: 12)).monospacedDigit()
                .foregroundStyle(status.latencyMs == nil ? .tertiary : .secondary)
            Circle().fill(dotColor).frame(width: 9, height: 9)
        }
        .padding(.horizontal, 14).padding(.vertical, 11)
    }

    private var latencyText: String {
        switch status.state {
        case .unknown: return "—"
        case .down:    return "—"
        default:       return status.latencyMs.map { "\($0) мс" } ?? "—"
        }
    }

    private var dotColor: Color {
        switch status.state {
        case .ok:       return .green
        case .degraded: return .orange
        case .down:     return .red
        case .unknown:  return Color(nsColor: .quaternaryLabelColor)
        }
    }

    private var meta: ServiceMeta { ServiceMeta.of(status.service) }
}

private struct ServiceMeta {
    let name: String; let subtitle: String; let asset: String; let tint: Color

    static func of(_ id: ServiceID) -> ServiceMeta {
        switch id {
        case .youtube:
            return .init(name: "YouTube", subtitle: "видео и превью", asset: "youtube",
                         tint: Color(red: 1.0, green: 0.0, blue: 0.2))
        case .discord:
            return .init(name: "Discord", subtitle: "чат, медиа, голос", asset: "discord",
                         tint: Color(red: 0.345, green: 0.396, blue: 0.949))
        case .telegram:
            return .init(name: "Telegram", subtitle: "web и звонки", asset: "telegram",
                         tint: Color(red: 0.133, green: 0.62, blue: 0.851))
        }
    }
}
