import Photos
import SwiftData
import SwiftUI

/// A day from the calendar, in a sheet that swipes down to close: the date in the bar with arrows to
/// the day before and after (or swipe sideways, page by page), then a list of that day's entries, the photos taken that day from the
/// photo library, the places the user spent time and the events in their calendar (those with nothing
/// to show moved to the end, `DayPage`). Also opened from an entry (the editor's View Day), which is then
/// left out of the list, and a place tapped becomes its place.
struct DaySheet: View {
    let entries: [Entry]
    /// The entry this was opened from, if any.
    let openedFrom: Entry?
    /// After a place is set on `openedFrom`.
    let onSetPlace: () -> Void

    /// The day the sheet opened on; pages are counted in days from it.
    private let firstDay: Date
    /// The page showing, in days from `firstDay`.
    @State private var page: Int? = 0
    /// The page the date and weekday show. Follows `page` with the arrows' animation, which a
    /// swipe (setting `page` through the scroll view, unanimated) wouldn't otherwise get.
    @State private var titlePage = 0
    /// The page the filled pages are centered on, moved to the page showing whenever scrolling stops.
    @State private var windowCenter = 0
    /// Pages built and on screen (or just beside it), by page.
    @State private var loadedPages: Set<Int> = []
    /// From an arrow or a swipe until the pages come to rest.
    @State private var isMoving = false
    @State private var openEntry: Entry?
    /// An entry started here from a place, whose place is provisional.
    @State private var startedEntry: PersistentIdentifier?
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    /// Where the weekday and the arrows (as the bar places them, level with the title) sit, so the
    /// arrows can be centered on the date and weekday together.
    @State private var weekdayMidY: CGFloat = 0
    /// Where the bar puts the arrows' slots (level with the title), by direction.
    @State private var arrowSlots: [Int: CGRect] = [:]
    private let calendar = Calendar.current

    init(day: Date, entries: [Entry], openedFrom: Entry? = nil, onSetPlace: @escaping () -> Void = {}) {
        firstDay = Calendar.current.startOfDay(for: day)
        self.entries = entries
        self.openedFrom = openedFrom
        self.onSetPlace = onSetPlace
    }

