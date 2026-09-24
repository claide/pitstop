import Foundation
import ServiceManagement

/// Wraps SMAppService so Pitstop shows up in System Settings → General → Login Items.
enum LaunchAtLogin {
    private static let setupKey = "didSetUpLaunchAtLogin"

    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    static func set(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }

    /// On by default: turn it on once, then respect whatever the user chooses.
    static func enableOnFirstRun() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: setupKey) else { return }
        try? set(true)
        defaults.set(true, forKey: setupKey)
    }
}
