import PhotosUI
import SwiftData
import SwiftUI

/// Full-screen writing surface. Edits save automatically; blank entries are discarded on exit.
struct EntryEditorView: View {
    @Bindable var entry: Entry

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(AppRouter.self) private var router

    @State private var editor = MarkdownEditorController()
    @State private var isTrashed = false
    @State private var confirmingDelete = false
    @State private var confirmingPermanentDelete = false
    @State private var editingDate = false
    @State private var editingLocation = false
    @State private var viewingDay = false
    @State private var choosingPhotos = false
    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var viewingPhoto: PhotoSelection?
    /// Videos being added: re-encoding one takes a while, so a note says so meanwhile.
    @State private var addingVideos = 0
    @State private var isEditing = false
    @AppStorage(LocationService.autoTagKey) private var autoTagLocation = false
    /// The place was added automatically, not chosen; an entry with nothing else is still discarded.
    @State private var autoPlaced = false
    @State private var autoPlaceTask: Task<Void, Never>?
    /// Captured before the editor is built, so a fresh page opens with the keyboard up.
    private let startsEmpty: Bool

    /// `placeIsProvisional`: the entry was started with its place (a long press on the map), so it's
    /// discarded if nothing else is added, like an automatically added place.
    init(entry: Entry, placeIsProvisional: Bool = false) {
        self.entry = entry
        self.startsEmpty = entry.isBlank || (placeIsProvisional && !entry.hasText && entry.photos.isEmpty)
        _autoPlaced = State(initialValue: placeIsProvisional)
    }

