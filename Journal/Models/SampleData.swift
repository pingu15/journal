#if DEBUG
import CoreLocation
import ImageIO
import Photos
import SwiftData
import UIKit

/// `-seedSampleData`: fills an empty store with `SampleJournal`, about four months of a life in New
/// York. Each entry gets its place, the weather a day like it would have had, and its photos; the
/// days get the location history that goes with them (home, the commute, the office, wherever the
/// entries say the day went), and the Photos library gets the photos, taken where and when the
/// journal says.
enum SampleData {
    typealias Place = SampleJournal.Place
    typealias Draft = SampleJournal.Draft

    /// When the store was seeded: the journal's dates all count back from it.
    private static let anchorKey = "sampleDataSeededAt"

    static func seed(_ context: ModelContext) {
        if populate(context) {
            let now = Date.now
            UserDefaults.standard.set(now, forKey: anchorKey)
            writePlaces(plan(anchor: now, through: now))
        }
        // Not only when the store was just seeded: Photos access may have been allowed since.
        guard let anchor = UserDefaults.standard.object(forKey: anchorKey) as? Date else { return }
        Task { await addToPhotoLibrary(plan(anchor: anchor, through: anchor)) }
    }

    /// `-seedSamplePlaces`: the journal's location history again, up to now, replacing whatever was
    /// noted on those days.
    static func seedPlaces() {
        let anchor = UserDefaults.standard.object(forKey: anchorKey) as? Date ?? .now
        writePlaces(plan(anchor: anchor, through: .now))
    }

    /// The entries alone, into an empty store. False when the store already had some.
    @discardableResult
    static func populate(_ context: ModelContext) -> Bool {
        let existing = (try? context.fetchCount(FetchDescriptor<Entry>())) ?? 0
        guard existing == 0 else { return false }

        let now = Date.now
        let calendar = Calendar.current
        for day in plan(anchor: now, through: now) {
            for draft in day.entries {
                insert(draft, on: day.date, sky: day.sky, in: context)
            }
        }
        for (years, draft) in [(1, SampleJournal.yearAgo), (2, SampleJournal.twoYearsAgo)] {
            guard let date = calendar.date(byAdding: .year, value: -years, to: calendar.startOfDay(for: now)) else { continue }
            insert(draft, on: date, sky: nil, in: context)
        }
        try? context.save()
        return true
    }

    // MARK: - Days

    /// A day of the journal: its entries, and where it went besides the usual.
    struct Day {
        let date: Date
        var entries: [Draft] = []
        var stops: [SampleJournal.Stop] = []
        var snapshots: [SampleJournal.Snapshot] = []

        var sky: SampleJournal.Sky? {
            entries.lazy.compactMap(\.sky).first
        }
    }

    private static func minutes(_ clock: Int) -> Int {
        clock / 100 * 60 + clock % 100
    }

    private static func date(_ day: Date, _ clock: Int) -> Date {
        Calendar.current.date(bySettingHour: clock / 100, minute: clock % 100, second: 0, of: day) ?? day
    }

