import AVFoundation
import CoreTransferable
import UIKit
import UniformTypeIdentifiers

/// A video picked from the library, copied to a temporary file (the picker's own file goes away).
struct PickedMovie: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { movie in
            SentTransferredFile(movie.url)
        } importing: { received in
            let copy = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension(received.file.pathExtension.isEmpty ? "mov" : received.file.pathExtension)
            try FileManager.default.copyItem(at: received.file, to: copy)
            return PickedMovie(url: copy)
        }
    }
}

/// Imported videos: re-encoded to a sensible size (1080p HEVC, any length), with their first frame
/// as the picture an entry shows.
enum VideoProcessing {
    struct Prepared: Sendable {
        let video: Data
        let poster: ImageProcessing.Prepared
        let duration: Double
    }

    @concurrent
    nonisolated static func prepare(_ source: URL) async -> Prepared? {
        defer { try? FileManager.default.removeItem(at: source) }
        let asset = AVURLAsset(url: source)
        guard let duration = try? await asset.load(.duration).seconds else { return nil }

        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 2048, height: 2048)
        guard let frame = try? await generator.image(at: .zero).image,
              let posterData = UIImage(cgImage: frame).jpegData(compressionQuality: 0.9),
              let poster = await ImageProcessing.prepare(posterData)
        else { return nil }

        let output = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString).appendingPathExtension("mp4")
        defer { try? FileManager.default.removeItem(at: output) }
        var video: Data?
        if let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetHEVC1920x1080) {
            try? await session.export(to: output, as: .mp4)
            video = try? Data(contentsOf: output)
        }
        // A video that can't be re-encoded is kept as it came.
        guard let video = video ?? (try? Data(contentsOf: source)) else { return nil }
        return Prepared(video: video, poster: poster, duration: duration)
    }

    /// The video as a file to play, written once to the caches and reused.
    static func playableURL(for attachment: Attachment) -> URL? {
        let folder = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Videos", isDirectory: true)
        let url = folder.appendingPathComponent(attachment.identifier.uuidString).appendingPathExtension("mp4")
        if FileManager.default.fileExists(atPath: url.path) { return url }
        guard let data = attachment.videoData else { return nil }
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        guard (try? data.write(to: url)) != nil else { return nil }
        return url
    }

    /// "0:42", "1:05:09".
    static func formatted(_ seconds: Double) -> String {
        let total = Int(seconds.rounded())
        let (hours, minutes, secs) = (total / 3600, total / 60 % 60, total % 60)
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, secs)
            : String(format: "%d:%02d", minutes, secs)
    }

    /// A video's picture as the editor shows it: its first frame with a play button and its length.
    static func badged(_ poster: UIImage, duration: Double?) -> UIImage {
        let size = poster.size
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = poster.scale
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            poster.draw(at: .zero)
            let unit = min(size.width, size.height)
            // The play button, centered.
            let diameter = unit * 0.18
            let circle = CGRect(x: (size.width - diameter) / 2, y: (size.height - diameter) / 2, width: diameter, height: diameter)
            UIColor.black.withAlphaComponent(0.45).setFill()
            UIBezierPath(ovalIn: circle).fill()
            let configuration = UIImage.SymbolConfiguration(pointSize: diameter * 0.42, weight: .bold)
            if let play = UIImage(systemName: "play.fill", withConfiguration: configuration)?
                .withTintColor(.white, renderingMode: .alwaysOriginal) {
                // Nudged right, as a triangle's weight sits left of its box's center.
                play.draw(at: CGPoint(x: circle.midX - play.size.width / 2 + diameter * 0.04, y: circle.midY - play.size.height / 2))
            }
            // Its length, in the bottom-right corner.
            if let duration {
                let font = UIFont.systemFont(ofSize: unit * 0.06, weight: .semibold)
                let text = formatted(duration) as NSString
                let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: UIColor.white]
                let textSize = text.size(withAttributes: attributes)
                let padding = unit * 0.025
                let pill = CGRect(
                    x: size.width - textSize.width - padding * 4,
                    y: size.height - textSize.height - padding * 3,
                    width: textSize.width + padding * 2,
                    height: textSize.height + padding
                )
                UIColor.black.withAlphaComponent(0.45).setFill()
                UIBezierPath(roundedRect: pill, cornerRadius: pill.height / 2).fill()
                text.draw(at: CGPoint(x: pill.minX + padding, y: pill.minY + padding / 2), withAttributes: attributes)
            }
        }
    }
}
