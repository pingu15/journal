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

    // Both on the main actor, not `nonisolated`: the completion handler Swift makes for an async
    // delegate method is called where the method returns, and UIKit aborts (an assertion in
    // `_updateSnapshotAndStateRestorationWithAction:`) when a tapped notification's handler is
    // called off the main thread.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        guard response.actionIdentifier == UNNotificationDefaultActionIdentifier,
              ReminderScheduler.isReminder(response.notification.request.identifier)
        else { return }
        AppRouter.shared.openDay(response.notification.date)
    }
}
