import Foundation
import SwiftData

/// A photo embedded in an entry. The entry's text refers to it by `identifier`
/// (`![](image:<identifier>)`). The full image lives outside the database file;
/// the small thumbnail stays inline so lists can render without loading the original.
@Model
final class Attachment {
    var identifier: UUID = UUID()
    var createdAt: Date = Date.now
    @Attribute(.externalStorage) var imageData: Data? = nil
    var thumbnailData: Data? = nil
    var entry: Entry?

    init(imageData: Data, thumbnailData: Data) {
        self.identifier = UUID()
        self.imageData = imageData
        self.thumbnailData = thumbnailData
    }
}
