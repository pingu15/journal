import UIKit

/// The journal typeset as a printable book: a title page, then every entry — date, place and
/// weather, its title, formatted Markdown and photos — flowed across pages with TextKit.
/// Always ink on white, whatever the app's appearance.
struct JournalPDF {
    let entries: [Entry]
    let journalName: String
    /// A whole-journal export opens with a title page; a single entry starts on page one.
    var includesTitlePage = true

    private let page: CGRect
    private let content: CGRect

    private let ink = UITheme.primaryText.resolvedColor(with: UITraitCollection(userInterfaceStyle: .light))
    private let stone = UITheme.secondaryText.resolvedColor(with: UITraitCollection(userInterfaceStyle: .light))

    /// `entries` should already be in reading order.
    init(entries: [Entry], journalName: String, includesTitlePage: Bool = true) {
        self.entries = entries
        self.journalName = journalName
        self.includesTitlePage = includesTitlePage
        // A4 where the metric system is used, US Letter elsewhere.
        let size = Locale.current.measurementSystem == .us ? CGSize(width: 612, height: 792) : CGSize(width: 595, height: 842)
        page = CGRect(origin: .zero, size: size)
        content = page.insetBy(dx: 64, dy: 72)
    }

    /// Space an entry's date line needs below it on a page, so it isn't stranded without its title and first lines.
    private let keepTogether: CGFloat = 100

    func render() -> Data {
        let (text, entryStarts) = body()
        let storage = NSTextStorage(attributedString: text)
        let layout = NSLayoutManager()
        let pageBreaks = PageBreaks()
        layout.delegate = pageBreaks
        storage.addLayoutManager(layout)

        // One container per page, until all the text has somewhere to go.
        var containers: [NSTextContainer] = []
        func addPages() {
            while true {
                if let last = containers.last {
                    let range = layout.glyphRange(for: last)
                    if NSMaxRange(range) >= layout.numberOfGlyphs { return }
                    if range.length == 0 && containers.count > 1 { return } // nothing more will fit
                }
                let container = NSTextContainer(size: content.size)
                container.lineFragmentPadding = 0
                layout.addTextContainer(container)
                containers.append(container)
            }
        }
        addPages()

        // An entry starting too near the foot of a page moves to the next one (a form feed breaks the page).
        var inserted = 0
        for start in entryStarts.dropFirst() {
            let index = start + inserted
            let line = layout.lineFragmentRect(forGlyphAt: layout.glyphIndexForCharacter(at: index), effectiveRange: nil)
            guard line.maxY > content.height - keepTogether else { continue }
            storage.insert(NSAttributedString(string: "\u{0C}", attributes: storage.attributes(at: index, effectiveRange: nil)), at: index)
            inserted += 1
            addPages()
        }

        let format = UIGraphicsPDFRendererFormat()
        format.documentInfo = [kCGPDFContextTitle as String: journalName]
        return UIGraphicsPDFRenderer(bounds: page, format: format).pdfData { context in
            if includesTitlePage {
                context.beginPage()
                drawTitlePage()
            }
            for (index, container) in containers.enumerated() {
                let range = layout.glyphRange(for: container)
                guard range.length > 0 else { continue }
                context.beginPage()
                layout.drawBackground(forGlyphRange: range, at: content.origin)
                layout.drawGlyphs(forGlyphRange: range, at: content.origin)
                drawPageNumber(index + 1)
            }
        }
    }

    // MARK: - Pages

    private func drawTitlePage() {
        let centered = paragraph { $0.alignment = .center }
        let title = NSAttributedString(string: journalName, attributes: [
            .font: Self.serif(34, .bold), .foregroundColor: ink, .paragraphStyle: centered,
        ])
        var details = [entries.count == 1 ? "1 entry" : "\(entries.count) entries"]
        if let first = entries.first?.createdAt, let last = entries.last?.createdAt {
            let start = first.formatted(.dateTime.month(.wide).year())
            let end = last.formatted(.dateTime.month(.wide).year())
            details.insert(start == end ? start : "\(start) – \(end)", at: 0)
        }
        let meta = NSAttributedString(string: details.joined(separator: "  ·  ").uppercased(), attributes: metaAttributes(centered))

        let titleHeight = title.boundingRect(with: CGSize(width: content.width, height: .greatestFiniteMagnitude), options: .usesLineFragmentOrigin, context: nil).height
        let top = page.height * 0.38
        title.draw(with: CGRect(x: content.minX, y: top, width: content.width, height: titleHeight + 4), options: .usesLineFragmentOrigin, context: nil)
        meta.draw(with: CGRect(x: content.minX, y: top + titleHeight + 18, width: content.width, height: 40), options: .usesLineFragmentOrigin, context: nil)
    }

