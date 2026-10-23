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

    @AppStorage(JournalName.storageKey) private var journalName = JournalName.default
    @State private var searchText = ""
    @State private var searchActive = false
    /// False when search opens with a query already filled in (a tapped tag), so results aren't hidden by the keyboard.
    @State private var focusSearchOnOpen = true
    @FocusState private var isSearching: Bool
    @State private var titleScroll = TitleScroll()
    @State private var filter = JournalFilter.all
    @State private var newEntryCount = 0
    @Namespace private var transition

    private static let topID = "top"

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
            .background(Theme.background)
            .inlinePageTitle(
                filter == .all ? JournalName.default : "Recently Deleted",
                navigationTitle: pageName,
                scroll: titleScroll,
                isHidden: searchActive
            )
            .toolbar { toolbarContent }
            .navigationDestination(for: Entry.self) { entry in
                EntryEditorView(entry: entry)
                    .navigationTransition(.zoom(sourceID: entry.id, in: transition))
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
        .sensoryFeedback(.impact(weight: .light), trigger: newEntryCount)
        .onChange(of: router.journalPath) { _, path in
            if path.isEmpty {
                Entry.deleteBlankEntries(in: context, keeping: router.openEntries)
            }
        }
        .onChange(of: filter) {
            titleScroll.progress = 0
        }
        .onChange(of: router.pendingNewEntry, initial: true) { _, pending in
            guard pending else { return }
            router.pendingNewEntry = false
            router.journalPath.removeAll()
            filter = .all
            newEntry()
        }
        .onChange(of: router.pendingSearch, initial: true) { _, query in
            guard let query else { return }
            router.pendingSearch = nil
            router.journalPath.removeAll()
            filter = .all
            searchText = query
            focusSearchOnOpen = false
            withAnimation(.snappy) { searchActive = true }
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

    private var pageName: String {
        filter == .all ? JournalName.display(journalName) : "Recently Deleted"
    }

    /// "2025 – 2026", or a single year, spanning the first and latest entries.
    private var yearSpan: String? {
        guard let newest = entries.first?.createdAt, let oldest = entries.last?.createdAt else { return nil }
        let calendar = Calendar.current
        let first = calendar.component(.year, from: oldest)
        let last = calendar.component(.year, from: newest)
        return first == last ? String(first) : "\(first) – \(last)"
    }

    @ViewBuilder
    private var content: some View {
        switch filter {
        case .all:
            timeline
        case .recentlyDeleted:
            TrashList(entries: trashed.filter { $0.matches(searchText) }, titleScroll: titleScroll) {
                header
            }
        }
    }

    private var timeline: some View {
        List {
            header

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

            // Section labels are ordinary rows rather than headers, so they scroll away instead of
            // pinning under the bar.
            if searchText.isEmpty && !onThisDay.isEmpty {
                Section {
                    SectionLabel("On this day")
                    ForEach(onThisDay) { entry in
                        row(for: entry, dateStyle: .dayAndYear)
                    }
                }
            }

            ForEach(sections, id: \.month) { section in
                Section {
                    SectionLabel(section.month.formatted(.dateTime.month(.wide).year()))
                    ForEach(section.entries) { entry in
                        row(for: entry)
                    }
                }
            }
        }
        .listStyle(.plain)
        .environment(\.defaultMinListRowHeight, 0)
        .scrollContentBackground(.hidden)
        .scrollDismissesKeyboard(.immediately)
        .tracksTitleScroll(titleScroll)
        // Room for the floating new-entry button below the last row.
        .contentMargins(.bottom, 96, for: .scrollContent)
    }

    /// The page's large title and year span — hidden while searching, so results start under the bar.
    private var header: some View {
        Group {
            if searchActive {
                Color.clear.frame(height: Spacing.xs)
            } else {
                LargePageTitle(pageName, subtitle: filter == .all ? yearSpan : nil)
                    .transition(.opacity)
            }
        }
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
        Button {
            router.journalPath.append(entry)
        } label: {
            EntryRow(entry: entry, dateStyle: dateStyle)
                .matchedTransitionSource(id: entry.id, in: transition)
        }
        .listRowBackground(Theme.background)
        .listRowSeparatorTint(Theme.hairline)
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
            .listRowInsets(EdgeInsets(top: 0, leading: Spacing.m, bottom: 0, trailing: Spacing.m))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .accessibilityAddTraits(.isHeader)
    }
}

/// Deleted entries, kept for `Entry.trashRetentionDays` days.
private struct TrashList<Header: View>: View {
    let entries: [Entry]
    let titleScroll: TitleScroll
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
        .tracksTitleScroll(titleScroll)
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
