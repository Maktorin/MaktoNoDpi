import AppKit
import SwiftUI
import MaktoNoDpiCore

@main
struct MaktoNoDpiApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var controller = ProxyController()

    var body: some Scene {
        WindowGroup {
            ContentView(controller: controller)
                .onAppear { appDelegate.attach(controller: controller) }
        }
        .windowResizability(.contentSize)

        Settings {
            SettingsView()
        }
    }
}

/// Owns the menu-bar status item and the app lifecycle hooks.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var tray: TrayController?
    private var controller: ProxyController?

    /// Called once the SwiftUI scene has constructed the shared controller.
    func attach(controller: ProxyController) {
        guard self.controller == nil else { return }
        self.controller = controller
        self.tray = TrayController(controller: controller)

        let settings = SettingsStore()

        // Apply the saved launch-at-login setting (electron-main.js:3061-3062).
        LoginItem.setEnabled(settings.autoStart)

        // Auto-connect ~1.5s after launch when enabled (electron-main.js:3066-3070).
        if settings.autoConnect {
            Task {
                try? await Task.sleep(for: .milliseconds(1500))
                await controller.connect()
            }
        }
    }
}
