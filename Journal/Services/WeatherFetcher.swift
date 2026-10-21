import CoreLocation
import OSLog
import WeatherKit

/// Looks up the weather at a place and moment using WeatherKit.
///
/// Requires the WeatherKit capability on the App ID and a signed build;
/// without it requests fail and the entry simply shows no weather.
enum WeatherFetcher {
    struct Snapshot: Sendable {
        let symbol: String
        let condition: String
        let celsius: Double
    }

    private static let logger = Logger(subsystem: "com.maxsun.journal", category: "weather")

    static func snapshot(at location: CLLocation, on date: Date) async -> Snapshot? {
        let service = WeatherService.shared
        do {
            // Within the hour: current conditions. Otherwise: the nearest hour (historical or forecast).
            if abs(date.timeIntervalSinceNow) < 45 * 60 {
                let current = try await service.weather(for: location, including: .current)
                return Snapshot(
                    symbol: current.symbolName,
                    condition: current.condition.description,
                    celsius: current.temperature.converted(to: .celsius).value
                )
            }
            let hours = try await service.weather(
                for: location,
                including: .hourly(startDate: date.addingTimeInterval(-90 * 60), endDate: date.addingTimeInterval(90 * 60))
            )
            guard let nearest = hours.forecast.min(by: {
                abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date))
            }) else { return nil }
            return Snapshot(
                symbol: nearest.symbolName,
                condition: nearest.condition.description,
                celsius: nearest.temperature.converted(to: .celsius).value
            )
        } catch {
            logger.error("Weather lookup failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }
}
