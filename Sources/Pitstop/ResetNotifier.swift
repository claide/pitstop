import Foundation
import PitstopCore
import UserNotifications

/// Schedules a notification for the moment a limit resets, but only for windows
/// you've used at least half of. Rescheduled on every refresh.
enum ResetNotifier {
    static let usedThreshold = 50.0
    private static let enabledKey = "notifyOnReset"

    static var isEnabled: Bool {
        get { UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: enabledKey) }
    }

    /// Notifications need a real app bundle; `swift run` has none.
    private static var center: UNUserNotificationCenter? {
        Bundle.main.bundleIdentifier == nil ? nil : UNUserNotificationCenter.current()
    }

    static func requestPermission() {
        center?.requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    static func schedule(for snapshots: [AccountSnapshot]) {
        guard let center else { return }
        for snapshot in snapshots {
            for window in snapshot.windows where window.kind != .other {
                let id = "reset-\(snapshot.account.id)-\(window.id)"
                guard isEnabled,
                      window.usedPercent >= usedThreshold,
                      let resetsAt = window.resetsAt,
                      resetsAt.timeIntervalSinceNow > 5 else {
                    center.removePendingNotificationRequests(withIdentifiers: [id])
                    continue
                }
                let content = UNMutableNotificationContent()
                content.title = "\(snapshot.account.provider.displayName) (\(snapshot.account.name))"
                content.body = "Your \(window.label.lowercased()) limit has reset. Good time to start a big ticket."
                content.sound = .default
                // A minute of slack so the provider has actually reset by the time you look.
                let trigger = UNTimeIntervalNotificationTrigger(timeInterval: resetsAt.timeIntervalSinceNow + 60, repeats: false)
                center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
            }
        }
    }

    static func cancelAll() {
        center?.removeAllPendingNotificationRequests()
    }
}
