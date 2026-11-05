import CoreLocation
import EventKit
import SwiftUI

/// The day sheet's Events section: the day's events from the user's calendars, laid out like the
/// Places section's stays (its title, then its location, with its times beside them). Like a stay,
/// tapping one from the calendar starts an entry at its time and place; from an entry, it asks
/// whether to take its time, its place, or both (just its time when it has no place).
struct DayEventsSection: View {
    let day: Date
    let action: Action

    enum Action {
        /// From an entry: the event's place and/or time for it.
        case setOnEntry((_ place: EventPlace?, _ time: Date?) -> Void)
        /// From the calendar: a new entry at the event's time, and its place when it has one.
        case newEntry((_ place: EventPlace?, _ time: Date) -> Void)
    }

    @Environment(\.openURL) private var openURL
    @State private var status = CalendarEvents.status
    @State private var events: [EKEvent]
    /// An event tapped from an entry, while it's asked what to take from it.
    @State private var choosing: String?

    init(day: Date, action: Action) {
        self.day = day
        self.action = action
        // Here, not on appear: the day slides in whole.
        _events = State(initialValue: CalendarEvents.events(on: day))
    }

    var body: some View {
        Section {
            switch status {
            case .notDetermined:
                AccessOffNote("Calendar access", canAsk: true) {
                    Task {
                        _ = await CalendarEvents.requestAccess()
                        status = CalendarEvents.status
                        events = CalendarEvents.events(on: day)
                    }
                }
            case .fullAccess:
                if events.isEmpty {
                    Text("No events on this day.")
                        .font(Typography.note)
                        .foregroundStyle(Theme.secondaryText)
                } else {
                    ForEach(events, id: \.rowID) { event in
                        row(event)
                    }
                }
            default:
                // Refused before: iOS won't ask again, so its Settings it is.
                AccessOffNote("Calendar access", canAsk: false) { openURL(.appSettings) }
            }
        } header: {
            MetaLabel("Events", systemImage: "calendar")
        }
    }

    /// Its title over its location (when it has one), with its times beside them.
    private func row(_ event: EKEvent) -> some View {
        let hasPlace = location(of: event) != nil
        return Button {
            tap(event)
        } label: {
            HStack(spacing: Spacing.s) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(event.title?.isEmpty == false ? event.title : "New Event")
                        .font(Typography.body)
                        .foregroundStyle(Theme.primaryText)
                        .lineLimit(1)
                    if let location = location(of: event) {
                        Text(location)
                            .font(Typography.detail)
                            .foregroundStyle(Theme.secondaryText)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: Spacing.s)
                Text(times(of: event))
                    .font(Typography.detail)
                    .foregroundStyle(Theme.secondaryText)
                    .layoutPriority(1)
            }
            .contentShape(.rect)
            .accessibilityElement(children: .combine)
        }
        // Pressed like the stays above it.
        .buttonStyle(TapPressStyle(scale: TapPressStyle.rowScale))
        .accessibilityHint(isNewEntry ? "Starts an entry at this event's time" : "Sets this event's time or place on the entry")
        // On each row, so it comes from the row tapped.
        .confirmationDialog(
            "Add to Entry",
            isPresented: Binding(get: { choosing == event.rowID }, set: { if !$0 { choosing = nil } }),
            titleVisibility: .hidden
        ) {
            if hasPlace {
                Button("Location Only") { set(event, place: true, time: false) }
                Button("Time Only") { set(event, place: false, time: true) }
                Button("Location and Time") { set(event, place: true, time: true) }
            } else {
                Button("Use Event's Time") { set(event, place: false, time: true) }
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    private var isNewEntry: Bool {
        if case .newEntry = action { true } else { false }
    }

    private func tap(_ event: EKEvent) {
        switch action {
        case .setOnEntry:
            choosing = event.rowID
        case .newEntry(let start):
            Task { start(await place(of: event), event.startDate) }
        }
    }

    private func set(_ event: EKEvent, place usePlace: Bool, time useTime: Bool) {
        guard case .setOnEntry(let set) = action else { return }
        Task {
            let place = usePlace ? await place(of: event) : nil
            set(place, useTime ? event.startDate : nil)
        }
    }

    /// Where the event is: the calendar's own point when it has one, else its address looked up.
    private func place(of event: EKEvent) async -> EventPlace? {
        guard let name = location(of: event) else { return nil }
        if let point = event.structuredLocation?.geoLocation {
            return EventPlace(name: event.structuredLocation?.title.flatMap { $0.isEmpty ? nil : $0 } ?? name, coordinate: point.coordinate)
        }
        guard let address = event.location,
              let found = try? await CLGeocoder().geocodeAddressString(address).first?.location
        else { return nil }
        return EventPlace(name: name, coordinate: found.coordinate)
    }

    /// Its first line: a location is often a name over a full address.
    private func location(of event: EKEvent) -> String? {
        let line = event.location?.split(whereSeparator: \.isNewline).first.map {
            $0.trimmingCharacters(in: .whitespaces)
        }
        return line?.isEmpty == false ? line : nil
    }

    private func times(of event: EKEvent) -> String {
        if event.isAllDay { return "All day" }
        return (event.startDate..<max(event.startDate, event.endDate)).formatted(.interval.hour().minute())
    }
}

/// An event's place, for an entry.
struct EventPlace {
    let name: String
    let coordinate: CLLocationCoordinate2D
}

private extension EKEvent {
    /// One row per occurrence: a repeating event's occurrences share their identifier.
    var rowID: String { "\(calendarItemIdentifier)@\(startDate.timeIntervalSinceReferenceDate)" }
}
