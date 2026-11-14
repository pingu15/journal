import Foundation
import SwiftData
import WidgetKit

/// Writes the widgets' snapshot (`WidgetSnapshot`) to the App Group container and asks WidgetKit to
/// redraw them: on launch, whenever the app comes to the foreground, when an entry closes, and when
/// the app leaves the foreground (after the save there). The Today widget's photos aren't in it: the
/// widget loads those itself (`DayPhotos`). The daily reminder is rescheduled from it too, for its streak.
enum WidgetSync {
    static func update(in context: ModelContext) {
        let descriptor = FetchDescriptor<Entry>(
            predicate: #Predicate { $0.deletedAt == nil },
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        guard let entries = try? context.fetch(descriptor) else { return }
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        let stats = JournalStats(entries: entries)

        // Enough days for the activity grid (at most 30 weeks) and any streak that runs into it.
        let gridStart = calendar.date(byAdding: .day, value: -31 * 7, to: today) ?? today
        let streakStart = calendar.date(byAdding: .day, value: -stats.currentStreak - 1, to: today) ?? today
        let from = min(gridStart, streakStart)
        let written = Set(entries.map { calendar.startOfDay(for: $0.createdAt) }).filter { $0 >= from }

        // Yesterday (the Today widget shows it on a morning it went unwritten), today and the coming
        // week, as the day sheet counts them.
        var days: [String: WidgetSnapshot.Day] = [:]
        for offset in -1..<8 {
            guard let date = calendar.date(byAdding: .day, value: offset, to: today) else { continue }
            let day = WidgetSnapshot.Day(
                entries: entries.filter { calendar.isDate($0.createdAt, inSameDayAs: date) }.count,
                places: DayPlaces.places(on: date).count,
                events: CalendarEvents.events(on: date).count,
                photos: PhotoLibrary.photos(on: date).count,
                videos: PhotoLibrary.videoCount(on: date)
            )
            days[WidgetSnapshot.dayKey(date)] = day
        }

        let snapshot = WidgetSnapshot(
            journalName: JournalName.display(UserDefaults.standard.string(forKey: JournalName.storageKey) ?? ""),
            writtenDays: written.sorted(),
            wordCount: stats.wordCount,
            days: days
        )
        removeOldPhotoFiles()
        guard let url = WidgetSnapshot.fileURL, let data = try? JSONEncoder().encode(snapshot) else { return }
        try? data.write(to: url, options: .atomic)
        WidgetCenter.shared.reloadAllTimelines()
        // The reminder names the streak, which this snapshot has just recounted.
        Task { await ReminderScheduler.refresh() }
    }

    /// The collage's photos were once copied here for the Today widget, which now loads its own.
    private static func removeOldPhotoFiles() {
        guard let folder = WidgetSnapshot.containerURL?.appending(path: "WidgetPhotos", directoryHint: .isDirectory)
        else { return }
        try? FileManager.default.removeItem(at: folder)
    }
}
