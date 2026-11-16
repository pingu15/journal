import UIKit

/// Photos on consecutive lines, with no text between them, shown as one collage. In the text it's a
/// single character standing for all of them; it's written back as the same photo tokens, one per
/// line, so the stored Markdown doesn't change.
nonisolated final class CollageAttachment: NSTextAttachment {
    let photos: [ImageAttachment]

    var imageIDs: [UUID] { photos.map(\.imageID) }

    init(photos: [ImageAttachment]) {
        self.photos = photos
        super.init(data: nil, ofType: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    /// The hairline between tiles, as in the day sheet's photos: the tiles read as one picture.
    static let gap: CGFloat = 2
    /// A row's height over the collage's width (a pair side by side, or a trio).
    private static let rowAspect: CGFloat = 0.6

    // MARK: Layout

    /// Laid out like the day sheet's photos: pairs side by side, and with an odd count the last
    /// three as one row, the first of them tall on the left and the other two stacked beside it.
    /// Each tile is filled (cropped around its middle), so the collage is one even block.
    static func layout(count: Int, width: CGFloat) -> (frames: [CGRect], height: CGFloat) {
        guard count > 0, width > 0 else { return ([], 0) }
        let rowHeight = (width * rowAspect).rounded()
        let half = ((width - gap) / 2).rounded()
        let right = width - half - gap
        var frames: [CGRect] = []
        var y: CGFloat = 0
        var remaining = count
        while remaining > 0 {
            switch remaining {
            case 1:
                frames.append(CGRect(x: 0, y: y, width: width, height: rowHeight))
                remaining = 0
            case 3:
                let upper = ((rowHeight - gap) / 2).rounded()
                frames.append(CGRect(x: 0, y: y, width: half, height: rowHeight))
                frames.append(CGRect(x: half + gap, y: y, width: right, height: upper))
                frames.append(CGRect(x: half + gap, y: y + upper + gap, width: right, height: rowHeight - upper - gap))
                remaining = 0
            default:
                frames.append(CGRect(x: 0, y: y, width: half, height: rowHeight))
                frames.append(CGRect(x: half + gap, y: y, width: right, height: rowHeight))
                remaining -= 2
            }
            y += rowHeight + gap
        }
        return (frames, y - gap)
    }

    private var laidOut: (width: CGFloat, frames: [CGRect], height: CGFloat)?

    private func frames(for width: CGFloat) -> (frames: [CGRect], height: CGFloat) {
        if let laidOut, laidOut.width == width { return (laidOut.frames, laidOut.height) }
        let result = Self.layout(count: photos.count, width: width)
        laidOut = (width, result.frames, result.height)
        return result
    }

    /// The photo under `point`, in the collage's own coordinates (a tap in a gap picks the nearest).
    func imageID(at point: CGPoint, width: CGFloat) -> UUID? {
        let frames = frames(for: width).frames
        let tolerance = Self.gap
        guard let index = frames.firstIndex(where: { $0.insetBy(dx: -tolerance, dy: -tolerance).contains(point) }) else {
            return nil
        }
        return photos[index].imageID
    }

    // MARK: Drawing

    /// Prepared at the exact size it's drawn, as `ImageAttachment` does, so typing nearby stays smooth.
    private var displayed: (size: CGSize, image: UIImage)?

    private func displayImage(for size: CGSize) -> UIImage? {
        guard size.width > 0, size.height > 0 else { return nil }
        if let displayed, displayed.size == size { return displayed.image }
        let frames = frames(for: size.width).frames
        let format = UIGraphicsImageRendererFormat()
        format.scale = ImageAttachment.displayScale
        format.preferredRange = .standard
        // The single photo's corner, on the collage as a whole: the tiles inside meet square.
        let radius = size.width * 0.025
        let result = UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIBezierPath(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: radius).addClip()
            for (photo, frame) in zip(photos, frames) {
                guard let image = photo.image, image.size.width > 0, image.size.height > 0 else { continue }
                context.cgContext.saveGState()
                context.cgContext.clip(to: frame)
                // Aspect-fill around the middle.
                let fill = max(frame.width / image.size.width, frame.height / image.size.height)
                let drawn = CGSize(width: image.size.width * fill, height: image.size.height * fill)
                image.draw(in: CGRect(x: frame.midX - drawn.width / 2, y: frame.midY - drawn.height / 2,
                                      width: drawn.width, height: drawn.height))
                context.cgContext.restoreGState()
            }
        }
        displayed = (size, result)
        return result
    }

    private func displayBounds(for available: CGFloat) -> CGRect {
        let width = max(available - 1, 40)
        return CGRect(x: 0, y: 0, width: width, height: frames(for: width).height)
    }

    // TextKit 2
    override func image(
        for bounds: CGRect,
        attributes: [NSAttributedString.Key: Any] = [:],
        location: any NSTextLocation,
        textContainer: NSTextContainer?
    ) -> UIImage? {
        displayImage(for: bounds.size)
    }

    // TextKit 1
    override func image(forBounds imageBounds: CGRect, textContainer: NSTextContainer?, characterIndex charIndex: Int) -> UIImage? {
        displayImage(for: imageBounds.size)
    }

    // TextKit 2
    override func attachmentBounds(
        for attributes: [NSAttributedString.Key: Any],
        location: any NSTextLocation,
        textContainer: NSTextContainer?,
        proposedLineFragment: CGRect,
        position: CGPoint
    ) -> CGRect {
        displayBounds(for: proposedLineFragment.width)
    }

    // TextKit 1
    override func attachmentBounds(
        for textContainer: NSTextContainer?,
        proposedLineFragment lineFrag: CGRect,
        glyphPosition position: CGPoint,
        characterIndex charIndex: Int
    ) -> CGRect {
        displayBounds(for: lineFrag.width)
    }
}

nonisolated extension MarkdownDocument {
    /// The photos a paragraph holds, when it holds nothing else (and isn't a title, heading or quote).
    private static func photosOnly(_ text: NSAttributedString, content: NSRange) -> [ImageAttachment]? {
        guard content.length > 0, text.blockStyle(at: content.location) == nil else { return nil }
        var photos: [ImageAttachment] = []
        var onlyPhotos = true
        text.enumerateAttribute(.attachment, in: content) { value, _, stop in
            switch value {
            case let photo as ImageAttachment: photos.append(photo)
            case let collage as CollageAttachment: photos.append(contentsOf: collage.photos)
            default: onlyPhotos = false; stop.pointee = true
            }
        }
        return onlyPhotos ? photos : nil
    }

    /// Joins photos on consecutive lines (or side by side on one) into a collage, and returns each
    /// replacement made (its original range and new length), first to last.
    @discardableResult
    static func collapsePhotoRuns(in text: NSMutableAttributedString) -> [(range: NSRange, length: Int)] {
        let ns = text.string as NSString
        guard ns.range(of: "\u{FFFC}").location != NSNotFound else { return [] }

        var runs: [(range: NSRange, photos: [ImageAttachment], paragraphs: Int)] = []
        var current: (range: NSRange, photos: [ImageAttachment], paragraphs: Int)?
        ns.enumerateSubstrings(in: NSRange(location: 0, length: ns.length), options: [.byParagraphs, .substringNotRequired]) { _, content, _, _ in
            if let photos = photosOnly(text, content: content) {
                if let run = current {
                    current = (NSUnionRange(run.range, content), run.photos + photos, run.paragraphs + 1)
                } else {
                    current = (content, photos, 1)
                }
            } else {
                if let run = current { runs.append(run) }
                current = nil
            }
        }
        if let run = current { runs.append(run) }

        var edits: [(range: NSRange, length: Int)] = []
        for run in runs.reversed() where run.photos.count > 1 {
            // Already a single collage of exactly these photos.
            if run.range.length == 1, let collage = text.attribute(.attachment, at: run.range.location, effectiveRange: nil) as? CollageAttachment,
               collage.photos.count == run.photos.count {
                continue
            }
            var attributes = text.attributes(at: run.range.location, effectiveRange: nil)
            attributes[.attachment] = CollageAttachment(photos: run.photos)
            text.replaceCharacters(in: run.range, with: NSAttributedString(string: "\u{FFFC}", attributes: attributes))
            edits.insert((run.range, 1), at: 0)
        }
        return edits
    }

    /// Where `location` ends up after `edits` (as returned by `collapsePhotoRuns`). A location
    /// inside a replaced run moves to just after its collage.
    static func location(_ location: Int, after edits: [(range: NSRange, length: Int)]) -> Int {
        var delta = 0
        for edit in edits {
            if location >= NSMaxRange(edit.range) {
                delta += edit.length - edit.range.length
            } else if location > edit.range.location {
                return edit.range.location + delta + edit.length
            } else {
                break
            }
        }
        return location + delta
    }
}
