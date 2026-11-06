import ImageIO
import SwiftData
import SwiftUI

/// Every photo and video in the journal, newest entry first, two to a row as squares, each with its
/// entry's date in the corner, under a filter for all of them, photos or videos. Tapping one opens
/// its entry.
struct MediaView: View {
    @Environment(\.modelContext) private var context
    @Environment(AppRouter.self) private var router
    @Query(filter: #Predicate<Entry> { $0.deletedAt == nil }, sort: \Entry.createdAt, order: .reverse)
    private var entries: [Entry]

    @State private var path: [Entry] = []
    @State private var filter = MediaFilter.all

    /// A hairline between photos, which otherwise run edge to edge.
    private static let gap: CGFloat = 1
    private let columns = [GridItem(.flexible(), spacing: gap), GridItem(.flexible(), spacing: gap)]

    /// Each entry's photos and videos in the order they appear in it, as the filter allows.
    private var media: [(entry: Entry, photo: Attachment)] {
        entries.flatMap { entry in entry.photos.map { (entry, $0) } }
            .filter { filter.includes($0.photo) }
    }

    var body: some View {
        NavigationStack(path: $path) {
            // The filter stays put; only the photos scroll, under it.
            VStack(spacing: 0) {
                Picker("Show", selection: $filter) {
                    ForEach(MediaFilter.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, Spacing.content)
                // Clear of the grabber at the card's top.
                .padding(.top, Spacing.l)
                .padding(.bottom, Spacing.m)
                ScrollView {
                    LazyVGrid(columns: columns, spacing: Self.gap) {
                        ForEach(media, id: \.photo.identifier) { item in
                            Button {
                                path.append(item.entry)
                            } label: {
                                MediaTile(photo: item.photo, date: item.entry.createdAt)
                            }
                            // Fades a little when pressed: shrinking would open a gap in the edge-to-edge grid.
                            .buttonStyle(TapPressStyle(scale: 1, opacity: 0.7))
                        }
                    }
                }
                // Room for the floating tab bar below the last row, as the journal leaves.
                .contentMargins(.bottom, 96, for: .scrollContent)
            }
            .overlay {
                if media.isEmpty {
                    EmptyState(title: filter.emptyTitle, systemImage: filter.symbol, message: filter.emptyMessage)
                }
            }
            .pageTitle()
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    InsightsButton()
                }
                ToolbarItem(placement: .topBarTrailing) {
                    SettingsButton()
                }
            }
            .navigationDestination(for: Entry.self) { entry in
                EntryEditorView(entry: entry)
            }
        }
        // Hidden from the stack, not the editor, so it returns as soon as the editor starts closing.
        .toolbar(path.isEmpty ? .visible : .hidden, for: .tabBar)
        .onChange(of: path) { _, path in
            if path.isEmpty {
                Entry.deleteBlankEntries(in: context, keeping: router.openEntries)
            }
        }
    }
}

/// A photo cropped to a square, with its entry's date in the bottom-right corner in translucent white:
/// the day large and always two digits, the month and year small below it, both right-aligned.
private struct MediaTile: View {
    let photo: Attachment
    let date: Date

    @State private var image: UIImage?

    init(photo: Attachment, date: Date) {
        self.photo = photo
        self.date = date
        _image = State(initialValue: MediaImages.cached(photo.identifier) ?? ThumbnailCache.image(for: photo))
    }

    var body: some View {
        Theme.surface
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                }
            }
            .clipped()
            // A video's length, with a play mark, in the top-left corner.
            .overlay(alignment: .topLeading) {
                if photo.isVideo {
                    HStack(spacing: Spacing.xs) {
                        Image(systemName: "play.fill")
                        if let duration = photo.videoDuration {
                            Text(VideoProcessing.formatted(duration))
                        }
                    }
                    .font(Typography.mediaMonth)
                    .foregroundStyle(.white.opacity(0.85))
                    .shadow(color: .black.opacity(0.35), radius: 4)
                    .padding(Spacing.m)
                }
            }
            .overlay(alignment: .bottomTrailing) {
                VStack(alignment: .trailing, spacing: 0) {
                    Text(date.formatted(.dateTime.day(.twoDigits)))
                        .font(Typography.mediaDay)
                        .monospacedDigit()
                    Text(date.formatted(.dateTime.month(.wide).year()))
                        .font(Typography.mediaMonth)
                }
                .foregroundStyle(.white.opacity(0.85))
                // Readable on a light photo without a backing.
                .shadow(color: .black.opacity(0.35), radius: 4)
                .padding(Spacing.m)
            }
            .contentShape(.rect)
            // The list thumbnail first, then a sharper one, drawn off the main thread.
            .task(id: photo.identifier) {
                guard MediaImages.cached(photo.identifier) == nil, let data = photo.imageData else { return }
                if let sharp = await MediaImages.load(photo.identifier, from: data) { image = sharp }
            }
            .accessibilityElement()
            .accessibilityLabel("\(photo.isVideo ? "Video" : "Photo"), \(date.formatted(date: .long, time: .omitted))")
            .accessibilityAddTraits(.isButton)
    }
}

/// Photos downscaled to a tile's size, kept by attachment.
private enum MediaImages {
    private static let cache = NSCache<NSUUID, UIImage>()
    /// Pixels across: a tile is about half the screen wide.
    nonisolated private static let maxPixels = 700

    static func cached(_ id: UUID) -> UIImage? {
        cache.object(forKey: id as NSUUID)
    }

    static func load(_ id: UUID, from data: Data) async -> UIImage? {
        let image = await Task.detached(priority: .userInitiated) { downsample(data) }.value
        if let image { cache.setObject(image, forKey: id as NSUUID) }
        return image
    }

    nonisolated private static func downsample(_ data: Data) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixels,
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}

/// What Media shows.
private enum MediaFilter: String, CaseIterable, Identifiable {
    case all, photos, videos

    var id: Self { self }

    var title: String {
        switch self {
        case .all: "All"
        case .photos: "Photos"
        case .videos: "Videos"
        }
    }

    func includes(_ attachment: Attachment) -> Bool {
        switch self {
        case .all: true
        case .photos: !attachment.isVideo
        case .videos: attachment.isVideo
        }
    }

    var symbol: String {
        self == .videos ? "video" : "photo.on.rectangle"
    }

    var emptyTitle: String {
        switch self {
        case .all: "Nothing here yet"
        case .photos: "No photos yet"
        case .videos: "No videos yet"
        }
    }

    var emptyMessage: String {
        switch self {
        case .all: "Media you add to entries will appear here."
        case .photos: "Photos you add to entries will appear here."
        case .videos: "Videos you add to entries will appear here."
        }
    }
}
