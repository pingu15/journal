import Foundation
import UserNotifications

/// Schedules the optional once-a-day writing reminder.
enum ReminderScheduler {
    static let enabledKey = "reminderEnabled"
    /// Minutes after midnight, so it survives time zone changes as a wall-clock time.
    static let minutesKey = "reminderMinutes"
    static let defaultMinutes = 21 * 60

    private static let identifier = "daily-reminder"

    static func requestAuthorization() async -> Bool {
        let center = UNUserNotificationCenter.current()
        return await SystemPrompts.shared.during {
            (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
        }
    }

    /// Whether iOS lets the app show notifications at all.
    static func isAllowed() async -> Bool {
        let status = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
        return status == .authorized || status == .provisional
    }

    /// Puts the reminder in place if it's on. It can be on with notifications off in iOS, when it can't
    /// be scheduled, so this runs whenever the app comes back, in case they've been turned on.
    static func refresh() async {
        let defaults = UserDefaults.standard
        guard defaults.bool(forKey: enabledKey), await isAllowed() else { return }
        let minutes = defaults.object(forKey: minutesKey) as? Int ?? defaultMinutes
        await schedule(minutesAfterMidnight: minutes)
    }

    static func schedule(minutesAfterMidnight minutes: Int) async {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [identifier])

        let content = UNMutableNotificationContent()
        content.title = "A moment to write"
        content.body = "A few lines about today is enough."
        content.sound = .default

        var components = DateComponents()
        components.hour = minutes / 60
        components.minute = minutes % 60
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
        try? await center.add(UNNotificationRequest(identifier: identifier, content: content, trigger: trigger))
    }

    static func cancel() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [identifier])
    }
}
