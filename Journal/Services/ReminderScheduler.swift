import Foundation
import OSLog
import UserNotifications

/// Schedules the optional once-a-day writing reminder.
enum ReminderScheduler {
    static let enabledKey = "reminderEnabled"
    /// Minutes after midnight, so it survives time zone changes as a wall-clock time.
    static let minutesKey = "reminderMinutes"
    static let defaultMinutes = 21 * 60

    /// The single repeating request it used to be; removed wherever it's still pending.
    private static let identifier = "daily-reminder"
    private static let logger = Logger(subsystem: "com.maxsun.journal", category: "notifications")

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

    /// What it says: how many places the day took in, once Track Visited Places has noted some; else
    /// the streak it would keep going; else a nudge to start one.
    static let title = "Take a moment to write"
    static let newStreakBody = "Start a new journaling streak today."

    static func streakBody(days: Int) -> String {
        "Keep your \(days.formatted()) day streak going."
    }

    static func placesBody(count: Int) -> String {
        count == 1 ? "You visited 1 place today." : "You visited \(count) places today."
    }

    /// A day's words depend on its places and the streak, and a request's words are fixed when it's
    /// scheduled — so each of the next days gets its own. A day's streak is the one it would have if
    /// nothing more were written (from the widget snapshot, so redone whenever `WidgetSync` writes
    /// one), which only today and tomorrow can have. Today's places are redone whenever
    /// `PlaceTracker` notes a sample (and when the app comes back); later days start with the streak
    /// or the nudge until their places come in.
    ///
    /// The new requests replace the old ones in place (same identifiers), and only then are leftovers
    /// removed. Clearing first left nothing scheduled whenever iOS suspended the app in between, which
    /// a sample noted in the background often does. Runs one at a time, so overlapping calls can't
    /// remove each other's requests.
    static func schedule(minutesAfterMidnight minutes: Int) async {
        let previous = pending
        let task = Task {
            await previous?.value
            await replace(with: requests(minutesAfterMidnight: minutes))
        }
        pending = task
        await task.value
    }

    private static var pending: Task<Void, Never>?

    private static func requests(minutesAfterMidnight minutes: Int) -> [UNNotificationRequest] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        let snapshot = WidgetSnapshot.load()
        let tracksPlaces = UserDefaults.standard.bool(forKey: PlaceTracker.enabledKey)
        return (0..<daysAhead).compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: offset, to: today),
                  let fire = calendar.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: day),
                  fire > .now
            else { return nil }
            let streak = snapshot.currentStreak(on: day, calendar: calendar)
            let places = tracksPlaces && offset == 0 ? DayPlaces.places(on: day).count : 0
            let body = if places > 0 {
                placesBody(count: places)
            } else if streak > 0 {
                streakBody(days: streak)
            } else {
                newStreakBody
            }
            let trigger = UNCalendarNotificationTrigger(
                dateMatching: calendar.dateComponents([.year, .month, .day, .hour, .minute], from: fire),
                repeats: false
            )
            return UNNotificationRequest(
                identifier: dayPrefix + day.formatted(.iso8601.year().month().day()),
                content: content(body: body),
                trigger: trigger
            )
        }
    }

    /// Adds `requests` (replacing any with the same identifier), then removes the reminder's others.
    private static func replace(with requests: [UNNotificationRequest]) async {
        let center = UNUserNotificationCenter.current()
        for request in requests {
            do {
                try await center.add(request)
            } catch {
                logger.error("Reminder couldn't be scheduled: \(error.localizedDescription, privacy: .public)")
            }
        }
        let kept = Set(requests.map(\.identifier))
        let stale = await center.pendingNotificationRequests().map(\.identifier)
            .filter { ($0 == identifier || $0.hasPrefix(dayPrefix)) && !kept.contains($0) }
        center.removePendingNotificationRequests(withIdentifiers: stale)
    }

    static func cancel() {
        let previous = pending
        pending = Task {
            await previous?.value
            await replace(with: [])
        }
    }

    private static let dayPrefix = "daily-reminder-"

    /// Whether a delivered notification is the daily reminder.
    static func isReminder(_ identifier: String) -> Bool {
        identifier == self.identifier || identifier.hasPrefix(dayPrefix)
    }
    /// Enough that it keeps coming for a month without the app being opened. With On This Day's 30,
    /// that's 60 of the 64 requests iOS keeps pending.
    private static let daysAhead = 30

    private static func content(body: String) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        return content
    }
}
