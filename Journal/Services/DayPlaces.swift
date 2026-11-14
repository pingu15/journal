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
/// stays close together are the same place. iOS's own visits (`PlaceVisit`) then set when the user
/// arrived and left.
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
        let places = places(from: PlaceTracker.samples(on: day), visits: PlaceTracker.visits, on: day)
        cache[key] = places
        return places
    }

    static func forget(_ day: Date) {
        cache[Calendar.current.startOfDay(for: day)] = nil
    }

    static func forgetAll() {
        cache = [:]
    }

    static func places(from samples: [LocationSample], visits: [PlaceVisit], on day: Date) -> [VisitedPlace] {
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
        stays = timed(stays, by: visits, on: day)

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

    /// Moves each stay's ends out to when iOS says the user arrived and left. Samples come every five
    /// minutes, and none at all while iOS has stopped the app, so a stay's first and last samples can
    /// be well inside it. A stay only stretches into the time around it, never past the samples of the
    /// stays on either side; a visit with no stay of its own adds nothing.
    private static func timed(_ stays: [Cluster], by visits: [PlaceVisit], on day: Date) -> [Cluster] {
        guard !visits.isEmpty, let dayInterval = Calendar.current.dateInterval(of: .day, for: day) else { return stays }
        let latest = min(dayInterval.end, .now)
        var timed: [Cluster] = []
        for (index, stay) in stays.enumerated() {
            guard let first = stay.first, let last = stay.last else { continue }
            var start = first, end = last
            // The stays somewhere else on either side, where the user was instead. A stay at the same
            // place is the same stay split by stray readings.
            let previousElsewhere = stays[..<index].last { $0.location.distance(from: stay.location) > radius }?.last
            let nextElsewhere = stays[(index + 1)...].first { $0.location.distance(from: stay.location) > radius }?.first
            for visit in visits where visit.location.distance(from: stay.location) <= radius + visit.accuracy {
                // Only a visit that overlaps the stay is the same one.
                guard visit.arrival ?? .distantPast <= last, first <= visit.departure ?? .distantFuture else { continue }
                // Nor one that reaches back past a stay somewhere else, or on past one: the user was
                // there in between, so it's an earlier or later visit here. An open visit whose
                // departure iOS never sent would otherwise pull every later stay here back to it.
                if let arrival = visit.arrival, let previousElsewhere, arrival < previousElsewhere { continue }
                if let nextElsewhere, visit.departure ?? .distantFuture > nextElsewhere { continue }
                if let arrival = visit.arrival { start = min(start, arrival) }
                if let departure = visit.departure { end = max(end, departure) }
            }
            let previousLast = index > 0 ? stays[index - 1].last : nil
            let nextFirst = index + 1 < stays.count ? stays[index + 1].first : nil
            start = max(start, previousLast ?? dayInterval.start, dayInterval.start)
            end = max(start, min(end, nextFirst ?? latest, latest))
            var stay = stay
            stay.visits = [DateInterval(start: start, end: end)]
            // Both stretched into the time between them.
            if let previous = timed.last, let before = previous.visits.first, before.end > start {
                if previous.location.distance(from: stay.location) <= radius {
                    // The same stay, split by stray readings.
                    var merged = previous
                    merged.merge(stay)
                    merged.visits = [DateInterval(start: before.start, end: max(before.end, end))]
                    timed[timed.count - 1] = merged
                    continue
                }
                let middle = Date(timeIntervalSinceReferenceDate:
                    (before.end.timeIntervalSinceReferenceDate + start.timeIntervalSinceReferenceDate) / 2)
                timed[timed.count - 1].visits = [DateInterval(start: before.start, end: middle)]
                stay.visits = [DateInterval(start: middle, end: max(middle, end))]
            }
            timed.append(stay)
        }
        return timed
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
