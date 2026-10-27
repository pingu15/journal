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

    /// Photos (not videos) taken on `day`, oldest first.
    static func photos(on day: Date) -> [PHAsset] {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: day)
        guard canRead, let end = calendar.date(byAdding: .day, value: 1, to: start) else { return [] }
        let options = PHFetchOptions()
        options.predicate = NSPredicate(format: "creationDate >= %@ AND creationDate < %@", start as NSDate, end as NSDate)
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: true)]
        let result = PHAsset.fetchAssets(with: .image, options: options)
        var assets: [PHAsset] = []
        result.enumerateObjects { asset, _, _ in assets.append(asset) }
        return assets
    }

    /// A square-cropped thumbnail about `side` points across.
    static func thumbnail(for asset: PHAsset, side: CGFloat) async -> UIImage? {
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
                continuation.resume(returning: image)
            }
        }
    }
}
