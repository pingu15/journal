import Foundation

/// What the Home Screen widgets show, written by the app (`WidgetSync`) to the App Group container
/// and read by the widget extension. A snapshot rather than the journal's store, so the store never
/// has to move or be opened by two processes; the widgets work out "today" from it themselves, so a
/// snapshot written yesterday still shows the right day after midnight.
///
/// Compiled into both the app and the widget extension (the `Shared` folder).
nonisolated struct WidgetSnapshot: Codable, Sendable {
    static let appGroup = "group.com.maxsun.journal"
    /// Opens a blank entry for today (`widgetURL`, handled in `RootView.onOpenURL`).
    static let newEntryURL = URL(string: "todayjournal://new")!
    /// Just opens the journal.
    static let openURL = URL(string: "todayjournal://open")!

    /// A day as the day sheet sees it: what was written, where you were, what was on, what was taken.
    struct Day: Codable, Sendable, Hashable {
        var entries = 0
        var places = 0
        var events = 0
        var photos = 0
        var videos = 0
        /// The day's first few photos from the library, files in `photosFolder` (today only).
        var photoFiles: [String] = []
    }

    var journalName: String
    /// Start of every day written on (the last 30 weeks or so: the grid and any streak shown).
    var writtenDays: [Date]
    var wordCount: Int
    /// Today and the coming week, keyed by `dayKey` (a day after the last one reads as empty).
    var days: [String: Day]

    static let empty = WidgetSnapshot(journalName: "Journal", writtenDays: [], wordCount: 0, days: [:])

    static var containerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup)
    }

    static var fileURL: URL? { containerURL?.appending(path: "widget-snapshot.json") }
    static var photosFolder: URL? { containerURL?.appending(path: "WidgetPhotos", directoryHint: .isDirectory) }

    static func load() -> WidgetSnapshot {
        guard let url = fileURL, let data = try? Data(contentsOf: url),
              let snapshot = try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
        else { return .empty }
        return snapshot
    }

    static func dayKey(_ date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    // MARK: As of a given day

    func day(_ date: Date) -> Day {
        days[Self.dayKey(date)] ?? Day()
    }

    func hasWritten(on day: Date, calendar: Calendar = .current) -> Bool {
        writtenDays.contains(calendar.startOfDay(for: day))
    }

    /// Days in a row up to `day`; today doesn't break it until it's over (as in Insights).
    func currentStreak(on day: Date, calendar: Calendar = .current) -> Int {
        let days = Set(writtenDays)
        var cursor = calendar.startOfDay(for: day)
        if !days.contains(cursor), let yesterday = calendar.date(byAdding: .day, value: -1, to: cursor) {
            cursor = yesterday
        }
        var count = 0
        while days.contains(cursor), let previous = calendar.date(byAdding: .day, value: -1, to: cursor) {
            count += 1
            cursor = previous
        }
        return count
    }
}
