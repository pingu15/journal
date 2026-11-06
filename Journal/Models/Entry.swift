import CoreLocation
import Foundation
import SwiftData

/// A single journal entry, stored as Markdown. The first line doubles as the title, and images
/// are embedded as `![](image:<uuid>)` tokens that point at the entry's `Attachment`s.
///
/// Every stored property has a default, relationships are optional, and there
/// are no unique constraints, so the model stays compatible with CloudKit sync.
@Model
final class Entry {
    var createdAt: Date = Date.now
    var updatedAt: Date = Date.now
    var text: String = ""
    /// Set when the entry is moved to Recently Deleted; purged after `Entry.trashRetentionDays`.
    var deletedAt: Date? = nil

    // Optional place.
    var latitude: Double? = nil
    var longitude: Double? = nil
    var placeName: String? = nil

    // Weather at the place and time of the entry (from WeatherKit).
    var weatherSymbol: String? = nil
    var weatherCondition: String? = nil
    var temperatureCelsius: Double? = nil

    /// The embedded photo chosen to represent the entry (calendar, lists). Falls back to the first photo.
    var coverImageID: UUID? = nil

    @Relationship(deleteRule: .cascade, inverse: \Attachment.entry)
    var attachments: [Attachment]? = []

    init(text: String = "", createdAt: Date = .now) {
        self.text = text
        self.createdAt = createdAt
        self.updatedAt = createdAt
    }
}

// MARK: - Derived content

extension Entry {
    /// Embedded photos in the order they appear in the text.
    var photos: [Attachment] {
        let byID = Dictionary((attachments ?? []).map { ($0.identifier, $0) }, uniquingKeysWith: { first, _ in first })
        return Markdown.imageIDs(in: text).compactMap { byID[$0] }
    }

    var coverPhoto: Attachment? {
        let photos = photos
        return photos.first { $0.identifier == coverImageID } ?? photos.first
    }

    private var plainText: String {
        Markdown.plainText(text)
    }

    var hasText: Bool {
        !plainText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Nothing worth keeping — no text, photos, or place. Text as read: a new entry left with only
    /// its empty title line ("# ") is blank too.
    var isBlank: Bool {
        !hasText
            && (attachments ?? []).isEmpty
            && placeName == nil
    }

    private var lines: [String] {
        plainText.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    /// The first line with text, if it's in the Title style (`# `); otherwise the entry has no title.
    var title: String? {
        let first = text.split(whereSeparator: \.isNewline)
            .first { !Markdown.plainText(String($0)).trimmingCharacters(in: .whitespaces).isEmpty }
        guard let first, first.hasPrefix("# ") else { return nil }
        return lines.first
    }

    /// Everything after the title (or all of the text, when there's no title), as one line.
    var excerpt: String {
        lines.dropFirst(title == nil ? 0 : 1).joined(separator: " ")
    }

    var wordCount: Int {
        plainText.split { $0.isWhitespace || $0.isNewline }.count
    }

    /// At 230 words a minute, rounded up: any part of a minute counts as one.
    var readingMinutes: Int {
        max(1, Int((Double(wordCount) / 230).rounded(.up)))
    }

    var shareText: String {
        var header = createdAt.formatted(date: .complete, time: .shortened)
        if let placeName { header += " · \(placeName)" }
        return "\(header)\n\n\(Markdown.replacingImages(in: text, with: "[photo]"))"
    }

    /// Every word of `query` must match: text and place by substring; dates by whole word
    /// ("friday", "oct", "october", "6", "2025", "10/6/2025"), so "Oct 6" doesn't match Oct 16 or 2026.
    func matches(_ query: String) -> Bool {
        let words = query.lowercased().split(whereSeparator: \.isWhitespace).map(String.init)
        guard !words.isEmpty else { return true }
        // Searched as read: no Markdown syntax, and no image tokens (whose hex digits would match).
        let content = Markdown.plainText(text) + " " + (placeName ?? "")
        let dates = dateTokens
        return words.allSatisfy { word in
            content.localizedStandardContains(word)
                || dates.contains { token in
                    token == word || (word.count >= 3 && word.allSatisfy(\.isLetter) && token.hasPrefix(word))
                }
        }
    }

    private var dateTokens: Set<String> {
        let spellings = [
            createdAt.formatted(.dateTime.weekday(.wide).month(.wide).day().year()),
            createdAt.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated)),
            createdAt.formatted(date: .numeric, time: .omitted),
        ]
        let separators = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "/")).inverted
        return Set(
            spellings.joined(separator: " ").lowercased()
                .components(separatedBy: separators)
                .filter { !$0.isEmpty }
        )
    }
}

