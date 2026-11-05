import Photos
import SwiftData
import SwiftUI

/// A day from the calendar, in a sheet that swipes down to close: the date in the bar with arrows to
/// the day before and after, then a list of that day's entries, the places the user spent time, the
/// events in their calendar, and the photos taken that day from the photo library. Also opened from an entry (the editor's View Day), which is then
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
    /// Where the weekday and the arrows (as the bar places them, level with the title) sit, so the
    /// arrows can be centered on the date and weekday together.
    @State private var weekdayMidY: CGFloat = 0
    @State private var arrowMidY: CGFloat = 0
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
                    DayEventsSection(day: day)
                    Section {
                        DayPhotos(day: day)
                    } header: {
                        MetaLabel("Photos", systemImage: "photo.on.rectangle")
                    }
                }
                .scrollContentBackground(.hidden)
                .listSectionSpacing(Spacing.m)
                // Everything in it dims while touched, like the app's other buttons.
                .buttonStyle(.borderless)
            }
            .background(Theme.background)
            // Rows pass under the header with a clean edge, `Spacing.m` below the weekday.
            .hidesTopScrollEdgeEffect()
            // Under the bar rather than in it, so the title stays exactly where every popup's is.
            .safeAreaInset(edge: .top, spacing: 0) {
                MetaLabel(day.formatted(.dateTime.weekday(.wide)))
                    .frame(maxWidth: .infinity)
                    .onGeometryChange(for: CGFloat.self) { $0.frame(in: .global).midY } action: { weekdayMidY = $0 }
                    // Right under the title, into the bar's own space below it, then clear of the list.
                    .padding(.top, -Spacing.m)
                    .padding(.bottom, Spacing.m)
                    // The bar and this line are one solid header: rows scroll under it.
                    .background(Theme.background.ignoresSafeArea(edges: .top))
                    .accessibilityHidden(true)
            }
            .sheetTitle(day.formatted(.dateTime.month(.wide).day().year()))
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar {
                if #available(iOS 26.0, *) {
                    // The bar's own glass stays level with the title, so each arrow draws its own and
                    // moves down with it, centered on the date and weekday together.
                    ToolbarItem(placement: .topBarLeading) {
                        DayArrow(title: "Previous Day", systemImage: "chevron.left", shift: arrowShift, midY: $arrowMidY) { shift(by: -1) }
                    }
                    .sharedBackgroundVisibility(.hidden)
                    ToolbarItem(placement: .topBarTrailing) {
                        DayArrow(title: "Next Day", systemImage: "chevron.right", shift: arrowShift, midY: $arrowMidY) { shift(by: 1) }
                    }
                    .sharedBackgroundVisibility(.hidden)
                } else {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Previous Day", systemImage: "chevron.left") { shift(by: -1) }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Next Day", systemImage: "chevron.right") { shift(by: 1) }
                    }
                }
            }
        }
        .tint(Theme.primaryText)
        .presentationDetents([.medium, .large])
        .sheetBackdrop(grabber: true)
        .sensoryFeedback(.selection, trigger: day)
        // The days either side, so their photos and places are already there as they slide in.
        .task(id: day) {
            for offset in [1, -1] {
                guard let neighbor = calendar.date(byAdding: .day, value: offset, to: day) else { continue }
                await PhotoLibrary.preloadThumbnails(on: neighbor, side: AssetThumbnail.side, limit: DayPhotos.shown)
                await DayMapSnapshots.preload(on: neighbor)
                await PlaceNames.preload(on: neighbor)
            }
        }
        .fullScreenCover(item: $openEntry) { entry in
            EntryCover(entry: entry, placeIsProvisional: entry.persistentModelID == startedEntry) { show(nil) }
        }
    }

    /// Halfway from the title down to the weekday.
    private var arrowShift: CGFloat {
        guard arrowMidY > 0, weekdayMidY > arrowMidY else { return 0 }
        return (weekdayMidY - arrowMidY) / 2
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

/// One of the day sheet's arrows: a glass circle like the bar's own, moved down by `shift`.
@available(iOS 26.0, *)
private struct DayArrow: View {
    let title: String
    let systemImage: String
    let shift: CGFloat
    /// Where the bar puts it (level with the title), before the shift.
    @Binding var midY: CGFloat
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(Typography.action)
                .frame(width: 44, height: 44)
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .circle)
        .accessibilityLabel(title)
        .offset(y: shift)
        .onGeometryChange(for: CGFloat.self) { $0.frame(in: .global).midY } action: { midY = $0 }
    }
}

