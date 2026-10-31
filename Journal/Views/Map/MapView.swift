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

    var body: some View {
        NavigationStack(path: $path) {
            EntryMap(pins: pins, onOpen: open(_:), onLongPress: newEntry(at:))
                .pageTitle()
                .toolbar {
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
        .sheet(item: $listed) { listed in
            PlaceEntriesSheet(entries: listed.entries) { entry in
                self.listed = nil
                Task {
                    try? await Task.sleep(for: .milliseconds(350))
                    path.append(entry)
                }
            }
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
            listed = ListedEntries(entries: chosen)
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
    let entries: [Entry]
}

/// The entries in one of the map's groups, newest first, in a sheet that swipes down to close.
private struct PlaceEntriesSheet: View {
    let entries: [Entry]
    let onOpen: (Entry) -> Void

    /// Their place, or the most common one: a group can span several.
    private var title: String {
        let places = Dictionary(grouping: entries.compactMap(\.placeName)) { $0 }
        return places.max { ($0.value.count, $1.key) < ($1.value.count, $0.key) }?.key ?? "Entries"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.s) {
                VStack(spacing: Spacing.s) {
                    Text(title)
                        .font(Typography.title)
                        .foregroundStyle(Theme.primaryText)
                        .multilineTextAlignment(.center)
                    MetaLabel(entries.count == 1 ? "1 entry" : "\(entries.count) entries")
                }
                .frame(maxWidth: .infinity)
                .padding(.bottom, Spacing.s)
                ForEach(entries) { entry in
                    Button {
                        onOpen(entry)
                    } label: {
                        EntryRow(entry: entry, dateStyle: .dayAndMonth)
                            .padding(.vertical, 6)
                    }
                    .buttonStyle(.plain)
                    Rectangle().fill(Theme.hairline).frame(height: 1)
                }
            }
            .padding(.horizontal, Spacing.m + 4)
            .padding(.vertical, Spacing.l)
        }
        .scrollIndicators(.hidden)
        .background(Theme.background)
        .presentationDetents([.medium, .large])
        .sheetGrabber()
    }
}
