import SwiftData
import SwiftUI

/// Months stacked vertically in one endless-feeling scroll (five centuries either way), each day a
/// rounded square — sand when written, or its cover photo. Only the months near the screen are
/// built. Tapping a day opens `DaySheet`.
struct CalendarView: View {
    @Environment(\.modelContext) private var context
    @Environment(AppRouter.self) private var router
    @Query(filter: #Predicate<Entry> { $0.deletedAt == nil }, sort: \Entry.createdAt)
    private var entries: [Entry]

    @State private var path: [Entry] = []
    @State private var width: CGFloat = 0
    @State private var position = ScrollPosition()
    /// The months built: those in view and a screen's worth either side (indexes into `weeks`).
    @State private var shownMonths: ClosedRange<Int>?
    /// The month at the top of the view. Every month's height follows the width, so when the width
    /// changes (it's reported more than once on the way in) the scroll is put back on this month.
    /// Taken from the scroll only while it's moving: before the opening position lands, it reads as
    /// the very first month.
    @State private var topMonth: Int?
    @State private var scrollPhase = ScrollPhase.idle
    @State private var openDay: DaySelection?
    @State private var newEntryCount = 0
    /// Each month's title row, fixed so a month's height is known before it's built.
    @ScaledMetric(relativeTo: .caption2) private var titleHeight: CGFloat = 34

    private let calendar = Calendar.current
    private static let weeks = MonthWeeks(monthsEachWay: 6000)
    private let gap: CGFloat = 3
    private let inset = Spacing.m + 4

    var body: some View {
        let days = dayIndex

        NavigationStack(path: $path) {
            // The weekday row sits above the scroll rather than in its safe-area inset: as an
            // inset, the opening scroll position put this month's title under it.
            VStack(spacing: 0) {
                weekdayRow
                    .padding(.horizontal, inset)
                    .padding(.vertical, Spacing.s + 3)
                    .overlay(alignment: .bottom) {
                        Rectangle().fill(Theme.hairline).frame(height: 1)
                    }

                ScrollView {
                    let monthLayout = layout(width: width)
                    let months = shownMonths ?? monthLayout.months(around: Self.weeks.index(of: .now))
                    ZStack(alignment: .top) {
                        Color.clear.frame(height: monthLayout.height + Spacing.m)
                        ForEach(Array(months), id: \.self) { index in
                            MonthSection(
                                month: Self.weeks.month(at: index),
                                days: days,
                                openDay: openDay?.day,
                                titleHeight: titleHeight,
                                cellSize: monthLayout.cellSize,
                                gap: gap,
                                inset: inset
                            ) { day in
                                openDay = DaySelection(day: day)
                            }
                            .offset(y: monthLayout.top(index))
                        }
                    }
                }
                .scrollPosition($position)
                .onScrollGeometryChange(for: [Int].self) { geometry in
                    let visible = geometry.visibleRect
                    let layout = layout(width: width)
                    let shown = layout.months(from: visible.minY - visible.height, to: visible.maxY + visible.height)
                    let top = layout.months(from: visible.minY, to: visible.minY).lowerBound
                    return [shown.lowerBound, shown.upperBound, top]
                } action: { _, value in
                    shownMonths = value[0]...value[1]
                    if scrollPhase != .idle { topMonth = value[2] }
                }
                .onScrollPhaseChange { _, phase in scrollPhase = phase }
                .onGeometryChange(for: CGFloat.self, of: \.size.width) { newWidth in
                    guard newWidth > 0, newWidth != width else { return }
                    width = newWidth
                    position.scrollTo(y: layout(width: newWidth).top(topMonth ?? Self.weeks.index(of: .now)))
                }
                .scrollIndicators(.hidden)
                // Room for the floating tab bar below the last month.
                .contentMargins(.bottom, 96, for: .scrollContent)
            }
            .pageTitle()
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Today", systemImage: "\(calendar.component(.day, from: .now)).square") {
                        showThisMonth()
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    SettingsButton()
                }
            }
            .navigationDestination(for: Entry.self) { entry in
                EntryEditorView(entry: entry)
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
        .onChange(of: router.calendarTabTaps) { showThisMonth() }
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
                    .frame(width: layout(width: width).cellSize)
            }
        }
    }

    private func layout(width: CGFloat) -> MonthLayout {
        MonthLayout(
            weeks: Self.weeks,
            titleHeight: titleHeight,
            cellSize: max(24, (width - inset * 2 - gap * 6) / 7),
            gap: gap
        )
    }

    private func showThisMonth() {
        let top = layout(width: width).top(Self.weeks.index(of: .now))
        withAnimation(.snappy) { position.scrollTo(y: top) }
    }

    /// Opens an entry from the day sheet, once the sheet is out of the way.
    private func open(_ entry: Entry) {
        openDay = nil
        Task {
            try? await Task.sleep(for: .milliseconds(350))
            path.append(entry)
        }
    }

    /// A new entry for `day`, once the day sheet is out of the way.
    private func newEntry(on day: Date) {
        newEntryCount += 1
        let entry = Entry.create(in: context, on: day)
        Task {
            try? await Task.sleep(for: .milliseconds(350))
            path.append(entry)
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

/// How many week rows each month spans, for every month the calendar shows (`monthsEachWay` either
/// side of the month it was first opened in), and how many come before each one.
private struct MonthWeeks {
    let first: Date
    /// Rows before each month, plus one entry past the last (the total).
    let rowsBefore: [Int]

    var count: Int { rowsBefore.count - 1 }

    init(monthsEachWay: Int, calendar: Calendar = .current) {
        first = calendar.date(byAdding: .month, value: -monthsEachWay, to: calendar.startOfMonth(for: .now)) ?? .now
        var rowsBefore = [0]
        rowsBefore.reserveCapacity(monthsEachWay * 2 + 2)
        for index in 0...(monthsEachWay * 2) {
            let month = calendar.date(byAdding: .month, value: index, to: first) ?? first
            let days = calendar.range(of: .day, in: .month, for: month)?.count ?? 30
            let rows = (calendar.leadingBlanks(inMonthStarting: month) + days + 6) / 7
            rowsBefore.append(rowsBefore[index] + rows)
        }
        self.rowsBefore = rowsBefore
    }

    func month(at index: Int) -> Date {
        Calendar.current.date(byAdding: .month, value: index, to: first) ?? first
    }

    func index(of date: Date) -> Int {
        let calendar = Calendar.current
        let months = calendar.dateComponents([.month], from: first, to: calendar.startOfMonth(for: date)).month ?? 0
        return min(max(months, 0), count - 1)
    }
}

/// Where each month sits in the scroll. Worked out from week counts rather than measured, so any
/// month can be placed without building the ones above it: a lazy stack estimated the heights of the
/// months it hadn't built, and the scroll jumped whenever those estimates changed.
private struct MonthLayout {
    let weeks: MonthWeeks
    let titleHeight: CGFloat
    let cellSize: CGFloat
    let gap: CGFloat

    /// Each month above is its title row, a gap, and its week rows each followed by a gap.
    func top(_ index: Int) -> CGFloat {
        CGFloat(index) * (titleHeight + gap) + CGFloat(weeks.rowsBefore[index]) * (cellSize + gap)
    }

    var height: CGFloat { top(weeks.count) - gap }

    /// The months overlapping `minY...maxY`.
    func months(from minY: CGFloat, to maxY: CGFloat) -> ClosedRange<Int> {
        let first = lastMonth(startingAtOrAbove: minY)
        return first...max(first, lastMonth(startingAtOrAbove: maxY))
    }

    /// `index` and its neighbors, before the scroll has reported what's in view.
    func months(around index: Int) -> ClosedRange<Int> {
        max(index - 1, 0)...min(index + 2, weeks.count - 1)
    }

    private func lastMonth(startingAtOrAbove y: CGFloat) -> Int {
        var low = 0
        var high = weeks.count - 1
        while low < high {
            let mid = (low + high + 1) / 2
            if top(mid) <= y { low = mid } else { high = mid - 1 }
        }
        return low
    }
}

/// One month: its title over its grid of days.
private struct MonthSection: View {
    let month: Date
    let days: [Date: DayInfo]
    let openDay: Date?
    let titleHeight: CGFloat
    let cellSize: CGFloat
    let gap: CGFloat
    let inset: CGFloat
    let onSelect: (Date) -> Void

    private let calendar = Calendar.current

    var body: some View {
        VStack(alignment: .leading, spacing: gap) {
            // Set like the editor's date line.
            MetaLabel(month.formatted(.dateTime.month(.wide).year()))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, inset)
                .frame(height: titleHeight)

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
        calendar.leadingBlanks(inMonthStarting: month)
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
                    .font(.system(.callout).weight(.semibold))
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

    /// Empty cells before a month's first day in a week row starting on `firstWeekday`.
    func leadingBlanks(inMonthStarting month: Date) -> Int {
        (component(.weekday, from: month) - firstWeekday + 7) % 7
    }
}

#Preview {
    CalendarView()
        .modelContainer(.preview)
        .environment(AppRouter())
}
