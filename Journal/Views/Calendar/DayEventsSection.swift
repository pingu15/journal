import EventKit
import SwiftUI

/// The day sheet's Events section: the day's events from the user's calendars, laid out like the
/// Places section's stays (name, then times, with how long beside them). Calendar access is asked
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
                Button {
                    Task {
                        _ = await CalendarEvents.requestAccess()
                        status = CalendarEvents.status
                        events = CalendarEvents.events(on: day)
                    }
                } label: {
                    AccessPromptLabel("Show events from your calendar", systemImage: "calendar")
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
                Button {
                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                } label: {
                    Text("Calendar access is off for Journal. ") + Text("Open Settings").underline()
                }
                .font(Typography.note)
                .foregroundStyle(Theme.secondaryText)
                .multilineTextAlignment(.leading)
            }
        } header: {
            MetaLabel("Events", systemImage: "calendar")
        }
    }

    private func row(_ event: EKEvent) -> some View {
        HStack(spacing: Spacing.s) {
            VStack(alignment: .leading, spacing: 2) {
                Text(event.title?.isEmpty == false ? event.title : "New Event")
                    .font(Typography.body)
                    .foregroundStyle(Theme.primaryText)
                    .lineLimit(1)
                Text(times(of: event))
                    .font(Typography.detail)
                    .foregroundStyle(Theme.secondaryText)
            }
            Spacer(minLength: Spacing.s)
            if !event.isAllDay {
                Text(Duration.seconds(event.endDate.timeIntervalSince(event.startDate)).formatted(.units(allowed: [.hours, .minutes], width: .abbreviated)))
                    .font(Typography.detail)
                    .foregroundStyle(Theme.secondaryText)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func times(of event: EKEvent) -> String {
        if event.isAllDay { return "All day" }
        return (event.startDate..<max(event.startDate, event.endDate)).formatted(.interval.hour().minute())
    }
}
