import SwiftUI
import WidgetKit

@main
struct JournalWidgets: WidgetBundle {
    var body: some Widget {
        DateWidget()
        StreakWidget()
        TodayWidget()
        ActivityWidget()
        WordsWidget()
    }
}

// MARK: - Timeline

struct JournalEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot
}

/// The app's snapshot, redrawn at each of the coming week's midnights, so the day, its counts and the
/// streak follow the date without the app opening.
struct JournalProvider: TimelineProvider {
    func placeholder(in context: Context) -> JournalEntry {
        JournalEntry(date: .now, snapshot: .preview)
    }

    func getSnapshot(in context: Context, completion: @escaping (JournalEntry) -> Void) {
        let snapshot = WidgetSnapshot.load()
        completion(JournalEntry(date: .now, snapshot: context.isPreview && snapshot.writtenDays.isEmpty ? .preview : snapshot))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<JournalEntry>) -> Void) {
        let snapshot = WidgetSnapshot.load()
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        var entries = [JournalEntry(date: .now, snapshot: snapshot)]
        for offset in 1...7 {
            guard let midnight = calendar.date(byAdding: .day, value: offset, to: today) else { continue }
            entries.append(JournalEntry(date: midnight, snapshot: snapshot))
        }
        completion(Timeline(entries: entries, policy: .atEnd))
    }
}

extension WidgetSnapshot {
    /// What the widget gallery shows before the app has written anything.
    static var preview: WidgetSnapshot {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        let days = (0..<210).compactMap { offset -> Date? in
            guard offset % 5 != 3, offset % 7 != 5 else { return nil }
            return calendar.date(byAdding: .day, value: -offset, to: today)
        }
        return WidgetSnapshot(
            journalName: "Journal", writtenDays: days.sorted(), wordCount: 14_200,
            days: [dayKey(today): Day(entries: 2, places: 4, events: 3, photos: 12, videos: 1)]
        )
    }
}

// MARK: - Pieces

/// The day's counts, a line each with its icon, as the day sheet's sections are headed.
struct DayCounts: View {
    let day: WidgetSnapshot.Day
    /// Tighter, for beside the Today widget's title and photos.
    var compact = false

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 2 : 5) {
            row("book.closed", day.entries, "entry", "entries")
            row("mappin.and.ellipse", day.places, "place", "places")
            row("calendar", day.events, "event", "events")
            row("photo", day.photos, "photo", "photos")
            row("video", day.videos, "video", "videos")
        }
    }

    private func row(_ symbol: String, _ count: Int, _ one: String, _ many: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(WidgetStyle.secondaryText)
                .frame(width: 16)
            Text("\(count)")
                .font(compact ? WidgetStyle.note.weight(.semibold) : WidgetStyle.rowTitle)
                .foregroundStyle(WidgetStyle.primaryText)
                .monospacedDigit()
            + Text(" \(count == 1 ? one : many)")
                .font(compact ? WidgetStyle.note : WidgetStyle.body)
                .foregroundStyle(WidgetStyle.secondaryText)
        }
        .lineLimit(1)
    }
}

// MARK: - Date

/// The date on the left, the day's counts on the right.
struct DateWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "Date", provider: JournalProvider()) { entry in
            DateView(entry: entry)
                .containerBackground(WidgetStyle.background, for: .widget)
                .widgetURL(WidgetSnapshot.dayURL())
        }
        .configurationDisplayName("Date")
        .description("What you've been up to today.")
        .supportedFamilies([.systemMedium])
    }
}

