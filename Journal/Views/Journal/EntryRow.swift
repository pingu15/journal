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
        let title = entry.title
        let excerpt = entry.excerpt
        let photo = entry.coverPhoto

        EntryRowLayout(
            dateCapTop: dateFont.ascender - dateFont.capHeight,
            textCapTop: (title == nil ? UIFont.sans(.subheadline) : UIFont.sans(.title3, bold: true)).capTopInset,
            hasPhoto: photo != nil
        ) {
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
                } else if title == nil {
                    Text(entry.photos.isEmpty ? "Empty entry" : "Photo")
                        .font(Typography.entryExcerpt)
                        .foregroundStyle(Theme.secondaryText)
                }
                EntryMetaLine(entry: entry)
                    .padding(.top, 2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if let photo {
                PhotoThumbnail(attachment: photo)
            }
        }
        .padding(.vertical, Spacing.xs)
        .contentShape(.rect)
    }

    /// The font of the date column's first line, for lining its cap height up with the text.
    private var dateFont: UIFont {
        switch dateStyle {
        case .day, .dayAndYear: .serif(.title2)
        case .time: .preferredFont(forTextStyle: .caption2)
        }
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

private extension UIFont {
    /// From the top of a line of this font to the top of its capital letters.
    var capTopInset: CGFloat { ascender - capHeight }
}

/// Date, text and cover photo side by side: the date and text with the tops of their letters on
/// one line, and the photo spanning the row's full height.
private struct EntryRowLayout: Layout {
    let dateCapTop: CGFloat
    let textCapTop: CGFloat
    let hasPhoto: Bool

    private let dateSpacing: CGFloat = 16 // Spacing.m
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

        // Cap tops line up at y = line; everything is placed relative to it.
        let textTop = textCapTop
        let line = max(dateCapTop, textTop)
        let date = CGRect(x: 0, y: line - dateCapTop, width: dateSize.width, height: dateSize.height)
        let text = CGRect(
            x: dateSize.width + dateSpacing, y: line - textTop,
            width: textWidth, height: textDimensions.height
        )
        // The photo spans the row's full height, top to bottom.
        let height = max(date.maxY, text.maxY, minPhotoHeight)
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
