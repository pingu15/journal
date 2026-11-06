import MapKit
import SwiftData
import SwiftUI

/// Set, change or clear an entry's place. With nothing typed: a small map of the entry's place (or
/// where you are, before one is set) with its name attached below, Current Location / Remove, and
/// places nearby. While searching, those give way to the journal's own places that match, then
/// suggestions from Maps.
struct LocationPicker: View {
    @Bindable var entry: Entry
    let onChange: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Query(filter: #Predicate<Entry> { $0.deletedAt == nil && $0.placeName != nil }, sort: \Entry.createdAt, order: .reverse)
    private var placedEntries: [Entry]
    @State private var search = PlaceSearch()
    @State private var camera: MapCameraPosition
    @State private var nearby: [NearbyPlace] = []
    /// The address under the place's name; looked up whenever the place changes.
    @State private var address: String?
    /// Where a long press on the map dropped the pin, while its name is looked up.
    @State private var dropped: CLLocationCoordinate2D?
    @State private var drops = 0
    /// In Your Journal's addresses, by place.
    @State private var journalAddresses: [String: String] = [:]
    /// What the map shows now, so a hold leaves it there (an automatic camera jumps to the new pin).
    @State private var visibleRegion: MKCoordinateRegion?
    @State private var isLocating = false
    @State private var resolvingID: String?
    @State private var errorMessage: String?
    @State private var locationDenied = false
    @FocusState private var searchFocused: Bool

    init(entry: Entry, onChange: @escaping () -> Void) {
        self.entry = entry
        self.onChange = onChange
        // Set up front: the Map ignores a camera change made in onAppear.
        if let coordinate = (entry.location ?? LocationService.shared.lastKnownLocation)?.coordinate {
            _camera = State(initialValue: .region(Self.region(around: coordinate)))
        } else {
            _camera = State(initialValue: .userLocation(fallback: .automatic))
        }
    }

    private static func region(around coordinate: CLLocationCoordinate2D) -> MKCoordinateRegion {
        MKCoordinateRegion(center: coordinate, latitudinalMeters: 1500, longitudinalMeters: 1500)
    }

    /// With no place set, the map shows where you are, so it needs location access.
    private var showsMap: Bool {
        entry.location != nil || LocationService.shared.isAuthorized
    }

    private var placeKey: String {
        "\(entry.placeName ?? "")|\(entry.latitude ?? 0)|\(entry.longitude ?? 0)"
    }

    private var isSearching: Bool {
        !search.query.trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// Where "Nearby" is measured from: the entry's place, else where you are, when that's allowed
    /// (never asking).
    private func nearbyCenter() async -> CLLocation? {
        if let location = entry.location { return location }
        guard LocationService.shared.isAuthorized else { return nil }
        if let location = LocationService.shared.lastKnownLocation { return location }
        return try? await LocationService.shared.currentLocation()
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: Spacing.m) {
                searchField
                results
            }
            .padding(.top, Spacing.m)
            .background(Theme.background)
            .navigationTitle("Set Location")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .tint(Theme.primaryText)
        .sensoryFeedback(.impact, trigger: drops)
        // Again when a hold on the map moves the place, as the sheet stays open.
        .task(id: placeKey) {
            address = nil
            if let coordinate = entry.location?.coordinate, let name = entry.placeName,
               let placemark = await PlaceAddress.lookup(coordinate) {
                address = PlaceAddress.describing(placemark, named: name)
            }
        }
        .task(id: placeKey) {
            guard let center = await nearbyCenter() else { return }
            // Where you are wasn't known when the sheet opened: go there, unless the map was moved.
            if entry.location == nil, visibleRegion == nil || camera.followsUserLocation {
                camera = .region(Self.region(around: center.coordinate))
            }
            search.prefer(around: center.coordinate)
            nearby = await NearbyPlace.around(center, excluding: entry.placeName)
        }
    }

    // MARK: - Pieces

    private var searchField: some View {
        HStack(spacing: Spacing.s) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(Theme.secondaryText)
            TextField("Search places", text: $search.query)
                .focused($searchFocused)
                .submitLabel(.search)
                .autocorrectionDisabled()
            if !search.query.isEmpty {
                Button("Clear", systemImage: "xmark.circle.fill") {
                    search.query = ""
                    searchFocused = true
                }
                .labelStyle(.iconOnly)
                .foregroundStyle(Theme.secondaryText)
                .buttonStyle(.borderless)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(Theme.primaryText.opacity(0.07), in: .capsule)
        .padding(.horizontal, Spacing.m)
    }

    /// Pans and zooms; holding a spot sets the place there.
    private var liveMap: some View {
        MapReader { proxy in
            Map(position: $camera) {
                if let coordinate = dropped ?? entry.location?.coordinate {
                    Annotation(entry.placeName ?? "", coordinate: coordinate, anchor: .center) {
                        MapPin()
                    }
                    .annotationTitles(.hidden)
                } else {
                    UserAnnotation()
                }
            }
            .mapStyle(.standard(pointsOfInterest: .excludingAll))
            .mapControls {}
            .onMapCameraChange(frequency: .onEnd) { visibleRegion = $0.region }
            .gesture(MapLongPress { point in
                if let coordinate = proxy.convert(point, from: .local) { drop(at: coordinate) }
            })
        }
        .frame(height: 170)
        .accessibilityLabel(entry.placeName.map { "Map showing \($0)" } ?? "Map")
        .accessibilityHint("Touch and hold a spot to set the place there")
    }

    private var results: some View {
        List {
            if isSearching {
                searchResults
            } else {
                currentPlace
            }
        }
        .scrollContentBackground(.hidden)
        .scrollDismissesKeyboard(.immediately)
        .contentMargins(.top, 0, for: .scrollContent)
        // Same gap as between the search field and the map.
        .listSectionSpacing(Spacing.m)
    }

    /// The map with the place set under it, in one card, then Current Location / Remove and nearby places.
    @ViewBuilder
    private var currentPlace: some View {
        if showsMap {
        Section {
            liveMap
                .listRowInsets(EdgeInsets())
                // The name row meets the map with no line between them.
                .listRowSeparator(.hidden)
            // Laid out like the day sheet's places: the name over its address.
            if let placeName = entry.placeName {
                VStack(alignment: .leading, spacing: 2) {
                    Text(placeName)
                        .font(Typography.body)
                        .foregroundStyle(Theme.primaryText)
                    Text(address ?? "Looking up the address")
                        .font(Typography.detail)
                        .foregroundStyle(Theme.secondaryText)
                        .redacted(reason: address == nil ? .placeholder : [])
                }
                .accessibilityElement(children: .combine)
            }
        }
        }

        Section {
            Button(action: useCurrentLocation) {
                HStack {
                    Label("Current Location", systemImage: "location")
                    Spacer()
                    if isLocating { ProgressView() }
                }
            }
            .disabled(isLocating || resolvingID != nil)

            if entry.placeName != nil {
                Button("Remove Location", systemImage: "location.slash", role: .destructive) {
                    entry.clearPlace()
                    onChange()
                    dismiss()
                }
            }
        } footer: {
            if locationDenied {
                Button {
                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                } label: {
                    Text("Location access is off. ") + Text("Open Settings").underline()
                }
                // A button takes the body size; set like a footer.
                .font(.footnote)
                .foregroundStyle(Theme.secondaryText)
                .buttonStyle(.borderless)
            } else if let errorMessage {
                Text(errorMessage)
            }
        }

        if !nearby.isEmpty {
            Section {
                ForEach(nearby) { place in
                    placeRow(title: place.name, subtitle: place.detail) {
                        choose(place.name, at: place.coordinate)
                    }
                }
            } header: {
                MetaLabel("Nearby", systemImage: "location.circle")
            }
        }
    }

    /// Places already in the journal that match, then suggestions from Maps.
    @ViewBuilder
    private var searchResults: some View {
        let journal = JournalPlace.all(in: placedEntries, excluding: entry).filter { $0.matches(search.query) }
        if !journal.isEmpty {
            Section {
                ForEach(journal.prefix(5)) { place in
                    placeRow(title: place.name, subtitle: journalAddresses[place.addressKey] ?? "") {
                        choose(place.name, at: place.coordinate)
                    }
                    // Looked up as the row shows, like Maps' own suggestions carry theirs.
                    .task(id: place.addressKey) {
                        guard journalAddresses[place.addressKey] == nil,
                              let placemark = await PlaceAddress.lookup(place.coordinate),
                              let address = PlaceAddress.full(placemark) else { return }
                        journalAddresses[place.addressKey] = address
                    }
                }
            } header: {
                MetaLabel("In My Journal", systemImage: "book.closed")
            }
        }

        if !search.suggestions.isEmpty {
            Section {
                ForEach(search.suggestions) { suggestion in
                    placeRow(title: suggestion.title, subtitle: suggestion.subtitle, isResolving: resolvingID == suggestion.id) {
                        Task { await select(suggestion) }
                    }
                }
            } header: {
                MetaLabel("Places", systemImage: "mappin.and.ellipse")
            } footer: {
                if let errorMessage { Text(errorMessage) }
            }
        }
    }

    private func placeRow(title: String, subtitle: String, isResolving: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .foregroundStyle(Theme.primaryText)
                    if !subtitle.isEmpty {
                        Text(subtitle)
                            .font(Typography.detail)
                            .foregroundStyle(Theme.secondaryText)
                    }
                }
                Spacer(minLength: 0)
                if isResolving { ProgressView() }
            }
        }
        .disabled(resolvingID != nil)
    }

    // MARK: - Actions

    private func drop(at coordinate: CLLocationCoordinate2D) {
        guard dropped == nil else { return }
        dropped = coordinate
        drops += 1
        if let visibleRegion { camera = .region(visibleRegion) }
        // The sheet stays open, the map where it is, so the spot can be moved again.
        Task {
            let name = await PlaceNames.name(for: coordinate)
            entry.setPlace(name: name, coordinate: coordinate)
            onChange()
            dropped = nil
        }
    }

    private func choose(_ name: String, at coordinate: CLLocationCoordinate2D) {
        entry.setPlace(name: name, coordinate: coordinate)
        onChange()
        dismiss()
    }

    private func useCurrentLocation() {
        isLocating = true
        errorMessage = nil
        locationDenied = false
        Task {
            defer { isLocating = false }
            do {
                let location = try await LocationService.shared.currentLocation()
                let name = await LocationService.shared.placeName(for: location) ?? "Current Location"
                choose(name, at: location.coordinate)
            } catch LocationService.Failure.denied {
                locationDenied = true
            } catch {
                errorMessage = "Couldn't find your location. Try again, or search for a place."
            }
        }
    }

    private func select(_ suggestion: PlaceSearch.Suggestion) async {
        guard resolvingID == nil else { return }
        resolvingID = suggestion.id
        defer { resolvingID = nil }
        guard let coordinate = await search.resolve(suggestion) else {
            errorMessage = "Couldn't find that place."
            return
        }
        choose(suggestion.title, at: coordinate)
    }
}