struct DateView: View {
    let entry: JournalEntry

    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 0) {
                WidgetLabel(text: entry.date.formatted(.dateTime.weekday(.wide)))
                Text(entry.date.formatted(.dateTime.day()))
                    .font(WidgetStyle.dayNumber)
                    .foregroundStyle(WidgetStyle.primaryText)
                    .widgetAccentable()
                Text(entry.date.formatted(.dateTime.month(.wide)))
                    .font(WidgetStyle.body)
                    .foregroundStyle(WidgetStyle.secondaryText)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            Rectangle().fill(WidgetStyle.hairline).frame(width: 1)
            DayCounts(day: entry.snapshot.day(entry.date))
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - Streak

/// The current streak, large, over this week's days; on the Lock Screen, a ring or a line.
struct StreakWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "Streak", provider: JournalProvider()) { entry in
            StreakView(entry: entry)
                .containerBackground(WidgetStyle.background, for: .widget)
                .widgetURL(WidgetSnapshot.dayURL())
        }
        .configurationDisplayName("Streak")
        .description("Days in a row you've written.")
        .supportedFamilies([.systemSmall, .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

struct StreakView: View {
    let entry: JournalEntry
    @Environment(\.widgetFamily) private var family

    private var streak: Int { entry.snapshot.currentStreak(on: entry.date) }
    private var writtenToday: Bool { entry.snapshot.hasWritten(on: entry.date) }

    var body: some View {
        switch family {
        case .accessoryCircular:
            ZStack {
                AccessoryWidgetBackground()
                VStack(spacing: 0) {
                    Image(systemName: "flame.fill")
                        .font(.caption)
                    Text("\(streak)")
                        .font(.system(.title2, weight: .bold))
                        .minimumScaleFactor(0.6)
                }
            }
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 1) {
                Label("\(streak) Day Streak", systemImage: "flame.fill")
                    .font(.headline)
                Text(writtenToday ? "Written today" : "Not written yet today")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        case .accessoryInline:
            Label("\(streak) day streak", systemImage: "flame.fill")
        default:
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 4) {
                    Image(systemName: "flame.fill")
                        .font(WidgetStyle.meta)
                        .foregroundStyle(WidgetStyle.accent)
                        .widgetAccentable()
                    WidgetLabel(text: "Streak")
                }
                Spacer(minLength: 0)
                // The count with "days" beside it, on one baseline.
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text("\(streak)")
                        .font(WidgetStyle.bigNumber)
                        .foregroundStyle(WidgetStyle.primaryText)
                        .minimumScaleFactor(0.5)
                        .lineLimit(1)
                        .contentTransition(.numericText())
                    Text(streak == 1 ? "day" : "days")
                        .font(WidgetStyle.body)
                        .foregroundStyle(WidgetStyle.secondaryText)
                        .fixedSize()
                }
                Spacer(minLength: 0)
                WeekDots(snapshot: entry.snapshot, today: entry.date)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
    }
}

/// The last seven days as dots, today last and ringed: filled where something was written.
struct WeekDots: View {
    let snapshot: WidgetSnapshot
    let today: Date

    var body: some View {
        let calendar = Calendar.current
        let days = (0..<7).reversed().compactMap { calendar.date(byAdding: .day, value: -$0, to: calendar.startOfDay(for: today)) }
        HStack(spacing: 0) {
            ForEach(days, id: \.self) { day in
                let written = snapshot.hasWritten(on: day)
                let isToday = calendar.isDate(day, inSameDayAs: today)
                VStack(spacing: 3) {
                    Circle()
                        .fill(written ? WidgetStyle.primaryText : WidgetStyle.activityEmpty)
                        .overlay {
                            if isToday && !written {
                                Circle().strokeBorder(WidgetStyle.primaryText, lineWidth: 1.5)
                            }
                        }
                        .frame(width: 10, height: 10)
                        .widgetAccentable()
                    Text(day.formatted(.dateTime.weekday(.narrow)))
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(WidgetStyle.secondaryText)
                }
                .frame(maxWidth: .infinity)
            }
        }
    }
}

// MARK: - Today

/// "Today" over the day's counts on the left; on the right, a collage of the day's photos. On a morning
/// after a day with nothing written, yesterday instead, until noon.
struct TodayWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "TodayPhotos", provider: TodayProvider()) { entry in
            TodayView(entry: entry)
                .containerBackground(WidgetStyle.background, for: .widget)
                // The day it shows: yesterday's sheet on a morning it shows yesterday.
                .widgetURL(WidgetSnapshot.dayURL(entry.unwrittenYesterday))
        }
        .configurationDisplayName("Today")
        .description("The day so far, with its photos.")
        .supportedFamilies([.systemMedium])
        // Its own margins: the text at the usual inset, the collage closer to the edge.
        .contentMarginsDisabled()
    }
}

