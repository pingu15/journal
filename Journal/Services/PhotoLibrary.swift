import Photos
import UIKit

/// Read-only access to the user's photo library, for showing the photos taken on a day.
enum PhotoLibrary {
    static var status: PHAuthorizationStatus {
        PHPhotoLibrary.authorizationStatus(for: .readWrite)
    }

    static var canRead: Bool {
        [.authorized, .limited].contains(status)
    }

    /// Asks for access if it hasn't been asked yet; returns the resulting status.
    static func requestAccess() async -> PHAuthorizationStatus {
        guard status == .notDetermined else { return status }
        return await SystemPrompts.shared.during {
            await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        }
    }

    /// Days already fetched, so a day sliding into the day sheet (fetched ahead, with its
    /// thumbnails) doesn't fetch again on the way; all dropped when the library changes.
    private static var fetched: [Date: [PHAsset]] = [:]
    private static let changes: LibraryChanges = {
        let changes = LibraryChanges()
        PHPhotoLibrary.shared().register(changes)
        return changes
    }()

    private final class LibraryChanges: NSObject, PHPhotoLibraryChangeObserver {
        nonisolated func photoLibraryDidChange(_ changeInstance: PHChange) {
            Task { @MainActor in PhotoLibrary.fetched = [:] }
        }
    }

    /// Photos (not videos) taken on `day`, oldest first.
    static func photos(on day: Date) -> [PHAsset] {
        let start = Calendar.current.startOfDay(for: day)
        guard canRead else { return [] }
        _ = changes
        if let assets = fetched[start] { return assets }
        let assets = fetchPhotos(from: start)
        fetched[start] = assets
        return assets
    }

    /// How many videos were taken on `day` (the widgets' count; the day sheet shows photos only).
    static func videoCount(on day: Date) -> Int {
        guard canRead else { return 0 }
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: day)
        guard let end = calendar.date(byAdding: .day, value: 1, to: start) else { return 0 }
        let options = PHFetchOptions()
        options.predicate = NSPredicate(format: "creationDate >= %@ AND creationDate < %@", start as NSDate, end as NSDate)
        return PHAsset.fetchAssets(with: .video, options: options).count
    }

    /// A square-cropped image about `pixels` across, fetched at once (on device only, never from
    /// iCloud), for the widgets' snapshot.
    static func imageNow(for asset: PHAsset, pixels: CGFloat) -> UIImage? {
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

    private static func fetchPhotos(from start: Date) -> [PHAsset] {
        let calendar = Calendar.current
        guard let end = calendar.date(byAdding: .day, value: 1, to: start) else { return [] }
        let options = PHFetchOptions()
        options.predicate = NSPredicate(format: "creationDate >= %@ AND creationDate < %@", start as NSDate, end as NSDate)
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: true)]
        let result = PHAsset.fetchAssets(with: .image, options: options)
        var assets: [PHAsset] = []
        result.enumerateObjects { asset, _, _ in assets.append(asset) }
        return assets
    }

    private static let thumbnails = NSCache<NSString, UIImage>()

    private static func key(_ asset: PHAsset, _ side: CGFloat) -> NSString {
        "\(asset.localIdentifier)@\(Int(side))" as NSString
    }

    /// A thumbnail already fetched, to show at once.
    static func cachedThumbnail(for asset: PHAsset, side: CGFloat) -> UIImage? {
        thumbnails.object(forKey: key(asset, side))
    }

    /// Fetches the first photos' thumbnails from `day` ahead of time, so they're there the moment
    /// they're shown.
    static func preloadThumbnails(on day: Date, side: CGFloat, limit: Int = 24) async {
        for asset in photos(on: day).prefix(limit) where cachedThumbnail(for: asset, side: side) == nil {
            _ = await thumbnail(for: asset, side: side)
        }
    }

    /// The whole photo at twice the screen's size (room to zoom), for the full-screen viewer.
    static func fullImage(for asset: PHAsset) async -> UIImage? {
        let screen = UIScreen.main.bounds.size
        let scale = UIScreen.main.scale * 2
        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.isNetworkAccessAllowed = true
        return await withCheckedContinuation { continuation in
            PHImageManager.default().requestImage(
                for: asset,
                targetSize: CGSize(width: screen.width * scale, height: screen.height * scale),
                contentMode: .aspectFit,
                options: options
            ) { image, _ in
                continuation.resume(returning: image)
            }
        }
    }

    /// A square-cropped thumbnail about `side` points across.
    static func thumbnail(for asset: PHAsset, side: CGFloat) async -> UIImage? {
        if let cached = cachedThumbnail(for: asset, side: side) { return cached }
        let scale = UIScreen.main.scale
        let options = PHImageRequestOptions()
        // One callback with the final image (opportunistic delivery calls back twice).
        options.deliveryMode = .highQualityFormat
        options.resizeMode = .fast
        options.isNetworkAccessAllowed = true
        return await withCheckedContinuation { continuation in
            PHImageManager.default().requestImage(
                for: asset,
                targetSize: CGSize(width: side * scale, height: side * scale),
                contentMode: .aspectFill,
                options: options
            ) { image, _ in
                if let image { thumbnails.setObject(image, forKey: key(asset, side)) }
                continuation.resume(returning: image)
            }
        }
    }
}
