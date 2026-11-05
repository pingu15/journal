import MapKit
import SwiftUI

/// The day sheet's Places section: where the user spent time that day (`DayPlaces`), on a map and
/// then each stay in turn with how long it lasted. Opened from an entry, tapping a stay offers its
/// place, or its place and the time the user got there, for the entry, and the place chosen gets the
/// halo on the map; from the calendar, it starts an entry there. Tracking is off until it's turned on,
/// here or in Settings.
struct DayPlacesSection: View {
    let day: Date
    let action: Action

    enum Action {
        /// From an entry: its place, and the time too when one's given.
        case setPlace((_ name: String, _ coordinate: CLLocationCoordinate2D, _ time: Date?) -> Void)
        /// From the calendar: a new entry, at the stay's place and the time it began.
        case newEntry((_ name: String, _ coordinate: CLLocationCoordinate2D, _ time: Date) -> Void)
    }

    @Environment(\.openURL) private var openURL
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage(PlaceTracker.enabledKey) private var tracking = false
    @State private var authorized = PlaceTracker.shared.isAuthorized
    @State private var places: [VisitedPlace]
    @State private var stays: [Stay]
    @State private var selected: Stay.ID?
    /// A stay tapped from an entry, while it's asked whether to take its time too.
    @State private var choosing: Stay.ID?
    @State private var names: [Int: String] = [:]
    /// A picture of the map rather than a map: a live one per day was most of the work of sliding to
    /// another day, and this one is never touched.
    @State private var snapshot: MKMapSnapshotter.Snapshot?
    @State private var mapWidth = DayMapSnapshots.width

    /// One time at a place: a place visited twice is two stays, with one pin.
    struct Stay: Identifiable {
        let id: Int
        let place: VisitedPlace
        let interval: DateInterval
    }

    /// `current`: the entry's place and time, which picks the stay chosen to begin with — the
    /// one at that place closest to the entry's time.
    init(day: Date, current: (CLLocation, Date)? = nil, action: Action) {
        self.day = day
        self.action = action
        // Here, not on appear, like the photos: the day slides in whole, its map too when the day was
        // drawn ahead.
        let places = DayPlaces.places(on: day)
        let stays = places
            .flatMap { place in place.visits.map { (place, $0) } }
            .sorted { $0.1.start < $1.1.start }
            .enumerated()
            .map { Stay(id: $0, place: $1.0, interval: $1.1) }
        _places = State(initialValue: places)
        _stays = State(initialValue: stays)
        if let (location, time) = current {
            let distance = { (stay: Stay) -> TimeInterval in
                stay.interval.contains(time) ? 0 : min(
                    abs(stay.interval.start.timeIntervalSince(time)), abs(stay.interval.end.timeIntervalSince(time))
                )
            }
            let initial = stays
                .filter { $0.place.location.distance(from: location) <= DayPlaces.radius }
                .min { distance($0) < distance($1) }
            _selected = State(initialValue: initial?.id)
        }
        _names = State(initialValue: Dictionary(uniqueKeysWithValues: places.compactMap { place in
            PlaceNames.cachedName(for: place.coordinate).map { (place.id, $0) }
        }))
        _snapshot = State(initialValue: DayMapSnapshots.cached(of: places))
    }

    private var selectedPlace: VisitedPlace.ID? {
        stays.first { $0.id == selected }?.place.id
    }

    var body: some View {
        Section {
            if !places.isEmpty {
                map
                ForEach(stays) { stay in
                    row(stay)
                }
            } else if !tracking || !authorized {
                // Turns tracking on (as Settings' switch does), asking for location if it hasn't yet;
                // refused before, only iOS's Settings can allow it.
                let canAsk = LocationService.shared.canAsk || authorized
                AccessOffNote(tracking ? "Location access" : "Place tracking", canAsk: canAsk) {
                    if canAsk {
                        Task { authorized = await PlaceTracker.shared.enable() }
                    } else {
                        openURL(.appSettings)
                    }
                }
            } else {
                Text("No places from this day.")
                    .font(Typography.note)
                    .foregroundStyle(Theme.secondaryText)
            }
        } header: {
            MetaLabel("Places", systemImage: "mappin.and.ellipse")
        }
    }

    /// The section's first row, edge to edge.
    private var map: some View {
        Theme.hairline
            .opacity(snapshot == nil ? 0.5 : 0)
            .frame(height: DayMapSnapshots.height)
            .frame(maxWidth: .infinity)
            .overlay {
                if let snapshot {
                    Image(uiImage: snapshot.image)
                        .resizable()
                        .overlay {
                            // The chosen place last, so it's drawn over the others.
                            ForEach(places.sorted { $0.id != selectedPlace && $1.id == selectedPlace }) { place in
                                MapPin(showsHalo: place.id == selectedPlace)
                                    .position(snapshot.point(for: place.coordinate))
                            }
                            .animation(.easeOut(duration: 0.25), value: selectedPlace)
                        }
                        .transition(.opacity)
                }
            }
            .onGeometryChange(for: CGFloat.self, of: \.size.width) { width in
                DayMapSnapshots.width = width
                mapWidth = width
            }
            .task(id: [mapWidth, colorScheme == .dark ? 1 : 0]) {
                DayMapSnapshots.style = colorScheme == .dark ? .dark : .light
                guard let drawn = await DayMapSnapshots.snapshot(of: places) else { return }
                if snapshot?.image !== drawn.image {
                    withAnimation(.easeOut(duration: 0.2)) { snapshot = drawn }
                }
            }
            .task(id: day) {
                for place in places where names[place.id] == nil {
                    let name = await PlaceNames.name(for: place.coordinate)
                    withAnimation(.easeOut(duration: 0.2)) { names[place.id] = name }
                }
            }
            .listRowInsets(EdgeInsets())
            .accessibilityHidden(true)
    }