/// A place other entries are set at, by name: where it was last used, and how often (most used first).
private struct JournalPlace: Identifiable {
    let name: String
    let coordinate: CLLocationCoordinate2D
    let count: Int

    var id: String { name }
    var addressKey: String { "\(coordinate.latitude),\(coordinate.longitude)" }

    func matches(_ query: String) -> Bool {
        query.split(whereSeparator: \.isWhitespace).allSatisfy { name.localizedStandardContains($0) }
    }

    /// Most used first. `entries` are newest first, so each place keeps its latest spot.
    static func all(in entries: [Entry], excluding entry: Entry) -> [JournalPlace] {
        var order: [String] = []
        var places: [String: JournalPlace] = [:]
        for other in entries where other != entry {
            guard let name = other.placeName, let coordinate = other.location?.coordinate else { continue }
            let key = name.lowercased()
            if let place = places[key] {
                places[key] = JournalPlace(name: place.name, coordinate: place.coordinate, count: place.count + 1)
            } else {
                order.append(key)
                places[key] = JournalPlace(name: name, coordinate: coordinate, count: 1)
            }
        }
        return order.compactMap { places[$0] }.sorted { $0.count > $1.count }
    }
}

/// A point of interest near the entry's place, from Maps, closest first.
private struct NearbyPlace: Identifiable {
    let name: String
    let coordinate: CLLocationCoordinate2D
    /// How far it is, and its address: "120 m · 432 Octavia St, San Francisco, CA 94102, United States".
    let detail: String

