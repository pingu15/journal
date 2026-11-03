import CoreLocation

/// A place the user stayed on a day, with every stay there that day counted together.
struct VisitedPlace: Identifiable {
    let id: Int
    let coordinate: CLLocationCoordinate2D
    /// Each stay, in order.
    let visits: [DateInterval]

    var duration: TimeInterval {
        visits.reduce(0) { $0 + $1.duration }
    }

    var location: CLLocation {
        CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
    }
}

/// Works out a day's places from `PlaceTracker`'s samples: a stay is at least `minimumSamples`
/// readings in a row within `radius` of each other (ten minutes or more, a reading every five), and
/// stays close together are the same place.
enum DayPlaces {
    static let radius: CLLocationDistance = 120
    static let minimumSamples = 3

    /// Worked out once a day, as the day sheet builds its card on every update; `PlaceTracker` drops a
    /// day when it notes a sample on it.
    private static var cache: [Date: [VisitedPlace]] = [:]

    /// In the order the user first got there.
    static func places(on day: Date) -> [VisitedPlace] {
        let key = Calendar.current.startOfDay(for: day)
        if let places = cache[key] { return places }
        let places = places(from: PlaceTracker.samples(on: day))
        cache[key] = places
        return places
    }

    static func forget(_ day: Date) {
        cache[Calendar.current.startOfDay(for: day)] = nil
    }

    static func places(from samples: [LocationSample]) -> [VisitedPlace] {
        let samples = samples.sorted { $0.time < $1.time }
        var stays: [Cluster] = []
        var run = Cluster()

        func endRun() {
            if run.count >= minimumSamples, let first = run.first, let last = run.last {
                run.visits = [DateInterval(start: first, end: last)]
                stays.append(run)
            }
            run = Cluster()
        }

        var index = 0
        while index < samples.count {
            let sample = samples[index]
            if run.count > 0 {
                let center = run.location
                if sample.location.distance(from: center) > radius {
                    // One stray reading in the middle of a stay doesn't end it.
                    if index + 1 < samples.count, samples[index + 1].location.distance(from: center) <= radius {
                        index += 1
                        continue
                    }
                    endRun()
                }
            }
            run.add(sample)
            index += 1
        }
        endRun()

        var places: [Cluster] = []
        for stay in stays {
            if let match = places.firstIndex(where: { $0.location.distance(from: stay.location) <= radius }) {
                places[match].merge(stay)
            } else {
                places.append(stay)
            }
        }
        return places.enumerated().map { index, place in
            VisitedPlace(id: index, coordinate: place.location.coordinate, visits: place.visits)
        }
    }

    /// Samples kept as running sums, so the center of a growing run doesn't go back over all of it.
    private struct Cluster {
        var count = 0
        var latitudes = 0.0
        var longitudes = 0.0
        var first: Date?
        var last: Date?
        var visits: [DateInterval] = []

        var location: CLLocation {
            let count = Double(max(count, 1))
            return CLLocation(latitude: latitudes / count, longitude: longitudes / count)
        }

        mutating func add(_ sample: LocationSample) {
            count += 1
            latitudes += sample.latitude
            longitudes += sample.longitude
            first = first ?? sample.time
            last = sample.time
        }

        mutating func merge(_ other: Cluster) {
            count += other.count
            latitudes += other.latitudes
            longitudes += other.longitudes
            visits += other.visits
        }
    }
}

/// Names for the places on a day — the point of interest, or the street address — looked up once.
enum PlaceNames {
    private static var names: [String: String] = [:]
    /// Lookups under way, shared, so a place asked for twice at once gets one name.
    private static var lookups: [String: Task<String?, Never>] = [:]

    private static func key(_ coordinate: CLLocationCoordinate2D) -> String {
        String(format: "%.4f,%.4f", coordinate.latitude, coordinate.longitude)
    }

    static func cachedName(for coordinate: CLLocationCoordinate2D) -> String? {
        names[key(coordinate)]
    }

    static func name(for coordinate: CLLocationCoordinate2D) async -> String {
        let key = key(coordinate)
        if let name = names[key] { return name }
        let lookup = lookups[key] ?? Task {
            let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
            let placemark = try? await CLGeocoder().reverseGeocodeLocation(location).first
            return placemark?.areasOfInterest?.first ?? placemark?.name ?? placemark?.locality
        }
        lookups[key] = lookup
        let name = await lookup.value
        lookups[key] = nil
        // Not kept when it fails, so it's tried again next time.
        guard let name else { return "Unknown Place" }
        names[key] = name
        return name
    }

    /// Looks up a day's names ahead of time, so they're there when it slides in.
    static func preload(on day: Date) async {
        for place in DayPlaces.places(on: day) where cachedName(for: place.coordinate) == nil {
            _ = await name(for: place.coordinate)
        }
    }
}
