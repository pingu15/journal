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

/// A horizontal rule, its own paragraph. Serialized back to `---`.
nonisolated final class DividerAttachment: NSTextAttachment {
    private static let line: UIImage = {
        let size = CGSize(width: 1200, height: 24)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 2
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            UIColor(hex: Palette.stone).withAlphaComponent(0.45).setFill()
            UIRectFill(CGRect(x: 0, y: size.height / 2 - 0.5, width: size.width, height: 1))
        }
    }()

    init() {
        super.init(data: nil, ofType: nil)
        image = Self.line
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func attachmentBounds(
        for attributes: [NSAttributedString.Key: Any],
        location: any NSTextLocation,
        textContainer: NSTextContainer?,
        proposedLineFragment: CGRect,
        position: CGPoint
    ) -> CGRect {
        CGRect(x: 0, y: 0, width: max(proposedLineFragment.width - 1, 40), height: 24)
    }

    override func attachmentBounds(
        for textContainer: NSTextContainer?,
        proposedLineFragment lineFrag: CGRect,
        glyphPosition position: CGPoint,
        characterIndex charIndex: Int
    ) -> CGRect {
        CGRect(x: 0, y: 0, width: max(lineFrag.width - 1, 40), height: 24)
    }
}

// MARK: - Semantic formatting

/// The editor holds formatted text, not Markdown syntax. These attributes are the source of truth
/// for formatting (they're what gets written back as Markdown); fonts and colors are derived from them.
nonisolated extension NSAttributedString.Key {
    /// `InlineStyle` raw value.
    static let inlineStyle = NSAttributedString.Key("journal.inlineStyle")
    /// Link destination (a `String`).
    static let linkURL = NSAttributedString.Key("journal.linkURL")
    /// `BlockStyle` raw value, on every character of the paragraph including its line break.
    static let blockStyle = NSAttributedString.Key("journal.blockStyle")
}

nonisolated struct InlineStyle: OptionSet, Hashable, Sendable {
    let rawValue: Int
    static let bold = InlineStyle(rawValue: 1)
    static let italic = InlineStyle(rawValue: 2)
    static let strikethrough = InlineStyle(rawValue: 4)
    static let code = InlineStyle(rawValue: 8)
}

nonisolated enum BlockStyle: Int, Sendable {
    case title = 1, heading = 2, subheading = 3, quote = 4

    var markdownPrefix: String {
        switch self {
        case .title: "# "
        case .heading: "## "
        case .subheading: "### "
        case .quote: "> "
        }
    }

    var isHeading: Bool { self != .quote }
}

nonisolated extension NSAttributedString {
    func inlineStyle(at index: Int) -> InlineStyle {
        InlineStyle(rawValue: attribute(.inlineStyle, at: index, effectiveRange: nil) as? Int ?? 0)
    }

    func blockStyle(at index: Int) -> BlockStyle? {
        (attribute(.blockStyle, at: index, effectiveRange: nil) as? Int).flatMap(BlockStyle.init(rawValue:))
    }
}

// MARK: - Markdown ⇄ formatted text

