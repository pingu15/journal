import SwiftUI

/// Full-screen, swipeable viewer for an entry's embedded photos, with "Set as Cover Image"
/// and delete in the ⋯ menu.
struct PhotoViewer: View {
    let onSetCover: (UUID) -> Void
    let onDelete: (UUID) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var photos: [Attachment]
    @State private var selection: UUID
    @State private var currentCover: UUID?
    @State private var confirmingDelete = false

    init(
        photos: [Attachment],
        initialID: UUID,
        coverID: UUID?,
        onSetCover: @escaping (UUID) -> Void,
        onDelete: @escaping (UUID) -> Void
    ) {
        self.onSetCover = onSetCover
        self.onDelete = onDelete
        _photos = State(initialValue: photos)
        _selection = State(initialValue: initialID)
        _currentCover = State(initialValue: coverID)
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            TabView(selection: $selection) {
                ForEach(photos) { photo in
                    FullImage(attachment: photo) { dismiss() }
                        .tag(photo.identifier)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: photos.count > 1 ? .automatic : .never))
            .ignoresSafeArea()
        }
        .overlay(alignment: .top) {
            HStack(spacing: Spacing.s) {
                Button { dismiss() } label: {
                    GlassIcon(symbol: "xmark")
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close")
                Spacer()
                Menu {
                    Button(
                        currentCover == selection ? "Cover Image" : "Set as Cover Image",
                        systemImage: currentCover == selection ? "checkmark" : "photo.badge.checkmark"
                    ) {
                        withAnimation { currentCover = selection }
                        onSetCover(selection)
                    }
                    .disabled(currentCover == selection)
                    Button("Delete Photo", systemImage: "trash", role: .destructive) {
                        confirmingDelete = true
                    }
                } label: {
                    GlassIcon(symbol: "ellipsis")
                }
                .accessibilityLabel("More")
            }
            .foregroundStyle(.white)
            .tint(.white)
            // Always over a black backdrop, so the glass is the dark kind.
            .environment(\.colorScheme, .dark)
            .padding(.horizontal, Spacing.m)
        }
        .confirmationDialog("Delete this photo?", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive, action: deleteCurrent)
        } message: {
            Text("It will be removed from the entry.")
        }
        .sensoryFeedback(.success, trigger: currentCover)
        .statusBarHidden()
    }

    private func deleteCurrent() {
        let deleted = selection
        guard let index = photos.firstIndex(where: { $0.identifier == deleted }) else { return }
        onDelete(deleted)
        photos.remove(at: index)
        if photos.isEmpty {
            dismiss()
        } else {
            selection = photos[min(index, photos.count - 1)].identifier
        }
    }
}

/// A toolbar-style glass circle around an icon.
private struct GlassIcon: View {
    let symbol: String

    var body: some View {
        Image(systemName: symbol)
            .font(.body.weight(.semibold))
            .frame(width: 44, height: 44)
            .glassBackground(in: .circle)
            .contentShape(.circle)
    }
}

/// One photo, fitted to the screen. A tap on the black around it calls `onTapOutside`.
private struct FullImage: View {
    let attachment: Attachment
    let onTapOutside: () -> Void
    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    // Taps on the photo itself do nothing (and don't reach the backdrop).
                    .onTapGesture {}
            } else {
                ProgressView().tint(.white)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            Color.black
                .contentShape(.rect)
                .onTapGesture(perform: onTapOutside)
        }
        .task {
            if let data = attachment.imageData {
                image = UIImage(data: data)
            }
        }
    }
}

/// Lets the user backdate an entry.
struct DateEditSheet: View {
    @Binding var date: Date
    @Environment(\.dismiss) private var dismiss
    /// The picker's height, so the sheet opens tall enough to show the time row too.
    @State private var pickerHeight: CGFloat = 420

    var body: some View {
        NavigationStack {
            DatePicker("Entry date", selection: $date, in: ...Date.now, displayedComponents: [.date, .hourAndMinute])
                .datePickerStyle(.graphical)
                .tint(Theme.primaryText)
                .padding(.horizontal)
                .fixedSize(horizontal: false, vertical: true)
                .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { pickerHeight = $0 }
                .frame(maxHeight: .infinity, alignment: .top)
                .navigationTitle("Entry Date")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                    }
                }
        }
        // Picker plus the sheet's title bar.
        .presentationDetents([.height(pickerHeight + 80)])
    }
}