struct TodayEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot
    /// Yesterday's and today's photos as of the reload, by `WidgetSnapshot.dayKey`; nil without
    /// access to the library (the snapshot's counts then, and no collage).
    let photos: [String: DayPhotos]?

    /// Yesterday, before noon on a day after one with nothing written.
    var unwrittenYesterday: Date? {
        let calendar = Calendar.current
        guard calendar.component(.hour, from: date) < 12,
              let yesterday = calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: date)),
              !snapshot.hasWritten(on: yesterday)
        else { return nil }
        return yesterday
    }

    /// The day shown, with the library's counts where they were read.
    var shownDay: (day: WidgetSnapshot.Day, images: [UIImage]) {
        let date = unwrittenYesterday ?? date
        var day = snapshot.day(date)
        guard let photos, let loaded = photos[WidgetSnapshot.dayKey(date)] else { return (day, []) }
        day.photos = loaded.photos
        day.videos = loaded.videos
        return (day, loaded.images)
    }
}

/// Reloads every 15 minutes, reading the library for new photos (the app also reloads it whenever it's
/// opened). The coming noon and midnight are in each timeline too, so the switch between yesterday and
/// today happens on time even when iOS holds a reload back.
struct TodayProvider: TimelineProvider {
    static let reloadInterval: TimeInterval = 15 * 60

    func placeholder(in context: Context) -> TodayEntry {
        TodayEntry(date: .now, snapshot: .preview, photos: nil)
    }

    func getSnapshot(in context: Context, completion: @escaping (TodayEntry) -> Void) {
        let snapshot = WidgetSnapshot.load()
        let preview = context.isPreview && snapshot.writtenDays.isEmpty
        completion(TodayEntry(date: .now, snapshot: preview ? .preview : snapshot, photos: Self.loadPhotos(at: .now)))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TodayEntry>) -> Void) {
        let snapshot = WidgetSnapshot.load()
        let now = Date.now
        let photos = Self.loadPhotos(at: now)
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        let boundaries = [12, 24, 36].compactMap { calendar.date(byAdding: .hour, value: $0, to: today) }
            .filter { $0 > now }
            .prefix(2)
        let entries = [TodayEntry(date: now, snapshot: snapshot, photos: photos)]
            + boundaries.map { TodayEntry(date: $0, snapshot: snapshot, photos: photos) }
        completion(Timeline(entries: entries, policy: .after(now.addingTimeInterval(Self.reloadInterval))))
    }

    /// Yesterday's and today's photos, the two days the widget can show.
    private static func loadPhotos(at date: Date) -> [String: DayPhotos]? {
        let calendar = Calendar.current
        guard DayPhotos.canRead,
              let yesterday = calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: date))
        else { return nil }
        var photos: [String: DayPhotos] = [:]
        for day in [yesterday, date] {
            photos[WidgetSnapshot.dayKey(day)] = DayPhotos.load(on: day)
        }
        return photos
    }
}

struct TodayView: View {
    let entry: TodayEntry
    /// The collage's share of the widget's width.
    private static let collageShare: CGFloat = 0.61

    var body: some View {
        let isYesterday = entry.unwrittenYesterday != nil
        let shown = entry.shownDay
        GeometryReader { proxy in
            HStack(spacing: 0) {
                // Sized to fit the widget's height with the same 12pt inset as the collage (the full-size
                // counts were taller than the widget and pushed the collage to its edges).
                VStack(alignment: .leading, spacing: 6) {
                    Text(isYesterday ? "Yesterday" : "Today")
                        .font(.headline)
                        .foregroundStyle(WidgetStyle.primaryText)
                    DayCounts(day: shown.day, compact: true)
                }
                .padding(.leading, 20)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                // The same inset as the text on its three outer sides, its corners following the widget's.
                // A little over half the width, so the counts aren't left beside a wide empty gap.
                Collage(images: shown.images, emptyText: isYesterday ? "No photos" : "No photos yet")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(12)
                    .frame(width: proxy.size.width * Self.collageShare)
            }
        }
    }
}

/// Up to three photos, as the day sheet lays them out: one alone, two side by side, three as one on
/// the left and two stacked on the right.
struct Collage: View {
    let images: [UIImage]
    var emptyText = "No photos yet"
    private let gap: CGFloat = 3

    var body: some View {
        Group {
            switch images.count {
            case 0:
                ZStack {
                    WidgetStyle.activityEmpty
                    VStack(spacing: 6) {
                        Image(systemName: "photo.on.rectangle")
                            .font(.title3)
                        Text(emptyText)
                            .font(WidgetStyle.note)
                    }
                    .foregroundStyle(WidgetStyle.secondaryText)
                }
            case 1:
                tile(images[0])
            case 2:
                HStack(spacing: gap) {
                    tile(images[0])
                    tile(images[1])
                }
            default:
                HStack(spacing: gap) {
                    tile(images[0])
                    VStack(spacing: gap) {
                        tile(images[1])
                        tile(images[2])
                    }
                }
            }
        }
        .clipShape(ContainerRelativeShape())
    }

