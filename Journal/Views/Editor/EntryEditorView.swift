import PhotosUI
import SwiftData
import SwiftUI

/// Full-screen writing surface. Edits save automatically; blank entries are discarded on exit.
struct EntryEditorView: View {
    @Bindable var entry: Entry

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(AppRouter.self) private var router

    @State private var editor = MarkdownEditorController()
    @State private var confirmingDelete = false
    @State private var isTrashed = false
    @State private var editingDate = false
    @State private var editingLocation = false
    @State private var choosingPhotos = false
    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var viewingPhoto: PhotoSelection?
    @State private var isEditing = false
    /// Captured before the editor is built, so a fresh page opens with the keyboard up.
    private let startsEmpty: Bool

    init(entry: Entry) {
        self.entry = entry
        self.startsEmpty = entry.isBlank
    }

    var body: some View {
        MarkdownEditor(
            text: $entry.text,
            isEditing: $isEditing,
            controller: editor,
            autofocus: startsEmpty,
            image: image(for:),
            onImageTap: { viewingPhoto = PhotoSelection(id: $0) },
            resolvePastedImage: resolvePastedImage,
            onPasteImages: { images in
                Task { await importImageData(images.compactMap { $0.jpegData(compressionQuality: 0.92) }) }
            }
        ) {
            EntryHeader(
                entry: entry,
                onEditDate: { editingDate = true },
                onEditLocation: { editingLocation = true }
            )
        }
        .ignoresSafeArea(.container, edges: .bottom)
        .overlay(alignment: .bottom) {
            // Rides on the keyboard's top edge (the overlay respects the keyboard safe area).
            if isEditing {
                MarkdownToolbar(controller: editor, onImage: { choosingPhotos = true })
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.2), value: isEditing)
        .background(Theme.background.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu("More", systemImage: "ellipsis") {
                    Section {
                        ShareLink(item: entry.shareText)
                        Button("Delete Entry", systemImage: "trash", role: .destructive) {
                            confirmingDelete = true
                        }
                    }
                    Section {
                        Text("\(entry.wordCount) words · \(entry.readingMinutes) min read")
                        Text("Edited \(entry.updatedAt.formatted(.relative(presentation: .named)))")
                    }
                }
            }
        }
        .photosPicker(isPresented: $choosingPhotos, selection: $pickerItems, maxSelectionCount: 10, matching: .images)
        .onChange(of: pickerItems) { _, items in
            guard !items.isEmpty else { return }
            Task { await importPhotos(items) }
        }
        .sheet(isPresented: $editingDate, onDismiss: { Task { await refreshWeather() } }) {
            DateEditSheet(date: $entry.createdAt)
        }
        .sheet(isPresented: $editingLocation) {
            LocationPicker(entry: entry) {
                Task { await refreshWeather() }
            }
        }
        .fullScreenCover(item: $viewingPhoto) { selection in
            PhotoViewer(
                photos: entry.photos,
                initialID: selection.id,
                coverID: entry.coverPhoto?.identifier,
                onSetCover: { entry.coverImageID = $0 },
                onDelete: { editor.removeImage($0) }
            )
        }
        .confirmationDialog("Delete this entry?", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                isTrashed = true
                entry.moveToTrash()
                try? context.save()
                dismiss()
            }
        } message: {
            Text("You can restore it from Recently Deleted for \(Entry.trashRetentionDays) days.")
        }
        .onAppear {
            router.openEntries.insert(entry.persistentModelID)
            entry.embedLoosePhotos()
            if entry.location != nil && entry.weather == nil {
                Task { await refreshWeather() }
            }
        }
        .onChange(of: entry.text) {
            entry.updatedAt = .now
        }
        .onDisappear {
            router.openEntries.remove(entry.persistentModelID)
            guard !isTrashed else { return }
            entry.removeUnreferencedPhotos(in: context)
            if entry.isBlank {
                context.delete(entry)
            }
            try? context.save()
        }
    }

    private func image(for id: UUID) -> UIImage? {
        guard let data = (entry.attachments ?? []).first(where: { $0.identifier == id })?.imageData else { return nil }
        return UIImage(data: data)
    }

    private func importPhotos(_ items: [PhotosPickerItem]) async {
        pickerItems = []
        var data: [Data] = []
        for item in items {
            if let loaded = try? await item.loadTransferable(type: Data.self) {
                data.append(loaded)
            }
        }
        await importImageData(data)
    }

    private func importImageData(_ images: [Data]) async {
        var inserted: [(id: UUID, image: UIImage)] = []
        for data in images {
            guard let prepared = await ImageProcessing.prepare(data),
                  let image = UIImage(data: prepared.full)
            else { continue }
            let attachment = Attachment(imageData: prepared.full, thumbnailData: prepared.thumbnail)
            context.insert(attachment)
            attachment.entry = entry
            inserted.append((attachment.identifier, image))
        }
        editor.insertImages(inserted)
    }

    /// A pasted photo token. Photos already in this entry are reused (a duplicate paste gets its own
    /// copy, so deleting one doesn't remove the other); photos from other entries are copied in.
    private func resolvePastedImage(_ id: UUID) -> (id: UUID, image: UIImage)? {
        let alreadyInText = Markdown.imageIDs(in: entry.text).contains(id)
        let source: Attachment?
        if let own = (entry.attachments ?? []).first(where: { $0.identifier == id }), !alreadyInText {
            return own.imageData.flatMap(UIImage.init(data:)).map { (id, $0) }
        } else if let own = (entry.attachments ?? []).first(where: { $0.identifier == id }) {
            source = own
        } else {
            let descriptor = FetchDescriptor<Attachment>(predicate: #Predicate { $0.identifier == id })
            source = try? context.fetch(descriptor).first
        }
        guard let source, let data = source.imageData, let image = UIImage(data: data) else { return nil }
        let copy = Attachment(imageData: data, thumbnailData: source.thumbnailData ?? data)
        context.insert(copy)
        copy.entry = entry
        return (copy.identifier, image)
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
            .buttonStyle(.plain)
            .accessibilityHint("Changes the entry's date")

            HStack(spacing: Spacing.s) {
                Button(action: onEditLocation) {
                    Label(entry.placeName ?? "Add location", systemImage: entry.placeName == nil ? "location" : "location.fill")
                        .lineLimit(1)
                }
                .buttonStyle(.plain)

                if let weather = entry.weather {
                    Text("·")
                    Label("\(weather.formattedTemperature) \(weather.condition)", systemImage: weather.symbol)
                        .lineLimit(1)
                        .accessibilityLabel("Weather: \(weather.formattedTemperature), \(weather.condition)")
                }
            }
            .font(.subheadline)
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
