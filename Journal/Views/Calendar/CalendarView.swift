import SwiftData
import SwiftUI

/// Swipeable month grid — each written day shows its cover photo — with the selected day's entries below.
struct CalendarView: View {
    @Environment(\.modelContext) private var context
    @Environment(AppRouter.self) private var router
    @Query(filter: #Predicate<Entry> { $0.deletedAt == nil }, sort: \Entry.createdAt)
    private var entries: [Entry]

    /// Months relative to the current month; the pager spans ten years back and one forward.
    @State private var monthOffset = 0
    @State private var selectedDay = Calendar.current.startOfDay(for: .now)
    @State private var path: [Entry] = []
    @State private var width: CGFloat = 360
    @State private var titleScroll = TitleScroll()
    @State private var newEntryCount = 0
    /// The pager's position, and how far through it the swipe is (in pages, fractional mid-swipe).
    @State private var pagerMonth: Int? = 0
    @State private var pagePosition: CGFloat = 0
    /// The month the pager's height shows: it switches as soon as a swipe is let go, before the
    /// pager settles.
    @State private var shownMonth = 0
    /// The title slot's width: a title slides across it for each page the pager moves.
    @State private var titleWidth: CGFloat = 200
    @Namespace private var transition

    private let calendar = Calendar.current
    private let monthRange = -120...12
    private let gap: CGFloat = 6
    /// The calendar's side inset; each month page reaches past it, so months swipe in from the screen edge.
    private let inset = Spacing.m + 4

    var body: some View {
        let days = dayIndex

        NavigationStack(path: $path) {
            ScrollView {
                LargePageTitle("Calendar", topPadding: Spacing.xs)
                    .padding(.horizontal, Spacing.m)

                VStack(alignment: .leading, spacing: Spacing.l) {
                    VStack(spacing: Spacing.m) {
                        monthHeader
                        weekdayRow
                        monthPager(days: days)
                    }
                    .onGeometryChange(for: CGFloat.self, of: { $0.size.width }) { width = $0 }

                    dayEntries
                }
                .padding(.horizontal, inset)
                .padding(.top, Spacing.m)
            }
            .tracksTitleScroll(titleScroll)
            // Room for the floating new-entry button below the day's entries.
            .contentMargins(.bottom, 96, for: .scrollContent)
            .background(Theme.background)
            .inlinePageTitle("Calendar", scroll: titleScroll)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Today", systemImage: "\(calendar.component(.day, from: .now)).square") {
                        withAnimation(.snappy) {
                            monthOffset = 0
                            selectedDay = calendar.startOfDay(for: .now)
                        }
                    }
                    .disabled(monthOffset == 0 && calendar.isDateInToday(selectedDay))
                }
                ToolbarItem(placement: .topBarTrailing) {
                    SettingsButton()
                }
            }
            .navigationDestination(for: Entry.self) { entry in
                EntryEditorView(entry: entry)
                    .navigationTransition(.zoom(sourceID: entry.id, in: transition))
            }
            .overlay(alignment: .bottomTrailing) {
                // Writes for the selected day; there's nothing to write about a day that hasn't happened.
                if selectedDay <= .now {
                    NewEntryButton(action: newEntry)
                        .padding(.trailing, Spacing.l)
                        .padding(.bottom, Spacing.l)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .animation(.snappy, value: selectedDay <= .now)
        }
        // Hidden from the stack, not the editor, so it returns as soon as the editor starts closing.
        .toolbar(path.isEmpty ? .visible : .hidden, for: .tabBar)
        .sensoryFeedback(.impact(weight: .light), trigger: newEntryCount)
        .onChange(of: monthOffset) { _, offset in
            followMonth(offset)
            show(offset)
            // Arrows and Today change the month directly; bring the pager along.
            if pagerMonth != offset {
                withAnimation(.snappy) { pagerMonth = offset }
            }
        }
        .onChange(of: path) { _, path in
            if path.isEmpty {
                Entry.deleteBlankEntries(in: context, keeping: router.openEntries)
            }
        }
    }

    // MARK: - Pieces

