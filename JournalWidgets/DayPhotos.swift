import Photos
import UIKit

/// A day's photos as the Today widget shows them, read from the library by the widget itself (the
/// extension shares the app's Photos access; it can't ask for it). Counts include every photo and
/// video; the collage keeps the newest few.
struct DayPhotos {
    var images: [UIImage] = []
    var photos = 0
    var videos = 0

    /// Photos kept for the collage.
    static let collageLimit = 3
    /// A collage photo's side, in pixels: the largest tile at 3x, with room to spare.
    static let pixels: CGFloat = 600

    static var canRead: Bool {
        [.authorized, .limited].contains(PHPhotoLibrary.authorizationStatus(for: .readWrite))
    }

    /// The day's photos and videos, or nil without access to the library.
    static func load(on day: Date, calendar: Calendar = .current) -> DayPhotos? {
        guard canRead else { return nil }
        let start = calendar.startOfDay(for: day)
        guard let end = calendar.date(byAdding: .day, value: 1, to: start) else { return nil }
        let options = PHFetchOptions()
        options.predicate = NSPredicate(format: "creationDate >= %@ AND creationDate < %@", start as NSDate, end as NSDate)
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]

        let photos = PHAsset.fetchAssets(with: .image, options: options)
        var newest: [PHAsset] = []
        photos.enumerateObjects { asset, index, stop in
            newest.append(asset)
            if index + 1 >= collageLimit { stop.pointee = true }
        }
        return DayPhotos(
            images: newest.compactMap(image),
            photos: photos.count,
            videos: PHAsset.fetchAssets(with: .video, options: options).count
        )
    }

    /// A square-cropped image, fetched at once from what's on the device (never from iCloud).
    private static func image(for asset: PHAsset) -> UIImage? {
        let options = PHImageRequestOptions()
        options.isSynchronous = true
        options.deliveryMode = .highQualityFormat
        options.resizeMode = .fast
        options.isNetworkAccessAllowed = false
        var result: UIImage?
        PHImageManager.default().requestImage(
            for: asset, targetSize: CGSize(width: pixels, height: pixels), contentMode: .aspectFill, options: options
        ) { image, _ in result = image }
        return result
    }
}
