import AppKit
import SwiftUI

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
    }
}
