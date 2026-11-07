import SwiftData
import SwiftUI

/// The journal's numbers and writing activity, in a sheet from the journal's top-left button.
struct InsightsView: View {
    @Query(filter: #Predicate<Entry> { $0.deletedAt == nil }, sort: \Entry.createdAt, order: .reverse)
    private var entries: [Entry]
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        let stats = JournalStats(entries: entries)
        NavigationStack {
            ScrollView {
                InsightsContent(stats: stats)
            }
            .background(Theme.background)
            .sheetTitle("Insights")
            .toolbar {
                // Plain icons: no glass circles behind them on iOS 26.
                if #available(iOS 26.0, *) {
                    ToolbarItem(placement: .topBarLeading) { closeButton }
                        .sharedBackgroundVisibility(.hidden)
                    ToolbarItem(placement: .topBarTrailing) { shareButton(stats) }
                        .sharedBackgroundVisibility(.hidden)
                } else {
                    ToolbarItem(placement: .topBarLeading) { closeButton }
                    ToolbarItem(placement: .topBarTrailing) { shareButton(stats) }
                }
            }
        }
        .tint(Theme.primaryText)
    }

    private var closeButton: some View {
        Button("Close", systemImage: "xmark") { dismiss() }
    }

    private func shareButton(_ stats: JournalStats) -> some View {
        Button("Share", systemImage: "square.and.arrow.up") { share(stats) }
    }

    /// The page as a picture, as it looks now (light or dark), at the screen's width.
    private func share(_ stats: JournalStats) {
        let width = UIScreen.main.bounds.width
        let renderer = ImageRenderer(
            content: ZStack {
                Theme.background
                InsightsContent(stats: stats)
                    .padding(.vertical, Spacing.m)
            }
            .frame(width: width)
            .environment(\.colorScheme, colorScheme)
        )
        renderer.scale = displayScale
        // Solid to the edges: transparent margins showed up white in Photos.
        renderer.isOpaque = true
        // As a named JPEG ("Today Journal 2026-11-05.jpg"): the share sheet previews it and shows
        // the name, and Save Image still works.
        // Today where the user is: ISO 8601 alone is in UTC, a day ahead in the evening here.
        let date = Date.now.formatted(Date.ISO8601FormatStyle(timeZone: .current).year().month().day())
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Today Journal \(date).jpg")
        guard let data = renderer.uiImage?.jpegData(compressionQuality: 0.9),
              (try? data.write(to: url)) != nil
        else { return }
        Task { await ShareSheet.present(url) }
    }
}

/// The crest, the activity grid and the figures: the sheet's page, and the picture it shares.
private struct InsightsContent: View {
    let stats: JournalStats

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.l) {
            StreakCrest(streak: stats.currentStreak)
            ActivityHeatmap(wordsByDay: stats.wordsByDay)
            StatGrid(stats: stats)
        }
        .padding(.horizontal, Spacing.content)
        .padding(.top, Spacing.m)
        .padding(.bottom, Spacing.l)
    }
}

/// The current streak as a crest: "TODAY JOURNAL" (bold, then thin, widely spaced), "N Day" and
/// "Journal 🔥 Streak" (the flame in sand), between two upright laurel branches, the way Apple frames an award.
private struct StreakCrest: View {
    let streak: Int
    /// How wide each branch is (about three fifths of the text's height), growing with Dynamic
    /// Type. Set rather than measured from the text: the shared picture is drawn in one pass,
    /// before any measurement comes back, and lost them.
    @ScaledMetric(relativeTo: .largeTitle) private var laurelWidth: CGFloat = 33

    var body: some View {
        HStack(spacing: Spacing.m) {
            laurel("laurel.leading")
            VStack(spacing: Spacing.s) {
                (Text("TODAY").font(Typography.crestNameBold)
                    + Text("JOURNAL").font(Typography.crestNameLight))
                    .tracking(Typography.crestNameTracking)
                    // Tracking also follows the last letter: as much again on the left centers it.
                    .padding(.leading, Typography.crestNameTracking)
                    .foregroundStyle(Theme.primaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text("\(streak.formatted()) Day")
                    .font(Typography.crestNumber)
                    .foregroundStyle(Theme.primaryText)
                    .contentTransition(.numericText())
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                HStack(spacing: Spacing.s) {
                    MetaLabel("Journal", color: Theme.primaryText)
                    Image(systemName: "flame.fill")
                        .font(Typography.meta)
                        .foregroundStyle(Theme.accent)
                    MetaLabel("Streak", color: Theme.primaryText)
                }
            }
            laurel("laurel.trailing")
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Spacing.s)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(streak) day streak")
    }

    /// A branch, fitted to its width.
    private func laurel(_ name: String) -> some View {
        Image(systemName: name)
            .resizable()
            .scaledToFit()
            .frame(width: laurelWidth)
            .foregroundStyle(Theme.primaryText)
            .accessibilityHidden(true)
    }
}

/// Headline numbers as plain typographic tiles.
private struct StatGrid: View {
    let stats: JournalStats

    var body: some View {
        Grid(horizontalSpacing: Spacing.m, verticalSpacing: Spacing.m) {
            GridRow {
                tile(stats.wordCount, "Words written", large: true)
                    .gridCellColumns(2)
            }
            GridRow {
                tile(stats.entryCount, stats.entryCount == 1 ? "Entry" : "Entries")
                tile(stats.longestStreak, "Longest streak")
            }
            GridRow {
                tile(stats.placeCount, stats.placeCount == 1 ? "Place visited" : "Places visited")
                tile(stats.photoCount, stats.photoCount == 1 ? "Photo" : "Photos")
            }
        }
    }

    private func tile(_ value: Int, _ label: String, large: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text(value, format: .number)
                .font(large ? Typography.largeStatNumber : Typography.statNumber)
                .foregroundStyle(Theme.primaryText)
                .contentTransition(.numericText())
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            MetaLabel(label)
        }
        .surfaceCard()
        .accessibilityElement(children: .combine)
    }
}

/// The last 18 weeks as a day grid: filled if anything was written.
private struct ActivityHeatmap: View {
    let wordsByDay: [Date: Int]

    private let weeks = 18
    private let gap: CGFloat = 4
    private let calendar = Calendar.current

    var body: some View {
        HStack(alignment: .top, spacing: gap) {
            ForEach(columns, id: \.self) { weekStart in
                VStack(spacing: gap) {
                    ForEach(0..<7, id: \.self) { offset in
                        dayCell(calendar.date(byAdding: .day, value: offset, to: weekStart)!)
                            .aspectRatio(1, contentMode: .fit)
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    @ViewBuilder
    private func dayCell(_ day: Date) -> some View {
        if day > .now {
            Color.clear
        } else {
            RoundedRectangle(cornerRadius: 3)
                .fill(wordsByDay[day] != nil ? Theme.activityFilled : Theme.activityEmpty)
                .accessibilityElement()
                .accessibilityLabel(day.formatted(date: .abbreviated, time: .omitted))
                .accessibilityValue(wordsByDay[day].map { "\($0) words" } ?? "No entries")
        }
    }

    private var columns: [Date] {
        let thisWeek = calendar.dateInterval(of: .weekOfYear, for: .now)?.start ?? calendar.startOfDay(for: .now)
        return (0..<weeks).reversed().compactMap {
            calendar.date(byAdding: .weekOfYear, value: -$0, to: thisWeek)
        }
    }
}

#Preview {
    InsightsView()
        .modelContainer(.preview)
        .environment(AppRouter())
}
