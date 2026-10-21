import SwiftUI

/// One entry in a list. `dateStyle` picks between a day column (timeline) and a time (calendar day).
struct EntryRow: View {
    enum DateStyle {
        /// Day number over weekday (timeline).
        case day
        /// Day number over year (On this day).
        case dayAndYear
        /// Time only (a single calendar day).
        case time
    }

    let entry: Entry
    var dateStyle: DateStyle = .day

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.m) {
            HStack(alignment: .firstTextBaseline, spacing: Spacing.m) {
                dateColumn

                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text(entry.title)
                        .font(Typography.entryTitle)
                        .foregroundStyle(Theme.primaryText)
                        .lineLimit(1)
                    if !entry.excerpt.isEmpty {
                        Text(entry.excerpt)
                            .font(Typography.excerpt)
                            .foregroundStyle(Theme.secondaryText)
                            .lineLimit(2)
                    }
                    EntryMetaLine(entry: entry)
                        .padding(.top, 2)
                }
            }
            Spacer(minLength: 0)
            if let photo = entry.coverPhoto {
                PhotoThumbnail(attachment: photo)
                    .padding(.top, 4)
            }
        }
        .padding(.vertical, Spacing.s)
        .contentShape(.rect)
    }

    @ViewBuilder
    private var dateColumn: some View {
        switch dateStyle {
        case .day, .dayAndYear:
            VStack(spacing: 2) {
                Text(entry.createdAt.formatted(.dateTime.day()))
                    .font(Typography.dayNumber)
                    .foregroundStyle(Theme.primaryText)
                MetaLabel(dateStyle == .day
                          ? entry.createdAt.formatted(.dateTime.weekday(.abbreviated))
                          : entry.createdAt.formatted(.dateTime.year()))
            }
            .frame(width: 44)
        case .time:
            MetaLabel(entry.createdAt.formatted(date: .omitted, time: .shortened))
                .frame(width: 64, alignment: .leading)
        }
    }
}
