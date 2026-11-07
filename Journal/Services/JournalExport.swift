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
            case .markdown: "zip"
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
            try writeMarkdownArchive(entries: entries, folderName: url.deletingPathExtension().lastPathComponent, to: url)
        case .pdf:
            try JournalPDF(entries: entries, journalName: journalName).render().write(to: url, options: .atomic)
        }
        return url
    }

    /// Shares one entry as a PDF through the share sheet (the editor's ⋯ menu, a row's swipe and
    /// context menu).
    static func sharePDF(of entry: Entry) async {
        guard let url = try? writePDF(of: entry) else { return }
        await ShareSheet.present(url)
    }

    /// One entry as a PDF (no title page), named after its title or, without one, its date.
    static func writePDF(of entry: Entry) throws -> URL {
        let name = entry.title ?? entry.createdAt.formatted(date: .abbreviated, time: .omitted)
        let url = URL.temporaryDirectory.appending(path: "\(fileSafe(name)).pdf")
        try JournalPDF(entries: [entry], journalName: name, includesTitlePage: false).render().write(to: url, options: .atomic)
        return url
    }

    /// The journal as a zip of Markdown files: a folder named like the zip, one `.md` per entry
    /// ("2026-11-06 Morning pages.md"; its date when it has no title), each starting with its date,
    /// place and weather in italics and then the entry as written; photos and videos in `Media/`
    /// beside them, linked where they sit in the text.
    static func writeMarkdownArchive(entries: [Entry], folderName: String, to url: URL) throws {
        let fileManager = FileManager.default
        let staging = URL.temporaryDirectory.appending(path: UUID().uuidString)
        let folder = staging.appending(path: folderName)
        let media = folder.appending(path: "Media")
        try fileManager.createDirectory(at: media, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: staging) }

        var usedNames = Set<String>()
        var hasMedia = false
        for entry in entries {
            let stamp = entry.createdAt.formatted(Date.ISO8601FormatStyle(timeZone: .current).year().month().day())
            let base = "\(stamp) \(fileSafe(fileTitle(for: entry)))"
            var name = base
            var copy = 2
            while usedNames.contains(name.lowercased()) {
                name = "\(base) \(copy)"
                copy += 1
            }
            usedNames.insert(name.lowercased())

            let (body, files) = markdown(for: entry)
            for (fileName, data) in files {
                try data.write(to: media.appending(path: fileName), options: .atomic)
                hasMedia = true
            }
            try body.write(to: folder.appending(path: "\(name).md"), atomically: true, encoding: .utf8)
        }
        if !hasMedia { try? fileManager.removeItem(at: media) }

        // Zipped by the system: reading a folder "for uploading" hands back a zip of it.
        var coordinationError: NSError?
        var copyError: Error?
        NSFileCoordinator().coordinate(readingItemAt: folder, options: .forUploading, error: &coordinationError) { zipped in
            do {
                try? fileManager.removeItem(at: url)
                try fileManager.copyItem(at: zipped, to: url)
            } catch {
                copyError = error
            }
        }
        if let error = coordinationError ?? copyError { throw error }
    }

    /// What an entry's file is called after its date: its title, else its first words, else (a photo
    /// alone, say) its time, as 24-hour digits — a colon can't go in a file name.
    private static func fileTitle(for entry: Entry) -> String {
        if let title = entry.title { return String(title.prefix(60)) }
        let words = Markdown.plainText(entry.text).split(whereSeparator: \.isWhitespace)
        var name = ""
        for word in words {
            guard name.count + word.count < 40 else { break }
            name += (name.isEmpty ? "" : " ") + word
        }
        // No dangling punctuation before ".md" ("again..md", "Slow,.md").
        name = name.trimmingCharacters(in: .punctuationCharacters.union(.whitespaces))
        if !name.isEmpty { return name }
        let time = Calendar.current.dateComponents([.hour, .minute], from: entry.createdAt)
        return String(format: "%02d.%02d", time.hour ?? 0, time.minute ?? 0)
    }

    /// One entry as Markdown, its photos and videos as files for `Media/` (by name) and linked there:
    /// a photo shown, a video as its first frame linking to the video.
    static func markdown(for entry: Entry) -> (String, [(String, Data)]) {
        var header = entry.createdAt.formatted(date: .complete, time: .shortened)
        let meta = metaParts(for: entry)
        if !meta.isEmpty { header += " · " + meta.joined(separator: " · ") }

        var files: [(String, Data)] = []
        var text = entry.text
        let byID = Dictionary((entry.attachments ?? []).map { ($0.identifier, $0) }, uniquingKeysWith: { first, _ in first })
        for id in Markdown.imageIDs(in: entry.text) {
            let token = Markdown.imageToken(id)
            guard let attachment = byID[id], let image = attachment.imageData else {
                text = text.replacingOccurrences(of: token, with: "")
                continue
            }
            // As JPEG, whatever it was stored as, so any Markdown app shows it.
            let picture = UIImage(data: image)?.jpegData(compressionQuality: 0.9) ?? image
            let pictureName = "\(id.uuidString).jpg"
            files.append((pictureName, picture))
            var link = "![](Media/\(pictureName))"
            if let video = attachment.videoData {
                let videoName = "\(id.uuidString).mov"
                files.append((videoName, video))
                link = "[\(link)](Media/\(videoName))"
            }
            text = text.replacingOccurrences(of: token, with: link)
        }
        let body = "*\(header)*\n\n\(text.trimmingCharacters(in: .whitespacesAndNewlines))\n"
        return (body, files)
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