    var id: String { "\(name)|\(coordinate.latitude)|\(coordinate.longitude)" }

    static func around(_ center: CLLocation, excluding placeName: String?) async -> [NearbyPlace] {
        let request = MKLocalPointsOfInterestRequest(center: center.coordinate, radius: 500)
        guard let items = try? await MKLocalSearch(request: request).start().mapItems else { return [] }
        let places = items.compactMap { item -> (NearbyPlace, CLLocationDistance)? in
            guard let name = item.name, name != placeName else { return nil }
            let coordinate = item.placemark.coordinate
            let distance = center.distance(from: CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude))
            let length = Measurement(value: distance, unit: UnitLength.meters)
                .formatted(.measurement(width: .abbreviated, usage: .road, numberFormatStyle: .number.precision(.fractionLength(0))))
            let detail = [length, PlaceAddress.full(item.placemark)].compactMap { $0 }.joined(separator: " · ")
            return (NearbyPlace(name: name, coordinate: coordinate, detail: detail), distance)
        }
        return places.sorted { $0.1 < $1.1 }.prefix(15).map(\.0)
    }
}

/// The exact spot: a sand dot ringed in white, on a soft sand halo. Also the day sheet's places,
/// where only the chosen one has the halo.
struct MapPin: View {
    var showsHalo = true

    var body: some View {
        ZStack {
            Circle()
                .fill(Theme.accent.opacity(0.3))
                .frame(width: 44, height: 44)
                .scaleEffect(showsHalo ? 1 : 0.3)
                .opacity(showsHalo ? 1 : 0)
            Circle()
                .fill(Theme.accent)
                .frame(width: 16, height: 16)
                .overlay { Circle().strokeBorder(.white, lineWidth: 3) }
                .shadow(color: .black.opacity(0.3), radius: 2, y: 1)
        }
    }
}

/// A long press on the map, reporting where it began. A UIKit recognizer, so the map still pans and zooms.
private struct MapLongPress: UIGestureRecognizerRepresentable {
    let action: (CGPoint) -> Void

    func makeUIGestureRecognizer(context: Context) -> UILongPressGestureRecognizer {
        UILongPressGestureRecognizer()
    }

    func handleUIGestureRecognizerAction(_ recognizer: UILongPressGestureRecognizer, context: Context) {
        if recognizer.state == .began { action(context.converter.localLocation) }
    }
}
