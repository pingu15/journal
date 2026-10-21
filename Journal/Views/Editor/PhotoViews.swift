import SwiftUI

/// Full-screen, swipeable viewer for an entry's embedded photos,
/// with delete and "Set as Cover Image" in the top-right.
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
                    FullImage(attachment: photo)
                        .tag(photo.identifier)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: photos.count > 1 ? .automatic : .never))
            .ignoresSafeArea()
        }
        .overlay(alignment: .top) {
            HStack(spacing: Spacing.xs) {
                Button("Close", systemImage: "xmark") { dismiss() }
                    .buttonStyle(.plain)
                    .frame(width: 44, height: 44)
                Spacer()
                if currentCover == selection {
                    Text("Cover")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(.white.opacity(0.18), in: .capsule)
                        .transition(.opacity)
                }
                Menu {
                    Button(
                        currentCover == selection ? "Cover Image" : "Set as Cover Image",
                        systemImage: currentCover == selection ? "checkmark" : "photo.badge.checkmark"
                    ) {
                        withAnimation { currentCover = selection }
                        onSetCover(selection)
                    }
                    .disabled(currentCover == selection)
                } label: {
                    Image(systemName: "ellipsis")
                        .frame(width: 44, height: 44)
                        .contentShape(.rect)
                }
                .accessibilityLabel("More")
                Button("Delete Photo", systemImage: "trash") { confirmingDelete = true }
                    .buttonStyle(.plain)
                    .frame(width: 44, height: 44)
            }
            .labelStyle(.iconOnly)
            .font(.body.weight(.semibold))
            .foregroundStyle(.white)
            .tint(.white)
            .padding(.horizontal, Spacing.s)
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

private struct FullImage: View {
    let attachment: Attachment
    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
            } else {
                ProgressView().tint(.white)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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

    var body: some View {
        NavigationStack {
            DatePicker("Entry date", selection: $date, in: ...Date.now, displayedComponents: [.date, .hourAndMinute])
                .datePickerStyle(.graphical)
                .tint(Theme.primaryText)
                .padding(.horizontal)
                .frame(maxHeight: .infinity, alignment: .top)
                .navigationTitle("Entry Date")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                    }
                }
        }
        .presentationDetents([.medium, .large])
    }
}