/// An entry opened from a sheet (the day sheet, a map group's): the full editor, pushed onto an empty stack in a clear cover,
/// so it slides in from the right over the sheet, which stays where it is.
struct EntryCover: View {
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

/// The photos the user took on a day, from their library (asks for access the first time): edge to
/// edge across the section, one alone; two side by side; three or more as one on the left and two
/// stacked on the right, the last with "+N" for those not shown.
private struct DayPhotos: View {
    let day: Date

    /// The most shown at once.
    static let shown = 3
    private static let height: CGFloat = 220
    private static let gap: CGFloat = 2

    @Environment(\.openURL) private var openURL
    @State private var status = PhotoLibrary.status
    @State private var assets: [PHAsset]
    @State private var viewing: ViewedPhoto?

    init(day: Date) {
        self.day = day
        // Here, not on appear: a day's card slides in whole, and anything added to it once it's moving
        // takes a path of its own.
        _assets = State(initialValue: PhotoLibrary.photos(on: day))
    }

    private var showsGrid: Bool { PhotoLibrary.canRead && !assets.isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            switch status {
            case .notDetermined:
                AccessOffNote("Photo access") {
                    Task {
                        status = await PhotoLibrary.requestAccess()
                        assets = PhotoLibrary.photos(on: day)
                    }
                }
            case .denied, .restricted:
                // Refused before: iOS won't ask again, so its Settings it is.
                AccessOffNote("Photo access") { openURL(.appSettings) }
            default:
                if assets.isEmpty {
                    Text("No photos from this day.")
                        .font(Typography.note)
                        .foregroundStyle(Theme.secondaryText)
                } else {
                    grid
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        // The grid runs edge to edge, like the Places map.
        .listRowInsets(showsGrid ? EdgeInsets() : nil)
        // Like an entry's photos, swiping between the day's.
        .fullScreenCover(item: $viewing) { photo in
            PhotoViewer(photos: assets.map(ViewerPhoto.init), initialID: photo.id)
        }
    }

    @ViewBuilder
    private var grid: some View {
        let gap = Self.gap
        Group {
            switch assets.count {
            case 1:
                tile(0)
            case 2:
                HStack(spacing: gap) {
                    tile(0)
                    tile(1)
                }
            default:
                HStack(spacing: gap) {
                    tile(0)
                    VStack(spacing: gap) {
                        tile(1)
                        tile(2, more: assets.count - Self.shown)
                    }
                }
            }
        }
        .frame(height: Self.height)
    }

    /// The photo at `index`, filling its space; `more` photos not shown are counted in its corner.
    private func tile(_ index: Int, more: Int = 0) -> some View {
        let asset = assets[index]
        return Button {
            viewing = ViewedPhoto(id: asset.localIdentifier)
        } label: {
            AssetThumbnail(asset: asset)
                .overlay(alignment: .bottomTrailing) {
                    if more > 0 {
                        Text("+\(more)")
                            .font(Typography.caption.weight(.semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, Spacing.s)
                            .padding(.vertical, Spacing.xs)
                            .background(.black.opacity(0.55), in: .capsule)
                            // Clear of the section's rounded corner.
                            .padding(Spacing.m)
                            .accessibilityLabel("\(more) more")
                    }
                }
        }
        .buttonStyle(.borderless)
    }
}

private struct ViewedPhoto: Identifiable {
    let id: String
}

private struct AssetThumbnail: View {
    /// Large enough for the grid's widest tile, a lone photo across the section.
    static let side: CGFloat = 400

    let asset: PHAsset
    @State private var image: UIImage?

    init(asset: PHAsset) {
        self.asset = asset
        // From the cache when it's there, so a day's card slides in with its photos.
        _image = State(initialValue: PhotoLibrary.cachedThumbnail(for: asset, side: Self.side))
    }

    var body: some View {
        Color.primary.opacity(0.06)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .transition(.opacity)
                }
            }
            .clipped()
            .contentShape(.rect)
            .task(id: asset.localIdentifier) {
                guard image == nil else { return }
                let thumbnail = await PhotoLibrary.thumbnail(for: asset, side: Self.side)
                withAnimation(.easeOut(duration: 0.2)) { image = thumbnail }
            }
            .accessibilityLabel(asset.creationDate?.formatted(date: .omitted, time: .shortened) ?? "Photo")
    }
}
