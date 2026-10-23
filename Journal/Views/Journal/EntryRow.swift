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
        HStack(alignment: .top, spacing: Spacing.s) {
            HStack(alignment: .firstTextBaseline, spacing: Spacing.m) {
                dateColumn

                VStack(alignment: .leading, spacing: Spacing.xs) {
                    let title = entry.title
                    let excerpt = entry.excerpt
                    // A title only when the entry's first line is in the Title style.
                    if let title {
                        Text(title)
                            .font(Typography.entryTitle)
                            .foregroundStyle(Theme.primaryText)
                            .lineLimit(1)
                    }
                    if !excerpt.isEmpty {
                        Text(excerpt)
                            .font(Typography.entryExcerpt)
                            .foregroundStyle(Theme.secondaryText)
                            .lineLimit(title == nil ? 3 : 2)
                    } else if title == nil {
                        Text(entry.photos.isEmpty ? "Empty entry" : "Photo")
                            .font(Typography.entryExcerpt)
                            .foregroundStyle(Theme.secondaryText)
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
        .padding(.vertical, Spacing.xs)
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
