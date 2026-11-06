import Foundation

/// Aggregate numbers for the Insights screen and the journal header.
struct JournalStats {
    let entryCount: Int
    let wordCount: Int
    /// Different places written from: entries' places by name (ignoring case), or by
    /// coordinates to about 100 m for a place with no name.
    let placeCount: Int
    /// Photos and videos across all entries.
    let photoCount: Int
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

        var places = Set<String>()
        for entry in entries {
            if let name = entry.placeName?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty {
                places.insert("name:" + name.lowercased())
            } else if let latitude = entry.latitude, let longitude = entry.longitude {
                places.insert(String(format: "at:%.3f,%.3f", latitude, longitude))
            }
        }
        placeCount = places.count
        photoCount = entries.reduce(0) { $0 + $1.photos.count }

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
