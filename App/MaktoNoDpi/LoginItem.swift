import Foundation
import ServiceManagement

/// Wraps `SMAppService.mainApp` for login-item (launch-at-login) registration.
/// Registration does not require code signing, but errors are swallowed so an
/// unsigned/dev build never crashes here.
enum LoginItem {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// Enable or disable launch-at-login. Returns the resulting enabled state.
    @discardableResult
    static func setEnabled(_ enabled: Bool) -> Bool {
        do {
            if enabled {
                if SMAppService.mainApp.status != .enabled {
                    try SMAppService.mainApp.register()
                }
            } else {
                if SMAppService.mainApp.status == .enabled {
                    try SMAppService.mainApp.unregister()
                }
            }
        } catch {
            NSLog("LoginItem: failed to set enabled=\(enabled): \(error)")
        }
        return isEnabled
    }
}
