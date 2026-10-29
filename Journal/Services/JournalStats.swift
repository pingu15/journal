import Foundation

/// Aggregate numbers for the Insights screen and the journal header.
struct JournalStats {
    let entryCount: Int
    let wordCount: Int
    let daysJournaled: Int
    let currentStreak: Int
    let longestStreak: Int
    /// Words written per calendar day (keyed by start of day).
    let wordsByDay: [Date: Int]

    init(entries: [Entry], calendar: Calendar = .current, today: Date = .now) {
        entryCount = entries.count
        wordCount = entries.reduce(0) { $0 + $1.wordCount }

        var wordsByDay: [Date: Int] = [:]
        for entry in entries {
            wordsByDay[calendar.startOfDay(for: entry.createdAt), default: 0] += entry.wordCount
        }
        self.wordsByDay = wordsByDay

        let days = Set(wordsByDay.keys)
        daysJournaled = days.count

        // Today doesn't break the streak until it's over.
        var current = 0
        var cursor = calendar.startOfDay(for: today)
        if !days.contains(cursor), let yesterday = calendar.date(byAdding: .day, value: -1, to: cursor) {
            cursor = yesterday
        }
        while days.contains(cursor), let previous = calendar.date(byAdding: .day, value: -1, to: cursor) {
            current += 1
            cursor = previous
        }
        currentStreak = current

        var longest = 0
        var run = 0
        var previousDay: Date?
        for day in days.sorted() {
            if let previousDay, calendar.date(byAdding: .day, value: 1, to: previousDay) == day {
                run += 1
            } else {
                run = 1
            }
            longest = max(longest, run)
            previousDay = day
        }
        longestStreak = longest
    }
}
