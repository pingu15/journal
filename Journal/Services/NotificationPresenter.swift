import UserNotifications

/// Shows the reminder and On This Day as banners while the app is open too. Without a delegate iOS
/// drops a notification that arrives with the app in front, so writing at reminder time meant never
/// seeing one. A tapped reminder opens its day in the day sheet.
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

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        guard response.actionIdentifier == UNNotificationDefaultActionIdentifier else { return }
        let identifier = response.notification.request.identifier
        let date = response.notification.date
        await MainActor.run {
            guard ReminderScheduler.isReminder(identifier) else { return }
            AppRouter.shared.openDay(date)
        }
    }
}
