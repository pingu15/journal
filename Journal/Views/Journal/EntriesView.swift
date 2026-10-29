import SwiftData
import SwiftUI

/// The home screen: entries grouped by month, newest first — or Recently Deleted.
struct EntriesView: View {
    @Environment(\.modelContext) private var context
    @Environment(AppRouter.self) private var router
    @Query(filter: #Predicate<Entry> { $0.deletedAt == nil }, sort: \Entry.createdAt, order: .reverse)
    private var entries: [Entry]
    @Query(filter: #Predicate<Entry> { $0.deletedAt != nil }, sort: \Entry.deletedAt, order: .reverse)
    private var trashed: [Entry]

    @State private var searchText = ""
    @State private var searchActive = false
    /// False when search opens with a query already filled in (a tapped tag), so results aren't hidden by the keyboard.
    @State private var focusSearchOnOpen = true
    @FocusState private var isSearching: Bool
    @State private var filter = JournalFilter.all
    @State private var newEntryCount = 0

    private static let topID = "top"
    /// Where row separators start, from a row's content edge; month labels start there too.
    static let separatorInset = Spacing.xs

    var body: some View {
        @Bindable var router = router

        NavigationStack(path: $router.journalPath) {
            ScrollViewReader { proxy in
                content
                    .onChange(of: searchActive) { _, active in
                        if active {
                            withAnimation { proxy.scrollTo(Self.topID, anchor: .top) }
                        }
                    }
            }
            .pageTitle(filter == .all ? nil : "Recently Deleted", isHidden: searchActive)
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
        .overlay(alignment: .top) {
            if searchActive {
                ExpandingSearchBar(
                    text: $searchText,
                    isFocused: $isSearching,
                    prompt: "Search by text, date, or tag",
                    focusOnAppear: focusSearchOnOpen,
                    onClose: closeSearch
                )
                .padding(.horizontal, Spacing.m)
                // Steps aside while an entry opened from the results is on screen.
                .opacity(router.journalPath.isEmpty ? 1 : 0)
                .allowsHitTesting(router.journalPath.isEmpty)
                .animation(.easeOut(duration: 0.15), value: router.journalPath.isEmpty)
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
                        .font(.system(.title2, design: .serif).weight(.semibold))
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

            // Each section's label is its header, so the current one stays pinned at the top.
            if searchText.isEmpty && !onThisDay.isEmpty {
                Section {
                    ForEach(onThisDay) { entry in
                        row(for: entry, dateStyle: .dayAndYear)
                    }
                } header: {
                    SectionLabel("On this day")
                }
            }

            ForEach(sections, id: \.month) { section in
                Section {
                    ForEach(section.entries) { entry in
                        row(for: entry)
                    }
                } header: {
                    SectionLabel(section.month.formatted(.dateTime.month(.wide).year()))
                }
            }
        }
        .listStyle(.plain)
        .listSectionSpacing(0)
        .environment(\.defaultMinListRowHeight, 0)
        .environment(\.defaultMinListHeaderHeight, 0)
        .scrollContentBackground(.hidden)
        .scrollDismissesKeyboard(.immediately)
        // Room for the floating new-entry button below the last row.
        .contentMargins(.bottom, 96, for: .scrollContent)
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
            router.journalPath.append(entry)
        } label: {
            EntryRow(entry: entry, dateStyle: dateStyle)
                // The text and photo end as far in from the right as the month labels start from
                // the left.
                .padding(.trailing, inset)
        }
        .listRowBackground(Theme.background)
        .listRowSeparatorTint(Theme.hairline)
        // Including under a month's last row, which a list leaves bare above the next header.
        .listRowSeparator(.visible, edges: .bottom)
        // Every separator starts at the same point (by default each follows its row's weekday
        // label, so they differed row to row) and ends where the row's content does, and the month
        // labels start where it does.
        .alignmentGuide(.listRowSeparatorLeading) { _ in inset }
        .alignmentGuide(.listRowSeparatorTrailing) { d in d.width - inset }
        .swipeActions(edge: .trailing) {
            Button("Delete", systemImage: "trash", role: .destructive) {
                withAnimation { entry.moveToTrash() }
                try? context.save()
            }
        }
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

    private var sections: [(month: Date, entries: [Entry])] {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        let matching = query.isEmpty ? entries : entries.filter { $0.matches(query) }

        let calendar = Calendar.current
        let groups = Dictionary(grouping: matching) {
            calendar.dateInterval(of: .month, for: $0.createdAt)?.start ?? $0.createdAt
        }
        return groups
            .sorted { $0.key > $1.key }
            .map { (month: $0.key, entries: $0.value) }
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

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        MetaLabel(text)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, Spacing.l)
            .padding(.bottom, Spacing.xs)
            // In line with the row separators.
            .padding(.leading, Spacing.m + EntriesView.separatorInset)
            .padding(.trailing, Spacing.m)
            // Edge to edge, so rows passing under a pinned label don't show beside it.
            .background(Theme.background)
            .listRowInsets(EdgeInsets())
            .accessibilityAddTraits(.isHeader)
    }
}

/// Deleted entries, kept for `Entry.trashRetentionDays` days.
private struct TrashList<Header: View>: View {
    let entries: [Entry]
    @ViewBuilder let header: Header

    @Environment(\.modelContext) private var context
    @State private var confirmingDeleteAll = false

    var body: some View {
        List {
            header

            if !entries.isEmpty {
                Section {
                    HStack {
                        MetaLabel("Deleted after \(Entry.trashRetentionDays) days")
                        Spacer()
                        Button("Restore All") {
                            withAnimation { entries.forEach { $0.restore() } }
                            try? context.save()
                        }
                        Button("Delete All", role: .destructive) {
                            confirmingDeleteAll = true
                        }
                        .padding(.leading, Spacing.m)
                    }
                    .font(.subheadline.weight(.medium))
                    .buttonStyle(.borderless)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                }

                ForEach(entries) { entry in
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        EntryRow(entry: entry)
                        MetaLabel(entry.daysUntilPurge == 1 ? "1 day left" : "\(entry.daysUntilPurge) days left")
                            .padding(.leading, 44 + Spacing.m)
                    }
                    .listRowBackground(Theme.background)
                    .listRowSeparatorTint(Theme.hairline)
                    .swipeActions(edge: .leading) {
                        Button("Restore", systemImage: "arrow.uturn.backward") {
                            withAnimation { entry.restore() }
                            try? context.save()
                        }
                        .tint(Theme.accent)
                    }
                    .swipeActions(edge: .trailing) {
                        Button("Delete Now", systemImage: "trash", role: .destructive) {
                            withAnimation { context.delete(entry) }
                            try? context.save()
                        }
                    }
                    .contextMenu {
                        Button("Restore", systemImage: "arrow.uturn.backward") {
                            withAnimation { entry.restore() }
                            try? context.save()
                        }
                        Button("Delete Now", systemImage: "trash", role: .destructive) {
                            withAnimation { context.delete(entry) }
                            try? context.save()
                        }
                    }
                }
            }
        }
        .listStyle(.plain)
        .environment(\.defaultMinListRowHeight, 0)
        .scrollContentBackground(.hidden)
        .scrollDismissesKeyboard(.immediately)
        .overlay {
            // Centered on the screen rather than placed in the list.
            if entries.isEmpty {
                VStack(spacing: Spacing.m) {
                    Image(systemName: "trash")
                        .font(.title2)
                    Text("Deleted entries stay here for \(Entry.trashRetentionDays) days.")
                        .font(Typography.note)
                        .multilineTextAlignment(.center)
                }
                .foregroundStyle(Theme.secondaryText)
                .padding(.horizontal, Spacing.l)
                .allowsHitTesting(false)
            }
        }
        .confirmationDialog(
            "Permanently delete \(entries.count == 1 ? "1 entry" : "\(entries.count) entries")?",
            isPresented: $confirmingDeleteAll,
            titleVisibility: .visible
        ) {
            Button("Delete All", role: .destructive) {
                withAnimation { entries.forEach { context.delete($0) } }
                try? context.save()
            }
        } message: {
            Text("This can't be undone.")
        }
    }
}

#Preview {
    EntriesView()
        .modelContainer(.preview)
        .environment(AppLock())
        .environment(AppRouter())
}