/// Entries are stored as Markdown; the editor shows them as formatted text with no visible syntax.
/// Lists keep a visible marker (• ☐ ☑, or the number), since that's how a list reads.
nonisolated enum MarkdownDocument {
    private static func regex(_ pattern: String) -> NSRegularExpression {
        try! NSRegularExpression(pattern: pattern)
    }

    private static let ruleLine = regex(#"^[ \t]*([-*_])([ \t]*\1){2,}[ \t]*$"#)
    private static let headingLine = regex(#"^(#{1,6})[ \t]+(.*)$"#)
    private static let quoteLine = regex(#"^>[ \t]?(.*)$"#)
    private static let checklistLine = regex(#"^([ \t]*)[-*+][ \t]+\[([ xX])\][ \t]+(.*)$"#)
    private static let bulletLine = regex(#"^([ \t]*)[-*+][ \t]+(.*)$"#)
    /// Any list marker that Return continues: indent, marker, and (for numbers) the number and its punctuation.
    static let listPrefix = regex(#"^([ \t]*)([•☐☑]\x{FE0E}?[ \t]|(\d+)([.)])[ \t]+)"#)
    /// The editor's own list markers, at the start of a line.
    static let markerLine = regex(#"^([ \t]*)([•☐☑]\x{FE0E}?)[ \t]"#)

    static let bullet = "•"
    static let unchecked = "☐"
    /// With the text-presentation selector, so it draws like ☐ rather than as an emoji.
    static let checked = "\u{2611}\u{FE0E}"

    /// ☑ with or without its presentation selector (Swift treats those as different characters).
    static func isChecked(_ marker: String) -> Bool {
        marker.unicodeScalars.contains("\u{2611}")
    }

    /// The whole document. `attachment` supplies the photo for an image token (nil drops the token).
    static func attributed(from markdown: String, attachment: (UUID) -> NSTextAttachment?) -> NSMutableAttributedString {
        let result = NSMutableAttributedString()
        let lines = markdown.components(separatedBy: "\n")
        for (index, line) in lines.enumerated() {
            let (paragraph, block) = parseLine(line, attachment: attachment)
            if index < lines.count - 1 {
                paragraph.append(NSAttributedString(string: "\n"))
            }
            if let block, paragraph.length > 0 {
                paragraph.addAttribute(.blockStyle, value: block.rawValue, range: NSRange(location: 0, length: paragraph.length))
            }
            result.append(paragraph)
        }
        return result
    }

    /// One line of Markdown as formatted text (no line break) and its paragraph style.
    static func parseLine(_ line: String, attachment: (UUID) -> NSTextAttachment?) -> (NSMutableAttributedString, BlockStyle?) {
        let ns = line as NSString
        let all = NSRange(location: 0, length: ns.length)
        func group(_ match: NSTextCheckingResult, _ index: Int) -> String {
            let range = match.range(at: index)
            return range.location == NSNotFound ? "" : ns.substring(with: range)
        }

        if ruleLine.firstMatch(in: line, range: all) != nil {
            return (NSMutableAttributedString(attachment: DividerAttachment()), nil)
        }
        if let match = headingLine.firstMatch(in: line, range: all) {
            let level = min(match.range(at: 1).length, 3)
            return (inline(group(match, 2), attachment: attachment), BlockStyle(rawValue: level))
        }
        if let match = quoteLine.firstMatch(in: line, range: all) {
            return (inline(group(match, 1), attachment: attachment), .quote)
        }
        if let match = checklistLine.firstMatch(in: line, range: all) {
            let marker = group(match, 2) == " " ? unchecked : checked
            let result = NSMutableAttributedString(string: group(match, 1) + marker + " ")
            result.append(inline(group(match, 3), attachment: attachment))
            return (result, nil)
        }
        if let match = bulletLine.firstMatch(in: line, range: all) {
            let result = NSMutableAttributedString(string: group(match, 1) + bullet + " ")
            result.append(inline(group(match, 2), attachment: attachment))
            return (result, nil)
        }
        return (inline(line, attachment: attachment), nil)
    }

    static func inline(_ text: String, attachment: (UUID) -> NSTextAttachment?) -> NSMutableAttributedString {
        withoutActuallyEscaping(attachment) { attachment in
            var parser = InlineParser(chars: Array(text), attachment: attachment)
            let result = NSMutableAttributedString()
            _ = parser.parse(until: nil, style: [], link: nil, into: result)
            return result
        }
    }

    // MARK: Serializing

    static func markdown(from attributed: NSAttributedString) -> String {
        let ns = attributed.string as NSString
        var lines: [String] = []
        var location = 0
        while true {
            let newline = ns.range(of: "\n", range: NSRange(location: location, length: ns.length - location))
            let end = newline.location == NSNotFound ? ns.length : newline.location
            let content = NSRange(location: location, length: end - location)
            let block = content.location < ns.length ? attributed.blockStyle(at: content.location) : nil
            lines.append(markdownLine(attributed, content: content, block: block))
            if newline.location == NSNotFound { break }
            location = end + 1
        }
        return lines.joined(separator: "\n")
    }

    /// One paragraph's content (no line break) as a line of Markdown.
    static func markdownLine(_ attributed: NSAttributedString, content: NSRange, block: BlockStyle?) -> String {
        if content.length == 1, attributed.attribute(.attachment, at: content.location, effectiveRange: nil) is DividerAttachment {
            return "---"
        }
        var output = block?.markdownPrefix ?? ""
        var body = content
        let text = attributed.attributedSubstring(from: content).string
        if block == nil, let match = markerLine.firstMatch(in: text, range: NSRange(location: 0, length: (text as NSString).length)) {
            let ns = text as NSString
            let indent = ns.substring(with: match.range(at: 1))
            let marker = ns.substring(with: match.range(at: 2))
            if marker.hasPrefix(unchecked) {
                output += indent + "- [ ] "
            } else if MarkdownDocument.isChecked(marker) {
                output += indent + "- [x] "
            } else {
                output += indent + "- "
            }
            body = NSRange(location: content.location + match.range.length, length: content.length - match.range.length)
        }
        var line = inlineMarkdown(attributed, range: body)
        if output.isEmpty {
            line = escapeLineStart(line)
        }
        return output + line
    }

    private static let literalBlockStart = regex(#"^([ \t]*)(#{1,6}[ \t]|>|[-+*][ \t]|([-*_])([ \t]*\3){2,}[ \t]*$)"#)

    /// Text that happens to begin like Markdown block syntax ("# ", "> ", "- ", "---") gets a
    /// backslash, so it reads back as the text that was typed.
    private static func escapeLineStart(_ line: String) -> String {
        let ns = line as NSString
        guard let match = literalBlockStart.firstMatch(in: line, range: NSRange(location: 0, length: ns.length)) else { return line }
        let at = match.range(at: 1).length
        return ns.replacingCharacters(in: NSRange(location: at, length: 0), with: "\\")
    }

    private enum Mark: Equatable {
        case link(String), bold, italic, strike, code

        var open: String {
            switch self {
            case .link: "["
            case .bold: "**"
            case .italic: "*"
            case .strike: "~~"
            case .code: "`"
            }
        }

        var close: String {
            switch self {
            case .link(let url): "](\(url))"
            default: open
            }
        }
    }

    /// Formatting runs as Markdown, opening and closing markers as styles start and stop, so
    /// overlapping styles nest (`**a *b* c**`). Spaces only keep the emphasis shared by the words
    /// on both sides, so a marker never sits next to a space (which Markdown wouldn't recognise).
    private static func inlineMarkdown(_ attributed: NSAttributedString, range: NSRange) -> String {
        struct Piece {
            var text: String
            var style: InlineStyle
            var link: String?
            var isSpace: Bool
            var image: UUID?
        }
        let emphasis: InlineStyle = [.bold, .italic, .strikethrough]

        // Split runs into whitespace / non-whitespace pieces.
        var pieces: [Piece] = []
        attributed.enumerateAttributes(in: range) { attributes, run, _ in
            if let image = attributes[.attachment] as? ImageAttachment {
                for _ in 0..<run.length {
                    pieces.append(Piece(text: "", style: [], link: nil, isSpace: false, image: image.imageID))
                }
                return
            }
            if attributes[.attachment] != nil { return }
            let style = InlineStyle(rawValue: attributes[.inlineStyle] as? Int ?? 0)
            let link = attributes[.linkURL] as? String
            let text = (attributed.string as NSString).substring(with: run).replacingOccurrences(of: "\u{FFFC}", with: "")
            if style.contains(.code) {
                pieces.append(Piece(text: text, style: style, link: link, isSpace: false))
                return
            }
            for character in text {
                let isSpace = character.isWhitespace
                if let last = pieces.last, last.isSpace == isSpace, last.style == style, last.link == link, last.image == nil {
                    pieces[pieces.count - 1].text.append(character)
                } else {
                    pieces.append(Piece(text: String(character), style: style, link: link, isSpace: isSpace))
                }
            }
        }
        for index in pieces.indices where pieces[index].isSpace {
            let before = pieces[..<index].last { !$0.isSpace }
            let after = pieces[(index + 1)...].first { !$0.isSpace }
            let shared = (before?.image == nil ? before?.style : nil).flatMap { b in
                (after?.image == nil ? after?.style : nil).map { b.intersection($0) }
            } ?? []
            pieces[index].style = pieces[index].style.subtracting(emphasis).union(pieces[index].style.intersection(shared))
        }

        var output = ""
        var open: [Mark] = []
        func transition(to marks: [Mark]) {
            if let first = open.firstIndex(where: { !marks.contains($0) }) {
                for mark in open[first...].reversed() { output += mark.close }
                open.removeSubrange(first...)
            }
            for mark in marks where !open.contains(mark) {
                output += mark.open
                open.append(mark)
            }
        }
        // Literal characters that would otherwise read back as formatting get a backslash. Only
        // where they could: "5 * 3" and "snake_case" stay as typed.
        let flat = pieces.map { $0.image != nil || $0.style.contains(.code) ? "\u{FFFC}" : $0.text }.joined()
        let chars = Array(flat)
        var offset = 0
        func escaped(_ text: String) -> String {
            var result = ""
            for character in text {
                let before: Character = offset > 0 ? chars[offset - 1] : " "
                let after: Character = offset + 1 < chars.count ? chars[offset + 1] : " "
                offset += 1
                let isWord = { (c: Character) in c.isLetter || c.isNumber }
                var escape = false
                switch character {
                case "\\":
                    escape = after.isPunctuation || after.isSymbol
                case "*":
                    escape = !(before.isWhitespace && after.isWhitespace)
                case "_":
                    escape = (!isWord(before) && !after.isWhitespace) || (!before.isWhitespace && !isWord(after))
                case "~":
                    escape = before == "~" || after == "~"
                case "`", "[":
                    escape = true
                default:
                    break
                }
                if escape { result.append("\\") }
                result.append(character)
            }
            return result
        }

        for piece in pieces {
            if piece.image != nil || piece.style.contains(.code) {
                offset += 1
            }
            if let image = piece.image {
                transition(to: [])
                output += Markdown.imageToken(image)
                continue
            }
            var marks: [Mark] = []
            if let link = piece.link { marks.append(.link(link)) }
            if piece.style.contains(.bold) { marks.append(.bold) }
            if piece.style.contains(.italic) { marks.append(.italic) }
            if piece.style.contains(.strikethrough) { marks.append(.strike) }
            if piece.style.contains(.code) { marks.append(.code) }
            transition(to: marks)
            output += piece.style.contains(.code) ? piece.text : escaped(piece.text)
        }
        transition(to: [])
        return output
    }
}

/// Recursive inline Markdown parser: code spans, links, image tokens, and nested **bold**,
/// *italic* and ~~strikethrough~~. Unmatched markers stay as literal text.
nonisolated private struct InlineParser {
    let chars: [Character]
    let attachment: (UUID) -> NSTextAttachment?
    var index = 0

    /// Parses until `closer` (returning true) or the end (returning `closer == nil`).
    mutating func parse(until closer: [Character]?, style: InlineStyle, link: String?, into out: NSMutableAttributedString) -> Bool {
        var literal = ""
        func flush() {
            guard !literal.isEmpty else { return }
            var attributes: [NSAttributedString.Key: Any] = [:]
            if !style.isEmpty { attributes[.inlineStyle] = style.rawValue }
            if let link { attributes[.linkURL] = link }
            out.append(NSAttributedString(string: literal, attributes: attributes))
            literal = ""
        }

        while index < chars.count {
            if let closer, isCloser(closer) {
                flush()
                index += closer.count
                return true
            }
            let character = chars[index]

            if character == "\\", index + 1 < chars.count, chars[index + 1].isPunctuation || chars[index + 1].isSymbol {
                literal.append(chars[index + 1])
                index += 2
                continue
            }
            if character == "!", let (id, length) = imageToken() {
                flush()
                if let image = attachment(id) { out.append(NSAttributedString(attachment: image)) }
                index += length
                continue
            }
            if character == "`", !style.contains(.code),
               let end = chars[(index + 1)...].firstIndex(of: "`"), end > index + 1 {
                flush()
                let code = String(chars[(index + 1)..<end])
                var attributes: [NSAttributedString.Key: Any] = [.inlineStyle: style.union(.code).rawValue]
                if let link { attributes[.linkURL] = link }
                out.append(NSAttributedString(string: code, attributes: attributes))
                index = end + 1
                continue
            }
            if character == "[", link == nil, let (textEnd, url, end) = linkAt() {
                flush()
                var inner = InlineParser(chars: Array(chars[(index + 1)..<textEnd]), attachment: attachment)
                _ = inner.parse(until: nil, style: style, link: url, into: out)
                index = end
                continue
            }
            if let (marker, markerStyle) = opener(style: style) {
                flush()
                let start = index
                index += marker.count
                let inner = NSMutableAttributedString()
                if parse(until: marker, style: style.union(markerStyle), link: link, into: inner), inner.length > 0 {
                    out.append(inner)
                } else {
                    index = start + marker.count
                    literal = String(marker)
                }
                continue
            }
            literal.append(character)
            index += 1
        }
        flush()
        return closer == nil
    }

    private func matches(_ marker: [Character], at position: Int) -> Bool {
        position + marker.count <= chars.count && Array(chars[position..<(position + marker.count)]) == marker
    }

    private func isCloser(_ marker: [Character]) -> Bool {
        guard matches(marker, at: index), index > 0, !chars[index - 1].isWhitespace else { return false }
        if marker.first == "_" {
            let after = index + marker.count
            if after < chars.count, chars[after].isLetter || chars[after].isNumber { return false }
        }
        return true
    }

    /// An emphasis marker that can open here: followed by non-space text, with a closer somewhere after.
    private func opener(style: InlineStyle) -> ([Character], InlineStyle)? {
        let candidates: [([Character], InlineStyle)] = [
            (["*", "*"], .bold), (["_", "_"], .bold), (["~", "~"], .strikethrough), (["*"], .italic), (["_"], .italic),
        ]
        for (marker, markerStyle) in candidates where !style.contains(markerStyle) && matches(marker, at: index) {
            let after = index + marker.count
            guard after < chars.count, !chars[after].isWhitespace else { continue }
            if marker.count == 1, chars[after] == marker[0] { continue }
            if marker.first == "_", index > 0, chars[index - 1].isLetter || chars[index - 1].isNumber { continue }
            // Cheap check before recursing: is there a closer at all?
            var probe = after + 1
            var found = false
            while probe + marker.count <= chars.count {
                if matches(marker, at: probe) { found = true; break }
                probe += 1
            }
            if found { return (marker, markerStyle) }
        }
        return nil
    }

    /// `![](image:<uuid>)` at the current index.
    private func imageToken() -> (UUID, Int)? {
        let prefix = Array("![](image:")
        let length = prefix.count + 36 + 1
        guard matches(prefix, at: index), index + length <= chars.count, chars[index + length - 1] == ")",
              let id = UUID(uuidString: String(chars[(index + prefix.count)..<(index + prefix.count + 36)]))
        else { return nil }
        return (id, length)
    }

    /// `[text](url)` at the current index: where the text ends, the URL, and the index after `)`.
    private func linkAt() -> (Int, String, Int)? {
        guard let close = chars[(index + 1)...].firstIndex(of: "]"), close > index + 1,
              close + 1 < chars.count, chars[close + 1] == "(",
              let end = chars[(close + 2)...].firstIndex(of: ")"), end > close + 2
        else { return nil }
        let url = String(chars[(close + 2)..<end])
        guard !url.contains(where: \.isWhitespace) else { return nil }
        return (close, url, end + 1)
    }
}

// MARK: - Display styling

/// Derives fonts, colors and paragraph styles from the semantic formatting attributes.
enum MarkdownStyler {
    static var bodyFont: UIFont { .sans(.body) }

    static func font(for block: BlockStyle?) -> UIFont {
        switch block {
        case .title: .sans(.title1, bold: true)
        case .heading: .sans(.title2, bold: true)
        case .subheading: .sans(.title3, bold: true)
        case .quote, nil: bodyFont
        }
    }

    static func paragraphStyle(for block: BlockStyle?) -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        switch block {
        case .title, .heading, .subheading:
            style.lineSpacing = 2
            style.paragraphSpacingBefore = block == .title ? 10 : 6
            style.paragraphSpacing = 6
        case .quote:
            style.lineSpacing = Typography.bodyLineSpacing
            style.paragraphSpacing = 6
            style.firstLineHeadIndent = 16
            style.headIndent = 16
        case nil:
            style.lineSpacing = Typography.bodyLineSpacing
            style.paragraphSpacing = 6
        }
        return style
    }

    /// List items sit closer together than paragraphs, with wrapped lines hanging under the text.
    private static func listParagraph(indent: CGFloat) -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.lineSpacing = Typography.bodyLineSpacing
        style.paragraphSpacing = 2
        style.headIndent = indent
        return style
    }

    /// What a run with these styles looks like.
    static func displayAttributes(block: BlockStyle?, inline: InlineStyle) -> [NSAttributedString.Key: Any] {
        var font = font(for: block)
        var traits = font.fontDescriptor.symbolicTraits
        if inline.contains(.bold) { traits.insert(.traitBold) }
        if inline.contains(.italic) || block == .quote { traits.insert(.traitItalic) }
        if let descriptor = font.fontDescriptor.withSymbolicTraits(traits) {
            font = UIFont(descriptor: descriptor, size: font.pointSize)
        }
        if inline.contains(.code) {
            font = .monospacedSystemFont(ofSize: font.pointSize * 0.88, weight: inline.contains(.bold) ? .semibold : .regular)
        }
        var attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: block == .quote ? UITheme.secondaryText : UITheme.primaryText,
            .paragraphStyle: paragraphStyle(for: block),
        ]
        if inline.contains(.strikethrough) {
            attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
        }
        if inline.contains(.code) {
            attributes[.backgroundColor] = UITheme.surface
        }
        return attributes
    }

    /// Display plus semantic attributes, for text about to be typed.
    static func typingAttributes(block: BlockStyle?, inline: InlineStyle) -> [NSAttributedString.Key: Any] {
        var attributes = displayAttributes(block: block, inline: inline)
        if let block { attributes[.blockStyle] = block.rawValue }
        if !inline.isEmpty { attributes[.inlineStyle] = inline.rawValue }
        return attributes
    }

    static var typingAttributes: [NSAttributedString.Key: Any] {
        typingAttributes(block: nil, inline: [])
    }

    /// Restyles the paragraphs touching `range` (or the whole document when nil). Also makes each
    /// paragraph's block style uniform, taken from its first character.
    static func style(_ storage: NSTextStorage, in range: NSRange? = nil) {
        let text = storage.string as NSString
        guard text.length > 0 else { return }
        let full: NSRange
        if let range {
            let start = min(range.location, text.length)
            let end = min(NSMaxRange(range), text.length)
            full = text.paragraphRange(for: NSRange(location: start, length: end - start))
        } else {
            full = NSRange(location: 0, length: text.length)
        }
        guard full.length > 0 else { return }

        storage.beginEditing()
        text.enumerateSubstrings(in: full, options: [.byParagraphs, .substringNotRequired]) { _, content, enclosing, _ in
            styleParagraph(content: content, enclosing: enclosing, in: storage, text: text)
        }
        storage.endEditing()
    }

    private static func styleParagraph(content: NSRange, enclosing: NSRange, in storage: NSTextStorage, text: NSString) {
        guard enclosing.length > 0 else { return }
        let block = storage.blockStyle(at: enclosing.location)
        if let block {
            storage.addAttribute(.blockStyle, value: block.rawValue, range: enclosing)
        } else {
            storage.removeAttribute(.blockStyle, range: enclosing)
        }
        for key in [NSAttributedString.Key.strikethroughStyle, .underlineStyle, .underlineColor, .backgroundColor] {
            storage.removeAttribute(key, range: enclosing)
        }
        storage.addAttributes(displayAttributes(block: block, inline: []), range: enclosing)

        let line = text.substring(with: content)
        let local = NSRange(location: 0, length: content.length)

        // Photos and dividers stand alone, centered.
        if line.trimmingCharacters(in: .whitespaces) == "\u{FFFC}" {
            let style = NSMutableParagraphStyle()
            style.alignment = .center
            style.paragraphSpacing = 14
            style.paragraphSpacingBefore = 6
            storage.addAttribute(.paragraphStyle, value: style, range: enclosing)
            return
        }

        storage.enumerateAttributes(in: content) { attributes, run, _ in
            let inline = InlineStyle(rawValue: attributes[.inlineStyle] as? Int ?? 0)
            if !inline.isEmpty {
                var display = displayAttributes(block: block, inline: inline)
                display[.paragraphStyle] = nil
                storage.addAttributes(display, range: run)
            }
            if attributes[.linkURL] != nil {
                storage.addAttributes([
                    .underlineStyle: NSUnderlineStyle.single.rawValue,
                    .underlineColor: UITheme.secondaryText.withAlphaComponent(0.45),
                ], range: run)
            }
        }

        // List markers: quiet, and wrapped lines hang under the item's text.
        if block == nil {
            let prefix = MarkdownDocument.markerLine.firstMatch(in: line, range: local)
                ?? numberedLine.firstMatch(in: line, range: local)
            if let prefix {
                let markerRange = NSRange(location: content.location + prefix.range.location, length: prefix.range.length)
                let prefixWidth = (text.substring(with: markerRange) as NSString)
                    .size(withAttributes: [.font: bodyFont]).width
                storage.addAttribute(.paragraphStyle, value: listParagraph(indent: prefixWidth), range: enclosing)
                storage.addAttribute(.foregroundColor, value: UITheme.secondaryText, range: markerRange)
                if (line as NSString).substring(with: prefix.range).unicodeScalars.contains("\u{2611}") {
                    let done = NSRange(location: NSMaxRange(markerRange), length: NSMaxRange(content) - NSMaxRange(markerRange))
                    storage.addAttributes([
                        .foregroundColor: UITheme.secondaryText,
                        .strikethroughStyle: NSUnderlineStyle.single.rawValue,
                    ], range: done)
                }
            }
        }

        for match in Markdown.tagPattern.matches(in: storage.string, range: content) {
            storage.addAttribute(.foregroundColor, value: UITheme.secondaryText, range: match.range)
        }
    }

    private static let numberedLine = try! NSRegularExpression(pattern: #"^[ \t]*\d+[.)][ \t]"#)
}
