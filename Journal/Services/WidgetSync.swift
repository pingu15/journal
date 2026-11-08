import Foundation
import Photos
import SwiftData
import UIKit
import WidgetKit

/// Writes the widgets' snapshot (`WidgetSnapshot`) to the App Group container and asks WidgetKit to
/// redraw them: on launch, when an entry closes, and when the app leaves the foreground (after the
/// save there).
enum WidgetSync {
    /// Today's library photos kept for the collage.
    static let collageLimit = 3
    /// A collage photo's side, in pixels.
    static let photoPixels: CGFloat = 600

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

        // Today and the coming week, as the day sheet counts them.
        var days: [String: WidgetSnapshot.Day] = [:]
        for offset in 0..<8 {
            guard let date = calendar.date(byAdding: .day, value: offset, to: today) else { continue }
            let assets = PhotoLibrary.photos(on: date)
            var day = WidgetSnapshot.Day(
                entries: entries.filter { calendar.isDate($0.createdAt, inSameDayAs: date) }.count,
                places: DayPlaces.places(on: date).count,
                events: CalendarEvents.events(on: date).count,
                photos: assets.count,
                videos: PhotoLibrary.videoCount(on: date)
            )
            if offset == 0 { day.photoFiles = writeCollage(from: assets) }
            days[WidgetSnapshot.dayKey(date)] = day
        }

        let snapshot = WidgetSnapshot(
            journalName: JournalName.display(UserDefaults.standard.string(forKey: JournalName.storageKey) ?? ""),
            writtenDays: written.sorted(),
            wordCount: stats.wordCount,
            days: days
        )
        guard let url = WidgetSnapshot.fileURL, let data = try? JSONEncoder().encode(snapshot) else { return }
        try? data.write(to: url, options: .atomic)
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// The day's newest few photos, kept by their asset (written once each); any others in the folder
    /// are removed.
    private static func writeCollage(from assets: [PHAsset]) -> [String] {
        guard let folder = WidgetSnapshot.photosFolder else { return [] }
        let fileManager = FileManager.default
        try? fileManager.createDirectory(at: folder, withIntermediateDirectories: true)

        var files: [String] = []
        for asset in assets.suffix(collageLimit).reversed() {
            let name = asset.localIdentifier.replacingOccurrences(of: "/", with: "_") + ".jpg"
            let url = folder.appending(path: name)
            if !fileManager.fileExists(atPath: url.path) {
                guard let image = PhotoLibrary.imageNow(for: asset, pixels: photoPixels),
                      let data = image.jpegData(compressionQuality: 0.85)
                else { continue }
                try? data.write(to: url, options: .atomic)
            }
            files.append(name)
        }

        let keep = Set(files)
        for name in (try? fileManager.contentsOfDirectory(atPath: folder.path)) ?? [] where !keep.contains(name) {
            try? fileManager.removeItem(at: folder.appending(path: name))
        }
        return files
    }
}
