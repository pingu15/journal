import Photos
import SwiftUI

/// A day from the calendar, in a sheet that swipes down to close: the date with arrows to the day
/// before and after, that day's entries, then the photos taken that day from the photo library.
struct DaySheet: View {
    let entries: [Entry]
    let onOpen: (Entry) -> Void

    @State private var day: Date
    private let calendar = Calendar.current

    init(day: Date, entries: [Entry], onOpen: @escaping (Entry) -> Void) {
        _day = State(initialValue: Calendar.current.startOfDay(for: day))
        self.entries = entries
        self.onOpen = onOpen
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.l) {
                header
                entriesSection
                VStack(alignment: .leading, spacing: Spacing.s) {
                    MetaLabel("Photos")
                    DayPhotos(day: day)
                }
            }
            .padding(.horizontal, Spacing.m + 4)
            .padding(.top, Spacing.l)
            .padding(.bottom, Spacing.l)
        }
        .scrollIndicators(.hidden)
        .background(Theme.background)
        .presentationDetents([.medium, .large])
        .sheetGrabber()
        .sensoryFeedback(.selection, trigger: day)
    }

    private var header: some View {
        HStack {
            Button("Previous Day", systemImage: "chevron.left") { shift(by: -1) }
                .frame(width: 44, height: 44)
                .contentShape(.rect)
            Spacer(minLength: 0)
            VStack(spacing: 2) {
                Text(day.formatted(.dateTime.month(.wide).day()))
                    .font(Typography.title)
                    .foregroundStyle(Theme.primaryText)
                MetaLabel("\(day.formatted(.dateTime.weekday(.wide))) · \(day.formatted(.dateTime.year()))")
            }
            .contentTransition(.numericText())
            Spacer(minLength: 0)
            Button("Next Day", systemImage: "chevron.right") { shift(by: 1) }
                .frame(width: 44, height: 44)
                .contentShape(.rect)
        }
        .labelStyle(.iconOnly)
        .font(Typography.action)
        .foregroundStyle(Theme.primaryText)
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var entriesSection: some View {
        let dayEntries = entries.filter { calendar.isDate($0.createdAt, inSameDayAs: day) }

        VStack(alignment: .leading, spacing: Spacing.s) {
            MetaLabel("Entries")

            if dayEntries.isEmpty {
                Text(day > .now ? "This day hasn't happened yet." : "Nothing written on this day.")
                    .font(Typography.note)
                    .foregroundStyle(Theme.secondaryText)
                    .padding(.vertical, Spacing.xs)
            } else {
                ForEach(dayEntries) { entry in
                    Button {
                        onOpen(entry)
                    } label: {
                        EntryRow(entry: entry, dateStyle: .time)
                            .padding(.vertical, 6)
                    }
                    .buttonStyle(.plain)
                    Rectangle().fill(Theme.hairline).frame(height: 1)
                }
            }
        }
    }

    private func shift(by days: Int) {
        guard let next = calendar.date(byAdding: .day, value: days, to: day) else { return }
        withAnimation(.snappy) { day = next }
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
