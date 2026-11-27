import Foundation
import SwiftData
import UserNotifications

/// The optional "On This Day" notification: at the chosen time, on a day the user wrote on in an
/// earlier year. A notification's words are fixed when it's scheduled, so the next 30 days are
/// scheduled ahead, one request a day that has past entries, and redone whenever the app comes back
/// (`refresh`) or the setting changes. The entries' text is never shown, only that they were written:
/// a notification is seen on the lock screen, even with the journal locked. Titled with the journal's
/// name, so renaming it schedules them again (Settings).
enum OnThisDayScheduler {
    static let enabledKey = "onThisDayEnabled"
    /// Minutes after midnight, like the daily reminder's.
    static let minutesKey = "onThisDayMinutes"
    static let defaultMinutes = 9 * 60

    private static let prefix = "on-this-day-"
    private static let daysAhead = 30

    /// Schedules the coming days if it's on and notifications are allowed; clears them otherwise.
    static func refresh(in context: ModelContext) async {
        let defaults = UserDefaults.standard
        guard defaults.bool(forKey: enabledKey), await ReminderScheduler.isAllowed() else {
            await cancel()
            return
        }
        let minutes = defaults.object(forKey: minutesKey) as? Int ?? defaultMinutes
        await schedule(minutesAfterMidnight: minutes, in: context)
    }

    /// Adds the new requests (replacing any with the same identifier) and only then removes the rest,
    /// so nothing is left unscheduled if iOS suspends the app in between.
    static func schedule(minutesAfterMidnight minutes: Int, in context: ModelContext) async {
        let calendar = Calendar.current
        let descriptor = FetchDescriptor<Entry>(predicate: #Predicate { $0.deletedAt == nil })
        let entries = (try? context.fetch(descriptor)) ?? []

        // The years written in, by month and day.
        var years: [DayKey: Set<Int>] = [:]
        for entry in entries {
            let date = calendar.dateComponents([.year, .month, .day], from: entry.createdAt)
            guard let year = date.year, let month = date.month, let day = date.day else { continue }
            years[DayKey(month: month, day: day), default: []].insert(year)
        }

        let center = UNUserNotificationCenter.current()
        var kept: Set<String> = []
        let today = calendar.startOfDay(for: .now)
        for offset in 0..<daysAhead {
            guard let day = calendar.date(byAdding: .day, value: offset, to: today),
                  let fire = calendar.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: day),
                  fire > .now
            else { continue }
            let date = calendar.dateComponents([.year, .month, .day], from: day)
            guard let year = date.year, let month = date.month, let dayOfMonth = date.day else { continue }
            let past = (years[DayKey(month: month, day: dayOfMonth)] ?? []).filter { $0 < year }.sorted()
            guard !past.isEmpty else { continue }

            let content = UNMutableNotificationContent()
            content.title = "On This Day"
            content.body = body(years: past, now: year)
            content.sound = .default
            let trigger = UNCalendarNotificationTrigger(
                dateMatching: calendar.dateComponents([.year, .month, .day, .hour, .minute], from: fire),
                repeats: false
            )
            let identifier = prefix + day.formatted(.iso8601.year().month().day())
            try? await center.add(UNNotificationRequest(identifier: identifier, content: content, trigger: trigger))
            kept.insert(identifier)
        }
        await remove(except: kept)
    }

    static func cancel() async {
        await remove(except: [])
    }

    private static func remove(except kept: Set<String>) async {
        let center = UNUserNotificationCenter.current()
        let ids = await center.pendingNotificationRequests().map(\.identifier)
            .filter { $0.hasPrefix(prefix) && !kept.contains($0) }
        center.removePendingNotificationRequests(withIdentifiers: ids)
    }

    /// "You wrote on this day a year ago.", "…3 years ago.", or "…in 2023 and 2025."
    private static func body(years: [Int], now: Int) -> String {
        if years.count == 1, let year = years.first {
            let ago = now - year
            return ago == 1 ? "You wrote on this day a year ago." : "You wrote on this day \(ago) years ago."
        }
        return "You wrote on this day in \(years.map(String.init).formatted(.list(type: .and)))."
    }

    private struct DayKey: Hashable {
        let month: Int
        let day: Int
    }
}
