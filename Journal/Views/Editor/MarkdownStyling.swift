import UIKit

// MARK: - Inline images

/// An embedded photo inside the editor. Serialized back to `![](image:<imageID>)`.
nonisolated final class ImageAttachment: NSTextAttachment {
    let imageID: UUID

    /// Rounded, downsized renders, so reopening an entry doesn't redraw every photo.
    // NSCache is internally synchronized.
    nonisolated(unsafe) private static let renderCache = NSCache<NSUUID, UIImage>()

    init(imageID: UUID, image: UIImage?) {
        self.imageID = imageID
        super.init(data: nil, ofType: nil)
        self.image = image.map { Self.rendered($0, id: imageID) }
    }

    /// Builds an attachment from the cache alone; nil if this photo hasn't been rendered yet.
    static func cached(imageID: UUID) -> ImageAttachment? {
        guard let image = renderCache.object(forKey: imageID as NSUUID) else { return nil }
        let attachment = ImageAttachment(imageID: imageID, image: nil)
        attachment.image = image
        return attachment
    }

    private static func rendered(_ image: UIImage, id: UUID) -> UIImage {
        if let cached = renderCache.object(forKey: id as NSUUID) { return cached }
        let result = rounded(image)
        renderCache.setObject(result, forKey: id as NSUUID)
        return result
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
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

    /// Fill the measure, but keep tall portraits from swallowing the page.
    private func displayBounds(for available: CGFloat) -> CGRect {
        let width = max(available - 1, 40)
        guard let size = image?.size, size.width > 0, size.height > 0 else {
            return CGRect(x: 0, y: 0, width: width, height: width * 0.66)
        }
        var displayWidth = width
        var displayHeight = width * size.height / size.width
        let maxHeight = width * 1.25
        if displayHeight > maxHeight {
            displayHeight = maxHeight
            displayWidth = displayHeight * size.width / size.height
        }
        return CGRect(x: 0, y: 0, width: displayWidth, height: displayHeight)
    }

    private static func rounded(_ image: UIImage) -> UIImage {
        let scale = min(1, 1400 / max(image.size.width, 1))
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            let rect = CGRect(origin: .zero, size: size)
            UIBezierPath(roundedRect: rect, cornerRadius: size.width * 0.025).addClip()
            image.draw(in: rect)
        }
    }
}

// MARK: - Markdown ⇄ attributed text

enum MarkdownDocument {
    /// Replaces image tokens with inline attachments; everything else stays as literal Markdown.
    static func attributed(from markdown: String, image: (UUID) -> UIImage?) -> NSMutableAttributedString {
        let result = NSMutableAttributedString(string: markdown)
        let ns = markdown as NSString
        let matches = Markdown.imagePattern.matches(in: markdown, range: NSRange(location: 0, length: ns.length))
        for match in matches.reversed() {
            guard let id = UUID(uuidString: ns.substring(with: match.range(at: 1))) else { continue }
            let attachment = ImageAttachment.cached(imageID: id) ?? ImageAttachment(imageID: id, image: image(id))
            result.replaceCharacters(in: match.range, with: NSAttributedString(attachment: attachment))
        }
        return result
    }

    static func markdown(from attributed: NSAttributedString) -> String {
        var output = ""
        let ns = attributed.string as NSString
        attributed.enumerateAttribute(.attachment, in: NSRange(location: 0, length: attributed.length)) { value, range, _ in
            if let attachment = value as? ImageAttachment {
                output += String(repeating: Markdown.imageToken(attachment.imageID), count: range.length)
            } else {
                output += ns.substring(with: range).replacingOccurrences(of: "\u{FFFC}", with: "")
            }
        }
        return output
    }
}

// MARK: - Live styling

/// Styles literal Markdown in place: syntax stays visible but recedes; the content takes the style.
enum MarkdownStyler {
    private static func regex(_ pattern: String, _ options: NSRegularExpression.Options = []) -> NSRegularExpression {
        try! NSRegularExpression(pattern: pattern, options: options)
    }

