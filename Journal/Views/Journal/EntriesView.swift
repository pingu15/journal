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
    /// The field, which outlasts `searchActive`: the card starts down as it starts to shrink.
    @State private var searchBarShown = false
    /// Changes as search closes, for a new search button: the bar was hidden as the old one was
    /// pressed, so it would come back big and shrink.
    @State private var searchButtonID = 0
    /// What the list leaves above it for the field.
    @State private var searchRoom: CGFloat = 0
    @FocusState private var isSearching: Bool
    @State private var filter = JournalFilter.all
    @State private var newEntryCount = 0
    /// Where the bar's search button is, for the field to grow out of.
    @State private var searchButtonFrame: CGRect = .zero
    @State private var labelTops = LabelTops()
    /// The row swiped open to show its delete button, if any.
    @State private var swipedOpen: PersistentIdentifier?

    private static let topID = "top"
    /// How far in from the screen's edges row separators and month labels start and end. Rows' text
    /// and swipe buttons end there too.
    static let contentInset = Spacing.content
    /// Above and below each row's content, as the list would give it, but inside the row so that its
    /// highlight reaches from separator to separator. The sides too: it spans the screen.
    static let rowInset: CGFloat = 15

    var body: some View {
        @Bindable var router = router

        NavigationStack(path: $router.journalPath) {
            ScrollViewReader { proxy in
                content
                    // While searching the card is full screen, with the field over its top.
                    .padding(.top, searchRoom)
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
            .overlay {
                if searchBarShown {
                    ExpandingSearchBar(
                        text: $searchText,
                        isFocused: $isSearching,
                        prompt: "Search entries",
                        buttonFrame: searchButtonFrame,
                        onClosing: closingSearch,
                        onClose: closeSearch
                    )
                    .padding(.horizontal, Spacing.m)
                    .belowNotch()
                    .transition(.asymmetric(insertion: .identity, removal: .opacity))
                }
            }
            .overlay(alignment: .bottomTrailing) {
                ZStack {
                    if filter == .all && !searchActive {
                        NewEntryButton(action: newEntry)
                            .padding(.trailing, Spacing.l)
                            .padding(.bottom, Spacing.l)
                            .transition(.scale.combined(with: .opacity))
                    }
                }
                .animation(.snappy, value: searchActive)
            }
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

    /// These stay while searching, when the bar is hidden: taken out, they'd fly off on their own.
    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            InsightsButton()
        }
        ToolbarItem(placement: .topBarTrailing) {
            Button("Search", systemImage: "magnifyingglass", action: openSearch)
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { searchButtonFrame = $0 }
                .disabled(filter == .all && entries.isEmpty)
                .id(searchButtonID)
        }
        ToolbarItem(placement: .topBarTrailing) {
            filterMenu
        }
        ToolbarItem(placement: .topBarTrailing) {
            SettingsButton()
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

            // Section labels are ordinary rows; the one for the section at the top is drawn again,
            // pinned, over the list (`PinnedSectionLabel`). A list's own pinned headers faded out, under
            // the rows, as the next one came up.
            ForEach(labelledSections, id: \.id) { section in
                Section {
                    SectionLabel(section.title, isFirst: section.id == labelledSections.first?.id) { top in
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
        .overlay {
            if entries.isEmpty {
                EmptyState(title: "A blank page", systemImage: "book", message: "Write a few lines about today.")
            } else if sections.isEmpty {
                // The system's own, as Mail and Notes show it: centered in the card (as the list's
                // first row it sat at the top).
                ContentUnavailableView.search(text: searchText)
                    .padding(.bottom, Spacing.l)
                    .allowsHitTesting(false)
            }
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
        // Not in an animation: the field takes the button's place as it is, and animates from there.
        searchBarShown = true
        searchActive = true
        // On the next turn, with the card (`PageTitle.move(up:)`): started here, it isn't animated.
        DispatchQueue.main.async {
            withAnimation(.snappy) { searchRoom = ExpandingSearchBar.room }
        }
    }

    /// The field has started to shrink, so everything else starts back.
    private func closingSearch() {
        searchButtonID += 1
        searchActive = false
        withAnimation(.smooth(duration: 0.25)) { searchRoom = 0 }
    }

    private func closeSearch() {
        searchText = ""
        isSearching = false
        searchActive = false
        searchRoom = 0
        // Fading into the button, which it only nearly matches.
        withAnimation(.easeOut(duration: 0.15)) { searchBarShown = false }
    }

    private func row(for entry: Entry, dateStyle: EntryRow.DateStyle = .day) -> some View {
        JournalEntryRow(entry: entry, dateStyle: dateStyle, swipedOpen: $swipedOpen) {
            router.journalPath.append(entry)
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

/// An entry's row in a journal-style list: a plain button rather than a NavigationLink, so it carries
/// no disclosure chevron, swiping open to Share and Delete, with the same in its context menu.
struct JournalEntryRow: View {
    let entry: Entry
    var dateStyle: EntryRow.DateStyle = .day
    @Binding var swipedOpen: PersistentIdentifier?
    let open: () -> Void

    @Environment(\.modelContext) private var context
    @State private var taps = 0
    @State private var confirmingDelete = false
    /// When a row last started opening its entry: a tap on another row in the moment before the
    /// entry opens is ignored, or both would open, one over the other.
    private static var openingSince = Date.distantPast

    var body: some View {
        Button {
            // A tap while a row is swiped open just closes it.
            if swipedOpen != nil {
                swipedOpen = nil
            } else if Date.now.timeIntervalSince(Self.openingSince) > 0.5 {
                // The press shows first, then the entry opens.
                taps += 1
                Self.openingSince = .now
                Task {
                    try? await Task.sleep(for: SwipeRowButtonStyle.tapDuration)
                    open()
                }
            }
        } label: {
            EntryRow(entry: entry, dateStyle: dateStyle)
                .entryRowPadding()
        }
        .buttonStyle(SwipeRowButtonStyle())
        .environment(\.rowTaps, taps)
        .rowSwipeActions(
            id: entry.persistentModelID,
            openRow: $swipedOpen,
            trailingInset: EntriesView.contentInset,
            actions: [
                RowSwipeAction(title: "Share", symbol: "square.and.arrow.up", tint: Theme.accent, removesRow: false) {
                    Task { await ShareSheet.present(entry.shareText) }
                },
                // Leaves the row in place while it asks.
                RowSwipeAction(title: "Delete", symbol: "trash", tint: Theme.destructive, removesRow: false) {
                    confirmingDelete = true
                },
            ]
        )
        .entryListRow()
        // A list's context menu covers the whole row, so none while its buttons are showing.
        .contextMenu {
            if swipedOpen != entry.persistentModelID {
                ShareLink(item: entry.shareText)
                Button("Delete", systemImage: "trash", role: .destructive) {
                    confirmingDelete = true
                }
            }
        }
        .deleteEntryAlert(isPresented: $confirmingDelete, action: moveToTrash)
    }

    /// Saved in the animation too: that's what takes the row out of the list.
    private func moveToTrash() {
        withAnimation {
            entry.moveToTrash()
            try? context.save()
        }
    }
}

extension View {
    /// Asks before an entry goes to Recently Deleted, from a list or the editor.
    func deleteEntryAlert(isPresented: Binding<Bool>, action: @escaping () -> Void) -> some View {
        alert("Delete this entry?", isPresented: isPresented) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive, action: action)
        } message: {
            Text("It will stay in Recently Deleted for \(Entry.trashRetentionDays) days.")
        }
    }
}

/// Entries under month labels, laid out like the journal (the map's group sheet): the top month's
/// label pinned, rows that swipe open.
struct EntryMonthList: View {
    let entries: [Entry]
    /// How far its content (and the pinned label) starts above where the list would put it: up
    /// under a solid bar, eating into the room above the first label.
    var raisedBy: CGFloat = 0
    let open: (Entry) -> Void

    @State private var labelTops = LabelTops()
    @State private var swipedOpen: PersistentIdentifier?

    var body: some View {
        let months = EntryMonth.grouping(entries)
        List {
            ForEach(months, id: \.month) { month in
                Section {
                    SectionLabel(month.title, isFirst: month.month == months.first?.month) { top in
                        labelTops.report(top, for: month.month)
                    }
                    ForEach(month.entries) { entry in
                        JournalEntryRow(entry: entry, swipedOpen: $swipedOpen) { open(entry) }
                    }
                }
            }
        }
        .contentMargins(.top, -raisedBy, for: .scrollContent)
        .pinnedSectionLabels(months.map { ($0.month, $0.title) }, tops: labelTops, bottomMargin: Spacing.l, raisedBy: raisedBy)
        .onScrollPhaseChange { _, phase in
            if phase == .interacting { swipedOpen = nil }
        }
    }
}

/// A month or "On this day" label, as a row of its own.
private struct SectionLabel: View {
    let text: String
    let isFirst: Bool
    /// Reports the label's top on screen as it scrolls (no coordinate space reaches into a list's
    /// rows from the list: a named one doesn't, and `.scrollView` is the screen's).
    let onTopChange: (CGFloat) -> Void

    init(_ text: String, isFirst: Bool, onTopChange: @escaping (CGFloat) -> Void) {
        self.text = text
        self.isFirst = isFirst
        self.onTopChange = onTopChange
    }

    var body: some View {
        SectionLabelContent(text: text, isFirst: isFirst)
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

/// A section label's look, shared by its row and the pinned copy over the list. The row ends in a
/// separator. The pinned copy stops just above that line, leaving it showing while the label is in
/// place, and it scrolls away under the copy with the rows.
private struct SectionLabelContent: View {
    let text: String
    /// The list's first label, which has no line above it.
    var isFirst = false
    var isPinned = false

    /// Above and below a label between two lines alike, so it's centered between them.
    static let padding = (Spacing.l + Spacing.m) / 2

    /// Above the text. The first label keeps more room under the card's top (and the grabber), and
    /// the pinned copy always has that much, so a label's text sits as far down when pinned.
    static func top(isFirst: Bool) -> CGFloat { isFirst ? Spacing.l : padding }

    /// Below the text. The first label's line stays where the Calendar's and Insights' match it.
    static func bottom(isFirst: Bool) -> CGFloat { isFirst ? Spacing.m : padding }

    var body: some View {
        MetaLabel(text)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, isPinned ? Spacing.l : Self.top(isFirst: isFirst))
            .padding(.bottom, Self.bottom(isFirst: isFirst) - (isPinned ? 1 : 0))
            .overlay(alignment: .bottom) {
                if !isPinned {
                    Rectangle()
                        .fill(Theme.hairline)
                        .frame(height: 1)
                }
            }
            // In line with the row separators.
            .padding(.horizontal, EntriesView.contentInset)
            // So rows passing under the pinned label don't show beside it. Short of the edge, which
            // rows stop well before, to leave the scroll bar showing.
            .background(Theme.background.padding(.trailing, Spacing.s))
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

extension View {
    /// An entry's content inside its row, so that the row's highlight reaches past it. The text and
    /// photo end as far in from the right as the month labels start from the left.
    func entryRowPadding() -> some View {
        padding(.leading, Spacing.m)
            .padding(.trailing, EntriesView.contentInset)
            .padding(.vertical, EntriesView.rowInset)
    }
}

private extension View {
    /// A list of sections led by `SectionLabel`s, with the top section's label pinned over it.
    func pinnedSectionLabels(_ sections: [(id: Date, title: String)], tops: LabelTops, bottomMargin: CGFloat = 96, raisedBy: CGFloat = 0) -> some View {
        listStyle(.plain)
            // Rows pass under the pinned label with a clean edge, not iOS 26's soft fade.
            .hidesTopScrollEdgeEffect()
            .listSectionSpacing(0)
            .environment(\.defaultMinListRowHeight, 0)
            .scrollContentBackground(.hidden)
            .scrollDismissesKeyboard(.immediately)
            // Room for the floating tab bar and new-entry button below the last row.
            .contentMargins(.bottom, bottomMargin, for: .scrollContent)
            .overlay {
                // Clipped to the list, so a label pushed up out of it doesn't show above the card.
                Color.clear
                    .overlay(alignment: .top) {
                        VStack(spacing: 0) {
                            PinnedSectionLabel(sections: sections, labelTops: tops)
                        }
                        .frame(maxWidth: .infinity)
                        // The list's top is where the pinned label is drawn, measured there: worked
                        // out from the list's frame and safe area, it came out lower than the label
                        // in a sheet at full height, so labels pinned late, leaving a gap with none.
                        .onGeometryChange(for: CGFloat.self) { $0.frame(in: .global).minY } action: { tops.listTop = $0 }
                    }
                    // Raised with the list's content (and clipped that far up).
                    .padding(.top, -raisedBy)
                    .clipped()
            }
    }

    /// An entry's row in a list of months.
    func entryListRow() -> some View {
        let inset = EntriesView.contentInset // Read here: the alignment guides run off the main actor.
        // The row keeps its insets inside it (`entryRowPadding`).
        return listRowInsets(EdgeInsets())
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
        // The last section whose label's text has reached its pinned place (a label below the first
        // has less room above it, so it's pinned a little before its row reaches the top).
        if let index = sections.indices.last(where: { index in
            (labelTops.tops[sections[index].id] ?? .infinity) <= Spacing.l - SectionLabelContent.top(isFirst: index == 0)
        }) {
            let nextTop = sections.indices.contains(index + 1) ? labelTops.tops[sections[index + 1].id] : nil
            SectionLabelContent(text: sections[index].title, isFirst: index == 0, isPinned: true)
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
    /// Asked about before it goes: unlike moving an entry here, this can't be undone.
    @State private var deleting: Entry?

    /// The one pinned label's key: labels are keyed by date, for the journal's months.
    private static var labelID: Date { .distantPast }
    private var count: String { entries.count == 1 ? "1 entry" : "\(entries.count) entries" }

    var body: some View {
        List {
            header

            if !entries.isEmpty {
                Section {
                    SectionLabel(count, isFirst: true) { top in
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
        // Worded like the photo viewer's: the same question for the same kind of delete.
        .alert("Delete this entry?", isPresented: Binding(
            get: { deleting != nil },
            set: { if !$0 { deleting = nil } }
        ), presenting: deleting) { entry in
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) { deletePermanently(entry) }
        } message: { _ in
            Text("It will be deleted permanently. This can't be undone.")
        }
        .overlay {
            // Centered on the screen rather than placed in the list.
            if entries.isEmpty {
                EmptyState(
                    title: "Nothing deleted",
                    systemImage: "trash",
                    message: "Deleted entries stay here for \(Entry.trashRetentionDays) days."
                )
            }
        }
    }

    private func row(for entry: Entry) -> some View {
        // A tap only closes an open row: these open nothing.
        Button {
            swipedOpen = nil
        } label: {
            EntryRow(entry: entry, warning: entry.daysUntilPurge == 1 ? "1 day left" : "\(entry.daysUntilPurge) days left")
                .entryRowPadding()
        }
        .buttonStyle(SwipeRowButtonStyle())
        .accessibilityRemoveTraits(.isButton)
        .rowSwipeActions(
            id: entry.persistentModelID,
            openRow: $swipedOpen,
            trailingInset: EntriesView.contentInset,
            actions: [
                RowSwipeAction(title: "Restore", symbol: "arrow.uturn.backward", tint: Theme.accent) {
                    restore(entry)
                },
                // Leaves the row in place while it asks.
                RowSwipeAction(title: "Delete", accessibilityTitle: "Delete Permanently", symbol: "trash", tint: Theme.destructive, removesRow: false) {
                    deleting = entry
                },
            ]
        )
        .entryListRow()
        // A list's context menu covers the whole row, so none while its buttons are showing.
        .contextMenu {
            if swipedOpen != entry.persistentModelID {
                Button("Restore", systemImage: "arrow.uturn.backward") {
                    restore(entry)
                }
                Button("Delete Permanently", systemImage: "trash", role: .destructive) {
                    deleting = entry
                }
            }
        }
    }

    // Saved in the animation too: that's what takes the row out of the list.

    private func restore(_ entry: Entry) {
        withAnimation {
            entry.restore()
            try? context.save()
        }
    }

    private func deletePermanently(_ entry: Entry) {
        withAnimation {
            context.delete(entry)
            try? context.save()
        }
    }
}

#Preview {
    EntriesView()
        .modelContainer(.preview)
        .environment(AppLock())
        .environment(AppRouter())
}
