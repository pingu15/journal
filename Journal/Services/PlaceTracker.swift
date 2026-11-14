import CoreLocation
import UIKit

/// One reading of where the user was.
struct LocationSample: Codable {
    var time: Date
    var latitude: Double
    var longitude: Double
    /// Horizontal accuracy, in meters.
    var accuracy: Double

    var location: CLLocation {
        CLLocation(latitude: latitude, longitude: longitude)
    }
}

/// A stay iOS noticed on its own (`CLVisit`). Kept mostly for its times: iOS knows when the user
/// arrived and left even while the app wasn't running, so `DayPlaces` stretches the stays it found in
/// the samples out to them. It makes a place of its own only where a sample agrees and the samples
/// found none (`DayPlaces.visitStays`).
struct PlaceVisit: Codable {
    /// Nil when iOS doesn't know.
    var arrival: Date?
    /// Nil while the user is still there.
    var departure: Date?
    var latitude: Double
    var longitude: Double
    /// Horizontal accuracy, in meters.
    var accuracy: Double

    var location: CLLocation {
        CLLocation(latitude: latitude, longitude: longitude)
    }
}

/// Notes where the user is through the day — a sample every five minutes, in the background too —
/// so a day can show the places they spent time (`DayPlaces`). Off until it's turned on, in
/// Settings or from a day's Places card. The samples stay on this iPhone, a file a day.
final class PlaceTracker: NSObject, CLLocationManagerDelegate {
    static let shared = PlaceTracker()
    /// Settings: Track Visited Places.
    static let enabledKey = "trackPlaces"
    static let interval: TimeInterval = 5 * 60
    /// Readings vaguer than this (meters) are left out.
    private static let maximumInaccuracy: Double = 200

    private let manager = CLLocationManager()
    private var lastSampleTime: Date?
    private var clock: Timer?
    private static let tick: TimeInterval = 60
    /// When the clock last ticked, and since when it has without missing any.
    private var lastTick: Date?
    private var tickingSince: Date?
    private var authorizationWaiters: [CheckedContinuation<Void, Never>] = []

    override private init() {
        super.init()
        manager.delegate = self
        // Wi-Fi and cell towers are enough to tell places apart, and much cheaper than GPS.
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        manager.distanceFilter = kCLDistanceFilterNone
        manager.activityType = .other
    }