    // Block-level (matched against a single line)
    static let headingLine = regex(#"^(#{1,3})[ \t]+"#)
    static let quoteLine = regex(#"^>[ \t]?"#)
    static let checklistLine = regex(#"^[ \t]*[-*+][ \t]+\[([ xX])\][ \t]+"#)
    static let bulletLine = regex(#"^[ \t]*[-*+][ \t]+"#)
    static let numberedLine = regex(#"^[ \t]*\d+[.)][ \t]+"#)
    static let ruleLine = regex(#"^[ \t]*([-*_])([ \t]*\1){2,}[ \t]*$"#)
    /// Any list/quote prefix that Return should continue: indent, marker, and number parts.
    static let listContinuation = regex(#"^([ \t]*)([-*+][ \t]+\[[ xX]\][ \t]+|[-*+][ \t]+|(\d+)([.)])[ \t]+|>[ \t]?)"#)

    // Inline (matched across the document)
    private static let bold = regex(#"(\*\*|__)(?=\S)(.+?)(?<=\S)\1"#)
    private static let italic = regex(#"(?<![*_\w])([*_])(?![*_\s])(.+?)(?<![*_\s])\1(?![*_\w])"#)
    private static let strike = regex(#"(~~)(?=\S)(.+?)(?<=\S)~~"#)
    private static let code = regex(#"(`)([^`\n]+)`"#)
    private static let link = regex(#"\[([^\]\n]+)\]\(([^)\s]+)\)"#)

    static var bodyFont: UIFont { .serif(.body) }

    static var bodyParagraph: NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.lineSpacing = Typography.bodyLineSpacing
        style.paragraphSpacing = 6
        return style
    }

    /// List items sit closer together than paragraphs.
    static var listParagraph: NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.lineSpacing = Typography.bodyLineSpacing
        style.paragraphSpacing = 0
        return style
    }

    static var typingAttributes: [NSAttributedString.Key: Any] {
        [.font: bodyFont, .foregroundColor: UITheme.primaryText, .paragraphStyle: bodyParagraph]
    }

    /// Styles `range` (expanded to whole paragraphs), or the whole document when nil.
    /// Every rule is line-local, so restyling just the edited paragraphs is exact.
    static func style(_ storage: NSTextStorage, in range: NSRange? = nil) {
        let text = storage.string as NSString
        guard text.length > 0 else { return }
        let full: NSRange
        if let range {
            let clamped = NSRange(
                location: min(range.location, text.length),
                length: max(0, min(NSMaxRange(range), text.length) - min(range.location, text.length))
            )
            full = text.paragraphRange(for: clamped)
        } else {
            full = NSRange(location: 0, length: text.length)
        }
        guard full.length > 0 else { return }

        storage.beginEditing()
        for key in [NSAttributedString.Key.strikethroughStyle, .underlineStyle, .backgroundColor, .kern] {
            storage.removeAttribute(key, range: full)
        }
        storage.addAttributes(typingAttributes, range: full)

        text.enumerateSubstrings(in: full, options: [.byParagraphs, .substringNotRequired]) { _, lineRange, _, _ in
            styleLine(lineRange, in: storage, text: text)
        }

        for match in bold.matches(in: storage.string, range: full) {
            addTraits(.traitBold, in: match.range(at: 2), of: storage)
            dim([match.range(at: 1), NSRange(location: NSMaxRange(match.range) - match.range(at: 1).length, length: match.range(at: 1).length)], in: storage)
        }
        for match in italic.matches(in: storage.string, range: full) {
            addTraits(.traitItalic, in: match.range(at: 2), of: storage)
            dim([match.range(at: 1), NSRange(location: NSMaxRange(match.range) - 1, length: 1)], in: storage)
        }
        for match in strike.matches(in: storage.string, range: full) {
            storage.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: match.range(at: 2))
            dim([match.range(at: 1), NSRange(location: NSMaxRange(match.range) - 2, length: 2)], in: storage)
        }
        for match in code.matches(in: storage.string, range: full) {
            let font = UIFont.monospacedSystemFont(ofSize: bodyFont.pointSize * 0.88, weight: .regular)
            storage.addAttributes([.font: font, .backgroundColor: UITheme.surface], range: match.range)
            dim([match.range(at: 1), NSRange(location: NSMaxRange(match.range) - 1, length: 1)], in: storage)
        }
        for match in link.matches(in: storage.string, range: full) {
            storage.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: match.range(at: 1))
            dim([
                NSRange(location: match.range.location, length: 1),
                NSRange(location: NSMaxRange(match.range(at: 1)), length: NSMaxRange(match.range) - NSMaxRange(match.range(at: 1))),
            ], in: storage)
        }
        for match in Markdown.tagPattern.matches(in: storage.string, range: full) {
            storage.addAttribute(.foregroundColor, value: UITheme.secondaryText, range: match.range)
        }
        storage.endEditing()
    }

    private static func styleLine(_ lineRange: NSRange, in storage: NSTextStorage, text: NSString) {
        guard lineRange.length > 0 else { return }
        let line = text.substring(with: lineRange)
        let local = NSRange(location: 0, length: (line as NSString).length)
        func shifted(_ range: NSRange) -> NSRange {
            NSRange(location: lineRange.location + range.location, length: range.length)
        }

        if line.contains("\u{FFFC}") && line.trimmingCharacters(in: .whitespaces) == "\u{FFFC}" {
            let style = NSMutableParagraphStyle()
            style.alignment = .center
            style.paragraphSpacing = 14
            style.paragraphSpacingBefore = 6
            storage.addAttribute(.paragraphStyle, value: style, range: lineRange)
        } else if let match = headingLine.firstMatch(in: line, range: local) {
            let level = match.range(at: 1).length
            let textStyle: UIFont.TextStyle = [.title1, .title2, .title3][level - 1]
            let style = NSMutableParagraphStyle()
            style.lineSpacing = 2
            style.paragraphSpacingBefore = level == 1 ? 10 : 6
            style.paragraphSpacing = 6
            storage.addAttributes([.font: UIFont.serif(textStyle, bold: true), .paragraphStyle: style], range: lineRange)
            dim([shifted(match.range)], in: storage)
        } else if let match = quoteLine.firstMatch(in: line, range: local) {
            let style = NSMutableParagraphStyle()
            style.lineSpacing = Typography.bodyLineSpacing
            style.paragraphSpacing = 6
            style.firstLineHeadIndent = 4
            style.headIndent = 16
            storage.addAttribute(.paragraphStyle, value: style, range: lineRange)
            storage.addAttribute(.foregroundColor, value: UITheme.secondaryText, range: lineRange)
            addTraits(.traitItalic, in: lineRange, of: storage)
            dim([shifted(match.range)], in: storage)
        } else if let match = checklistLine.firstMatch(in: line, range: local) {
            storage.addAttribute(.paragraphStyle, value: listParagraph, range: lineRange)
            dim([shifted(match.range)], in: storage)
            let isDone = (line as NSString).substring(with: match.range(at: 1)) != " "
            if isDone {
                let content = NSRange(location: lineRange.location + match.range.length, length: lineRange.length - match.range.length)
                storage.addAttributes([
                    .foregroundColor: UITheme.secondaryText,
                    .strikethroughStyle: NSUnderlineStyle.single.rawValue,
                ], range: content)
            }
        } else if let match = bulletLine.firstMatch(in: line, range: local) ?? numberedLine.firstMatch(in: line, range: local) {
            storage.addAttribute(.paragraphStyle, value: listParagraph, range: lineRange)
            storage.addAttribute(.foregroundColor, value: UITheme.secondaryText, range: shifted(match.range))
        } else if ruleLine.firstMatch(in: line, range: local) != nil {
            dim([lineRange], in: storage)
        }
    }

    /// Syntax characters recede so the writing stays in front.
    private static func dim(_ ranges: [NSRange], in storage: NSTextStorage) {
        for range in ranges where range.length > 0 && NSMaxRange(range) <= storage.length {
            storage.addAttribute(.foregroundColor, value: UITheme.secondaryText.withAlphaComponent(0.55), range: range)
        }
    }

    private static func addTraits(_ traits: UIFontDescriptor.SymbolicTraits, in range: NSRange, of storage: NSTextStorage) {
        storage.enumerateAttribute(.font, in: range) { value, subrange, _ in
            guard let font = value as? UIFont,
                  let descriptor = font.fontDescriptor.withSymbolicTraits(font.fontDescriptor.symbolicTraits.union(traits))
            else { return }
            storage.addAttribute(.font, value: UIFont(descriptor: descriptor, size: font.pointSize), range: subrange)
        }
    }
}
