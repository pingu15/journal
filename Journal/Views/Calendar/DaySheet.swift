import Photos
import SwiftUI

/// A day from the calendar, in a sheet that swipes down to close: the date with arrows to the day
/// before and after, that day's entries, then the photos taken that day from the photo library.
struct DaySheet: View {
    let entries: [Entry]
    let onOpen: (Entry) -> Void

    @State private var day: Date
    /// Which way the last arrow went, so the day slides out that way.
    @State private var movingForward = true
    private let calendar = Calendar.current

    init(day: Date, entries: [Entry], onOpen: @escaping (Entry) -> Void) {
        _day = State(initialValue: Calendar.current.startOfDay(for: day))
        self.entries = entries
        self.onOpen = onOpen
    }

    var body: some View {
        SheetPage {
            header
        } content: {
            slidingDay {
                VStack(spacing: Spacing.m) {
                    entriesSection
                    VStack(alignment: .leading, spacing: Spacing.s) {
                        MetaLabel("Photos")
                        DayPhotos(day: day)
                    }
                    .surfaceCard()
                }
            }
        }
        .presentationDetents([.medium, .large])
        .sheetGrabber()
        .sensoryFeedback(.selection, trigger: day)
    }

    private var header: some View {
        slidingDay {
            SheetHeader(
                title: day.formatted(.dateTime.month(.wide).day().year()),
                label: day.formatted(.dateTime.weekday(.wide))
            )
        }
        .overlay(alignment: .leading) {
            arrow("Previous Day", "chevron.left", by: -1)
        }
        .overlay(alignment: .trailing) {
            arrow("Next Day", "chevron.right", by: 1)
        }
    }

    /// Part of the page that belongs to the day, sliding across the sheet when the day changes. It
    /// moves with the page's margins inside it, out to the sheet's edges: a move goes by the view's
    /// own width, which would otherwise leave the cards' ends showing until they're removed.
    private func slidingDay<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        ZStack(alignment: .top) {
            content()
                .padding(.horizontal, Spacing.m + 4)
                .id(day)
                .transition(.asymmetric(
                    insertion: .move(edge: movingForward ? .trailing : .leading),
                    removal: .move(edge: movingForward ? .leading : .trailing)
                ))
        }
        // Only at the sides: the height changes as it goes, which would cut off the taller day.
        .mask { Color.black.padding(.vertical, -2000) }
        .padding(.horizontal, -(Spacing.m + 4))
    }

    private func arrow(_ label: String, _ symbol: String, by days: Int) -> some View {
        Button(label, systemImage: symbol) { shift(by: days) }
            .labelStyle(.iconOnly)
            .font(Typography.action)
            .foregroundStyle(Theme.primaryText)
            .buttonStyle(.plain)
            .frame(width: 44, height: 44)
            .contentShape(.rect)
    }

    @ViewBuilder
    private var entriesSection: some View {
        let dayEntries = entries.filter { calendar.isDate($0.createdAt, inSameDayAs: day) }

        if dayEntries.isEmpty {
            Text(day > .now ? "This day hasn't happened yet." : "Nothing written on this day.")
                .font(Typography.note)
                .foregroundStyle(Theme.secondaryText)
                .surfaceCard()
        } else {
            ForEach(dayEntries) { entry in
                Button {
                    onOpen(entry)
                } label: {
                    EntryRow(entry: entry, dateStyle: .none)
                        .surfaceCard()
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func shift(by days: Int) {
        guard let next = calendar.date(byAdding: .day, value: days, to: day) else { return }
        movingForward = days > 0
        // On the next turn: the outgoing day takes its transition from the last update, so the
        // direction has to be in place before the day changes.
        DispatchQueue.main.async {
            withAnimation(.snappy) { day = next }
        }
    }
}

/// The photos the user took on a day, from their library (asks for access the first time).
private struct DayPhotos: View {
    let day: Date

    @Environment(\.openURL) private var openURL
    @State private var status = PhotoLibrary.status
    @State private var assets: [PHAsset]

    private let columns = [GridItem(.adaptive(minimum: 96), spacing: 4)]

    init(day: Date) {
        self.day = day
        // Here, not on appear: a day's card slides in whole, and anything added to it once it's moving
        // takes a path of its own.
        _assets = State(initialValue: PhotoLibrary.photos(on: day))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            switch status {
            case .notDetermined:
                Button {
                    Task {
                        status = await PhotoLibrary.requestAccess()
                        assets = PhotoLibrary.photos(on: day)
                    }
                } label: {
                    Label("Show Photos From Your Library", systemImage: "photo.on.rectangle")
                        .font(Typography.action)
                        .foregroundStyle(Theme.onAccent)
                        .padding(.horizontal, Spacing.m)
                        .padding(.vertical, Spacing.s + 2)
                        .background(Theme.accent, in: .capsule)
                }
                .buttonStyle(.plain)
            case .denied, .restricted:
                Button {
                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                } label: {
                    Text("Photo access is off for Journal. ") + Text("Open Settings").underline()
                }
                .font(Typography.note)
                .foregroundStyle(Theme.secondaryText)
                .multilineTextAlignment(.leading)
                .buttonStyle(.plain)
            default:
                if assets.isEmpty {
                    Text("No photos from this day.")
                        .font(Typography.note)
                        .foregroundStyle(Theme.secondaryText)
                        .padding(.vertical, Spacing.xs)
                } else {
                    LazyVGrid(columns: columns, spacing: 4) {
                        ForEach(assets, id: \.localIdentifier) { asset in
                            AssetThumbnail(asset: asset)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct AssetThumbnail: View {
    let asset: PHAsset
    @State private var image: UIImage?

    var body: some View {
        Color.primary.opacity(0.06)
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .transition(.opacity)
                }
            }
            .clipShape(.rect(cornerRadius: 6, style: .continuous))
            .task(id: asset.localIdentifier) {
                let thumbnail = await PhotoLibrary.thumbnail(for: asset, side: 120)
                withAnimation(.easeOut(duration: 0.2)) { image = thumbnail }
            }
            .accessibilityLabel(asset.creationDate?.formatted(date: .omitted, time: .shortened) ?? "Photo")
    }
}
