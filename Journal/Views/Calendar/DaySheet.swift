import Photos
import SwiftUI

/// A day from the calendar, in a sheet that swipes down to close: the date with arrows to the day
/// before and after, that day's entries, then the photos taken that day from the photo library.
struct DaySheet: View {
    let entries: [Entry]
    let onOpen: (Entry) -> Void

    @State private var day: Date
    /// Which way the last arrow went, so the date slides out that way.
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
            VStack(spacing: Spacing.m) {
                entriesSection
                VStack(alignment: .leading, spacing: Spacing.s) {
                    MetaLabel("Photos")
                    DayPhotos(day: day)
                }
                .surfaceCard()
            }
        }
        .sensoryFeedback(.selection, trigger: day)
    }

    private var header: some View {
        ZStack {
            SheetHeader(
                title: day.formatted(.dateTime.month(.wide).day().year()),
                label: day.formatted(.dateTime.weekday(.wide))
            )
            .id(day)
            .transition(.asymmetric(
                insertion: .move(edge: movingForward ? .trailing : .leading),
                removal: .move(edge: movingForward ? .leading : .trailing)
            ))
        }
        // Out to the sheet's edges, so the dates slide right across it.
        .padding(.horizontal, Spacing.m + 4)
        .clipped()
        .padding(.horizontal, -(Spacing.m + 4))
        .overlay(alignment: .leading) {
            arrow("Previous Day", "chevron.left", by: -1)
        }
        .overlay(alignment: .trailing) {
            arrow("Next Day", "chevron.right", by: 1)
        }
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
        // On the next turn: the outgoing date takes its transition from the last update, so the
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
    @State private var assets: [PHAsset] = []
    @State private var loaded = false

    private let columns = [GridItem(.adaptive(minimum: 96), spacing: 4)]

    var body: some View {
        // A stack, not a Group: before loading there's nothing to show, and an empty Group never appears.
        VStack(alignment: .leading, spacing: 0) {
            switch status {
            case .notDetermined:
                Button {
                    Task {
                        status = await PhotoLibrary.requestAccess()
                        load()
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
                    if loaded {
                        Text("No photos from this day.")
                            .font(Typography.note)
                            .foregroundStyle(Theme.secondaryText)
                            .padding(.vertical, Spacing.xs)
                    }
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
        .onChange(of: day) { load() }
        .onAppear { load() }
    }

    private func load() {
        assets = PhotoLibrary.photos(on: day)
        loaded = true
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
