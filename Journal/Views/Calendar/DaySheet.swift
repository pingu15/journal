import Photos
import SwiftData
import SwiftUI

/// A day from the calendar, in a sheet that swipes down to close: the date in the bar with arrows to
/// the day before and after, then a list of that day's entries, the places the user spent time, and
/// the photos taken that day from the photo library. Also opened from an entry (the editor's View Day), which is then
/// left out of the list, and a place tapped becomes its place.
struct DaySheet: View {
    let entries: [Entry]
    /// The entry this was opened from, if any.
    let openedFrom: Entry?
    /// After a place is set on `openedFrom`.
    let onSetPlace: () -> Void

    @State private var day: Date
    @State private var openEntry: Entry?
    /// An entry started here from a place, whose place is provisional.
    @State private var startedEntry: PersistentIdentifier?
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    /// Which way the last arrow went, so the day slides out that way.
    @State private var movingForward = true
    private let calendar = Calendar.current

    init(day: Date, entries: [Entry], openedFrom: Entry? = nil, onSetPlace: @escaping () -> Void = {}) {
        _day = State(initialValue: Calendar.current.startOfDay(for: day))
        self.entries = entries
        self.openedFrom = openedFrom
        self.onSetPlace = onSetPlace
    }

    var body: some View {
        NavigationStack {
            slidingDay {
                List {
                    entriesSection
                    DayPlacesSection(day: day, current: openedFrom.flatMap { entry in
                        entry.location.map { ($0, entry.createdAt) }
                    }, action: placeAction)
                    Section {
                        DayPhotos(day: day)
                    } header: {
                        MetaLabel("Photos", systemImage: "photo.on.rectangle")
                    }
                }
                .scrollContentBackground(.hidden)
                .listSectionSpacing(Spacing.m)
            }
            .background(Theme.background)
            .sheetTitle(
                day.formatted(.dateTime.month(.wide).day().year()),
                subtitle: day.formatted(.dateTime.weekday(.wide))
            )
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Previous Day", systemImage: "chevron.left") { shift(by: -1) }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Next Day", systemImage: "chevron.right") { shift(by: 1) }
                }
            }
        }
        .tint(Theme.primaryText)
        .presentationDetents([.medium, .large])
        .sheetBackdrop(dragIndicator: .visible)
        .sensoryFeedback(.selection, trigger: day)
        // The days either side, so their photos and places are already there as they slide in.
        .task(id: day) {
            for offset in [1, -1] {
                guard let neighbor = calendar.date(byAdding: .day, value: offset, to: day) else { continue }
                await PhotoLibrary.preloadThumbnails(on: neighbor, side: AssetThumbnail.side)
                await DayMapSnapshots.preload(on: neighbor)
                await PlaceNames.preload(on: neighbor)
            }
        }
        .fullScreenCover(item: $openEntry) { entry in
            EntryCover(entry: entry, placeIsProvisional: entry.persistentModelID == startedEntry) { show(nil) }
        }
    }

    private var placeAction: DayPlacesSection.Action {
        guard let entry = openedFrom else { return .newEntry(startEntry) }
        return .setPlace { name, coordinate, time in
            entry.setPlace(name: name, coordinate: coordinate)
            if let time { entry.createdAt = time }
            onSetPlace()
            dismiss()
        }
    }

    /// An entry at a place the user spent time, dated when they got there, opened over the sheet. Its
    /// place is provisional, so it's discarded if nothing else is added (`EntryEditorView`).
    private func startEntry(name: String, coordinate: CLLocationCoordinate2D, time: Date) {
        let entry = Entry.create(in: context, at: time)
        entry.setPlace(name: name, coordinate: coordinate)
        startedEntry = entry.persistentModelID
        show(entry)
    }

    /// With no animation of the cover's own: the slide is the push inside it.
    private func show(_ entry: Entry?) {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) { openEntry = entry }
    }

    /// The day's list, sliding across the sheet when the day changes (the sheet's edges clip it).
    private func slidingDay<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        ZStack(alignment: .top) {
            content()
                .id(day)
                .transition(.asymmetric(
                    insertion: .move(edge: movingForward ? .trailing : .leading),
                    removal: .move(edge: movingForward ? .leading : .trailing)
                ))
        }
    }

    @ViewBuilder
    private var entriesSection: some View {
        let dayEntries = entries.filter { calendar.isDate($0.createdAt, inSameDayAs: day) && $0 != openedFrom }
        let isOpenedFromDay = openedFrom.map { calendar.isDate($0.createdAt, inSameDayAs: day) } ?? false

        Section {
            if dayEntries.isEmpty {
                Text(isOpenedFromDay ? "Nothing else written on this day." : "Nothing written on this day.")
                    .font(Typography.note)
                    .foregroundStyle(Theme.secondaryText)
            } else {
                ForEach(dayEntries) { entry in
                    SheetEntryRow(entry: entry) { show(entry) }
                }
            }
        } header: {
            MetaLabel("Entries", systemImage: "book")
        }
    }

    private func shift(by days: Int) {
        guard let next = calendar.date(byAdding: .day, value: days, to: day) else { return }
        movingForward = days > 0
        // On the next turn: the outgoing day takes its transition from the last update, so the
        // direction has to be in place before the day changes.
        DispatchQueue.main.async {
            withAnimation(.snappy) { day = next }
        }
    }
}