    var body: some View {
        MarkdownEditor(
            text: $entry.text,
            isEditing: $isEditing,
            controller: editor,
            autofocus: startsEmpty,
            isEditable: !isDeleted,
            image: image(for:),
            onImageTap: {
                // The viewer lists the photos from the entry's text.
                editor.flush()
                viewingPhoto = PhotoSelection(id: $0)
            },
            resolvePastedImage: resolvePastedImage,
            onPasteImages: { images in
                Task { await importImageData(images.compactMap { $0.jpegData(compressionQuality: 0.92) }) }
            }
        ) {
            EntryHeader(
                entry: entry,
                onEditDate: { if !isDeleted { editingDate = true } },
                onEditLocation: { if !isDeleted { editingLocation = true } }
            )
        }
        // Runs to the screen's top edge: the page scrolls up under the bar's buttons, with no band
        // kept for them. The text view still starts below the bar (its inset adjusts for it).
        .ignoresSafeArea(.container, edges: [.top, .bottom])
        .overlay(alignment: .bottom) {
            // Rides on the keyboard's top edge (the overlay respects the keyboard safe area).
            if isEditing {
                MarkdownToolbar(controller: editor, onImage: { choosingPhotos = true })
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.2), value: isEditing)
        .overlay(alignment: .top) {
            if addingVideos > 0 {
                HStack(spacing: Spacing.s) {
                    ProgressView()
                    Text(addingVideos == 1 ? "Adding video…" : "Adding \(addingVideos) videos…")
                        .font(Typography.note)
                        .foregroundStyle(Theme.primaryText)
                }
                .padding(.horizontal, Spacing.m)
                .padding(.vertical, Spacing.s)
                .glassBackground(in: .capsule)
                .padding(.top, Spacing.s)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(.snappy, value: addingVideos)
        .background(Theme.background.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .hidesBackButtonMenu()
        .deleteEntryAlert(isPresented: $confirmingDelete, action: moveToTrash)
        // As in Recently Deleted's list.
        .alert("Delete this entry?", isPresented: $confirmingPermanentDelete) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive, action: deletePermanently)
        } message: {
            Text("It will be deleted permanently. This can't be undone.")
        }
        .toolbar {
            if isDeleted {
                // The same ⋯ as a live entry's, with what Recently Deleted offers.
                ToolbarItem(placement: .topBarTrailing) {
                    Menu("More", systemImage: "ellipsis") {
                        Section {
                            Button("Restore", systemImage: "arrow.uturn.backward", action: restore)
                            // Asks first, as from Recently Deleted's list.
                            Button("Delete Permanently", systemImage: "trash", role: .destructive) {
                                confirmingPermanentDelete = true
                            }
                        }
                        Section {
                            Text("\(entry.wordCount) words · \(entry.readingMinutes) min read")
                            Text("Edited \(entry.updatedAt.formatted(.relative(presentation: .named)))")
                        }
                    }
                }
            } else {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu("More", systemImage: "ellipsis") {
                        Section {
                            Button("View Day", systemImage: "calendar") { viewingDay = true }
                            Button("Share", systemImage: "square.and.arrow.up", action: sharePDF)
                            // Asks first, as from the list.
                            Button("Delete Entry", systemImage: "trash", role: .destructive) { confirmingDelete = true }
                        }
                        Section {
                            Text("\(entry.wordCount) words · \(entry.readingMinutes) min read")
                            Text("Edited \(entry.updatedAt.formatted(.relative(presentation: .named)))")
                        }
                    }
                }
            }
            if isEditing {
                // Finishes editing (puts the keyboard away); moved here from the keyboard bar.
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done", systemImage: "checkmark") { editor.endEditing() }
                        .buttonStyle(.borderedProminent)
                        .tint(Theme.accent)
                        .foregroundStyle(Theme.onAccent)
                }
            }
        }
        .photosPicker(isPresented: $choosingPhotos, selection: $pickerItems, maxSelectionCount: 10, matching: .any(of: [.images, .videos]))
        .onChange(of: pickerItems) { _, items in
            guard !items.isEmpty else { return }
            Task { await importPhotos(items) }
        }
        .sheet(isPresented: $editingDate, onDismiss: { Task { await refreshWeather() } }) {
            DateEditSheet(date: $entry.createdAt)
                .sheetBackdrop()
        }
        .sheet(isPresented: $editingLocation) {
            LocationPicker(entry: entry) {
                autoPlaced = false
                Task { await refreshWeather() }
            }
            .sheetBackdrop()
        }
        .sheet(isPresented: $viewingDay) {
            EntryDaySheet(entry: entry) {
                autoPlaced = false
                Task { await refreshWeather() }
            }
        }
        .fullScreenCover(item: $viewingPhoto) { selection in
            PhotoViewer(
                photos: entry.photos.map(ViewerPhoto.init),
                initialID: selection.id,
                coverID: entry.coverPhoto?.identifier,
                onSetCover: isDeleted ? nil : { entry.coverImageID = $0 },
                onDelete: isDeleted ? nil : { editor.removeImage($0) }
            )
        }
        .onAppear {
            router.openEntries.insert(entry.persistentModelID)
            // A deleted entry is only read: nothing is added to it.
            guard !isDeleted else { return }
            entry.embedLoosePhotos()
            if entry.location != nil && entry.weather == nil {
                Task { await refreshWeather() }
            }
            if startsEmpty && autoTagLocation && entry.placeName == nil {
                autoPlaceTask = Task { await addCurrentPlace() }
            }
        }
        .onChange(of: entry.text) {
            entry.updatedAt = .now
        }
        .onChange(of: scenePhase) { _, phase in
            // The app saves as it leaves `.active`; the latest typing goes with it.
            guard phase != .active else { return }
            editor.flush()
            try? context.save()
        }
        .onDisappear {
            editor.flush()
            router.openEntries.remove(entry.persistentModelID)
            autoPlaceTask?.cancel()
            guard !isTrashed, !isDeleted else { return }
            entry.removeUnreferencedPhotos(in: context)
            if autoPlaced && !entry.hasText && entry.photos.isEmpty {
                entry.clearPlace()
            }
            if entry.isBlank {
                context.delete(entry)
            }
            try? context.save()
        }
    }

    /// In Recently Deleted, so read-only until restored.
    private var isDeleted: Bool { entry.deletedAt != nil }

    /// Back in the journal, and editable again here.
    private func restore() {
        entry.restore()
        try? context.save()
    }

    private func deletePermanently() {
        isTrashed = true
        dismiss()
        // Once the editor has gone: it reads the entry until then.
        let entry = entry
        Task {
            try? await Task.sleep(for: .milliseconds(600))
            context.delete(entry)
            try? context.save()
        }
    }

    private func moveToTrash() {
        isTrashed = true
        entry.moveToTrash()
        try? context.save()
        dismiss()
    }

    /// Shares the entry as a PDF.
    private func sharePDF() {
        editor.flush()
        Task { await JournalExport.sharePDF(of: entry) }
    }

    private func image(for id: UUID) -> AttachmentPicture? {
        guard let attachment = (entry.attachments ?? []).first(where: { $0.identifier == id }) else { return nil }
        return Self.picture(of: attachment)
    }

    /// What the text shows for a photo or video: a video's first frame, with its length.
    private static func picture(of attachment: Attachment) -> AttachmentPicture? {
        guard let image = attachment.imageData.flatMap(UIImage.init(data:)) else { return nil }
        return AttachmentPicture(image: image, isVideo: attachment.isVideo, duration: attachment.videoDuration)
    }

    /// Photos and videos from the library, in the order picked.
    private func importPhotos(_ items: [PhotosPickerItem]) async {
        pickerItems = []
        var inserted: [(id: UUID, picture: AttachmentPicture)] = []
        for item in items {
            let attachment: Attachment?
            if item.supportedContentTypes.contains(where: { $0.conforms(to: .movie) }) {
                attachment = await importVideo(item)
            } else if let data = try? await item.loadTransferable(type: Data.self),
                      let prepared = await ImageProcessing.prepare(data) {
                attachment = Attachment(imageData: prepared.full, thumbnailData: prepared.thumbnail)
            } else {
                attachment = nil
            }
            guard let attachment else { continue }
            context.insert(attachment)
            attachment.entry = entry
            if let picture = Self.picture(of: attachment) {
                inserted.append((attachment.identifier, picture))
            }
        }
        editor.insertImages(inserted)
    }

    private func importVideo(_ item: PhotosPickerItem) async -> Attachment? {
        addingVideos += 1
        defer { addingVideos -= 1 }
        guard let movie = try? await item.loadTransferable(type: PickedMovie.self),
              let prepared = await VideoProcessing.prepare(movie.url)
        else { return nil }
        let attachment = Attachment(imageData: prepared.poster.full, thumbnailData: prepared.poster.thumbnail)
        attachment.videoData = prepared.video
        attachment.videoDuration = prepared.duration
        return attachment
    }

    private func importImageData(_ images: [Data]) async {
        var inserted: [(id: UUID, picture: AttachmentPicture)] = []
        for data in images {
            guard let prepared = await ImageProcessing.prepare(data),
                  let image = UIImage(data: prepared.full)
            else { continue }
            let attachment = Attachment(imageData: prepared.full, thumbnailData: prepared.thumbnail)
            context.insert(attachment)
            attachment.entry = entry
            inserted.append((attachment.identifier, AttachmentPicture(image: image)))
        }
        editor.insertImages(inserted)
    }

    /// A pasted photo token. Photos already in this entry are reused (a duplicate paste gets its own
    /// copy, so deleting one doesn't remove the other); photos from other entries are copied in.
    private func resolvePastedImage(_ id: UUID) -> (id: UUID, picture: AttachmentPicture)? {
        let alreadyInText = Markdown.imageIDs(in: entry.text).contains(id)
        let source: Attachment?
        if let own = (entry.attachments ?? []).first(where: { $0.identifier == id }), !alreadyInText {
            return Self.picture(of: own).map { (id, $0) }
        } else if let own = (entry.attachments ?? []).first(where: { $0.identifier == id }) {
            source = own
        } else {
            let descriptor = FetchDescriptor<Attachment>(predicate: #Predicate { $0.identifier == id })
            source = try? context.fetch(descriptor).first
        }
        guard let copy = source?.duplicate(), let image = Self.picture(of: copy) else { return nil }
        context.insert(copy)
        copy.entry = entry
        return (copy.identifier, image)
    }

    /// The "Add current location" setting: tags a fresh entry for today with where the user is.
    /// Never prompts — Settings asked for access when the setting was turned on.
    private func addCurrentPlace() async {
        guard LocationService.shared.isAuthorized, Calendar.current.isDateInToday(entry.createdAt),
              let location = try? await LocationService.shared.currentLocation() else { return }
        let name = await LocationService.shared.placeName(for: location) ?? "Current Location"
        // Not if the editor has closed, or a place was picked meanwhile.
        guard !Task.isCancelled, entry.placeName == nil else { return }
        entry.setPlace(name: name, coordinate: location.coordinate)
        autoPlaced = true
        await refreshWeather()
    }

    private func refreshWeather() async {
        guard let location = entry.location else {
            entry.clearWeather()
            return
        }
        if let snapshot = await WeatherFetcher.snapshot(at: location, on: entry.createdAt) {
            entry.apply(snapshot)
        }
    }
}