    var body: some View {
        NavigationStack {
            pagedDays
            .background(Theme.background)
            // Rows pass under the header with a clean edge, `Spacing.m` below the weekday.
            .hidesTopScrollEdgeEffect()
            // Under the bar rather than in it, so the title stays exactly where every popup's is.
            .safeAreaInset(edge: .top, spacing: 0) {
                MetaLabel(titleDay.formatted(.dateTime.weekday(.wide)))
                    .frame(maxWidth: .infinity)
                    .onGeometryChange(for: CGFloat.self) { $0.frame(in: .global).midY } action: { weekdayMidY = $0 }
                    // Right under the title, into the bar's own space below it, then clear of the list.
                    .padding(.top, -Spacing.m)
                    .padding(.bottom, Spacing.m)
                    // The bar and this line are one solid header: rows scroll under it.
                    .background(Theme.background.ignoresSafeArea(edges: .top))
                    .accessibilityHidden(true)
            }
            .sheetTitle(titleDay.formatted(.dateTime.month(.wide).day().year()))
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar {
                if #available(iOS 26.0, *) {
                    // The bar's own glass stays level with the title, so each arrow draws its own and
                    // moves down with it, centered on the date and weekday together.
                    // Only their places: the arrows themselves are drawn over the sheet (`dayArrows`).
                    ToolbarItem(placement: .topBarLeading) {
                        ArrowSlot { arrowSlots[-1] = $0 }
                    }
                    .sharedBackgroundVisibility(.hidden)
                    ToolbarItem(placement: .topBarTrailing) {
                        ArrowSlot { arrowSlots[1] = $0 }
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
        .overlay {
            if #available(iOS 26.0, *) { dayArrows }
        }
        .tint(Theme.primaryText)
        .presentationDetents([.medium, .large])
        // The list scrolls at half height too; the sheet grows only when dragged by its top.
        .presentationContentInteraction(.scrolls)
        .sheetBackdrop(grabber: true)
        .sensoryFeedback(.selection, trigger: day)
        .onChange(of: page) { _, page in
            withAnimation(.snappy) { titlePage = page ?? 0 }
        }
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

    /// The arrows, each where the bar puts its slot but moved halfway from the title down to the
    /// weekday, centered on both. Drawn over the sheet rather than in the bar: moved down in the bar,
    /// their lower half hung outside it and didn't take taps.
    @available(iOS 26.0, *)
    private var dayArrows: some View {
        GeometryReader { proxy in
            // Measured in the window, where the sheet's contents are scaled down while it's at half
            // height; placed in the overlay's own, unscaled points.
            let frame = proxy.frame(in: .global)
            let scale = frame.width > 0 ? proxy.size.width / frame.width : 1
            if let leading = arrowSlots[-1], let trailing = arrowSlots[1], leading.midY > 0 {
                let titleY = leading.midY
                let y = (weekdayMidY > titleY ? (titleY + weekdayMidY) / 2 : titleY) - frame.minY
                ForEach([-1, 1], id: \.self) { direction in
                    let slot = direction < 0 ? leading : trailing
                    DayArrow(
                        title: direction < 0 ? "Previous Day" : "Next Day",
                        systemImage: direction < 0 ? "chevron.left" : "chevron.right"
                    ) { shift(by: direction) }
                    .position(x: (slot.midX - frame.minX) * scale, y: y * scale)
                }
            }
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

    private var eventAction: DayEventsSection.Action {
        guard let entry = openedFrom else {
            return .newEntry { place, time in startEntry(at: time, place: place.map { ($0.name, $0.coordinate) }) }
        }
        return .setOnEntry { place, time in
            if let place { entry.setPlace(name: place.name, coordinate: place.coordinate) }
            if let time {
                entry.createdAt = time
                entry.clearWeather()
            }
            onSetPlace()
            dismiss()
        }
    }

    /// An entry at a place the user spent time, dated when they got there, opened over the sheet. Its
    /// place is provisional, so it's discarded if nothing else is added (`EntryEditorView`).
    private func startEntry(name: String, coordinate: CLLocationCoordinate2D, time: Date) {
        startEntry(at: time, place: (name, coordinate))
    }

    /// Also for an event, which may have no place.
    private func startEntry(at time: Date, place: (name: String, coordinate: CLLocationCoordinate2D)?) {
        let entry = Entry.create(in: context, at: time)
        if let place { entry.setPlace(name: place.name, coordinate: place.coordinate) }
        startedEntry = entry.persistentModelID
        show(entry)
    }

    /// With no animation of the cover's own: the slide is the push inside it.
    private func show(_ entry: Entry?) {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) { openEntry = entry }
    }

    /// The day showing.
    private var day: Date {
        date(atPage: page ?? 0)
    }

    private var titleDay: Date {
        date(atPage: titlePage)
    }

    private func date(atPage page: Int) -> Date {
        calendar.date(byAdding: .day, value: page, to: firstDay) ?? firstDay
    }

    /// How many days either side of the first one the sheet pages through.
    private static let pageRange = 3650
    /// How many days either side of `windowCenter` are filled in: room for a swipe or an arrow tap
    /// before the window catches up.
    private static let windowRadius = 2

    /// The days side by side, a page each, swiped between like any paged view in iOS: the day
    /// before or after follows the finger in and settles on a whole page (the arrows scroll there
    /// too). The pages never change, but only those near the one showing are filled in, the rest
    /// empty: thousands of full pages took seconds to open on a phone, and a window of pages that
    /// moved along (inserting days before the one showing) sometimes left the scroll a page off
    /// from the day it named.
    private var pagedDays: some View {
        ScrollView(.horizontal) {
            LazyHStack(spacing: 0) {
                ForEach(-Self.pageRange...Self.pageRange, id: \.self) { page in
                    Group {
                        if abs(page - windowCenter) <= Self.windowRadius {
                            dayPage(for: date(atPage: page))
                                .onAppear { loadedPages.insert(page) }
                                .onDisappear { loadedPages.remove(page) }
                        } else {
                            Color.clear
                        }
                    }
                    .containerRelativeFrame(.horizontal)
                }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.paging)
        .scrollPosition(id: $page)
        .scrollIndicators(.hidden)
        .onScrollPhaseChange { _, phase in
            isMoving = phase != .idle
            if phase == .idle, let page, page != windowCenter { windowCenter = page }
        }
    }

    /// A day's page, rebuilt only when what it shows changes (`DayPage`): every change to the sheet
    /// (the page, the title, the arrows' places, the calendar behind redrawing) rebuilt every page's
    /// list, which froze the sheet for hundreds of milliseconds on a phone.
    private func dayPage(for day: Date) -> some View {
        DayPage(
            day: day,
            entries: entries.filter { calendar.isDate($0.createdAt, inSameDayAs: day) && $0 != openedFrom },
            isOpenedFromDay: openedFrom.map { calendar.isDate($0.createdAt, inSameDayAs: day) } ?? false,
            current: openedFrom.flatMap { entry in entry.location.map { ($0, entry.createdAt) } },
            placeAction: placeAction,
            eventAction: eventAction,
            open: { show($0) }
        )
        .equatable()
    }

    /// Only once the day showing has loaded and the pages are at rest: taps while a day was still
    /// coming in queued up moves on top of it.
    private func shift(by days: Int) {
        let current = page ?? 0
        guard !isMoving, loadedPages.contains(current) else { return }
        isMoving = true
        withAnimation(.snappy) { page = current + days }
    }
}

/// One day's list: Entries, Photos, Places, Events — but those with nothing to show (none that day,
/// or no access yet) go to the end, still in that order among themselves. Compared by what it shows,
/// not its actions, which only reach state that outlives a copy of the sheet.
private struct DayPage: View, Equatable {
    let day: Date
    /// The day's entries, but the one the sheet was opened from.
    let entries: [Entry]
    let isOpenedFromDay: Bool
    /// The place and time of the entry the sheet was opened from.
    let current: (CLLocation, Date)?
    let placeAction: DayPlacesSection.Action
    let eventAction: DayEventsSection.Action
    let open: (Entry) -> Void

    static func == (lhs: DayPage, rhs: DayPage) -> Bool {
        lhs.day == rhs.day
            && lhs.entries.map(\.persistentModelID) == rhs.entries.map(\.persistentModelID)
            && lhs.isOpenedFromDay == rhs.isOpenedFromDay
            && lhs.current?.0.coordinate.latitude == rhs.current?.0.coordinate.latitude
            && lhs.current?.0.coordinate.longitude == rhs.current?.0.coordinate.longitude
            && lhs.current?.1 == rhs.current?.1
    }

    private enum Section: CaseIterable {
        case entries, photos, places, events
    }

    private var sectionOrder: [Section] {
        let empty: Set<Section> = Set(Section.allCases.filter { section in
            switch section {
            case .entries: entries.isEmpty
            case .photos: PhotoLibrary.photos(on: day).isEmpty
            case .places: DayPlaces.places(on: day).isEmpty
            case .events: CalendarEvents.events(on: day).isEmpty
            }
        })
        return Section.allCases.filter { !empty.contains($0) } + Section.allCases.filter { empty.contains($0) }
    }

    var body: some View {
        List {
            ForEach(sectionOrder, id: \.self) { section in
                switch section {
                case .entries:
                    entriesSection
                case .photos:
                    SwiftUI.Section {
                        DayPhotos(day: day)
                    } header: {
                        MetaLabel("Photos", systemImage: "photo.on.rectangle")
                    }
                case .places:
                    DayPlacesSection(day: day, current: current, action: placeAction)
                case .events:
                    DayEventsSection(day: day, action: eventAction)
                }
            }
            // White at every height: left to the system, rows went grey while the sheet was at
            // half height (its glass) and white only at full.
            .listRowBackground(Theme.card)
        }
        .scrollContentBackground(.hidden)
        .listSectionSpacing(Spacing.m)
        // Everything in it dims while touched, like the app's other buttons.
        .buttonStyle(.borderless)
    }

    private var entriesSection: some View {
        SwiftUI.Section {
            if entries.isEmpty {
                Text(isOpenedFromDay ? "Nothing else written on this day." : "Nothing written on this day.")
                    .font(Typography.note)
                    .foregroundStyle(Theme.secondaryText)
            } else {
                ForEach(entries) { entry in
                    SheetEntryRow(entry: entry) { open(entry) }
                }
            }
        } header: {
            MetaLabel("Entries", systemImage: "book")
        }
    }
}

/// Holds an arrow's place in the bar and reports where that is, in global coordinates.
@available(iOS 26.0, *)
private struct ArrowSlot: View {
    let onChange: (CGRect) -> Void

    var body: some View {
        Color.clear
            .frame(width: 44, height: 44)
            .accessibilityHidden(true)
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { onChange($0) }
    }
}

/// One of the day sheet's arrows: a glass circle like the bar's own.
@available(iOS 26.0, *)
private struct DayArrow: View {
    let title: String
    let systemImage: String
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
                AccessOffNote("Photo gallery access", canAsk: true) {
                    Task {
                        status = await PhotoLibrary.requestAccess()
                        assets = PhotoLibrary.photos(on: day)
                    }
                }
            case .denied, .restricted:
                // Refused before: iOS won't ask again, so its Settings it is.
                AccessOffNote("Photo gallery access", canAsk: false) { openURL(.appSettings) }
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
