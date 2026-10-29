import SwiftData
import SwiftUI

/// Months stacked vertically in one long scroll (ten years back, two forward), each day a rounded
/// square — sand when written, or its cover photo. Tapping a day opens `DaySheet`.
struct CalendarView: View {
    @Environment(\.modelContext) private var context
    @Environment(AppRouter.self) private var router
    @Query(filter: #Predicate<Entry> { $0.deletedAt == nil }, sort: \Entry.createdAt)
    private var entries: [Entry]

    @State private var path: [Entry] = []
    @State private var width: CGFloat = 360
    /// The month at the top of the scroll, as an offset from this month.
    @State private var visibleMonth: Int? = 0
    @State private var openDay: DaySelection?
    @State private var newEntryCount = 0

    private let calendar = Calendar.current
    private let monthRange = -120...24
    private let gap: CGFloat = 3
    private let inset = Spacing.m + 4

    var body: some View {
        let days = dayIndex

        NavigationStack(path: $path) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: Spacing.m) {
                    ForEach(monthRange, id: \.self) { offset in
                        MonthSection(
                            month: month(at: offset),
                            days: days,
                            openDay: openDay?.day,
                            cellSize: cellSize,
                            gap: gap,
                            inset: inset
                        ) { day in
                            openDay = DaySelection(day: day)
                        }
                        .id(offset)
                    }
                }
                .scrollTargetLayout()
                .padding(.bottom, Spacing.m)
                .onGeometryChange(for: CGFloat.self, of: { $0.size.width - inset * 2 }) { width = $0 }
            }
            .scrollPosition(id: $visibleMonth, anchor: .top)
            .scrollIndicators(.hidden)
            // Room for the floating new-entry button below the last month.
            .contentMargins(.bottom, 96, for: .scrollContent)
            .safeAreaInset(edge: .top, spacing: 0) {
                weekdayRow
                    .padding(.horizontal, inset)
                    .padding(.vertical, Spacing.s)
                    .background(Theme.background)
                    .overlay(alignment: .bottom) {
                        Rectangle().fill(Theme.hairline).frame(height: 1)
                    }
                    // Taps on the row do nothing (otherwise they scroll the calendar to its top).
                    .contentShape(.rect)
                    .onTapGesture {}
            }
            .pageTitle()
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Today", systemImage: "\(calendar.component(.day, from: .now)).square") {
                        withAnimation(.snappy) { visibleMonth = 0 }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    SettingsButton()
                }
            }
            .navigationDestination(for: Entry.self) { entry in
                EntryEditorView(entry: entry)
            }
            .overlay(alignment: .bottomTrailing) {
                NewEntryButton(action: { newEntry(on: nil) })
                    .padding(.trailing, Spacing.l)
                    .padding(.bottom, Spacing.l)
            }
        }
        // Hidden from the stack, not the editor, so it returns as soon as the editor starts closing.
        .toolbar(path.isEmpty ? .visible : .hidden, for: .tabBar)
        .sensoryFeedback(.impact(weight: .light), trigger: newEntryCount)
        .sensoryFeedback(.selection, trigger: openDay?.day)
        .sheet(item: $openDay) { selection in
            DaySheet(
                day: selection.day,
                entries: entries,
                onOpen: { entry in open(entry) },
                onNewEntry: { day in
                    openDay = nil
                    newEntry(on: day)
                }
            )
        }
        .onChange(of: path) { _, path in
            if path.isEmpty {
                Entry.deleteBlankEntries(in: context, keeping: router.openEntries)
            }
        }
    }

    private var weekdayRow: some View {
        HStack(spacing: gap) {
            ForEach(Array(weekdaySymbols.enumerated()), id: \.offset) { _, symbol in
                MetaLabel(symbol)
                    .frame(width: cellSize)
            }
        }
    }

    /// Opens an entry from the day sheet, once the sheet is out of the way.
    private func open(_ entry: Entry) {
        openDay = nil
        Task {
            try? await Task.sleep(for: .milliseconds(350))
            path.append(entry)
        }
    }

    /// A new entry for `day` (today when nil).
    private func newEntry(on day: Date?) {
        newEntryCount += 1
        let entry = Entry.create(in: context, on: day)
        if day == nil {
            path.append(entry)
        } else {
            Task {
                try? await Task.sleep(for: .milliseconds(350))
                path.append(entry)
            }
        }
    }

    // MARK: - Data

    /// Written days, each with the cover photo of its earliest entry that has one.
    private var dayIndex: [Date: DayInfo] {
        var index: [Date: DayInfo] = [:]
        for entry in entries {
            let day = calendar.startOfDay(for: entry.createdAt)
            if index[day]?.cover == nil {
                index[day] = DayInfo(cover: entry.coverPhoto)
            }
        }
        return index
    }

    private var cellSize: CGFloat {
        max(24, (width - gap * 6) / 7)
    }

    private func month(at offset: Int) -> Date {
        calendar.date(byAdding: .month, value: offset, to: calendar.startOfMonth(for: .now)) ?? .now
    }

    private var weekdaySymbols: [String] {
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        let first = calendar.firstWeekday - 1
        return Array(symbols[first...] + symbols[..<first])
    }
}

