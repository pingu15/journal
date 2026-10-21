import UIKit

enum ImageProcessing {
    struct Prepared: Sendable {
        let full: Data
        let thumbnail: Data
    }

    /// Downscales an imported photo to a sensible archive size plus a list thumbnail.
    /// Runs off the main actor so importing several photos doesn't hitch the editor.
    @concurrent
    nonisolated static func prepare(_ data: Data) async -> Prepared? {
        guard let image = UIImage(data: data),
              let full = resized(image, maxDimension: 2048).jpegData(compressionQuality: 0.85),
              let thumbnail = resized(image, maxDimension: 300).jpegData(compressionQuality: 0.8)
        else { return nil }
        return Prepared(full: full, thumbnail: thumbnail)
    }

    nonisolated private static func resized(_ image: UIImage, maxDimension: CGFloat) -> UIImage {
        let longest = max(image.size.width, image.size.height)
        guard longest > maxDimension else { return image }
        let scale = maxDimension / longest
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
    }
}
