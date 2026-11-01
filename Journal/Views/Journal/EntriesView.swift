import SwiftData
import SwiftUI

/// The home screen: entries grouped by month, newest first — or Recently Deleted.
struct EntriesView: View {
    @Environment(\.modelContext) private var context
    @Environment(AppRouter.self) private var router
    @Query(filter: #Predicate<Entry> { $0.deletedAt == nil }, sort: \Entry.createdAt, order: .reverse)
    private var entries: [Entry]
    /// Oldest deletion first: fewest days left at the top.
    @Query(filter: #Predicate<Entry> { $0.deletedAt != nil }, sort: \Entry.deletedAt)
    private var trashed: [Entry]

    @State private var searchText = ""
    @State private var searchActive = false
    /// False when search opens with a query already filled in (a tapped tag), so results aren't hidden by the keyboard.
    @State private var focusSearchOnOpen = true
    @FocusState private var isSearching: Bool
    @State private var filter = JournalFilter.all
    @State private var newEntryCount = 0
    @State private var labelTops = LabelTops()
    /// The row swiped open to show its delete button, if any.
    @State private var swipedOpen: PersistentIdentifier?

    private static let topID = "top"
    /// Where row separators start, from a row's content edge; month labels start there too.
    static let separatorInset = Spacing.xs
    /// Above and below each row, as the list would give it.
    static let rowInset: CGFloat = 15

    var body: some View {
        @Bindable var router = router

        NavigationStack(path: $router.journalPath) {
            ScrollViewReader { proxy in
                VStack(spacing: 0) {
                    // While searching the card is full screen, with the field at its top.
                    if searchActive {
                        ExpandingSearchBar(
                            text: $searchText,
                            isFocused: $isSearching,
                            prompt: "Search by text, date, or tag",
                            focusOnAppear: focusSearchOnOpen,
                            onClose: closeSearch
                        )
                        .padding(.horizontal, Spacing.m)
                        .padding(.top, Spacing.m)
                    }
                    content
                }
                .onChange(of: searchActive) { _, active in
                    if active {
                        withAnimation { proxy.scrollTo(Self.topID, anchor: .top) }
                    }
                }
            }
            .pageTitle(filter == .all ? nil : "Recently Deleted", isFullScreen: searchActive)
            .toolbar { toolbarContent }
            .navigationDestination(for: Entry.self) { entry in
                EntryEditorView(entry: entry)
            }
            .overlay(alignment: .bottomTrailing) {
                if filter == .all && !searchActive {
                    NewEntryButton(action: newEntry)
                        .padding(.trailing, Spacing.l)
                        .padding(.bottom, Spacing.l)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .animation(.snappy, value: searchActive)
        }
        // Hidden from the stack rather than the editor, so it's back as soon as the editor starts
        // closing (a pushed view's own setting only lifts once its pop animation ends).
        .toolbar(router.journalPath.isEmpty ? .visible : .hidden, for: .tabBar)
        .sensoryFeedback(.impact(weight: .light), trigger: newEntryCount)
        .onChange(of: router.journalPath) { _, path in
            if path.isEmpty {
                Entry.deleteBlankEntries(in: context, keeping: router.openEntries)
            }
        }
        .onChange(of: router.pendingNewEntry, initial: true) { _, pending in
            guard pending else { return }
            router.pendingNewEntry = false
            router.journalPath.removeAll()
            filter = .all
            newEntry()
        }
    }

    // MARK: - Content

    /// While searching, the bar is left to the search field (drawn over it), so it has no buttons.
    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        if !searchActive {
            ToolbarItem(placement: .topBarLeading) {
                Button("Search", systemImage: "magnifyingglass", action: openSearch)
                    .disabled(filter == .all && entries.isEmpty)
            }
            ToolbarItem(placement: .topBarTrailing) {
                filterMenu
            }
            ToolbarItem(placement: .topBarTrailing) {
                SettingsButton()
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch filter {
        case .all:
            timeline
        case .recentlyDeleted:
            TrashList(entries: trashed.filter { $0.matches(searchText) }) {
                topMarker
            }
        }
    }

    private var timeline: some View {
        List {
            topMarker

            if entries.isEmpty {
                ContentUnavailableView {
                    Text("A blank page")
                        .font(Typography.title)
                        .foregroundStyle(Theme.primaryText)
                } description: {
                    Text("Write a few lines about today.")
                        .font(Typography.note)
                        .foregroundStyle(Theme.secondaryText)
                }
                .padding(.top, 140)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            } else if sections.isEmpty {
                ContentUnavailableView.search(text: searchText)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }

            // Section labels are ordinary rows; the one for the section at the top is drawn again,
            // pinned, over the list (`PinnedSectionLabel`). A list's own pinned headers faded out, under
            // the rows, as the next one came up.
            ForEach(labelledSections, id: \.id) { section in
                Section {
                    SectionLabel(section.title) { top in
                        labelTops.report(top, for: section.id)
                    }
                    ForEach(section.entries) { entry in
                        row(for: entry, dateStyle: section.dateStyle)
                    }
                }
            }
        }
        .pinnedSectionLabels(labelledSections.map { ($0.id, $0.title) }, tops: labelTops)
        .onScrollPhaseChange { _, phase in
            if phase == .interacting { swipedOpen = nil }
        }
    }

    /// "On this day" (when it shows), then each month, newest first.
    private var labelledSections: [LabelledSection] {
        var result: [LabelledSection] = []
        if searchText.isEmpty && !onThisDay.isEmpty {
            result.append(LabelledSection(id: .distantFuture, title: "On this day", entries: onThisDay, dateStyle: .dayAndYear))
        }
        for section in sections {
            result.append(LabelledSection(id: section.month, title: section.title, entries: section.entries, dateStyle: .day))
        }
        return result
    }

    /// The top of the list, for scrolling back to when search opens.
    private var topMarker: some View {
        Color.clear
            .frame(height: 0)
            .id(Self.topID)
        .listRowInsets(EdgeInsets(top: 0, leading: Spacing.m, bottom: 0, trailing: Spacing.m))
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }

    private func openSearch() {
        focusSearchOnOpen = true
        withAnimation(.snappy) { searchActive = true }
    }

    private func closeSearch() {
        searchText = ""
        isSearching = false
        withAnimation(.snappy) { searchActive = false }
    }

    /// A plain button rather than a NavigationLink, so rows carry no disclosure chevron.
    private func row(for entry: Entry, dateStyle: EntryRow.DateStyle = .day) -> some View {
        let inset = Self.separatorInset // Read here: the alignment guides run off the main actor.
        return Button {
            // A tap while a row is swiped open just closes it.
            if swipedOpen != nil {
                swipedOpen = nil
            } else {
                router.journalPath.append(entry)
            }
        } label: {
            EntryRow(entry: entry, dateStyle: dateStyle)
                // The text and photo end as far in from the right as the month labels start from
                // the left.
                .padding(.trailing, inset)
        }
        .rowSwipeActions(
            id: entry.persistentModelID,
            openRow: $swipedOpen,
            trailingInset: inset,
            actions: [
                RowSwipeAction(title: "Share", symbol: "square.and.arrow.up", tint: Theme.accent, removesRow: false) {
                    Task { await ShareSheet.present(entry.shareText) }
                },
                RowSwipeAction(title: "Delete", symbol: "trash", tint: Theme.destructive) {
                    withAnimation { entry.moveToTrash() }
                    try? context.save()
                },
            ]
        )
        .entryListRow()
        .contextMenu {
            ShareLink(item: entry.shareText)
            Button("Delete", systemImage: "trash", role: .destructive) {
                withAnimation { entry.moveToTrash() }
                try? context.save()
            }
        }
    }

    private var filterMenu: some View {
        Menu {
            Picker("Show", selection: $filter.animation()) {
                ForEach(JournalFilter.allCases, id: \.self) { option in
                    Label(option.label, systemImage: option.symbol).tag(option)
                }
            }
        } label: {
            Label("Filter", systemImage: filter == .all
                  ? "line.3.horizontal.decrease"
                  : "line.3.horizontal.decrease.circle.fill")
        }
    }

    // MARK: - Data

    private var sections: [EntryMonth] {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        return EntryMonth.grouping(query.isEmpty ? entries : entries.filter { $0.matches(query) })
    }

    private var onThisDay: [Entry] {
        let calendar = Calendar.current
        let today = calendar.dateComponents([.month, .day, .year], from: .now)
        return entries.filter { entry in
            let date = calendar.dateComponents([.month, .day, .year], from: entry.createdAt)
            return date.month == today.month && date.day == today.day && date.year != today.year
        }
    }

    private func newEntry() {
        closeSearch()
        let entry = Entry.create(in: context)
        newEntryCount += 1
        router.journalPath.append(entry)
    }
}

/// A month or "On this day" label, as a row of its own.
/// A month or "On this day" label, as its section's header (pinned while its rows scroll by). It sits
/// as far below the card's top edge, or the separator above it, as the label's top padding.
private struct SectionLabel: View {
    let text: String
    /// Reports the label's top on screen as it scrolls (no coordinate space reaches into a list's
    /// rows from the list: a named one doesn't, and `.scrollView` is the screen's).
    let onTopChange: (CGFloat) -> Void

    init(_ text: String, onTopChange: @escaping (CGFloat) -> Void) {
        self.text = text
        self.onTopChange = onTopChange
    }

    var body: some View {
        // The first row's top inset makes up the rest of the space below the label.
        SectionLabelContent(text: text, bottomPadding: Spacing.m - EntriesView.rowInset)
            .onGeometryChange(for: CGFloat.self) { proxy in
                proxy.frame(in: .global).minY
            } action: { top in
                onTopChange(top)
            }
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .accessibilityAddTraits(.isHeader)
    }
}

/// A section label's look, shared by its row and the pinned copy over the list.
private struct SectionLabelContent: View {
    let text: String
    /// The pinned copy keeps the full space below it, which rows scroll under.
    var bottomPadding = Spacing.m

    var body: some View {
        MetaLabel(text)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, Spacing.l)
            // With the first row's top inset and padding, the label sits as far above that row's text
            // as below the card's edge; while pinned, rows pass under here.
            .padding(.bottom, bottomPadding)
            // In line with the row separators.
            .padding(.leading, Spacing.m + EntriesView.separatorInset)
            .padding(.trailing, Spacing.m)
            // So rows passing under the pinned label don't show beside it.
            .background(Theme.background)
    }
}

/// Entries written in one month.
private struct EntryMonth {
    let month: Date
    let entries: [Entry]

    var title: String { month.formatted(.dateTime.month(.wide).year()) }

    /// `entries` by the month they were written, newest first.
    static func grouping(_ entries: [Entry]) -> [EntryMonth] {
        let calendar = Calendar.current
        let groups = Dictionary(grouping: entries) {
            calendar.dateInterval(of: .month, for: $0.createdAt)?.start ?? $0.createdAt
        }
        return groups
            .sorted { $0.key > $1.key }
            .map { EntryMonth(month: $0.key, entries: $0.value) }
    }
}

private extension View {
    /// A list of sections led by `SectionLabel`s, with the top section's label pinned over it.
    func pinnedSectionLabels(_ sections: [(id: Date, title: String)], tops: LabelTops) -> some View {
        listStyle(.plain)
            // Rows pass under the pinned label with a clean edge, not iOS 26's soft fade.
            .hidesTopScrollEdgeEffect()
            .listSectionSpacing(0)
            .environment(\.defaultMinListRowHeight, 0)
            .scrollContentBackground(.hidden)
            .scrollDismissesKeyboard(.immediately)
            // Room for the floating tab bar and new-entry button below the last row.
            .contentMargins(.bottom, 96, for: .scrollContent)
            .onGeometryChange(for: CGFloat.self) { $0.frame(in: .global).minY } action: { tops.listTop = $0 }
            .overlay {
                // Clipped to the list, so a label pushed up out of it doesn't show above the card.
                Color.clear
                    .overlay(alignment: .top) {
                        PinnedSectionLabel(sections: sections, labelTops: tops)
                    }
                    .clipped()
            }
    }

    /// An entry's row in a list of months.
    func entryListRow() -> some View {
        let inset = EntriesView.separatorInset // Read here: the alignment guides run off the main actor.
        // The list's own insets. (A section's first row keeps its inset too — the label row leaves that
        // much less below it — so its long-press preview isn't cut off at the top.)
        return listRowInsets(EdgeInsets(
            top: EntriesView.rowInset, leading: Spacing.m, bottom: EntriesView.rowInset, trailing: Spacing.m
        ))
        .listRowBackground(Theme.background)
        .listRowSeparatorTint(Theme.hairline)
        // Including under a month's last row, which a list leaves bare above the next header.
        .listRowSeparator(.visible, edges: .bottom)
        // Every separator starts at the same point (by default each follows its row's weekday
        // label, so they differed row to row) and ends where the row's content does, and the month
        // labels start where it does.
        .alignmentGuide(.listRowSeparatorLeading) { _ in inset }
        .alignmentGuide(.listRowSeparatorTrailing) { d in d.width - inset }
    }
}

private struct LabelledSection {
    let id: Date
    let title: String
    let entries: [Entry]
    let dateStyle: EntryRow.DateStyle
}

/// Where each section's label row sits in the list (its top), as last reported.
/// Kept in an object the list only holds, so the scroll redraws just the pinned label.
@Observable
private final class LabelTops {
    private(set) var tops: [Date: CGFloat] = [:]
    /// The list's top on screen. It moves with the card, whose movement rows don't report, so a
    /// label's place is worked out when it's reported, not from its last place on screen later.
    @ObservationIgnored var listTop: CGFloat = 0

    func report(_ top: CGFloat, for id: Date) {
        tops[id] = top - listTop
    }
}

/// The label of the section at the top of the list, drawn over it. It covers that section's own label
/// while it's in place, stays at the top once it has scrolled past, and is pushed up by the next
/// section's label as that one arrives — moving with it, never fading.
private struct PinnedSectionLabel: View {
    let sections: [(id: Date, title: String)]
    let labelTops: LabelTops
    @State private var height: CGFloat = 0

    var body: some View {
        // The last section whose label has reached the top.
        if let index = sections.lastIndex(where: { (labelTops.tops[$0.id] ?? .infinity) <= 0 }) {
            let nextTop = sections.indices.contains(index + 1) ? labelTops.tops[sections[index + 1].id] : nil
            SectionLabelContent(text: sections[index].title)
                // Short of the edge, which rows stop well before, to leave the scroll bar showing.
                .padding(.trailing, Spacing.s)
                .onGeometryChange(for: CGFloat.self, of: \.size.height) { height = $0 }
                .offset(y: min(0, (nextTop ?? .infinity) - height))
                // Drags go through to the list beneath.
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }
}

/// Deleted entries, kept for `Entry.trashRetentionDays` days.
private struct TrashList<Header: View>: View {
    let entries: [Entry]
    @ViewBuilder let header: Header

    @Environment(\.modelContext) private var context
    @State private var labelTops = LabelTops()
    /// The row swiped open to show its buttons, if any.
    @State private var swipedOpen: PersistentIdentifier?

    /// The one pinned label's key: labels are keyed by date, for the journal's months.
    private static var labelID: Date { .distantPast }
    private var count: String { entries.count == 1 ? "1 entry" : "\(entries.count) entries" }

    var body: some View {
        List {
            header

            if !entries.isEmpty {
                Section {
                    SectionLabel(count) { top in
                        labelTops.report(top, for: Self.labelID)
                    }
                    ForEach(entries) { entry in
                        row(for: entry)
                    }
                }
            }
        }
        .pinnedSectionLabels(entries.isEmpty ? [] : [(Self.labelID, count)], tops: labelTops)
        .onScrollPhaseChange { _, phase in
            if phase == .interacting { swipedOpen = nil }
        }
        .overlay {
            // Centered on the screen rather than placed in the list.
            if entries.isEmpty {
                VStack(spacing: Spacing.m) {
                    Image(systemName: "trash")
                        .font(Typography.icon)
                    Text("Deleted entries stay here for \(Entry.trashRetentionDays) days.")
                        .font(Typography.note)
                        .multilineTextAlignment(.center)
                }
                .foregroundStyle(Theme.secondaryText)
                .padding(.horizontal, Spacing.l)
                .allowsHitTesting(false)
            }
        }
    }

    private func row(for entry: Entry) -> some View {
        EntryRow(entry: entry, warning: entry.daysUntilPurge == 1 ? "1 day left" : "\(entry.daysUntilPurge) days left")
            // The text and photo end as far in from the right as the month labels start from the left.
            .padding(.trailing, EntriesView.separatorInset)
            // A tap only closes an open row: these open nothing.
            .contentShape(.rect)
            .onTapGesture { swipedOpen = nil }
            .rowSwipeActions(
                id: entry.persistentModelID,
                openRow: $swipedOpen,
                trailingInset: EntriesView.separatorInset,
                actions: [
                    RowSwipeAction(title: "Restore", symbol: "arrow.uturn.backward", tint: Theme.accent) {
                        withAnimation { entry.restore() }
                        try? context.save()
                    },
                    RowSwipeAction(title: "Delete Permanently", symbol: "trash", tint: Theme.destructive) {
                        withAnimation { context.delete(entry) }
                        try? context.save()
                    },
                ]
            )
            .entryListRow()
            .contextMenu {
                Button("Restore", systemImage: "arrow.uturn.backward") {
                    withAnimation { entry.restore() }
                    try? context.save()
                }
                Button("Delete Permanently", systemImage: "trash", role: .destructive) {
                    withAnimation { context.delete(entry) }
                    try? context.save()
                }
            }
    }
}

#Preview {
    EntriesView()
        .modelContainer(.preview)
        .environment(AppLock())
        .environment(AppRouter())
}
