import CoreLocation
import MapKit
import Observation

/// One-shot "where am I" lookups for tagging an entry with the current place. Observable, so views
/// that say whether location is allowed follow iOS's answer, which arrives a moment after a prompt
/// or a trip to Settings ends.
@Observable
final class LocationService: NSObject, CLLocationManagerDelegate {
    enum Failure: LocalizedError {
        case denied

        var errorDescription: String? {
            "Location access is off. You can turn it on in Settings."
        }
    }

    static let shared = LocationService()
    /// Settings: tag new entries with the current place.
    static let autoTagKey = "autoTagLocation"

    @ObservationIgnored private let manager = CLLocationManager()
    @ObservationIgnored private var authorizationWaiters: [CheckedContinuation<Void, Never>] = []
    @ObservationIgnored private var locationWaiters: [CheckedContinuation<CLLocation, Error>] = []
    /// iOS's answer, kept up to date from `locationManagerDidChangeAuthorization`.
    private(set) var authorizationStatus: CLAuthorizationStatus

    override private init() {
        authorizationStatus = manager.authorizationStatus
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    var isAuthorized: Bool {
        [.authorizedWhenInUse, .authorizedAlways].contains(authorizationStatus)
    }

    /// Always, which tracking visited places needs to carry on in the background.
    var allowsAlways: Bool {
        authorizationStatus == .authorizedAlways
    }

    /// The last location the system has, at once, though it may be out of date.
    var lastKnownLocation: CLLocation? {
        isAuthorized ? manager.location : nil
    }

    /// Brings `lastKnownLocation` up to date ahead of time, if that's allowed; it never asks.
    func refreshLastKnownLocation() {
        if isAuthorized { manager.requestLocation() }
    }

    /// Whether iOS will still show its prompt: it hasn't been asked yet.
    var canAsk: Bool {
        authorizationStatus == .notDetermined
    }

    /// Asks for permission if it hasn't been asked yet; true when location is allowed.
    func requestAuthorization() async -> Bool {
        if authorizationStatus == .notDetermined {
            await SystemPrompts.shared.during {
                await withCheckedContinuation { continuation in
                    authorizationWaiters.append(continuation)
                    manager.requestWhenInUseAuthorization()
                }
            }
        }
        return isAuthorized
    }

    func currentLocation() async throws -> CLLocation {
        guard await requestAuthorization() else {
            throw Failure.denied
        }
        return try await withCheckedThrowingContinuation { continuation in
            locationWaiters.append(continuation)
            manager.requestLocation()
        }
    }

    /// A short human name for a coordinate: neighbourhood or city.
    func placeName(for location: CLLocation) async -> String? {
        let placemark = try? await CLGeocoder().reverseGeocodeLocation(location).first
        return placemark?.locality ?? placemark?.name ?? placemark?.administrativeArea
    }

    // MARK: CLLocationManagerDelegate

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        MainActor.assumeIsolated {
            authorizationStatus = status
            guard status != .notDetermined else { return }
            authorizationWaiters.forEach { $0.resume() }
            authorizationWaiters.removeAll()
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        MainActor.assumeIsolated {
            locationWaiters.forEach { $0.resume(returning: location) }
            locationWaiters.removeAll()
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        let message = error.localizedDescription
        MainActor.assumeIsolated {
            let failure = NSError(domain: kCLErrorDomain, code: 0, userInfo: [NSLocalizedDescriptionKey: message])
            locationWaiters.forEach { $0.resume(throwing: failure) }
            locationWaiters.removeAll()
        }
    }
}

/// Live place suggestions while the user types in the location picker.
@Observable
final class PlaceSearch: NSObject, MKLocalSearchCompleterDelegate {
    struct Suggestion: Identifiable {
        let id: String
        let title: String
        let subtitle: String
        fileprivate let completion: MKLocalSearchCompletion
    }

    var query = "" {
        didSet { completer.queryFragment = query }
    }
    private(set) var suggestions: [Suggestion] = []

    /// Suggestions favour places around here (a city's width), else where Maps thinks you are.
    func prefer(around center: CLLocationCoordinate2D) {
        completer.region = MKCoordinateRegion(center: center, latitudinalMeters: 20_000, longitudinalMeters: 20_000)
    }

    @ObservationIgnored private let completer = MKLocalSearchCompleter()

    override init() {
        super.init()
        completer.delegate = self
        completer.resultTypes = [.address, .pointOfInterest]
    }

    /// Resolves a suggestion to a coordinate.
    func resolve(_ suggestion: Suggestion) async -> CLLocationCoordinate2D? {
        let response = try? await MKLocalSearch(request: MKLocalSearch.Request(completion: suggestion.completion)).start()
        return response?.mapItems.first?.placemark.coordinate
    }

    nonisolated func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        MainActor.assumeIsolated {
            // Read our own (main-actor) completer rather than sending the parameter across.
            suggestions = self.completer.results.prefix(12).map {
                Suggestion(id: "\($0.title)|\($0.subtitle)", title: $0.title, subtitle: $0.subtitle, completion: $0)
            }
        }
    }

    nonisolated func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        MainActor.assumeIsolated {
            suggestions = []
        }
    }
}

/// Addresses written out from a placemark, the way Maps writes them.
enum PlaceAddress {
    static func lookup(_ coordinate: CLLocationCoordinate2D) async -> CLPlacemark? {
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        return try? await CLGeocoder().reverseGeocodeLocation(location).first
    }

    /// "432 Octavia St, San Francisco, CA 94102, United States".
    static func full(_ placemark: CLPlacemark) -> String? {
        let state = [placemark.administrativeArea, placemark.postalCode].compactMap { $0 }.joined(separator: " ")
        return joined([street(placemark), placemark.locality, state, placemark.country])
    }

    /// The full address, or just "San Francisco, CA, United States" when `name` already is the street.
    static func describing(_ placemark: CLPlacemark, named name: String) -> String? {
        if let street = street(placemark), street.caseInsensitiveCompare(name) == .orderedSame {
            return joined([placemark.locality, placemark.administrativeArea, placemark.country])
        }
        return full(placemark)
    }

    private static func street(_ placemark: CLPlacemark) -> String? {
        joined([placemark.subThoroughfare, placemark.thoroughfare], separator: " ")
    }

    private static func joined(_ parts: [String?], separator: String = ", ") -> String? {
        let parts = parts.compactMap { $0 }.filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: separator)
    }
}
