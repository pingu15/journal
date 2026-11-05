import Foundation

/// Plain-text helpers for the Markdown stored in `Entry.text`.
/// (Rich rendering for editing lives in `MarkdownStyler`.)
nonisolated enum Markdown {
    private static func regex(_ pattern: String, _ options: NSRegularExpression.Options = []) -> NSRegularExpression {
        try! NSRegularExpression(pattern: pattern, options: options)
    }

    static let imagePattern = regex(#"!\[[^\]\n]*\]\(image:([0-9A-Fa-f-]{36})\)"#)

    static func imageToken(_ id: UUID) -> String {
        "![](image:\(id.uuidString))"
    }

    static func imageIDs(in text: String) -> [UUID] {
        let ns = text as NSString
        return imagePattern.matches(in: text, range: NSRange(location: 0, length: ns.length))
            .compactMap { UUID(uuidString: ns.substring(with: $0.range(at: 1))) }
    }

    static func replacingImages(in text: String, with replacement: String) -> String {
        imagePattern.stringByReplacingMatches(
            in: text, range: NSRange(location: 0, length: (text as NSString).length),
            withTemplate: NSRegularExpression.escapedTemplate(for: replacement)
        )
    }

    private static let stripRules: [(NSRegularExpression, String)] = [
        (imagePattern, ""),
        (regex(#"^[ \t]{0,3}#{1,6}[ \t]+"#, .anchorsMatchLines), ""),
        (regex(#"^[ \t]*>[ \t]?"#, .anchorsMatchLines), ""),
        (regex(#"^[ \t]*[-*+][ \t]+\[[ xX]\][ \t]+"#, .anchorsMatchLines), ""),
        (regex(#"^[ \t]*[-*+][ \t]+"#, .anchorsMatchLines), ""),
        (regex(#"^[ \t]*\d+[.)][ \t]+"#, .anchorsMatchLines), ""),
        (regex(#"^[ \t]*([-*_])([ \t]*\1){2,}[ \t]*$"#, .anchorsMatchLines), ""),
        (regex(#"\[([^\]\n]+)\]\([^)\n]*\)"#), "$1"),
        (regex(#"(\*\*|__|~~|`)"#), ""),
        (regex(#"(?<![\w*])\*(?=\S)([^*\n]+?)(?<=\S)\*(?![\w*])"#), "$1"),
        (regex(#"(?<![\w_])_(?=\S)([^_\n]+?)(?<=\S)_(?![\w_])"#), "$1"),
    ]

    private static let escapedCharacter = regex(#"\\([\p{P}\p{S}])"#)

    /// The text as a reader would see it: no syntax, no image tokens. Backslash-escaped characters
    /// are literal text, so they're set aside while the syntax is stripped.
    static func plainText(_ text: String) -> String {
        var escapes: [String] = []
        let ns = text as NSString
        var protected = ""
        var cursor = 0
        for match in escapedCharacter.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            protected += ns.substring(with: NSRange(location: cursor, length: match.range.location - cursor))
            protected += String(UnicodeScalar(0xE000 + escapes.count) ?? "?")
            escapes.append(ns.substring(with: match.range(at: 1)))
            cursor = NSMaxRange(match.range)
        }
        protected += ns.substring(from: cursor)

        var result = stripRules.reduce(protected) { result, rule in
            rule.0.stringByReplacingMatches(
                in: result, range: NSRange(location: 0, length: (result as NSString).length),
                withTemplate: rule.1
            )
        }
        for (index, character) in escapes.enumerated() {
            if let scalar = UnicodeScalar(0xE000 + index) {
                result = result.replacingOccurrences(of: String(scalar), with: character)
            }
        }
        return result
    }
}
