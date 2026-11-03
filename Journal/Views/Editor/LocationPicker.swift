import MapKit
import SwiftUI

/// Set, change or clear an entry's place: search, current location, or remove.
/// A small map shows the entry's place (or where you are, before one is set).
struct LocationPicker: View {
    @Bindable var entry: Entry
    let onChange: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var search = PlaceSearch()
    @State private var camera: MapCameraPosition
    @State private var isLocating = false
    @State private var resolvingID: String?
    @State private var errorMessage: String?
    @State private var locationDenied = false
    @FocusState private var searchFocused: Bool

    init(entry: Entry, onChange: @escaping () -> Void) {
        self.entry = entry
        self.onChange = onChange
        // Set up front: the Map ignores a camera change made in onAppear.
        if let coordinate = entry.location?.coordinate {
            _camera = State(initialValue: .region(
                MKCoordinateRegion(center: coordinate, latitudinalMeters: 1500, longitudinalMeters: 1500)
            ))
        } else {
            _camera = State(initialValue: .userLocation(fallback: .automatic))
        }
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
        .onAppear {
            if let place = entry.placeName {
                search.query = place
            }
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

    @ViewBuilder
    private var map: some View {
        if entry.location == nil && !LocationService.shared.isAuthorized {
            // Nothing to show yet: a quiet placeholder rather than a zoomed-out continent.
            RoundedRectangle(cornerRadius: Radius.card)
                .fill(Theme.primaryText.opacity(0.05))
                .overlay {
                    VStack(spacing: Spacing.s) {
                        Image(systemName: "map")
                            .font(Typography.icon.weight(.light))
                        Text("No location set")
                            .font(Typography.note)
                    }
                    .foregroundStyle(Theme.secondaryText)
                }
                .frame(height: 170)
        } else {
            liveMap
        }
    }

    private var liveMap: some View {
        Map(position: $camera) {
            if let coordinate = entry.location?.coordinate {
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
        .frame(height: 170)
        .clipShape(.rect(cornerRadius: Radius.card))
        .overlay {
            RoundedRectangle(cornerRadius: Radius.card).strokeBorder(Theme.hairline)
        }
        .allowsHitTesting(false)
        .accessibilityLabel(entry.placeName.map { "Map showing \($0)" } ?? "Map")
    }

    /// The map is the list's first row, so it scrolls away with the places below it.
    private var results: some View {
        List {
            map
                // The List already insets rows to its card width; no extra inset, so the map matches the cards.
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)

            Section {
                Button(action: useCurrentLocation) {
                    HStack {
                        Label("Current Location", systemImage: "location.fill")
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
                        Text("Location access is off for Journal. ") + Text("Open Settings").underline()
                    }
                    .foregroundStyle(Theme.secondaryText)
                    .buttonStyle(.borderless)
                } else if let errorMessage {
                    Text(errorMessage)
                }
            }

            // Hide suggestions that just echo the place already set.
            let suggestions = search.suggestions.filter { !(search.query == entry.placeName && $0.title == entry.placeName) }
            if !suggestions.isEmpty {
                Section {
                    ForEach(suggestions) { suggestion in
                        Button {
                            Task { await select(suggestion) }
                        } label: {
                            HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(suggestion.title)
                                    .foregroundStyle(Theme.primaryText)
                                if !suggestion.subtitle.isEmpty {
                                    Text(suggestion.subtitle)
                                        .font(Typography.note)
                                        .foregroundStyle(Theme.secondaryText)
                                }
                            }
                            Spacer(minLength: 0)
                            if resolvingID == suggestion.id { ProgressView() }
                            }
                        }
                        .disabled(resolvingID != nil)
                    }
                } header: {
                    MetaLabel("Places")
                }
            }
        }
        .scrollContentBackground(.hidden)
        .scrollDismissesKeyboard(.immediately)
        .contentMargins(.top, 0, for: .scrollContent)
        // Same gap as between the search field and the map.
        .listSectionSpacing(Spacing.m)
    }

    // MARK: - Actions


    private func useCurrentLocation() {
        isLocating = true
        errorMessage = nil
        locationDenied = false
        Task {
            defer { isLocating = false }
            do {
                let location = try await LocationService.shared.currentLocation()
                let name = await LocationService.shared.placeName(for: location) ?? "Current Location"
                entry.setPlace(name: name, coordinate: location.coordinate)
                onChange()
                dismiss()
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
        entry.setPlace(name: suggestion.title, coordinate: coordinate)
        onChange()
        dismiss()
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