// MARK: - Place & weather

struct WeatherSummary {
    let symbol: String
    let condition: String
    let temperature: Measurement<UnitTemperature>

    var formattedTemperature: String {
        temperature.formatted(.measurement(width: .narrow, usage: .weather, numberFormatStyle: .number.precision(.fractionLength(0))))
    }
}

extension Entry {
    var location: CLLocation? {
        guard let latitude, let longitude else { return nil }
        return CLLocation(latitude: latitude, longitude: longitude)
    }

    func setPlace(name: String, coordinate: CLLocationCoordinate2D) {
        placeName = name
        latitude = coordinate.latitude
        longitude = coordinate.longitude
        clearWeather()
    }

    func clearPlace() {
        placeName = nil
        latitude = nil
        longitude = nil
        clearWeather()
    }

    var weather: WeatherSummary? {
        guard let weatherSymbol, let temperatureCelsius else { return nil }
        return WeatherSummary(
            symbol: weatherSymbol,
            condition: weatherCondition ?? "",
            temperature: Measurement(value: temperatureCelsius, unit: .celsius)
        )
    }

    func apply(_ snapshot: WeatherFetcher.Snapshot) {
        weatherSymbol = snapshot.symbol
        weatherCondition = snapshot.condition
        temperatureCelsius = snapshot.celsius
    }

    func clearWeather() {
        weatherSymbol = nil
        weatherCondition = nil
        temperatureCelsius = nil
    }
}

// MARK: - Lifecycle

extension Entry {
    static let trashRetentionDays = 30

    /// Creates and inserts an entry dated now.
    static func create(in context: ModelContext, at date: Date = .now) -> Entry {
        let entry = Entry(createdAt: date)
        context.insert(entry)
        return entry
    }

    func moveToTrash() {
        deletedAt = .now
    }

    func restore() {
        deletedAt = nil
    }

    var daysUntilPurge: Int {
        guard let deletedAt else { return Entry.trashRetentionDays }
        let elapsed = Calendar.current.dateComponents([.day], from: deletedAt, to: .now).day ?? 0
        return max(0, Entry.trashRetentionDays - elapsed)
    }

    static func purgeExpiredTrash(in context: ModelContext) {
        let descriptor = FetchDescriptor<Entry>(predicate: #Predicate { $0.deletedAt != nil })
        guard let trashed = try? context.fetch(descriptor) else { return }
        for entry in trashed where entry.daysUntilPurge == 0 {
            context.delete(entry)
        }
    }

    /// Removes entries that were created but never written in (e.g. an editor that was
    /// dismissed before it could clean up after itself). `keeping` are entries still open.
    static func deleteBlankEntries(in context: ModelContext, keeping open: Set<PersistentIdentifier>) {
        // Blank text is empty, or an empty title line ("# ") or bare line breaks: anything else
        // starts with a character worth keeping. Those are checked as read (`isBlank`).
        let descriptor = FetchDescriptor<Entry>(predicate: #Predicate {
            $0.deletedAt == nil && ($0.text == "" || $0.text.starts(with: "#") || $0.text.starts(with: "\n") || $0.text.starts(with: " "))
        })
        guard let candidates = try? context.fetch(descriptor) else { return }
        for entry in candidates where entry.isBlank && !open.contains(entry.persistentModelID) {
            context.delete(entry)
        }
    }

    /// Photos whose token was deleted from the text are no longer part of the entry.
    func removeUnreferencedPhotos(in context: ModelContext) {
        let referenced = Set(Markdown.imageIDs(in: text))
        for attachment in attachments ?? [] where !referenced.contains(attachment.identifier) {
            attachments?.removeAll { $0 == attachment }
            context.delete(attachment)
        }
    }

    /// Photos added before images were embedded in the text get appended as tokens.
    func embedLoosePhotos() {
        let referenced = Set(Markdown.imageIDs(in: text))
        let loose = (attachments ?? [])
            .filter { !referenced.contains($0.identifier) }
            .sorted { $0.createdAt < $1.createdAt }
        guard !loose.isEmpty else { return }
        for attachment in loose {
            attachment.identifier = UUID()
            text += (text.isEmpty || text.hasSuffix("\n") ? "" : "\n") + Markdown.imageToken(attachment.identifier) + "\n"
        }
    }
}

/// The user's name for their journal, shown as the home screen title (Settings → Name).
enum JournalName {
    static let storageKey = "journalName"
    static let `default` = "Journal"
    static let maxLength = 40

    static func display(_ stored: String) -> String {
        let trimmed = stored.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? Self.default : trimmed
    }
}