    private func tile(_ image: UIImage) -> some View {
        Color.clear
            .overlay {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            }
            .clipped()
    }
}

// MARK: - Activity and Words

/// The streak over the weeks' grid, as in Insights.
struct ActivityWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "Activity", provider: JournalProvider()) { entry in
            GridWidgetView(
                entry: entry,
                value: entry.snapshot.currentStreak(on: entry.date).formatted(),
                label: "Day streak"
            )
            .containerBackground(WidgetStyle.background, for: .widget)
            .widgetURL(WidgetSnapshot.dayURL())
        }
        .configurationDisplayName("Activity")
        .description("Your recent journaling history.")
        .supportedFamilies([.systemMedium])
    }
}

/// Every word written, over the weeks' grid.
struct WordsWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "Words", provider: JournalProvider()) { entry in
            GridWidgetView(
                entry: entry,
                value: entry.snapshot.wordCount.formatted(),
                label: entry.snapshot.wordCount == 1 ? "Word" : "Words"
            )
            .containerBackground(WidgetStyle.background, for: .widget)
            .widgetURL(WidgetSnapshot.dayURL())
        }
        .configurationDisplayName("Words")
        .description("Every word you've ever written.")
        .supportedFamilies([.systemMedium])
    }
}

/// A number and its label over the grid of written days, with the journal's name at the right.
struct GridWidgetView: View {
    let entry: JournalEntry
    let value: String
    let label: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(value)
                        .font(.system(size: 24, weight: .black))
                        .foregroundStyle(WidgetStyle.primaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    WidgetLabel(text: label, color: WidgetStyle.primaryText)
                }
                Spacer(minLength: 8)
                WidgetLabel(text: entry.snapshot.journalName)
            }
            ActivityGrid(snapshot: entry.snapshot, today: entry.date)
                .frame(maxHeight: .infinity)
        }
    }
}

/// The latest weeks, a column each (this week at the right), filling the width exactly: as many
/// columns as squares tall enough to fill the height allow, then widened to the full width (a column
/// more whenever that would overflow the height).
struct ActivityGrid: View {
    let snapshot: WidgetSnapshot
    let today: Date
    private let gap: CGFloat = 3

    var body: some View {
        GeometryReader { proxy in
            let layout = Self.layout(width: proxy.size.width, height: proxy.size.height, gap: gap)
            grid(weeks: layout.weeks, side: layout.side)
                .frame(width: proxy.size.width, height: proxy.size.height, alignment: .top)
        }
    }

    private static func layout(width: CGFloat, height: CGFloat, gap: CGFloat) -> (weeks: Int, side: CGFloat) {
        let fromHeight = max(1, (height - gap * 6) / 7)
        var weeks = max(1, Int(((width + gap) / (fromHeight + gap)).rounded()))
        var side = (width - gap * CGFloat(weeks - 1)) / CGFloat(weeks)
        while side * 7 + gap * 6 > height + 0.5 && weeks < 60 {
            weeks += 1
            side = (width - gap * CGFloat(weeks - 1)) / CGFloat(weeks)
        }
        return (weeks, side)
    }

    private func grid(weeks: Int, side: CGFloat) -> some View {
        let calendar = Calendar.current
        let thisWeek = calendar.dateInterval(of: .weekOfYear, for: today)?.start ?? calendar.startOfDay(for: today)
        let columns = (0..<weeks).reversed().compactMap { calendar.date(byAdding: .weekOfYear, value: -$0, to: thisWeek) }
        return HStack(alignment: .top, spacing: gap) {
            ForEach(columns, id: \.self) { weekStart in
                VStack(spacing: gap) {
                    ForEach(0..<7, id: \.self) { offset in
                        let day = calendar.date(byAdding: .day, value: offset, to: weekStart) ?? weekStart
                        let written = snapshot.hasWritten(on: day)
                        RoundedRectangle(cornerRadius: side * 0.22)
                            .fill(day > today ? Color.clear : written ? WidgetStyle.activityFilled : WidgetStyle.activityEmpty)
                            .frame(width: side, height: side)
                            .widgetAccentable(written)
                    }
                }
            }
        }
    }
}
