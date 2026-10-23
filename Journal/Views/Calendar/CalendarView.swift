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
    @Namespace private var transition

    private let calendar = Calendar.current
    private let monthRange = -120...12
    private let gap: CGFloat = 6

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
                        TabView(selection: $monthOffset.animation(.snappy)) {
                            ForEach(monthRange, id: \.self) { offset in
                                MonthGrid(
                                    month: month(at: offset),
                                    selectedDay: $selectedDay,
                                    days: days,
                                    cellSize: cellSize,
                                    gap: gap
                                )
                                .tag(offset)
                            }
                        }
                        .tabViewStyle(.page(indexDisplayMode: .never))
                        .frame(height: cellSize * 6 + gap * 5)
                    }
                    .onGeometryChange(for: CGFloat.self, of: { $0.size.width }) { width = $0 }

                    dayEntries
                }
                .padding(.horizontal, Spacing.m + 4)
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
        .sensoryFeedback(.impact(weight: .light), trigger: newEntryCount)
        .onChange(of: monthOffset) { _, offset in
            followMonth(offset)
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
            Spacer()
            Text(month(at: monthOffset).formatted(.dateTime.month(.wide).year()))
                .font(.system(.title3, design: .serif).weight(.semibold))
                .foregroundStyle(Theme.primaryText)
                .contentTransition(.numericText())
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Spacer()
            Button("Next Month", systemImage: "chevron.right") { shiftMonth(by: 1) }
                .disabled(monthOffset == monthRange.upperBound)
                .frame(width: 44, height: 44)
                .contentShape(.rect)
        }
        .labelStyle(.iconOnly)
        .font(.body.weight(.medium))
        .foregroundStyle(Theme.primaryText)
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