    private func drawPageNumber(_ number: Int) {
        let text = NSAttributedString(string: "\(number)", attributes: metaAttributes(paragraph { $0.alignment = .center }))
        text.draw(with: CGRect(x: content.minX, y: page.maxY - 44, width: content.width, height: 14), options: .usesLineFragmentOrigin, context: nil)
    }

    // MARK: - Text

    /// The flowing text, plus where each entry begins in it.
    private func body() -> (NSAttributedString, [Int]) {
        let text = NSMutableAttributedString()
        var starts: [Int] = []
        for (index, entry) in entries.enumerated() {
            starts.append(text.length)
            append(entry, to: text, isFirst: index == 0)
        }
        return (text, starts)
    }

    private func append(_ entry: Entry, to text: NSMutableAttributedString, isFirst: Bool) {
        // Date line, then place and weather under it, as the editor's header has them.
        let meta = [entry.createdAt.formatted(.dateTime.weekday(.wide).month(.wide).day().year()),
                    entry.createdAt.formatted(date: .omitted, time: .shortened)]
        let hasPlaceLine = entry.placeName != nil || entry.weather != nil
        let metaStyle = paragraph {
            $0.paragraphSpacingBefore = isFirst ? 0 : 40
            $0.paragraphSpacing = hasPlaceLine ? 3 : 6
        }
        text.append(NSAttributedString(string: meta.joined(separator: "  ·  ").uppercased() + "\n", attributes: metaAttributes(metaStyle)))
        if hasPlaceLine {
            text.append(placeLine(for: entry))
        }

        var lines = entry.text.components(separatedBy: .newlines)
        // The first line of text is the entry's title.
        if let first = lines.firstIndex(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty && imageID(in: $0) == nil }) {
            let title = lines.remove(at: first).replacing(#/^\s*#{1,3}\s+/#, with: "")
            text.append(inline(title, font: Self.serif(19, .semibold), color: ink, style: paragraph { $0.paragraphSpacing = 8 }))
        }

        var inCode = false
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") {
                inCode.toggle()
                continue
            }
            if inCode {
                text.append(NSAttributedString(string: line + "\n", attributes: [
                    .font: UIFont.monospacedSystemFont(ofSize: 9.5, weight: .regular), .foregroundColor: ink,
                    .paragraphStyle: paragraph { $0.firstLineHeadIndent = 12; $0.headIndent = 12; $0.lineSpacing = 2 },
                ]))
                continue
            }
            if trimmed.isEmpty { continue }
            if let id = imageID(in: trimmed) {
                if let photo = photo(id, in: entry) { text.append(photo) }
                continue
            }
            text.append(block(line))
        }
    }

    /// One line of Markdown as a paragraph: heading, list item, checklist, quote, rule or body text.
    private func block(_ line: String) -> NSAttributedString {
        let indent = CGFloat(line.prefix { $0 == " " || $0 == "\t" }.count / 2) * 16
        let trimmed = line.trimmingCharacters(in: .whitespaces)

        if let match = trimmed.wholeMatch(of: #/(#{1,3})\s+(.*)/#) {
            let size: CGFloat = [16, 14, 12.5][match.1.count - 1]
            return inline(String(match.2), font: Self.serif(size, .semibold), color: ink, style: paragraph {
                $0.paragraphSpacingBefore = 6
                $0.paragraphSpacing = 4
            })
        }
        if trimmed.wholeMatch(of: #/([-*_])(\s*\1){2,}/#) != nil {
            return NSAttributedString(string: "—\n", attributes: [
                .font: Self.serif(11), .foregroundColor: stone,
                .paragraphStyle: paragraph { $0.alignment = .center; $0.paragraphSpacingBefore = 4; $0.paragraphSpacing = 10 },
            ])
        }
        if let match = trimmed.wholeMatch(of: #/[-*+]\s+\[([ xX])\]\s+(.*)/#) {
            return listItem(match.1 == " " ? "☐" : "☑", String(match.2), indent: indent)
        }
        if let match = trimmed.wholeMatch(of: #/[-*+]\s+(.*)/#) {
            return listItem("•", String(match.1), indent: indent)
        }
        if let match = trimmed.wholeMatch(of: #/(\d+)([.)])\s+(.*)/#) {
            return listItem("\(match.1)\(match.2)", String(match.3), indent: indent)
        }
        if let match = trimmed.wholeMatch(of: #/>\s?(.*)/#) {
            return inline(String(match.1), font: Self.serif(11.5, italic: true), color: stone, style: paragraph {
                $0.firstLineHeadIndent = indent + 14
                $0.headIndent = indent + 14
            })
        }
        return inline(trimmed, font: Self.serif(11.5), color: ink, style: paragraph {
            $0.firstLineHeadIndent = indent
            $0.headIndent = indent
        })
    }

    private func listItem(_ marker: String, _ content: String, indent: CGFloat) -> NSAttributedString {
        let style = paragraph {
            $0.firstLineHeadIndent = indent
            $0.headIndent = indent + 18
            $0.tabStops = [NSTextTab(textAlignment: .left, location: indent + 18)]
            $0.paragraphSpacing = 3
        }
        let item = NSMutableAttributedString(string: marker + "\t", attributes: [
            .font: Self.serif(11.5), .foregroundColor: stone, .paragraphStyle: style,
        ])
        item.append(inline(content, font: Self.serif(11.5), color: ink, style: style))
        return item
    }

    /// `<u>…</u>`, which Markdown leaves as text: underlined, the tags taken out.
    private static func applyUnderlines(in text: NSMutableAttributedString) {
        while true {
            let string = text.string as NSString
            let open = string.range(of: "<u>")
            guard open.location != NSNotFound else { return }
            let afterOpen = NSMaxRange(open)
            let close = string.range(of: "</u>", range: NSRange(location: afterOpen, length: string.length - afterOpen))
            guard close.location != NSNotFound else { return }
            text.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue,
                              range: NSRange(location: afterOpen, length: close.location - afterOpen))
            text.deleteCharacters(in: close)
            text.deleteCharacters(in: open)
        }
    }

    /// Bold, italic, underline, strikethrough, code and links within a line; ends the paragraph.
    private func inline(_ markdown: String, font: UIFont, color: UIColor, style: NSParagraphStyle) -> NSAttributedString {
        let parsed = (try? AttributedString(markdown: markdown, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            ?? AttributedString(markdown)
        let result = NSMutableAttributedString()
        for run in parsed.runs {
            let intent = run.inlinePresentationIntent ?? []
            var runFont = font
            var traits = font.fontDescriptor.symbolicTraits
            if intent.contains(.stronglyEmphasized) { traits.insert(.traitBold) }
            if intent.contains(.emphasized) { traits.insert(.traitItalic) }
            if traits != font.fontDescriptor.symbolicTraits, let descriptor = font.fontDescriptor.withSymbolicTraits(traits) {
                runFont = UIFont(descriptor: descriptor, size: font.pointSize)
            }
            if intent.contains(.code) {
                runFont = .monospacedSystemFont(ofSize: font.pointSize * 0.88, weight: .regular)
            }
            var attributes: [NSAttributedString.Key: Any] = [.font: runFont, .foregroundColor: color, .paragraphStyle: style]
            if intent.contains(.strikethrough) {
                attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
            }
            if run.link != nil {
                attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue
                attributes[.underlineColor] = stone
            }
            result.append(NSAttributedString(string: String(parsed[run.range].characters), attributes: attributes))
        }
        Self.applyUnderlines(in: result)
        result.append(NSAttributedString(string: "\n", attributes: [.font: font, .paragraphStyle: style]))
        return result
    }

    // MARK: - Photos

    private func imageID(in line: String) -> UUID? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("!["), let id = Markdown.imageIDs(in: trimmed).first else { return nil }
        return id
    }

    /// A photo on its own centered line, fitted to the text column and downsampled for a sensible file size.
    private func photo(_ id: UUID, in entry: Entry) -> NSAttributedString? {
        guard let attachment = entry.attachments?.first(where: { $0.identifier == id }),
              let data = attachment.imageData ?? attachment.thumbnailData,
              let image = UIImage(data: data), image.size.width > 0, image.size.height > 0
        else { return nil }

        let scale = min(content.width / image.size.width, content.height * 0.6 / image.size.height)
        let size = CGSize(width: (image.size.width * scale).rounded(), height: (image.size.height * scale).rounded())
        let format = UIGraphicsImageRendererFormat()
        format.scale = 2
        let jpeg = UIGraphicsImageRenderer(size: size, format: format).jpegData(withCompressionQuality: 0.8) { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }

        let textAttachment = NSTextAttachment()
        textAttachment.image = UIImage(data: jpeg, scale: 2)
        textAttachment.bounds = CGRect(origin: .zero, size: size)
        let result = NSMutableAttributedString(attachment: textAttachment)
        result.append(NSAttributedString(string: "\n"))
        result.addAttribute(.paragraphStyle, value: paragraph {
            $0.alignment = .center
            $0.paragraphSpacingBefore = 6
            $0.paragraphSpacing = 12
        }, range: NSRange(location: 0, length: result.length))
        return result
    }

    // MARK: - Styles

    private func paragraph(_ configure: (NSMutableParagraphStyle) -> Void) -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.lineSpacing = 3.5
        style.paragraphSpacing = 6
        configure(style)
        return style
    }

    /// "Mission District · ☀︎ 19°": the editor's line under the date — sans, in stone, the weather's
    /// symbol drawn as in the app — at the PDF's scale (the editor's `Typography.detail` is to its body
    /// as 10 is to the PDF's 11.5).
    private func placeLine(for entry: Entry) -> NSAttributedString {
        let font = UIFont.systemFont(ofSize: 10)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font, .foregroundColor: stone, .paragraphStyle: paragraph { $0.paragraphSpacing = 10 },
        ]
        let line = NSMutableAttributedString()
        if let place = entry.placeName {
            line.append(NSAttributedString(string: place, attributes: attributes))
        }
        if let weather = entry.weather {
            if entry.placeName != nil {
                line.append(NSAttributedString(string: " · ", attributes: attributes))
            }
            let configuration = UIImage.SymbolConfiguration(font: font)
            if let glyph = UIImage(systemName: weather.symbol, withConfiguration: configuration)?
                .withTintColor(stone, renderingMode: .alwaysOriginal) {
                // Flattened to a transparent bitmap first: the symbol as it is drew as a solid square
                // in the PDF.
                let format = UIGraphicsImageRendererFormat()
                format.scale = 4
                format.opaque = false
                let symbol = UIGraphicsImageRenderer(size: glyph.size, format: format).image { _ in
                    glyph.draw(at: .zero)
                }
                let attachment = NSTextAttachment(image: symbol)
                // Sat on the text's baseline, centred on its capitals.
                attachment.bounds = CGRect(
                    x: 0, y: (font.capHeight - symbol.size.height) / 2,
                    width: symbol.size.width, height: symbol.size.height
                )
                let image = NSMutableAttributedString(attachment: attachment)
                image.addAttributes(attributes, range: NSRange(location: 0, length: image.length))
                line.append(image)
            }
            line.append(NSAttributedString(string: " \(weather.formattedTemperature)", attributes: attributes))
        }
        line.append(NSAttributedString(string: "\n", attributes: attributes))
        return line
    }

    private func metaAttributes(_ style: NSParagraphStyle) -> [NSAttributedString.Key: Any] {
        [.font: UIFont.systemFont(ofSize: 8, weight: .semibold), .foregroundColor: stone, .kern: 1.1, .paragraphStyle: style]
    }

    private static func serif(_ size: CGFloat, _ weight: UIFont.Weight = .regular, italic: Bool = false) -> UIFont {
        var descriptor = UIFont.systemFont(ofSize: size, weight: weight).fontDescriptor
        descriptor = descriptor.withDesign(.serif) ?? descriptor
        if italic {
            descriptor = descriptor.withSymbolicTraits(descriptor.symbolicTraits.union(.traitItalic)) ?? descriptor
        }
        return UIFont(descriptor: descriptor, size: size)
    }
}

/// Treats a form feed as "continue on the next page".
private final class PageBreaks: NSObject, NSLayoutManagerDelegate {
    func layoutManager(
        _ layoutManager: NSLayoutManager,
        shouldUse action: NSLayoutManager.ControlCharacterAction,
        forControlCharacterAt charIndex: Int
    ) -> NSLayoutManager.ControlCharacterAction {
        let string = layoutManager.textStorage?.string as NSString?
        return string?.character(at: charIndex) == 0x0C ? .containerBreak : action
    }
}