    private var isNewEntry: Bool {
        if case .newEntry = action { true } else { false }
    }

    private func tap(_ stay: Stay) {
        switch action {
        case .setPlace:
            choosing = stay.id
        case .newEntry(let start):
            Task { start(await PlaceNames.name(for: stay.place.coordinate), stay.place.coordinate, stay.interval.start) }
        }
    }

    private func setPlace(of stay: Stay, withTime: Bool) {
        guard case .setPlace(let set) = action else { return }
        selected = stay.id
        Task {
            set(await PlaceNames.name(for: stay.place.coordinate), stay.place.coordinate, withTime ? stay.interval.start : nil)
        }
    }

    private func row(_ stay: Stay) -> some View {
        let name = names[stay.place.id]
        return Button {
            tap(stay)
        } label: {
            HStack(spacing: Spacing.s) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(name ?? "Somewhere nearby")
                        .font(Typography.body)
                        .foregroundStyle(Theme.primaryText)
                        .lineLimit(1)
                        .redacted(reason: name == nil ? .placeholder : [])
                    // A row's second line, as in Set Location; the duration beside it matches.
                    Text((stay.interval.start..<stay.interval.end).formatted(.interval.hour().minute()))
                        .font(Typography.detail)
                        .foregroundStyle(Theme.secondaryText)
                }
                Spacer(minLength: Spacing.s)
                Text(Duration.seconds(stay.interval.duration).formatted(.units(allowed: [.hours, .minutes], width: .abbreviated)))
                    .font(Typography.detail)
                    .foregroundStyle(Theme.secondaryText)
            }
            .contentShape(.rect)
            .accessibilityElement(children: .combine)
        }
        // Pressed like the entries above it.
        .buttonStyle(TapPressStyle(scale: TapPressStyle.rowScale))
        .accessibilityAddTraits(stay.id == selected ? .isSelected : [])
        .accessibilityHint(isNewEntry ? "Starts an entry here, at the time you got there" : "Sets this as the entry's place")
        // On each row, so it comes from the row tapped.
        .confirmationDialog(
            "Add to Entry",
            isPresented: Binding(get: { choosing == stay.id }, set: { if !$0 { choosing = nil } }),
            titleVisibility: .hidden
        ) {
            Button("Location Only") { setPlace(of: stay, withTime: false) }
            Button("Location and Time") { setPlace(of: stay, withTime: true) }
            Button("Cancel", role: .cancel) {}
        }
    }
}

/// Pictures of the day sheet's maps, drawn off the main thread at the section's width and in the current
/// appearance, kept per set of places so a day drawn ahead (the sheet's neighbours) slides in whole.
enum DayMapSnapshots {
    static let height: CGFloat = 170
    /// The section's, as last laid out: what a day is drawn ahead at.
    static var width: CGFloat = 0
    static var style: UIUserInterfaceStyle = .unspecified

    private static let drawn = NSCache<NSString, MKMapSnapshotter.Snapshot>()

    private static func key(_ places: [VisitedPlace]) -> NSString {
        let spots = places.map { String(format: "%.5f,%.5f", $0.coordinate.latitude, $0.coordinate.longitude) }
        return "\(spots.joined(separator: ";"))@\(Int(width))-\(style.rawValue)" as NSString
    }

    static func cached(of places: [VisitedPlace]) -> MKMapSnapshotter.Snapshot? {
        drawn.object(forKey: key(places))
    }

    static func snapshot(of places: [VisitedPlace]) async -> MKMapSnapshotter.Snapshot? {
        guard !places.isEmpty, width > 0 else { return nil }
        let key = key(places)
        if let snapshot = drawn.object(forKey: key) { return snapshot }
        let options = MKMapSnapshotter.Options()
        options.region = region(fitting: places.map(\.coordinate))
        options.size = CGSize(width: width, height: height)
        // The smallest labels: at the usual size a snapshot names the whole city in big type across
        // the places.
        options.traitCollection = UITraitCollection(traitsFrom: [
            UITraitCollection(userInterfaceStyle: style),
            UITraitCollection(preferredContentSizeCategory: .extraSmall),
        ])
        let configuration = MKStandardMapConfiguration()
        configuration.pointOfInterestFilter = .excludingAll
        options.preferredConfiguration = configuration
        guard let snapshot = try? await MKMapSnapshotter(options: options).start() else { return nil }
        drawn.setObject(snapshot, forKey: key)
        return snapshot
    }

    /// Draws `day`'s map ahead, once the section has been laid out.
    static func preload(on day: Date) async {
        _ = await snapshot(of: DayPlaces.places(on: day))
    }

    /// Every place in view, with a little room around them; a neighbourhood for a single one.
    private static func region(fitting coordinates: [CLLocationCoordinate2D]) -> MKCoordinateRegion {
        guard let first = coordinates.first else {
            return MKCoordinateRegion(.world)
        }
        let latitudes = coordinates.map(\.latitude), longitudes = coordinates.map(\.longitude)
        let minimum = MKCoordinateRegion(center: first, latitudinalMeters: 1500, longitudinalMeters: 1500).span
        let center = CLLocationCoordinate2D(
            latitude: (latitudes.min()! + latitudes.max()!) / 2,
            longitude: (longitudes.min()! + longitudes.max()!) / 2
        )
        let span = MKCoordinateSpan(
            latitudeDelta: max((latitudes.max()! - latitudes.min()!) * 1.6, minimum.latitudeDelta),
            longitudeDelta: max((longitudes.max()! - longitudes.min()!) * 1.6, minimum.longitudeDelta)
        )
        return MKCoordinateRegion(center: center, span: span)
    }
}
