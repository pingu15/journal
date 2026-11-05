import Foundation
import SwiftData

/// A photo or video embedded in an entry. The entry's text refers to it by `identifier`
/// (`![](image:<identifier>)`, a video too). The full image lives outside the database file;
/// the small thumbnail stays inline so lists can render without loading the original. A video's
/// image is its first frame, so it shows like a photo wherever one does (lists, covers, Media, the
/// PDF), and the video itself is `videoData`.
@Model
final class Attachment {
    var identifier: UUID = UUID()
    var createdAt: Date = Date.now
    @Attribute(.externalStorage) var imageData: Data? = nil
    var thumbnailData: Data? = nil
    @Attribute(.externalStorage) var videoData: Data? = nil
    /// Seconds; a video's only.
    var videoDuration: Double? = nil
    var entry: Entry?

    init(imageData: Data, thumbnailData: Data) {
        self.identifier = UUID()
        self.imageData = imageData
        self.thumbnailData = thumbnailData
    }

    var isVideo: Bool { videoData != nil }

    /// A copy for another place in the text (a paste): its own identifier, the same picture and video.
    func duplicate() -> Attachment? {
        guard let imageData else { return nil }
        let copy = Attachment(imageData: imageData, thumbnailData: thumbnailData ?? imageData)
        copy.videoData = videoData
        copy.videoDuration = videoDuration
        return copy
    }
}