    /// Every day from the Monday `SampleJournal.weeks` weeks back to `through`, with the entries
    /// written by `anchor`. Dated slots first; then what's in season goes on days still free.
    static func plan(anchor: Date, through: Date) -> [Day] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: anchor)
        let sinceMonday = (calendar.component(.weekday, from: today) + 5) % 7
        let first = calendar.date(byAdding: .day, value: -sinceMonday - 7 * (SampleJournal.weeks - 1), to: today) ?? today
        let count = (calendar.dateComponents([.day], from: first, to: calendar.startOfDay(for: through)).day ?? 0) + 1
        var days = (0..<max(count, 1)).map { offset in
            Day(date: calendar.date(byAdding: .day, value: offset, to: first) ?? first)
        }
        func index(week: Int, weekday: SampleJournal.Weekday) -> Int? {
            let index = (SampleJournal.weeks - 1 - week) * 7 + weekday.rawValue
            return days.indices.contains(index) ? index : nil
        }

        for slot in SampleJournal.slots {
            guard let index = index(week: slot.week, weekday: slot.weekday),
                  date(days[index].date, slot.draft.time) <= anchor else { continue }
            days[index].entries.append(slot.draft)
            days[index].stops += slot.draft.stops
        }
        for (number, item) in SampleJournal.seasonal.enumerated() {
            let free = days.indices.filter { index in
                index % 7 == item.weekday.rawValue
                    && days[index].entries.isEmpty
                    && item.months.contains(calendar.component(.month, from: days[index].date))
                    && date(days[index].date, item.draft.time) <= anchor
            }
            guard !free.isEmpty else { continue }
            let index = free[(number * 7 + 3) % free.count]
            days[index].entries.append(item.draft)
            days[index].stops += item.draft.stops
        }
        for snapshot in SampleJournal.snapshots {
            guard let index = index(week: snapshot.week, weekday: snapshot.weekday),
                  date(days[index].date, snapshot.time) <= anchor else { continue }
            days[index].snapshots.append(snapshot)
        }
        return days
    }

    // MARK: - Entries

    private static let photoLine = try! NSRegularExpression(pattern: #"^\{([a-z0-9-]+)\}$"#)

    private static func photoName(_ line: String) -> String? {
        let range = NSRange(location: 0, length: (line as NSString).length)
        guard let match = photoLine.firstMatch(in: line, range: range) else { return nil }
        return (line as NSString).substring(with: match.range(at: 1))
    }

    private static func inSeason(_ name: String, on day: Date) -> Bool {
        guard let photo = SampleJournal.photos[name] else { return false }
        return photo.months?.contains(Calendar.current.component(.month, from: day)) ?? true
    }

    /// The draft's photos that could have been taken on `day`, in the order they come in the text.
    private static func photoNames(in draft: Draft, on day: Date) -> [String] {
        draft.text.components(separatedBy: "\n").compactMap(photoName).filter { inSeason($0, on: day) }
    }

    private static func insert(_ draft: Draft, on day: Date, sky: SampleJournal.Sky?, in context: ModelContext) {
        let createdAt = date(day, draft.time)
        var attachments: [Attachment] = []
        // A photo's line becomes its token, or goes when the photo is out of season or not in the build.
        let lines = draft.text.components(separatedBy: "\n").compactMap { line -> String? in
            guard let name = photoName(line) else { return line }
            guard inSeason(name, on: day), let picture = picture(named: name) else { return nil }
            let attachment = Attachment(imageData: picture.full, thumbnailData: picture.thumbnail)
            attachment.createdAt = createdAt
            attachments.append(attachment)
            return Markdown.imageToken(attachment.identifier)
        }

        let entry = Entry(text: lines.joined(separator: "\n"), createdAt: createdAt)
        // Written at about a word every two seconds.
        entry.updatedAt = createdAt.addingTimeInterval(60 + Double(entry.wordCount) * 2)
        if let place = draft.place {
            entry.placeName = place.name
            entry.latitude = place.latitude
            entry.longitude = place.longitude
            entry.apply(weather(on: day, minute: minutes(draft.time), sky: sky))
        }
        context.insert(entry)
        for attachment in attachments {
            context.insert(attachment)
            attachment.entry = entry
        }
        // Now and then the cover isn't the first photo.
        if attachments.count > 1, dayNumber(day) % 2 == 0 {
            entry.coverImageID = attachments[1].identifier
        }
    }

    private static var pictures: [String: ImageProcessing.Prepared] = [:]

    /// A bundled photo, as it's stored, and its list thumbnail. The files are already the size the
    /// app keeps, so they're used as they are.
    private static func picture(named name: String) -> ImageProcessing.Prepared? {
        if let picture = pictures[name] { return picture }
        guard let url = Bundle.main.url(forResource: name, withExtension: "jpg"),
              let full = try? Data(contentsOf: url),
              let source = CGImageSourceCreateWithData(full as CFData, nil),
              let small = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                  kCGImageSourceCreateThumbnailFromImageAlways: true,
                  kCGImageSourceCreateThumbnailWithTransform: true,
                  kCGImageSourceThumbnailMaxPixelSize: 300,
              ] as CFDictionary),
              let thumbnail = UIImage(cgImage: small).jpegData(compressionQuality: 0.8)
        else { return nil }
        let picture = ImageProcessing.Prepared(full: full, thumbnail: thumbnail)
        pictures[name] = picture
        return picture
    }

    // MARK: - Weather

    /// New York's average high and low (°C), and sunrise and sunset (hours), January first.
    private static let climate: [(high: Double, low: Double, sunrise: Double, sunset: Double)] = [
        (4, -3, 7.3, 16.9), (6, -2, 6.8, 17.5), (10, 2, 7.0, 19.0), (17, 7, 6.2, 19.6),
        (22, 12, 5.6, 20.1), (27, 18, 5.4, 20.5), (30, 21, 5.6, 20.4), (29, 20, 6.1, 19.8),
        (25, 16, 6.6, 19.0), (18, 10, 7.1, 18.2), (12, 5, 6.7, 16.7), (7, 0, 7.2, 16.5),
    ]

    /// What a day like `day` would have had at `minute`: the same for every entry of the day, since
    /// it's worked out from the date. `sky` is the weather an entry speaks of.
    static func weather(on day: Date, minute: Int, sky forced: SampleJournal.Sky?) -> WeatherFetcher.Snapshot {
        let month = Calendar.current.component(.month, from: day)
        let normal = climate[month - 1]
        var generator = SeededGenerator(seed: UInt64(dayNumber(day)) &* 31 &+ 7)
        // A hot day is a clear one, well above the average.
        let warmth = forced == .hot ? 5 : Double.random(in: -4.5...4.5, using: &generator)
        let roll = Double.random(in: 0..<1, using: &generator)
        var sky: SampleJournal.Sky = (forced == .hot ? .clear : forced) ?? { () -> SampleJournal.Sky in
            switch roll {
            case ..<0.30: .clear
            case ..<0.50: .mostlyClear
            case ..<0.68: .partlyCloudy
            case ..<0.80: .cloudy
            case ..<0.86: .drizzle
            case ..<0.95: .rain
            case ..<0.98: (6...8).contains(month) ? .thunderstorms : .heavyRain
            default: .fog
            }
        }()
        let isWet = [.drizzle, .rain, .heavyRain, .thunderstorms, .snow].contains(sky)
        let hour = Double(minute) / 60
        // Coldest before dawn, warmest in the late afternoon.
        let warming = 0.5 - 0.5 * cos((hour - 4.5) / 24 * 2 * .pi)
        var celsius = normal.low + (normal.high - normal.low - (isWet ? 3 : 0)) * warming + warmth
        if sky == .snow {
            celsius = min(celsius, -0.5)
        } else if isWet, celsius < 1 {
            // Too cold for rain: snow in winter, or not that cold after all.
            if [12, 1, 2].contains(month) { sky = .snow } else { celsius = 2 }
        }

        let isNight = hour < normal.sunrise || hour >= normal.sunset
        let (symbol, condition) = switch sky {
        case .clear, .hot: (isNight ? "moon.stars" : "sun.max", "Clear")
        case .mostlyClear: (isNight ? "moon.stars" : "sun.max", "Mostly Clear")
        case .partlyCloudy: (isNight ? "cloud.moon" : "cloud.sun", "Partly Cloudy")
        case .cloudy: ("cloud", "Cloudy")
        case .drizzle: ("cloud.drizzle", "Drizzle")
        case .rain: ("cloud.rain", "Rain")
        case .heavyRain: ("cloud.heavyrain", "Heavy Rain")
        case .thunderstorms: ("cloud.bolt.rain", "Thunderstorms")
        case .snow: ("cloud.snow", "Snow")
        case .fog: ("cloud.fog", "Foggy")
        }
        return WeatherFetcher.Snapshot(symbol: symbol, condition: condition, celsius: (celsius * 10).rounded() / 10)
    }

    // MARK: - Location history

    /// Somewhere the day stayed, from and to in minutes after midnight.
    private struct Stay {
        let place: Place
        var from: Int
        var to: Int
    }

    private static func dayNumber(_ day: Date) -> Int {
        Int((day.timeIntervalSinceReferenceDate / 86_400).rounded())
    }

    private static func distance(_ a: Place, _ b: Place) -> CLLocationDistance {
        CLLocation(latitude: a.latitude, longitude: a.longitude)
            .distance(from: CLLocation(latitude: b.latitude, longitude: b.longitude))
    }

    /// Minutes from one place to another: on foot nearby, by subway across town, by train beyond.
    private static func travel(_ a: Place, _ b: Place) -> Int {
        let kilometers = distance(a, b) / 1000
        return switch kilometers {
        case ..<0.05: 0
        case ..<1.3: max(3, Int(kilometers * 13))
        case ..<25: 12 + Int(kilometers * 3)
        default: 30 + Int(kilometers * 0.75)
        }
    }

    /// An ordinary day of the week, before the journal says otherwise: the office Tuesday to
    /// Thursday, the climbing gym on Mondays, the market and the park at the weekend.
    private static func usual(weekday: Int, using generator: inout SeededGenerator) -> [Stay] {
        func chance(_ probability: Double) -> Bool {
            Double.random(in: 0..<1, using: &generator) < probability
        }
        func around(_ clock: Int, _ spread: Int) -> Int {
            minutes(clock) + Int.random(in: -spread...spread, using: &generator)
        }
        var stays: [Stay] = []
        func stay(_ place: Place, _ from: Int, _ length: Int) {
            stays.append(Stay(place: place, from: from, to: from + length))
        }
        switch weekday {
        case 1, 2, 3:
            let arrive = around(905, 10), leave = around(1750, 25)
            if chance(0.5) {
                let lunch = around(1240, 12)
                stays.append(Stay(place: .office, from: arrive, to: lunch - 4))
                stay(.madisonSquare, lunch, 30)
                stays.append(Stay(place: .office, from: lunch + 34, to: leave))
            } else {
                stays.append(Stay(place: .office, from: arrive, to: leave))
            }
        case 0:
            if chance(0.5) { stay(.cafe, around(840, 10), 30) }
            if chance(0.65) { stay(.climbingGym, around(1830, 10), 100) }
        case 4:
            if chance(0.5) { stay(.cafe, around(900, 15), 35) }
            if chance(0.3) { stay(chance(0.5) ? .williamsburg : .carrollGardens, around(1915, 15), 150) }
        case 5:
            if chance(0.4) { stay(.bagels, around(910, 8), 20) }
            if chance(0.65) { stay(.grandArmyPlaza, around(945, 5), 40) }
            if chance(0.45) { stay(.prospectPark, around(1040, 5), 60) }
            if chance(0.35) {
                stay([Place.brooklynMuseum, .brooklynBridgePark, .dumbo, .carrollGardens].randomElement(using: &generator) ?? .dumbo, around(1430, 20), 105)
            }
        default:
            if chance(0.55) { stay(.prospectPark, around(845, 10), 65) }
            if chance(0.35) { stay(.cafe, around(1015, 8), 45) }
        }
        return stays
    }

    /// Where the day was, minute by minute: the usual, moved aside for the journal's stops and for
    /// wherever an entry was written, with home in between.
    private static func stays(on day: Day, weekday: Int, using generator: inout SeededGenerator) -> [Stay] {
        var template = usual(weekday: weekday, using: &generator)
        var fixed = day.stops.map { stop in
            Stay(place: stop.place, from: minutes(stop.from), to: minutes(stop.from) + stop.minutes)
        }
        // An entry was written where it says it was.
        for draft in day.entries {
            guard let place = draft.place else { continue }
            let time = minutes(draft.time)
            let isThere = { (stay: Stay) in stay.place == place && stay.from <= time && time <= stay.to }
            if fixed.contains(where: isThere) || template.contains(where: isThere) { continue }
            let isOut = (fixed + template).contains { $0.from - 20 < time && time < $0.to + 20 }
            if place == .home, !isOut { continue }
            fixed.append(Stay(place: place, from: max(0, time - (place == .home ? 20 : 40)), to: min(1439, time + 30)))
        }
        // The usual gives way: what's left of it either side of a stop stays, if it's long enough.
        for stop in fixed {
            template = template.flatMap { stay -> [Stay] in
                let pad = max(5, travel(stay.place, stop.place))
                let from = stop.from - pad, to = stop.to + pad
                guard stay.from < to, from < stay.to else { return [stay] }
                return [Stay(place: stay.place, from: stay.from, to: from), Stay(place: stay.place, from: to, to: stay.to)]
                    .filter { $0.to - $0.from >= 20 }
            }
        }
        var all = (template + fixed).sorted { $0.from < $1.from }
        for index in all.indices.dropLast() where all[index].to > all[index + 1].from - travel(all[index].place, all[index + 1].place) {
            all[index].to = all[index + 1].from - travel(all[index].place, all[index + 1].place)
        }
        all.removeAll { $0.to - $0.from < 10 }

        // Home at midnight, home between stops far enough apart, and home again at the end.
        var timeline: [Stay] = []
        var last = Stay(place: .home, from: 0, to: 0)
        for stay in all {
            if stay.place == last.place {
                last.to = stay.to
                continue
            }
            if last.place == .home {
                last.to = max(last.to, stay.from - travel(.home, stay.place))
            } else if stay.place != .home {
                let back = travel(last.place, .home), out = travel(.home, stay.place)
                if stay.from - last.to >= back + out + 30 {
                    timeline.append(last)
                    last = Stay(place: .home, from: last.to + back, to: stay.from - out)
                }
            }
            timeline.append(last)
            last = stay
        }
        if last.place == .home {
            last.to = 1440
        } else {
            timeline.append(last)
            last = Stay(place: .home, from: min(last.to + travel(last.place, .home), 1440), to: 1440)
        }
        timeline.append(last)
        return timeline
    }

    /// A reading every five minutes, as `PlaceTracker` takes them: wandering a few tens of meters
    /// around a place, one now and then well off, strung out along the way between places, and
    /// mostly missing underground.
    private static func samples(on day: Day, upTo limit: Date) -> [LocationSample] {
        var generator = SeededGenerator(seed: UInt64(dayNumber(day.date)))
        let weekday = (Calendar.current.component(.weekday, from: day.date) + 5) % 7
        let timeline = stays(on: day, weekday: weekday, using: &generator)
        var samples: [LocationSample] = []
        for minute in stride(from: 0, to: 1440, by: 5) {
            let time = day.date.addingTimeInterval(Double(minute * 60) + .random(in: -20...20, using: &generator))
            guard time <= limit else { break }
            var latitude: Double, longitude: Double
            var accuracy: Double = ([12, 18, 25, 35, 48, 65] as [Double]).randomElement(using: &generator) ?? 35
            if let stay = timeline.first(where: { $0.from <= minute && minute <= $0.to }) {
                latitude = stay.place.latitude
                longitude = stay.place.longitude
                if Double.random(in: 0..<1, using: &generator) < 0.012 {
                    latitude += 0.003
                    accuracy = 140
                }
            } else if let before = timeline.last(where: { $0.to < minute }),
                      let after = timeline.first(where: { $0.from > minute }) {
                let isUnderground = distance(before.place, after.place) > 2500
                if isUnderground, Double.random(in: 0..<1, using: &generator) < 0.6 { continue }
                let fraction = Double(minute - before.to) / Double(max(after.from - before.to, 1))
                latitude = before.place.latitude + (after.place.latitude - before.place.latitude) * fraction
                longitude = before.place.longitude + (after.place.longitude - before.place.longitude) * fraction
            } else {
                continue
            }
            samples.append(LocationSample(
                time: time,
                latitude: latitude + .random(in: -0.00025...0.00025, using: &generator),
                longitude: longitude + .random(in: -0.0003...0.0003, using: &generator),
                accuracy: accuracy
            ))
        }
        return samples
    }

    private static func writePlaces(_ days: [Day]) {
        let now = Date.now
        for day in days {
            PlaceTracker.replaceSamples(samples(on: day, upTo: now), on: day.date)
        }
    }

    // MARK: - Photos library

    private static let albumTitle = "Today Sample Photos"

    /// Saves the journal's photos to the Photos library, dated and placed as the journal has them,
    /// so the day sheet and the Today widget have photos to show. Only with full access already
    /// allowed (`simctl privacy booted grant photos`): seeding doesn't ask. Once: the album it
    /// keeps them in says they're there.
    private static func addToPhotoLibrary(_ days: [Day]) async {
        guard PHPhotoLibrary.authorizationStatus(for: .readWrite) == .authorized else { return }
        let options = PHFetchOptions()
        options.predicate = NSPredicate(format: "title == %@", albumTitle)
        guard PHAssetCollection.fetchAssetCollections(with: .album, subtype: .albumRegular, options: options).count == 0 else { return }

        nonisolated struct Shot: Sendable {
            let file: URL
            let date: Date
            let latitude: Double
            let longitude: Double
        }
        var shots: [Shot] = []
        func add(_ name: String, on day: Day, at clock: Int?, near entry: Int) {
            guard let photo = SampleJournal.photos[name], inSeason(name, on: day.date),
                  let file = Bundle.main.url(forResource: name, withExtension: "jpg") else { return }
            // While it was there, if the day went there; otherwise a little before the entry.
            let stop = day.stops.first { $0.place == photo.place }
            let minute = clock.map(minutes) ?? stop.map { minutes($0.from) + $0.minutes / 3 + shots.count % 7 } ?? max(entry - 25, 0)
            shots.append(Shot(
                file: file,
                date: day.date.addingTimeInterval(Double(minute * 60 + shots.count * 37 % 60)),
                latitude: photo.place.latitude + Double(shots.count % 5 - 2) * 0.00008,
                longitude: photo.place.longitude + Double(shots.count % 3 - 1) * 0.0001
            ))
        }
        for day in days {
            for draft in day.entries {
                for name in photoNames(in: draft, on: day.date) {
                    add(name, on: day, at: nil, near: minutes(draft.time))
                }
            }
            for snapshot in day.snapshots {
                add(snapshot.photo, on: day, at: snapshot.time, near: 0)
            }
        }
        guard !shots.isEmpty else { return }

        let title = albumTitle, taken = shots
        // Photos runs the changes on a queue of its own.
        try? await PHPhotoLibrary.shared().performChanges { @Sendable in
            let album = PHAssetCollectionChangeRequest.creationRequestForAssetCollection(withTitle: title)
            var added: [PHObjectPlaceholder] = []
            for shot in taken {
                let request = PHAssetCreationRequest.forAsset()
                request.addResource(with: .photo, fileURL: shot.file, options: nil)
                request.creationDate = shot.date
                request.location = CLLocation(latitude: shot.latitude, longitude: shot.longitude)
                if let placeholder = request.placeholderForCreatedAsset { added.append(placeholder) }
            }
            album.addAssets(added as NSArray)
        }
        PhotoLibrary.refreshStatus()
    }
}

/// The same numbers for the same day, so a day's weather and wanderings come out the same however
/// often they're worked out (SplitMix64).
private struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed &* 0x9E37_79B9_7F4A_7C15 &+ 0x1234_5678_9ABC_DEF1
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var value = state
        value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
        value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
        return value ^ (value >> 31)
    }
}

extension ModelContainer {
    /// In-memory container with sample entries, for SwiftUI previews.
    static let preview: ModelContainer = {
        let container = try! ModelContainer(
            for: Entry.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        SampleData.populate(container.mainContext)
        return container
    }()
}
#endif
