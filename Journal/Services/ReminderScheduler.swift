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

    /// Whether iOS will still show its prompt: it hasn't been asked yet.
    static func canAsk() async -> Bool {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus == .notDetermined
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

    /// What it says: how many places the day took in, once Track Visited Places has noted some, else
    /// a nudge. Used for the onboarding's picture of it too.
    static let title = "Take a moment to write"
    static let defaultBody = "A few lines about today is enough."

    static func placesBody(count: Int) -> String {
        count == 1 ? "You visited 1 place today." : "You visited \(count) places today."
    }

    /// With tracking off, one request repeating every day. With it on, a day's words depend on its
    /// places, and a request's words are fixed when it's scheduled — so each of the next days gets its
    /// own, today's saying how many places so far, redone whenever `PlaceTracker` notes a sample (and
    /// when the app comes back); later days start with the nudge until their places come in.
    static func schedule(minutesAfterMidnight minutes: Int) async {
        let center = UNUserNotificationCenter.current()
        await removeAll()

        guard UserDefaults.standard.bool(forKey: PlaceTracker.enabledKey) else {
            var components = DateComponents()
            components.hour = minutes / 60
            components.minute = minutes % 60
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
            try? await center.add(UNNotificationRequest(identifier: identifier, content: content(body: defaultBody), trigger: trigger))
            return
        }

        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        for offset in 0..<daysAhead {
            guard let day = calendar.date(byAdding: .day, value: offset, to: today),
                  let fire = calendar.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: day),
                  fire > .now
            else { continue }
            let count = offset == 0 ? DayPlaces.places(on: day).count : 0
            let trigger = UNCalendarNotificationTrigger(
                dateMatching: calendar.dateComponents([.year, .month, .day, .hour, .minute], from: fire),
                repeats: false
            )
            let request = UNNotificationRequest(
                identifier: dayPrefix + day.formatted(.iso8601.year().month().day()),
                content: content(body: count > 0 ? placesBody(count: count) : defaultBody),
                trigger: trigger
            )
            try? await center.add(request)
        }
    }

    static func cancel() {
        Task { await removeAll() }
    }

    private static let dayPrefix = "daily-reminder-"
    private static let daysAhead = 14

    private static func content(body: String) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        return content
    }

    private static func removeAll() async {
        let center = UNUserNotificationCenter.current()
        let ids = await center.pendingNotificationRequests().map(\.identifier)
            .filter { $0 == identifier || $0.hasPrefix(dayPrefix) }
        center.removePendingNotificationRequests(withIdentifiers: ids)
    }
}
