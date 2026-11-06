import SwiftData
import SwiftUI

/// The journal's numbers and writing activity, in a sheet from the journal's top-left button.
struct InsightsView: View {
    @Query(filter: #Predicate<Entry> { $0.deletedAt == nil }, sort: \Entry.createdAt, order: .reverse)
    private var entries: [Entry]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                let stats = JournalStats(entries: entries)
                VStack(alignment: .leading, spacing: Spacing.l) {
                    StreakCrest(streak: stats.currentStreak)
                    ActivityHeatmap(wordsByDay: stats.wordsByDay)
                    StatGrid(stats: stats)
                }
                .padding(.horizontal, Spacing.content)
                .padding(.top, Spacing.m)
                .padding(.bottom, Spacing.l)
            }
            .background(Theme.background)
            .sheetTitle("Insights")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .tint(Theme.primaryText)
    }
}

/// The current streak as a crest: "TODAY JOURNAL" (bold, then thin, widely spaced), "N Day" and
/// "Journal 🔥 Streak" (the flame in sand), between two upright laurel branches, the way Apple frames an award.
private struct StreakCrest: View {
    let streak: Int
    /// The text's height, which sizes the branches: a fitted image left to size itself in a row
    /// takes its height from the width it's offered.
    @State private var textHeight: CGFloat = 0

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
            .onGeometryChange(for: CGFloat.self, of: \.size.height) { textHeight = $0 }
            laurel("laurel.trailing")
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Spacing.s)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(streak) day streak")
    }

    /// A branch three fifths as tall as the crest's text beside it.
    private func laurel(_ name: String) -> some View {
        Image(systemName: name)
            .resizable()
            .scaledToFit()
            .frame(height: textHeight * 0.6)
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
                tile(stats.currentStreak, "Day streak")
                tile(stats.longestStreak, "Longest streak")
            }
            GridRow {
                tile(stats.entryCount, stats.entryCount == 1 ? "Entry" : "Entries")
                tile(stats.daysJournaled, stats.daysJournaled == 1 ? "Day written" : "Days written")
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

/// The last 18 weeks as a day grid: filled if anything was written. Tap a day for its word count.
private struct ActivityHeatmap: View {
    let wordsByDay: [Date: Int]

    @State private var selectedDay: Date?

    private let weeks = 18
    private let gap: CGFloat = 4
    private let calendar = Calendar.current

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
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

            // Only once a day is tapped: its date and word count.
            if let detail {
                Text(detail)
                    .font(Typography.note)
                    .foregroundStyle(Theme.secondaryText)
                    .transition(.opacity)
            }
        }
        .sensoryFeedback(.selection, trigger: selectedDay)
    }

    @ViewBuilder
    private func dayCell(_ day: Date) -> some View {
        if day > .now {
            Color.clear
        } else {
            let words = wordsByDay[day] ?? 0
            let isSelected = selectedDay == day
            RoundedRectangle(cornerRadius: 3)
                .fill(wordsByDay[day] != nil ? Theme.activityFilled : Theme.activityEmpty)
                .overlay {
                    if isSelected {
                        RoundedRectangle(cornerRadius: 4)
                            .strokeBorder(Theme.primaryText, lineWidth: 1.5)
                            .padding(-2)
                    }
                }
                .padding(2) // larger hit target than the mark
                .contentShape(.rect)
                .padding(-2)
                .onTapGesture {
                    withAnimation(.snappy) { selectedDay = isSelected ? nil : day }
                }
                .accessibilityElement()
                .accessibilityLabel(day.formatted(date: .abbreviated, time: .omitted))
                .accessibilityValue(wordsByDay[day] == nil ? "No entries" : "\(words) words")
                .accessibilityAddTraits(.isButton)
        }
    }

    private var detail: String? {
        guard let selectedDay else { return nil }
        let date = selectedDay.formatted(.dateTime.month(.abbreviated).day())
        guard let words = wordsByDay[selectedDay] else { return "\(date) · nothing written" }
        return "\(date) · \(words.formatted()) words"
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
