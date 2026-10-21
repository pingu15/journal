import Foundation

/// Plain-text helpers for the Markdown stored in `Entry.text`.
/// (Rich rendering for editing lives in `MarkdownStyler`.)
nonisolated enum Markdown {
    private static func regex(_ pattern: String, _ options: NSRegularExpression.Options = []) -> NSRegularExpression {
        try! NSRegularExpression(pattern: pattern, options: options)
    }

    static let imagePattern = regex(#"!\[[^\]\n]*\]\(image:([0-9A-Fa-f-]{36})\)"#)
    static let tagPattern = regex(#"(?<![\w#&/])#([\p{L}\p{N}_-]*[\p{L}_-][\p{L}\p{N}_-]*)"#)

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

    static func tags(in text: String) -> [String] {
        let ns = text as NSString
        return tagPattern.matches(in: text, range: NSRange(location: 0, length: ns.length))
            .map { ns.substring(with: $0.range(at: 1)).lowercased() }
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

    /// The text as a reader would see it: no syntax, no image tokens.
    static func plainText(_ text: String) -> String {
        stripRules.reduce(text) { result, rule in
            rule.0.stringByReplacingMatches(
                in: result, range: NSRange(location: 0, length: (result as NSString).length),
                withTemplate: rule.1
            )
        }
    }
}