    private var monthHeader: some View {
        HStack {
            Button("Previous Month", systemImage: "chevron.left") { shiftMonth(by: -1) }
                .disabled(monthOffset == monthRange.lowerBound)
                .frame(width: 44, height: 44)
                .contentShape(.rect)
            // The titles either side of the pager's position, moved with it: mid-swipe, each is as far
            // through the slot as its month is through the screen.
            ZStack {
                let base = Int(pagePosition.rounded(.down))
                ForEach([base, base + 1], id: \.self) { offset in
                    if monthRange.contains(offset) {
                        let progress = CGFloat(offset) - pagePosition
                        Text(month(at: offset).formatted(.dateTime.month(.wide).year()))
                            .font(.system(.title3, design: .serif).weight(.semibold))
                            .foregroundStyle(Theme.primaryText)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                            .offset(x: progress * titleWidth)
                            .opacity(1 - abs(progress))
                            .accessibilityHidden(abs(progress) >= 0.5)
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .onGeometryChange(for: CGFloat.self, of: { $0.size.width }) { titleWidth = $0 }
            .clipped()
            Button("Next Month", systemImage: "chevron.right") { shiftMonth(by: 1) }
                .disabled(monthOffset == monthRange.upperBound)
                .frame(width: 44, height: 44)
                .contentShape(.rect)
        }
        .labelStyle(.iconOnly)
        .font(.body.weight(.medium))
        .foregroundStyle(Theme.primaryText)
    }

    /// Months side by side, a page per swipe. The pager is as tall as the shown month, so what's
    /// below sits at the grid's foot; it takes the new month's height as soon as a swipe is let go.
    private func monthPager(days: [Date: DayInfo]) -> some View {
        ScrollView(.horizontal) {
            LazyHStack(alignment: .top, spacing: 0) {
                ForEach(monthRange, id: \.self) { offset in
                    MonthGrid(
                        month: month(at: offset),
                        selectedDay: $selectedDay,
                        days: days,
                        cellSize: cellSize,
                        gap: gap
                    )
                    .frame(width: width, height: gridHeight(rows: 6), alignment: .top)
                    .containerRelativeFrame(.horizontal)
                    .id(offset)
                }
            }
            .scrollTargetLayout()
        }
        .scrollPosition(id: $pagerMonth)
        .scrollTargetBehavior(.viewAligned(limitBehavior: .alwaysByOne))
        .scrollIndicators(.hidden)
        .onScrollGeometryChange(for: CGFloat.self, of: { geometry in
            guard geometry.containerSize.width > 0 else { return CGFloat(monthOffset) }
            return geometry.contentOffset.x / geometry.containerSize.width + CGFloat(monthRange.lowerBound)
        }) { _, position in
            pagePosition = position
        }
        .onScrollPhaseChange { old, phase, context in
            switch phase {
            case .decelerating where old == .interacting:
                // Let go: the pager moves at most one month, the way the swipe was going.
                let start = shownMonth
                let velocity = context.velocity?.dx ?? 0
                let target = abs(velocity) > 0.05
                    ? start + (velocity > 0 ? 1 : -1)
                    : min(max(Int(pagePosition.rounded()), start - 1), start + 1)
                if monthRange.contains(target) { show(target) }
            case .idle:
                // Only a settled pager picks the month (and the selection): mid-scroll it reports
                // months it's passing through.
                let settled = Int(pagePosition.rounded())
                guard monthRange.contains(settled) else { return }
                show(settled)
                if settled != monthOffset {
                    withAnimation(.snappy) { monthOffset = settled }
                }
            default:
                break
            }
        }
        // Always six rows tall inside, shown only down to the current height.
        .frame(height: gridHeight(rows: 6))
        .frame(height: pagerHeight, alignment: .top)
        .clipped()
        .contentShape(.rect)
        .padding(.horizontal, -inset)
    }

    private var pagerHeight: CGFloat {
        gridHeight(rows: rows(at: shownMonth))
    }

    /// Animates the pager's height to `month`'s.
    private func show(_ month: Int) {
        guard month != shownMonth else { return }
        withAnimation(.snappy) { shownMonth = month }
    }

    private func gridHeight(rows: Int) -> CGFloat {
        cellSize * CGFloat(rows) + gap * CGFloat(rows - 1)
    }

    /// Weeks the month spans (4–6).
    private func rows(at offset: Int) -> Int {
        let clamped = min(max(offset, monthRange.lowerBound), monthRange.upperBound)
        let month = month(at: clamped)
        let blanks = (calendar.component(.weekday, from: month) - calendar.firstWeekday + 7) % 7
        let count = calendar.range(of: .day, in: .month, for: month)?.count ?? 30
        return (blanks + count + 6) / 7
    }

    private var weekdayRow: some View {
        HStack(spacing: gap) {
            ForEach(Array(weekdaySymbols.enumerated()), id: \.offset) { _, symbol in
                MetaLabel(symbol)
                    .frame(width: cellSize)
            }
        }
    }

    @ViewBuilder
    private var dayEntries: some View {
        let entriesForDay = entries.filter { calendar.isDate($0.createdAt, inSameDayAs: selectedDay) }

        VStack(alignment: .leading, spacing: Spacing.s) {
            MetaLabel(selectedDay.formatted(.dateTime.weekday(.wide).day().month(.wide)))

            if entriesForDay.isEmpty {
                Text(selectedDay > .now ? "This day hasn't happened yet." : "Nothing written on this day.")
                    .font(Typography.note)
                    .foregroundStyle(Theme.secondaryText)
                    .padding(.vertical, Spacing.s)
            } else {
                ForEach(entriesForDay) { entry in
                    Button {
                        path.append(entry)
                    } label: {
                        EntryRow(entry: entry, dateStyle: .time)
                            // The Journal tab's List adds this much around each row; match it.
                            .padding(.vertical, 6)
                            .matchedTransitionSource(id: entry.id, in: transition)
                    }
                    .buttonStyle(.plain)
                    // 1 pt, like the Journal list's separators (Divider is a single pixel).
                    Rectangle().fill(Theme.hairline).frame(height: 1)
                }
            }
        }
        .animation(.snappy, value: selectedDay)
    }

    private func newEntry() {
        newEntryCount += 1
        path.append(Entry.create(in: context, on: selectedDay))
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

    /// When the month changes, the selection follows: today if it's in that month, else the
    /// month's first written day, else the 1st.
    private func followMonth(_ offset: Int) {
        let month = month(at: offset)
        guard !calendar.isDate(selectedDay, equalTo: month, toGranularity: .month) else { return }
        if calendar.isDate(.now, equalTo: month, toGranularity: .month) {
            selectedDay = calendar.startOfDay(for: .now)
        } else if let first = entries.first(where: { calendar.isDate($0.createdAt, equalTo: month, toGranularity: .month) }) {
            selectedDay = calendar.startOfDay(for: first.createdAt)
        } else {
            selectedDay = month
        }
    }

    private func shiftMonth(by value: Int) {
        let next = monthOffset + value
        guard monthRange.contains(next) else { return }
        withAnimation(.snappy) { monthOffset = next }
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

private struct MonthGrid: View {
    let month: Date
    @Binding var selectedDay: Date
    let days: [Date: DayInfo]
    let cellSize: CGFloat
    let gap: CGFloat

    private let calendar = Calendar.current

    var body: some View {
        let columns = Array(repeating: GridItem(.fixed(cellSize), spacing: gap), count: 7)
        LazyVGrid(columns: columns, spacing: gap) {
            ForEach(0..<leadingBlanks, id: \.self) { _ in
                Color.clear.frame(width: cellSize, height: cellSize)
            }
            ForEach(dates, id: \.self) { day in
                DayCell(
                    day: day,
                    info: days[day],
                    isSelected: calendar.isDate(day, inSameDayAs: selectedDay),
                    size: cellSize
                ) {
                    selectedDay = day
                }
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .sensoryFeedback(.selection, trigger: selectedDay)
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
        let shape = RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)

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
                    if isSelected { shape.fill(Theme.onAccent.opacity(0.25)) }
                } else {
                    shape.fill(Theme.primaryText.opacity(0.05))
                }

                Text(day.formatted(.dateTime.day()))
                    .font(.system(.callout, design: .serif).weight(info != nil || isToday ? .semibold : .regular))
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
