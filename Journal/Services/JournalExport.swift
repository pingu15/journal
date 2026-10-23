import Foundation
import UIKit

/// Whole-journal exports, written to a temporary file for the share sheet.
enum JournalExport {
    enum Format: String, CaseIterable, Identifiable {
        case markdown, pdf

        var id: String { rawValue }

        var label: String {
            switch self {
            case .markdown: "Markdown"
            case .pdf: "PDF"
            }
        }

        var fileExtension: String {
            switch self {
            case .markdown: "md"
            case .pdf: "pdf"
            }
        }
    }

    /// Writes the live entries (oldest first, so the file reads like a book) and returns the file.
    static func write(_ format: Format, entries: [Entry], journalName: String) throws -> URL {
        let entries = entries.sorted { $0.createdAt < $1.createdAt }
        let stamp = Date.now.formatted(Date.ISO8601FormatStyle(timeZone: .current).year().month().day())
        let url = URL.temporaryDirectory.appending(path: "\(fileSafe(journalName)) \(stamp).\(format.fileExtension)")
        switch format {
        case .markdown:
            try markdown(entries: entries, journalName: journalName).write(to: url, atomically: true, encoding: .utf8)
        case .pdf:
            try JournalPDF(entries: entries, journalName: journalName).render().write(to: url, options: .atomic)
        }
        return url
    }

    /// One entry as a PDF (no title page), named after its title or, without one, its date.
    static func writePDF(of entry: Entry) throws -> URL {
        let name = entry.title ?? entry.createdAt.formatted(date: .abbreviated, time: .omitted)
        let url = URL.temporaryDirectory.appending(path: "\(fileSafe(name)).pdf")
        try JournalPDF(entries: [entry], journalName: name, includesTitlePage: false).render().write(to: url, options: .atomic)
        return url
    }

    static func markdown(entries: [Entry], journalName: String) -> String {
        let body = entries
            .map { entry in
                var section = "## \(entry.createdAt.formatted(date: .complete, time: .shortened))\n"
                let meta = metaParts(for: entry)
                if !meta.isEmpty { section += "\n*\(meta.joined(separator: " · "))*\n" }
                let content = Markdown.replacingImages(in: entry.text, with: "*(photo)*")
                section += "\n\(content.trimmingCharacters(in: .whitespacesAndNewlines))\n"
                return section
            }
            .joined(separator: "\n---\n\n")
        return "# \(journalName)\n\n\(body)"
    }

    /// Place and weather, for the line under an entry's date.
    static func metaParts(for entry: Entry) -> [String] {
        var meta: [String] = []
        if let place = entry.placeName { meta.append(place) }
        if let weather = entry.weather {
            meta.append([weather.formattedTemperature, weather.condition].filter { !$0.isEmpty }.joined(separator: " "))
        }
        return meta
    }

    private static func fileSafe(_ name: String) -> String {
        let cleaned = name.components(separatedBy: CharacterSet(charactersIn: "/\\:?%*|\"<>")).joined()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? JournalName.default : cleaned
    }
}