/// An entry opened from the day sheet: the full editor, pushed onto an empty stack in a clear cover,
/// so it slides in from the right over the sheet, which stays where it is.
private struct EntryCover: View {
    let entry: Entry
    var placeIsProvisional = false
    let onClose: () -> Void

    @Environment(\.modelContext) private var context
    @Environment(AppRouter.self) private var router
    @State private var path: [Entry] = []

    var body: some View {
        NavigationStack(path: $path) {
            Color.clear
                .toolbar(.hidden, for: .navigationBar)
                .containerBackground(.clear, for: .navigation)
                .navigationDestination(for: Entry.self) { entry in
                    EntryEditorView(entry: entry, placeIsProvisional: placeIsProvisional)
                        // Not on the path emptying, which is as the slide back starts.
                        .onDisappear {
                            guard path.isEmpty else { return }
                            Entry.deleteBlankEntries(in: context, keeping: router.openEntries)
                            onClose()
                        }
                }
        }
        .presentationBackground(.clear)
        .onAppear {
            // On the next turn, to animate.
            Task { path = [entry] }
        }
    }
}

/// The photos the user took on a day, from their library (asks for access the first time).
private struct DayPhotos: View {
    let day: Date

    @Environment(\.openURL) private var openURL
    @State private var status = PhotoLibrary.status
    @State private var assets: [PHAsset]
    @State private var viewing: ViewedPhoto?

    private let columns = [GridItem(.adaptive(minimum: 96), spacing: 4)]

    init(day: Date) {
        self.day = day
        // Here, not on appear: a day's card slides in whole, and anything added to it once it's moving
        // takes a path of its own.
        _assets = State(initialValue: PhotoLibrary.photos(on: day))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            switch status {
            case .notDetermined:
                Button {
                    Task {
                        status = await PhotoLibrary.requestAccess()
                        assets = PhotoLibrary.photos(on: day)
                    }
                } label: {
                    Label("Show Photos From Your Library", systemImage: "photo.on.rectangle")
                }
            case .denied, .restricted:
                Button {
                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                } label: {
                    Text("Photo access is off for Journal. ") + Text("Open Settings").underline()
                }
                .font(Typography.note)
                .foregroundStyle(Theme.secondaryText)
                .multilineTextAlignment(.leading)
            default:
                if assets.isEmpty {
                    Text("No photos from this day.")
                        .font(Typography.note)
                        .foregroundStyle(Theme.secondaryText)
                } else {
                    LazyVGrid(columns: columns, spacing: 4) {
                        ForEach(assets, id: \.localIdentifier) { asset in
                            Button {
                                viewing = ViewedPhoto(id: asset.localIdentifier)
                            } label: {
                                AssetThumbnail(asset: asset)
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        // Like an entry's photos, swiping between the day's.
        .fullScreenCover(item: $viewing) { photo in
            PhotoViewer(photos: assets.map(ViewerPhoto.init), initialID: photo.id)
        }
    }
}

private struct ViewedPhoto: Identifiable {
    let id: String
}

private struct AssetThumbnail: View {
    static let side: CGFloat = 120

    let asset: PHAsset
    @State private var image: UIImage?

    init(asset: PHAsset) {
        self.asset = asset
        // From the cache when it's there, so a day's card slides in with its photos.
        _image = State(initialValue: PhotoLibrary.cachedThumbnail(for: asset, side: Self.side))
    }

    var body: some View {
        Color.primary.opacity(0.06)
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .transition(.opacity)
                }
            }
            .clipShape(.rect(cornerRadius: 6, style: .continuous))
            .task(id: asset.localIdentifier) {
                guard image == nil else { return }
                let thumbnail = await PhotoLibrary.thumbnail(for: asset, side: Self.side)
                withAnimation(.easeOut(duration: 0.2)) { image = thumbnail }
            }
            .accessibilityLabel(asset.creationDate?.formatted(date: .omitted, time: .shortened) ?? "Photo")
    }
}
