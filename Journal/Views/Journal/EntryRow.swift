import SwiftUI

/// One entry in a list, with a day column beside it unless `dateStyle` is `.none`.
struct EntryRow: View {
    enum DateStyle {
        /// Day number over weekday (timeline).
        case day
        /// Day number over year (On this day).
        case dayAndYear
        /// Day number over month (a place's entries, which span months).
        case dayAndMonth
        /// No day column (a single calendar day: the meta line has the time).
        case none
    }

    let entry: Entry
    var dateStyle: DateStyle = .day
    /// A red line under the rest, as part of the row's text (the days a deleted entry has left).
    var warning: String?

    var body: some View {
        let title = entry.title
        let excerpt = entry.excerpt
        let photo = entry.coverPhoto

        EntryRowLayout(hasDate: dateStyle != .none, hasPhoto: photo != nil) {
            dateColumn

            VStack(alignment: .leading, spacing: Spacing.xs) {
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
                } else if title == nil && entry.photos.isEmpty {
                    // A photo-only entry needs no stand-in text: its thumbnail shows beside the row.
                    Text("No content yet.")
                        .font(Typography.entryExcerpt)
                        .foregroundStyle(Theme.secondaryText)
                }
                EntryMetaLine(entry: entry)
                    .padding(.top, 2)
                if let warning {
                    MetaLabel(warning, color: Theme.destructive)
                        .padding(.top, 2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if let photo {
                PhotoThumbnail(attachment: photo)
            }
        }
        .padding(.vertical, Spacing.xs)
        .contentShape(.rect)
    }

    /// What goes under the day number.
    private var dayCaption: String {
        switch dateStyle {
        case .dayAndYear: entry.createdAt.formatted(.dateTime.year())
        case .dayAndMonth: entry.createdAt.formatted(.dateTime.month(.abbreviated))
        default: entry.createdAt.formatted(.dateTime.weekday(.abbreviated))
        }
    }

    @ViewBuilder
    private var dateColumn: some View {
        switch dateStyle {
        case .day, .dayAndYear, .dayAndMonth:
            VStack(spacing: 2) {
                Text(entry.createdAt.formatted(.dateTime.day()))
                    .font(Typography.dayNumber)
                    .foregroundStyle(Theme.primaryText)
                MetaLabel(dayCaption)
            }
            .frame(width: 44)
        case .none:
            // Still a subview: the layout places the column by position.
            Color.clear.frame(width: 0, height: 0)
        }
    }
}

/// Date, text and cover photo side by side: the date centered vertically in the row, and the
/// photo spanning the row's full height.
private struct EntryRowLayout: Layout {
    let hasDate: Bool
    let hasPhoto: Bool

    private var dateSpacing: CGFloat { hasDate ? 16 : 0 } // Spacing.m
    private let photoSpacing: CGFloat = 8 // Spacing.s
    private let photoWidth: CGFloat = 72
    private let minPhotoHeight: CGFloat = 56

    private struct Frames {
        var date: CGRect, text: CGRect, photo: CGRect
        var size: CGSize { CGSize(width: max(text.maxX, photo.maxX), height: max(date.maxY, text.maxY, photo.maxY)) }
    }

    private func frames(width: CGFloat, subviews: Subviews) -> Frames {
        let dateSize = subviews[0].sizeThatFits(.unspecified)
        let textWidth = max(0, width - dateSize.width - dateSpacing - (hasPhoto ? photoWidth + photoSpacing : 0))
        let textDimensions = subviews[1].dimensions(in: ProposedViewSize(width: textWidth, height: nil))

        let text = CGRect(x: dateSize.width + dateSpacing, y: 0, width: textWidth, height: textDimensions.height)
        let height = max(dateSize.height, text.height, hasPhoto ? minPhotoHeight : 0)
        let date = CGRect(x: 0, y: (height - dateSize.height) / 2, width: dateSize.width, height: dateSize.height)
        // The photo spans the row's full height, top to bottom.
        let photo = hasPhoto
            ? CGRect(x: text.maxX + photoSpacing, y: 0, width: photoWidth, height: height)
            : CGRect(x: text.maxX, y: 0, width: 0, height: 0)
        return Frames(date: date, text: text, photo: photo)
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 360
        return CGSize(width: width, height: frames(width: width, subviews: subviews).size.height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let f = frames(width: bounds.width, subviews: subviews)
        func place(_ index: Int, _ rect: CGRect) {
            guard index < subviews.count else { return }
            subviews[index].place(
                at: CGPoint(x: bounds.minX + rect.minX, y: bounds.minY + rect.minY),
                proposal: ProposedViewSize(rect.size)
            )
        }
        place(0, f.date)
        place(1, f.text)
        if hasPhoto { place(2, f.photo) }
    }
}
