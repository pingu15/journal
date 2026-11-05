#if DEBUG
import Foundation
import SwiftData

enum SampleData {
    private static let texts = [
        "Morning pages\nWoke before the alarm. The light came in sideways and for once I didn't reach for my phone.",
        "On finishing things\nStarting is easy. The **middle** is where everything quietly asks to be abandoned.",
        "Walk by the river\nCold, bright. Saw a heron standing so still it looked *carved*.",
        "## Notes from the week\n- Too many meetings\n- Not enough making\n- [x] Protect the mornings\n- [ ] Call the landlord",
        "Dinner with Sam\nLong conversation about moving cities. Neither of us will, probably, but it was nice to imagine.",
        "Restless\nCouldn't settle into anything today. Cleaned the kitchen instead, which helped more than expected.",
        "Small win\nShipped the thing I'd been putting off for a month. It took forty minutes.",
        "Rain\nRead most of the afternoon.\n> The kind of day that doesn't ask anything of you.",
        "Running again\nFirst run in weeks. Slow, but the legs remembered.",
        "Gratitude\n1. Coffee\n2. The window seat\n3. The friend who texted out of nowhere",
        "Hard day\nSaid something sharp I didn't mean. Apologised. Still turning it over.",
        "Sunday\nFarmers market, then nothing at all. ~~Errands~~ Perfect.",
    ]

    private static let places: [(name: String, latitude: Double, longitude: Double)] = [
        ("Mission District", 37.7599, -122.4148),
        ("Golden Gate Park", 37.7694, -122.4862),
        ("Home", 37.7849, -122.4294),
    ]

    private static let weather: [(symbol: String, condition: String, celsius: Double)] = [
        ("sun.max", "Clear", 19),
        ("cloud.sun", "Partly Cloudy", 16),
        ("cloud.fog", "Foggy", 13),
        ("cloud.rain", "Rain", 12),
    ]

    /// Fills an empty store with ~4 months of varied entries, plus one from a year ago today.
    static func populate(_ context: ModelContext) {
        let existing = (try? context.fetchCount(FetchDescriptor<Entry>())) ?? 0
        guard existing == 0 else { return }

        let calendar = Calendar.current
        let skipDays: Set<Int> = [2, 5, 9, 10, 16, 17, 18, 23, 30, 31, 37, 44, 45, 52, 58, 59, 60, 66, 73, 80, 81, 88, 95, 101, 102, 109, 115]
        for daysAgo in 0..<120 where !skipDays.contains(daysAgo) {
            guard let day = calendar.date(byAdding: .day, value: -daysAgo, to: .now),
                  let date = calendar.date(bySettingHour: 7 + (daysAgo * 5) % 15, minute: (daysAgo * 13) % 60, second: 0, of: day)
            else { continue }
            // Vary length so the activity heatmap has some texture.
            let extra = String(repeating: "\n\nKept thinking about it on the walk home, turning the same few ideas over until they softened into something I could actually use.", count: daysAgo % 4 * (daysAgo % 3))
            let entry = Entry(text: texts[daysAgo % texts.count] + extra, createdAt: date)
            if daysAgo % 3 != 1 {
                let place = places[daysAgo % places.count]
                entry.placeName = place.name
                entry.latitude = place.latitude
                entry.longitude = place.longitude
                let conditions = weather[daysAgo % weather.count]
                entry.weatherSymbol = conditions.symbol
                entry.weatherCondition = conditions.condition
                entry.temperatureCelsius = conditions.celsius
            }
            context.insert(entry)
        }

        if let lastYear = calendar.date(byAdding: .year, value: -1, to: .now) {
            let entry = Entry(text: "First entry\nStarting a journal, again. This time it's going to stick.", createdAt: lastYear)
            context.insert(entry)
        }
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
