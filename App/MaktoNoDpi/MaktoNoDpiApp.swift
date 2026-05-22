import SwiftUI

@main
struct MaktoNoDpiApp: App {
    @StateObject private var controller = ProxyController()

    var body: some Scene {
        WindowGroup {
            ContentView(controller: controller)
        }
        .windowResizability(.contentSize)
    }
}
