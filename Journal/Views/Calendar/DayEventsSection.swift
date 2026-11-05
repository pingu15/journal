import EventKit
import SwiftUI

/// The day sheet's Events section: the day's events from the user's calendars, laid out like the
/// Places section's stays (its title, then its location, with its times beside them). Calendar access is asked
/// for from a row the first time.
struct DayEventsSection: View {
    let day: Date

    @Environment(\.openURL) private var openURL
    @State private var status = CalendarEvents.status
    @State private var events: [EKEvent]

    init(day: Date) {
        self.day = day
        // Here, not on appear: the day slides in whole.
        _events = State(initialValue: CalendarEvents.events(on: day))
    }

    var body: some View {
        Section {
            switch status {
            case .notDetermined:
                // iOS's Settings has no switch for Journal until it has asked once.
                AccessOffNote("Calendar access") {
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
                    ForEach(events, id: \.calendarItemIdentifier) { event in
                        row(event)
                    }
                }
            default:
                AccessOffNote("Calendar access") { openURL(.appSettings) }
            }
        } header: {
            MetaLabel("Events", systemImage: "calendar")
        }
    }

    /// Its title over its location (when it has one), with its times beside them.
    private func row(_ event: EKEvent) -> some View {
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
        .accessibilityElement(children: .combine)
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
