import SwiftData
import SwiftUI

struct InsightsView: View {
    @Query(filter: #Predicate<Entry> { $0.deletedAt == nil }, sort: \Entry.createdAt, order: .reverse)
    private var entries: [Entry]

    var body: some View {
        NavigationStack {
            ScrollView {
                if entries.isEmpty {
                    ContentUnavailableView {
                        Text("Nothing to see yet")
                            .font(.system(.title2, design: .serif).weight(.semibold))
                            .foregroundStyle(Theme.primaryText)
                    } description: {
                        Text("Insights appear as you write.")
                            .font(Typography.note)
                            .foregroundStyle(Theme.secondaryText)
                    }
                    .padding(.top, 120)
                } else {
                    let stats = JournalStats(entries: entries)
                    VStack(alignment: .leading, spacing: Spacing.l) {
                        InsightSection(title: "Writing activity") {
                            ActivityHeatmap(wordsByDay: stats.wordsByDay)
                        }
                        InsightSection(title: "Insights") {
                            StatGrid(stats: stats)
                        }
                    }
                    .padding(.horizontal, Spacing.m + 4)
                    .padding(.top, Spacing.m + 4)
                    .padding(.bottom, Spacing.l)
                }
            }
            .pageTitle()
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    SettingsButton()
                }
            }
        }
    }
}

private struct InsightSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            MetaLabel(title)
            content
        }
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
                .font(.system(size: large ? 52 : 40, weight: .regular, design: .serif))
                .foregroundStyle(Theme.primaryText)
                .contentTransition(.numericText())
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            MetaLabel(label)
        }
        .padding(Spacing.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface, in: .rect(cornerRadius: 16))
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
