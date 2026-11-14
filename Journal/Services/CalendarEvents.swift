import EventKit
import Foundation

/// Read-only access to the user's calendars, for showing a day's events.
enum CalendarEvents {
    private static let store = EKEventStore()

    /// Asked once and kept: iOS answers over IPC (6–8 ms on an iPhone 12), and the day sheet asks for
    /// every page it builds. Asked again whenever the app becomes active (it may have been changed in
    /// Settings) and after the prompt.
    private(set) static var status = EKEventStore.authorizationStatus(for: .event)

    static func refreshStatus() {
        status = EKEventStore.authorizationStatus(for: .event)
    }

    static var canRead: Bool { status == .fullAccess }

    /// Asks for access if it hasn't been asked yet; returns whether events can be read.
    static func requestAccess() async -> Bool {
        guard status == .notDetermined else { return canRead }
        _ = try? await SystemPrompts.shared.during {
            try await store.requestFullAccessToEvents()
        }
        refreshStatus()
        fetched = [:]
        return canRead
    }

    /// Days already fetched (the day sheet rebuilds its sections on every update); all dropped when
    /// the calendars change.
    private static var fetched: [Date: [EKEvent]] = [:]
    private static let changes: NSObjectProtocol = NotificationCenter.default.addObserver(
        forName: .EKEventStoreChanged, object: store, queue: .main
    ) { _ in
        MainActor.assumeIsolated { fetched = [:] }
    }

    /// The events on `day`, all-day ones first, then by when they start.
    static func events(on day: Date) -> [EKEvent] {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: day)
        guard canRead, let end = calendar.date(byAdding: .day, value: 1, to: start) else { return [] }
        _ = changes
        if let events = fetched[start] { return events }
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        let events = store.events(matching: predicate).sorted {
            ($0.isAllDay ? 0 : 1, $0.startDate) < ($1.isAllDay ? 0 : 1, $1.startDate)
        }
        fetched[start] = events
        return events
    }
}