struct DayInfo {
    let cover: Attachment?
}

/// The day shown in the day sheet.
private struct DaySelection: Identifiable {
    let day: Date
    var id: Date { day }
}

/// One month: its title on a faintly tinted band across the page, over its grid of days.
private struct MonthSection: View {
    let month: Date
    let days: [Date: DayInfo]
    let openDay: Date?
    let cellSize: CGFloat
    let gap: CGFloat
    let inset: CGFloat
    let onSelect: (Date) -> Void

    private let calendar = Calendar.current

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            // Set like the editor's date line.
            MetaLabel(month.formatted(.dateTime.month(.wide).year()))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, inset)
                .padding(.vertical, Spacing.s + 2)
                .background(Theme.band)

            let columns = Array(repeating: GridItem(.fixed(cellSize), spacing: gap), count: 7)
            LazyVGrid(columns: columns, spacing: gap) {
                ForEach(0..<leadingBlanks, id: \.self) { _ in
                    Color.clear.frame(width: cellSize, height: cellSize)
                }
                ForEach(dates, id: \.self) { day in
                    DayCell(
                        day: day,
                        info: days[day],
                        isSelected: openDay.map { calendar.isDate(day, inSameDayAs: $0) } ?? false,
                        size: cellSize
                    ) {
                        onSelect(day)
                    }
                }
            }
            .padding(.horizontal, inset)
        }
    }

    private var leadingBlanks: Int {
        let weekday = calendar.component(.weekday, from: month)
        return (weekday - calendar.firstWeekday + 7) % 7
    }

    private var dates: [Date] {
        guard let range = calendar.range(of: .day, in: .month, for: month) else { return [] }
        return range.compactMap { calendar.date(byAdding: .day, value: $0 - 1, to: month) }
    }
}

private struct DayCell: View {
    let day: Date
    let info: DayInfo?
    let isSelected: Bool
    let size: CGFloat
    let action: () -> Void

    var body: some View {
        let isToday = Calendar.current.isDateInToday(day)
        let isFuture = day > .now
        let image = info?.cover.flatMap(ThumbnailCache.image(for:))
        let shape = RoundedRectangle(cornerRadius: size * 0.12, style: .continuous)

        Button(action: action) {
            ZStack {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: size, height: size)
                        .clipped()
                    Color.black.opacity(0.22)
                } else if info != nil {
                    // Written day: sand, a shade deeper when selected.
                    shape.fill(Theme.accent)
                    if isSelected { shape.fill(Color.black.opacity(0.15)) }
                } else {
                    shape.fill(Theme.primaryText.opacity(0.05))
                }

                Text(day.formatted(.dateTime.day()))
                    .font(.system(.callout).weight(info != nil || isToday ? .semibold : .regular))
                    .foregroundStyle(
                        image != nil ? Color.white
                            : info != nil ? Theme.onAccent
                            : isFuture ? Theme.secondaryText.opacity(0.5)
                            : Theme.primaryText
                    )
                    .shadow(color: image != nil ? .black.opacity(0.4) : .clear, radius: 2, y: 1)
            }
            .frame(width: size, height: size)
            .clipShape(shape)
            .overlay {
                if isSelected {
                    shape.strokeBorder(Theme.primaryText, lineWidth: 2)
                } else if isToday {
                    shape.strokeBorder(Theme.secondaryText, lineWidth: 1)
                }
            }
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(day.formatted(date: .complete, time: .omitted))
        .accessibilityValue(info != nil ? "Has entries" : "")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

extension Calendar {
    func startOfMonth(for date: Date) -> Date {
        dateInterval(of: .month, for: date)?.start ?? startOfDay(for: date)
    }
}

#Preview {
    CalendarView()
        .modelContainer(.preview)
        .environment(AppRouter())
}
