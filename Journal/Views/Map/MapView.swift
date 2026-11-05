import MapKit
import SwiftData
import SwiftUI

/// Every entry with a place, as dots on a map (`EntryMap`). Long-pressing the map starts an entry
/// there.
struct MapView: View {
    @Environment(\.modelContext) private var context
    @Environment(AppRouter.self) private var router
    @Query(filter: #Predicate<Entry> { $0.deletedAt == nil && $0.latitude != nil }, sort: \Entry.createdAt, order: .reverse)
    private var entries: [Entry]

    @State private var path: [Entry] = []
    @State private var listed: ListedEntries?
    /// Entries started from a long press: their place came with them, so if nothing else is added
    /// they're still discarded (see `EntryEditorView.placeIsProvisional`).
    @State private var startedHere: Set<PersistentIdentifier> = []
    @State private var newEntryCount = 0
    @State private var recenterCount = 0
    @State private var locationDenied = false

    var body: some View {
        NavigationStack(path: $path) {
            EntryMap(pins: pins, recenterCount: recenterCount, onOpen: open(_:), onLongPress: newEntry(at:))
                .pageTitle()
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Current Location", systemImage: "location", action: recenter)
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        SettingsButton()
                    }
                }
                .navigationDestination(for: Entry.self) { entry in
                    EntryEditorView(entry: entry, placeIsProvisional: startedHere.contains(entry.persistentModelID))
                }
        }
        // Hidden from the stack, not the editor, so it returns as soon as the editor starts closing.
        .toolbar(path.isEmpty ? .visible : .hidden, for: .tabBar)
        .sensoryFeedback(.impact(weight: .medium), trigger: newEntryCount)
        .alert("Location access is off", isPresented: $locationDenied) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("You can turn it on in Settings.")
        }
        .sheet(item: $listed) { listed in
            // Live, so an entry trashed or moved from the sheet's editor leaves the list.
            PlaceEntriesSheet(entries: entries.filter { listed.ids.contains($0.persistentModelID) })
        }
        .onChange(of: path) { _, path in
            if path.isEmpty {
                startedHere.removeAll()
                Entry.deleteBlankEntries(in: context, keeping: router.openEntries)
            }
        }
    }

    private var pins: [EntryPin] {
        entries.compactMap { entry in
            guard let latitude = entry.latitude, let longitude = entry.longitude else { return nil }
            return EntryPin(id: entry.persistentModelID, coordinate: CLLocationCoordinate2D(latitude: latitude, longitude: longitude))
        }
    }

    /// One entry opens; several are listed first.
    private func open(_ ids: [PersistentIdentifier]) {
        let chosen = entries.filter { ids.contains($0.persistentModelID) }
        if chosen.count == 1, let entry = chosen.first {
            path.append(entry)
        } else if !chosen.isEmpty {
            listed = ListedEntries(ids: Set(chosen.map(\.persistentModelID)))
        }
    }

    /// Asks for access the first time, and says so if it's refused rather than doing nothing.
    private func recenter() {
        Task {
            if await LocationService.shared.requestAuthorization() {
                recenterCount += 1
            } else {
                locationDenied = true
            }
        }
    }

    private func newEntry(at coordinate: CLLocationCoordinate2D) {
        newEntryCount += 1
        Task {
            let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
            let name = await LocationService.shared.placeName(for: location) ?? "Dropped Pin"
            let entry = Entry.create(in: context)
            entry.setPlace(name: name, coordinate: coordinate)
            startedHere.insert(entry.persistentModelID)
            path.append(entry)
        }
    }
}

private struct ListedEntries: Identifiable {
    let id = UUID()
    let ids: Set<PersistentIdentifier>
}

/// The entries in one of the map's groups, newest first, in a sheet that swipes down to close. An
/// entry opens inside the sheet, grown to full height, and going back returns to the list.
private struct PlaceEntriesSheet: View {
    let entries: [Entry]

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(AppRouter.self) private var router
    @State private var path: [Entry] = []
    @State private var detent: PresentationDetent = .medium
    /// The list's size when an entry opened, to go back to.
    @State private var listDetent: PresentationDetent = .medium

    /// Their place, or the most common one: a group can span several.
    private var title: String {
        let places = Dictionary(grouping: entries.compactMap(\.placeName)) { $0 }
        return places.max { ($0.value.count, $1.key) < ($1.value.count, $0.key) }?.key ?? "Entries"
    }

    /// Every entry was trashed or moved from the editor, which has closed.
    private var isEmptied: Bool { path.isEmpty && entries.isEmpty }

    var body: some View {
        NavigationStack(path: $path) {
            // Laid out like the day sheet: the place in the bar over an inset-grouped list.
            List {
                Section {
                    ForEach(entries) { entry in
                        SheetEntryRow(entry: entry, dateStyle: .dayAndMonth) { open(entry) }
                    }
                } header: {
                    MetaLabel("Entries", systemImage: "book")
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .sheetTitle(title, subtitle: entries.count == 1 ? "1 entry" : "\(entries.count) entries")
            .navigationDestination(for: Entry.self) { entry in
                EntryEditorView(entry: entry)
            }
        }
        .tint(Theme.primaryText)
        .presentationDetents(path.isEmpty ? [.medium, .large] : [.large], selection: $detent)
        // A pull at the top of the text shouldn't take the entry away.
        .interactiveDismissDisabled(!path.isEmpty)
        .sheetBackdrop(grabber: true)
        .onChange(of: path) { _, path in
            if path.isEmpty {
                Task { detent = listDetent } // On the next turn, for the same reason as in `open`.
                Entry.deleteBlankEntries(in: context, keeping: router.openEntries)
            }
        }
        .onChange(of: isEmptied) {
            if isEmptied { dismiss() }
        }
    }

    private func open(_ entry: Entry) {
        listDetent = detent
        detent = .large
        // On the next turn: changing the sheet's detents in the same update as the one selected
        // leaves it where it was.
        Task { path.append(entry) }
    }
}
