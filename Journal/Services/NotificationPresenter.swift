import UserNotifications

/// Shows the reminder and On This Day as banners while the app is open too. Without a delegate iOS
/// drops a notification that arrives with the app in front, so writing at reminder time meant never
/// seeing one.
final class NotificationPresenter: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationPresenter()

    /// Set before the app finishes launching, so a notification that opened the app is handled too.
    func install() {
        UNUserNotificationCenter.current().delegate = self
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }
}
