import Sparkle
import Foundation

/// Thin @MainActor wrapper around Sparkle's standard updater controller.
/// Instantiate once from the @main App struct and pass it through the environment
/// so the "Check for Updates" command can call checkForUpdates().
@MainActor
final class UpdaterController: ObservableObject {
    private let sparkle: SPUStandardUpdaterController

    init() {
        sparkle = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
    }

    /// Triggers an immediate user-initiated update check (shows UI).
    func checkForUpdates() {
        sparkle.updater.checkForUpdates()
    }
}