    var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: Self.enabledKey)
    }

    var isAuthorized: Bool {
        LocationService.shared.isAuthorized
    }

    /// On launch, including when iOS relaunches the app in the background for a move.
    func resume() {
        if isEnabled && isAuthorized { start() }
    }

    /// Turns tracking on, like the daily reminder, whether or not location is allowed: it asks for
    /// access if it hasn't yet (and then for Always, so tracking carries on once the app has been
    /// closed), and starts once access is there — now, or when it's allowed later
    /// (`locationManagerDidChangeAuthorization`). True when it's tracking.
    @discardableResult
    func enable() async -> Bool {
        UserDefaults.standard.set(true, forKey: Self.enabledKey)
        // Its reminder now goes day by day, with each day's places.
        await ReminderScheduler.refresh()
        guard await LocationService.shared.requestAuthorization() else { return false }
        if manager.authorizationStatus == .authorizedWhenInUse {
            await SystemPrompts.shared.during { await askForAlways() }
        }
        start()
        return true
    }

    /// Stops tracking; the places already noted stay.
    func disable() {
        UserDefaults.standard.set(false, forKey: Self.enabledKey)
        Task { await ReminderScheduler.refresh() }
        manager.stopUpdatingLocation()
        manager.stopMonitoringSignificantLocationChanges()
        manager.stopMonitoringVisits()
        clock?.invalidate()
        clock = nil
    }

    private func start() {
        // In the background only with Always. With While Using, iOS treats location carrying on after
        // the app closes as a live activity it must show: the Dynamic Island's location indicator, which
        // the app shrank into when closed instead of into its icon. Settings already calls tracking off
        // then, so it notes places only while the app is open, until Always is allowed.
        let always = manager.authorizationStatus == .authorizedAlways
        manager.allowsBackgroundLocationUpdates = always
        // Standing still is the point: a place is somewhere the user stayed.
        manager.pausesLocationUpdatesAutomatically = false
        manager.showsBackgroundLocationIndicator = false
        manager.startUpdatingLocation()
        // Readings can stop coming while the phone doesn't move, which is just when a sample is wanted:
        // the last one still holds then. The app keeps running while it's tracking, so this fires.
        if clock == nil {
            tickingSince = .now
            lastTick = .now
            clock = Timer.scheduledTimer(withTimeInterval: Self.tick, repeats: true) { _ in
                MainActor.assumeIsolated { self.tickClock() }
            }
        }
        // Relaunches the app after it's been closed, which only Always allows.
        if manager.authorizationStatus == .authorizedAlways {
            manager.startMonitoringSignificantLocationChanges()
            // Arrive and leave times, for the stays the samples find (`PlaceVisit`).
            manager.startMonitoringVisits()
        }
    }

    /// Notes the last reading again, as now. It still holds only if the app has been running all along
    /// since it came: while iOS had the app stopped, the user may have gone anywhere, and the reading
    /// from before would put them back where they were. Then it waits for a new one.
    private func tickClock() {
        let now = Date.now
        // The clock missed ticks: the app was stopped.
        if let lastTick, now.timeIntervalSince(lastTick) > Self.tick * 1.5 { tickingSince = now }
        lastTick = now
        guard let location = manager.location, let tickingSince,
              location.timestamp >= tickingSince.addingTimeInterval(-Self.tick) else { return }
        record(location, at: now)
    }

    /// iOS asks to change While Using to Always once, and doesn't call back if the answer leaves it
    /// as it was: the prompt is answered when the app is active again.
    private func askForAlways() async {
        manager.requestAlwaysAuthorization()
        try? await Task.sleep(for: .milliseconds(600))
        guard UIApplication.shared.applicationState != .active else { return }
        for await _ in NotificationCenter.default.notifications(named: UIApplication.didBecomeActiveNotification) {
            break
        }
    }

    private func record(_ location: CLLocation, at time: Date) {
        guard location.horizontalAccuracy >= 0, location.horizontalAccuracy <= Self.maximumInaccuracy else { return }
        let last = lastSampleTime ?? Self.samples(on: time).last?.time
        // A little early is fine: readings don't arrive on the dot.
        if let last, time.timeIntervalSince(last) < Self.interval - 15 { return }
        lastSampleTime = time
        let sample = LocationSample(
            time: time,
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude,
            accuracy: location.horizontalAccuracy
        )
        Self.save(Self.samples(on: sample.time) + [sample], on: sample.time)
        // The daily reminder says how many places today took in.
        Task { await ReminderScheduler.refresh() }
    }

    private func recordVisit(arrival: Date, departure: Date, coordinate: CLLocationCoordinate2D, accuracy: Double) {
        guard accuracy >= 0, accuracy <= Self.maximumInaccuracy else { return }
        let new = PlaceVisit(
            arrival: arrival == .distantPast ? nil : arrival,
            departure: departure == .distantFuture ? nil : departure,
            latitude: coordinate.latitude,
            longitude: coordinate.longitude,
            accuracy: accuracy
        )
        var visits = Self.visits
        // The departure comes later, as the same visit again.
        if let arrival = new.arrival, let index = visits.lastIndex(where: { $0.arrival == arrival }) {
            visits[index] = new
        } else {
            // iOS doesn't always send the departure, and can send it with the arrival a few seconds off.
            // A visit still open from before this one, or this one again, was left at a time it never
            // said, and kept open it would claim every later stay there.
            if let arrival = new.arrival {
                visits.removeAll { $0.departure == nil && ($0.arrival ?? .distantPast) < arrival.addingTimeInterval(60) }
            }
            visits.append(new)
        }
        Self.saveVisits(visits)
    }

    // MARK: Storage

    private static var folder: URL {
        URL.applicationSupportDirectory.appending(path: "Places", directoryHint: .isDirectory)
    }

    private static func file(on day: Date) -> URL {
        let parts = Calendar.current.dateComponents([.year, .month, .day], from: day)
        let name = String(format: "%04d-%02d-%02d.json", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
        return folder.appending(path: name)
    }

    /// The samples taken on `day`, oldest first.
    static func samples(on day: Date) -> [LocationSample] {
        guard let data = try? Data(contentsOf: file(on: day)) else { return [] }
        return (try? JSONDecoder().decode([LocationSample].self, from: data)) ?? []
    }

    private static func save(_ samples: [LocationSample], on day: Date) {
        guard let data = try? JSONEncoder().encode(samples) else { return }
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        // Readable while the phone is locked, after the first unlock: most samples are taken then.
        try? data.write(to: file(on: day), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        DayPlaces.forget(day)
    }

    private static var visitsFile: URL {
        folder.appending(path: "visits.json")
    }

    private static var cachedVisits: [PlaceVisit]?

    /// Every visit iOS has reported, in the order it reported them.
    static var visits: [PlaceVisit] {
        if let cachedVisits { return cachedVisits }
        let data = try? Data(contentsOf: visitsFile)
        let visits = data.flatMap { try? JSONDecoder().decode([PlaceVisit].self, from: $0) } ?? []
        cachedVisits = visits
        return visits
    }

    private static func saveVisits(_ visits: [PlaceVisit]) {
        cachedVisits = visits
        guard let data = try? JSONEncoder().encode(visits) else { return }
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try? data.write(to: visitsFile, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        // A visit can span days.
        DayPlaces.forgetAll()
    }

    #if DEBUG
    /// `-seedSamplePlaces`: a made-up week of days around San Francisco — home, a café, the office,
    /// a stop too short to count, the park, and home again — replacing whatever was noted.
    static func seedSampleDays() {
        let calendar = Calendar.current
        let home = (37.7849, -122.4294), cafe = (37.7764, -122.4241), office = (37.7897, -122.3972)
        let corner = (37.7810, -122.4100), park = (37.7694, -122.4862)
        // (from, to) as minutes after midnight; a nil place is on the move.
        let plan: [((Double, Double)?, Int, Int)] = [
            (home, 0, 510), (nil, 515, 535), (cafe, 540, 585), (nil, 590, 595), (office, 600, 1050),
            (corner, 1055, 1060), (nil, 1065, 1075), (park, 1080, 1140), (nil, 1145, 1165), (home, 1170, 1435),
        ]
        var generator = SystemRandomNumberGenerator()
        for daysAgo in 0..<7 {
            guard let day = calendar.date(byAdding: .day, value: -daysAgo, to: calendar.startOfDay(for: .now)) else { continue }
            var samples: [LocationSample] = []
            for (place, from, to) in plan {
                for minute in stride(from: from, through: to, by: 5) {
                    let time = day.addingTimeInterval(TimeInterval(minute * 60))
                    guard time <= .now else { break }
                    // On the move: somewhere new each time, well apart.
                    let spot = place ?? (37.76 + Double(minute % 97) / 2000, -122.44 + Double(minute % 89) / 1500)
                    // Readings wander a few tens of meters; one strays far in the middle of the office day.
                    let stray = place.map { $0 == office } == true && minute == 800 ? 0.004 : 0
                    samples.append(LocationSample(
                        time: time,
                        latitude: spot.0 + Double.random(in: -0.0003...0.0003, using: &generator) + stray,
                        longitude: spot.1 + Double.random(in: -0.0003...0.0003, using: &generator),
                        accuracy: 65
                    ))
                }
            }
            save(samples, on: day)
        }
    }
    #endif

    // MARK: CLLocationManagerDelegate

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        MainActor.assumeIsolated {
            for location in locations {
                record(location, at: location.timestamp)
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didVisit visit: CLVisit) {
        // CLVisit isn't Sendable: its values are taken out here.
        let arrival = visit.arrivalDate, departure = visit.departureDate
        let coordinate = visit.coordinate, accuracy = visit.horizontalAccuracy
        MainActor.assumeIsolated {
            recordVisit(arrival: arrival, departure: departure, coordinate: coordinate, accuracy: accuracy)
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        MainActor.assumeIsolated {
            // Picks up again when access comes back, or Always is newly allowed.
            resume()
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {}
}