/// The day sheet for the entry's day, without the entry itself. Its own view with its own query,
/// so the editor doesn't re-render as entries change.
private struct EntryDaySheet: View {
    let entry: Entry
    let onSetPlace: () -> Void

    @Query(filter: #Predicate<Entry> { $0.deletedAt == nil }, sort: \Entry.createdAt)
    private var entries: [Entry]

    var body: some View {
        DaySheet(day: entry.createdAt, entries: entries, openedFrom: entry, onSetPlace: onSetPlace)
    }
}

private struct PhotoSelection: Identifiable {
    let id: UUID
}

/// Date, place and weather — scrolls with the page.
struct EntryHeader: View {
    @Bindable var entry: Entry
    let onEditDate: () -> Void
    let onEditLocation: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s + 2) {
            Button(action: onEditDate) {
                MetaLabel(dateLine)
            }
            .buttonStyle(.borderless)
            .accessibilityHint("Changes the entry's date")

            HStack(spacing: 0) {
                Button(action: onEditLocation) {
                    Text(entry.placeName ?? "Add location")
                        .lineLimit(1)
                }
                .buttonStyle(.borderless)

                if let weather = entry.weather {
                    // Spaced like the lists' meta line; the condition is still spoken by VoiceOver.
                    Text(" · \(Image(systemName: weather.symbol)) \(weather.formattedTemperature)")
                        .fixedSize()
                        .accessibilityLabel("Weather: \(weather.formattedTemperature), \(weather.condition)")
                }
            }
            .font(Typography.detail)
            .foregroundStyle(Theme.secondaryText)
        }
    }

    /// "Friday, October 9 · 7:00 AM", with the year when it isn't this year.
    private var dateLine: String {
        let isThisYear = Calendar.current.isDate(entry.createdAt, equalTo: .now, toGranularity: .year)
        let day = isThisYear
            ? entry.createdAt.formatted(.dateTime.weekday(.wide).month(.wide).day())
            : entry.createdAt.formatted(.dateTime.weekday(.wide).month(.wide).day().year())
        return day + " · " + entry.createdAt.formatted(date: .omitted, time: .shortened)
    }
}

#Preview {
    let container = ModelContainer.preview
    let entry = try! container.mainContext.fetch(FetchDescriptor<Entry>()).first!
    return NavigationStack {
        EntryEditorView(entry: entry)
    }
    .modelContainer(container)
    .environment(AppRouter())
}
