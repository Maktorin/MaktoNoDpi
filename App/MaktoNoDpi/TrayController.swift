import AppKit
import Combine
import SwiftUI
import MaktoNoDpiCore

/// Menu-bar status item. Ports `updateTrayMenu` (electron-main.js:1177-1191):
/// Открыть / status line / Подключить / Отключить / Выход. The menu is rebuilt
/// whenever `controller.phase` changes.
@MainActor
final class TrayController {
    private let statusItem: NSStatusItem
    private let controller: ProxyController
    private var cancellable: AnyCancellable?

    init(controller: ProxyController) {
        self.controller = controller
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem.button {
            let image = NSImage(systemSymbolName: "shield.lefthalf.filled",
                                accessibilityDescription: "MaktoNoDpi")
            image?.isTemplate = true
            button.image = image
        }

        rebuildMenu()

        // Rebuild the menu whenever the published phase changes.
        cancellable = controller.$phase
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.rebuildMenu() }
    }

    private var isConnected: Bool {
        if case .connected = controller.phase { return true }
        return false
    }

    private var isSearching: Bool {
        if case .searching = controller.phase { return true }
        return false
    }

    private var statusLine: String {
        switch controller.phase {
        case .connected: return "● Подключено"
        case .searching: return "◌ Поиск..."
        case .error: return "● Ошибка"
        case .disconnected: return "○ Отключено"
        }
    }

    private func rebuildMenu() {
        let menu = NSMenu()

        let open = NSMenuItem(title: "Открыть", action: #selector(openWindow), keyEquivalent: "")
        open.target = self
        menu.addItem(open)

        menu.addItem(.separator())

        let status = NSMenuItem(title: statusLine, action: nil, keyEquivalent: "")
        status.isEnabled = false
        menu.addItem(status)

        let connect = NSMenuItem(title: "Подключить", action: #selector(connect), keyEquivalent: "")
        connect.target = self
        connect.isEnabled = !isConnected && !isSearching
        menu.addItem(connect)

        let disconnect = NSMenuItem(title: "Отключить", action: #selector(disconnect), keyEquivalent: "")
        disconnect.target = self
        disconnect.isEnabled = isConnected
        menu.addItem(disconnect)

        menu.addItem(.separator())

        let quit = NSMenuItem(title: "Выход", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        statusItem.menu = menu
    }

    // MARK: - Actions

    @objc private func openWindow() {
        NSApp.activate(ignoringOtherApps: true)
        for window in NSApp.windows where window.canBecomeMain {
            window.makeKeyAndOrderFront(nil)
        }
    }

    @objc private func connect() {
        Task { await controller.connect() }
    }

    @objc private func disconnect() {
        Task { await controller.stop() }
    }

    @objc private func quit() {
        // Best-effort cleanup before quitting, then terminate.
        Task {
            await controller.stop()
            NSApp.terminate(nil)
        }
    }
}
