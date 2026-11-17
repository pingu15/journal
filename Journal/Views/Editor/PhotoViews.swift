import AVKit
import Photos
import SwiftUI

/// A photo the viewer shows: one of an entry's, or one from the photo library. An entry's video
/// (`video`) plays in its place.
struct ViewerPhoto<ID: Hashable>: Identifiable {
    let id: ID
    var video: (() -> URL?)? = nil
    let load: () async -> UIImage?
}

extension ViewerPhoto where ID == UUID {
    init(_ attachment: Attachment) {
        self.init(
            id: attachment.identifier,
            video: attachment.isVideo ? { VideoProcessing.playableURL(for: attachment) } : nil
        ) {
            // The data is read here, with the model; the decoding happens off the main thread.
            guard let image = attachment.imageData.flatMap(UIImage.init(data:)) else { return nil }
            return await image.byPreparingForDisplay() ?? image
        }
    }
}

extension ViewerPhoto where ID == String {
    init(_ asset: PHAsset) {
        self.init(id: asset.localIdentifier) { await PhotoLibrary.fullImage(for: asset) }
    }
}

/// Full-screen, swipeable photo viewer. For an entry's embedded photos it has "Set as Cover Image"
/// and delete in a ⋯ menu; for the library's (the day sheet's), just the close button.
struct PhotoViewer<ID: Hashable>: View {
    let onSetCover: ((ID) -> Void)?
    let onDelete: ((ID) -> Void)?

    @Environment(\.dismiss) private var dismiss
    @State private var photos: [ViewerPhoto<ID>]
    @State private var selection: ID
    @State private var currentCover: ID?
    @State private var confirmingDelete = false
    /// How far a swipe-down has pulled the photo toward closing (0–1); fades the backdrop and buttons.
    @State private var dismissProgress: CGFloat = 0
    /// A video's own controls are up: the close and ⋯ buttons step aside for them.
    @State private var videoControlsShown = false
    /// Decoded photos: the one shown and its neighbors, loaded ahead so a swipe rarely waits on one.
    /// Kept outside the viewer's own state and read only by each page, so a photo arriving updates
    /// that page alone, never the pager mid-swipe (which stopped the swipe halfway).
    @State private var images = LoadedPhotos<ID>()

    init(
        photos: [ViewerPhoto<ID>],
        initialID: ID,
        coverID: ID? = nil,
        onSetCover: ((ID) -> Void)? = nil,
        onDelete: ((ID) -> Void)? = nil
    ) {
        self.onSetCover = onSetCover
        self.onDelete = onDelete
        _photos = State(initialValue: photos)
        _selection = State(initialValue: initialID)
        _currentCover = State(initialValue: coverID)
    }

    var body: some View {
        ZStack {
            Color.black
                .opacity(1 - dismissProgress)
                .ignoresSafeArea()

            TabView(selection: $selection) {
                ForEach(photos) { photo in
                    if let video = photo.video {
                        VideoPage(
                            url: video,
                            isCurrent: selection == photo.id,
                            controlsShown: $videoControlsShown,
                            onDragDown: dragDown
                        ) { dismiss() }
                            .tag(photo.id)
                    } else {
                    FullImage(images: images, id: photo.id, onDragDown: dragDown) { dismiss() }
                        .tag(photo.id)
                    }
                }
            }
            .tabViewStyle(.page(indexDisplayMode: photos.count > 1 ? .automatic : .never))
            .ignoresSafeArea()
        }
        .task(id: selection) { await loadAround(selection) }
        .overlay(alignment: .top) {
            HStack(spacing: Spacing.s) {
                Button { dismiss() } label: {
                    GlassIcon(symbol: "xmark")
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close")
                Spacer()
                if let onSetCover, onDelete != nil {
                    Menu {
                        Button(
                            "Set as Cover Image",
                            systemImage: currentCover == selection ? "checkmark" : "photo.badge.checkmark"
                        ) {
                            withAnimation { currentCover = selection }
                            onSetCover(selection)
                        }
                        .disabled(currentCover == selection)
                        Button(isVideo ? "Delete Video" : "Delete Photo", systemImage: "trash", role: .destructive) {
                            confirmingDelete = true
                        }
                    } label: {
                        GlassIcon(symbol: "ellipsis")
                    }
                    .accessibilityLabel("More")
                }
            }
            // Always over a black backdrop, so the glass is the dark kind.
            .environment(\.colorScheme, .dark)
            .padding(.horizontal, Spacing.m)
            .opacity(videoControlsShown && isVideo ? 0 : 1 - min(1, dismissProgress * 3))
            .allowsHitTesting(!(videoControlsShown && isVideo))
            .animation(.easeOut(duration: 0.2), value: videoControlsShown)
        }
        // An alert rather than a confirmation dialog: the dialog's glass took on the photo's colors
        // and was hard to read, and had no Cancel.
        .alert(isVideo ? "Delete this video?" : "Delete this photo?", isPresented: $confirmingDelete) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive, action: deleteCurrent)
        } message: {
            Text("It will be removed from the entry.")
        }
        .sensoryFeedback(.success, trigger: currentCover)
        .statusBarHidden()
        // Lets the editor (or day sheet) show through as the photo is swiped down.
        .presentationBackground(.clear)
    }

    /// A swipe-down on a photo or video fading the backdrop; a cancelled one springs back, and
    /// brings the backdrop back with it.
    private func dragDown(_ progress: CGFloat) {
        if progress == 0 {
            withAnimation(.snappy) { dismissProgress = 0 }
        } else {
            dismissProgress = progress
        }
    }

    /// The photo shown first, then the ones either side of it.
    private func loadAround(_ id: ID) async {
        guard let index = photos.firstIndex(where: { $0.id == id }) else { return }
        for offset in [0, 1, -1] {
            let neighbor = index + offset
            guard photos.indices.contains(neighbor) else { continue }
            let photo = photos[neighbor]
            guard photo.video == nil, images.byID[photo.id] == nil else { continue }
            if let image = await photo.load() {
                images.byID[photo.id] = image
            }
            if Task.isCancelled { return }
        }
        // Only a few full-size photos held at once.
        let kept = Set(photos.indices.filter { abs($0 - index) <= 2 }.map { photos[$0].id })
        images.byID = images.byID.filter { kept.contains($0.key) }
    }

    private var isVideo: Bool {
        photos.first { $0.id == selection }?.video != nil
    }

    private func deleteCurrent() {
        let deleted = selection
        guard let onDelete, let index = photos.firstIndex(where: { $0.id == deleted }) else { return }
        onDelete(deleted)
        photos.remove(at: index)
        if photos.isEmpty {
            dismiss()
        } else {
            selection = photos[min(index, photos.count - 1)].id
        }
    }
}

/// A video in iOS's own player, without its AirPlay button, playing while it's the page shown and
/// paused when swiped away. The player's controls sit where the viewer's close and ⋯ buttons do, so
/// a tap that brings them up also reports it (`controlsShown`), and the buttons step aside until
/// they go: by themselves a few seconds later while it plays, as the player's do, or on the next tap.
/// A swipe down closes it, as it does a photo.
private struct VideoPage: View {
    let url: () -> URL?
    let isCurrent: Bool
    @Binding var controlsShown: Bool
    let onDragDown: (CGFloat) -> Void
    let onClose: () -> Void

    @State private var player: AVPlayer?
    @State private var hideTask: Task<Void, Never>?
    /// How far the video has been pulled by a swipe down.
    @State private var drag: CGSize = .zero
    /// Whether the drag under way is a swipe down, decided once as it starts, so a sideways swipe
    /// stays the pager's and the scrubber's.
    @State private var isSwipingDown: Bool?

    /// How long the player's controls stay up while it plays.
    private static let controlsLinger: Duration = .seconds(3)
    /// The drag a swipe-down needs to close the video, and the drag that fully fades the backdrop:
    /// the same as a photo's.
    private static let closeDistance: CGFloat = 120
    private static let fadeDistance: CGFloat = 300

    var body: some View {
        VideoPlayer(player: player)
            .ignoresSafeArea()
            // Shrinks a little as it's pulled down, like a photo.
            .scaleEffect(1 - min(drag.height / Self.fadeDistance, 1) * 0.25)
            .offset(drag)
            // Alongside the player's own tap, which shows or hides its controls.
            .simultaneousGesture(TapGesture().onEnded { toggleControls() })
            .simultaneousGesture(swipeDown)
            .task {
                guard player == nil, let url = url() else { return }
                let player = AVPlayer(url: url)
                // No AirPlay button.
                player.allowsExternalPlayback = false
                self.player = player
                VideoAudio.begin()
                if isCurrent { player.play() }
            }
            .onChange(of: isCurrent) { _, current in
                if current {
                    player?.play()
                } else {
                    player?.pause()
                    hideTask?.cancel()
                    controlsShown = false
                }
            }
            .onDisappear {
                player?.pause()
                hideTask?.cancel()
                controlsShown = false
                VideoAudio.end()
            }
    }

    private var swipeDown: some Gesture {
        DragGesture(minimumDistance: 20)
            .onChanged { value in
                if isSwipingDown == nil {
                    isSwipingDown = value.translation.height > abs(value.translation.width)
                }
                guard isSwipingDown == true else { return }
                let y = max(0, value.translation.height)
                drag = CGSize(width: value.translation.width, height: y)
                onDragDown(min(y / Self.fadeDistance, 1))
            }
            .onEnded { value in
                defer { isSwipingDown = nil }
                guard isSwipingDown == true else { return }
                // A quick flick closes it too.
                let flicked = value.predictedEndTranslation.height - value.translation.height > 200
                if value.translation.height > Self.closeDistance || flicked {
                    onClose()
                } else {
                    withAnimation(.spring(duration: 0.35, bounce: 0.15)) { drag = .zero }
                    onDragDown(0)
                }
            }
    }

    private func toggleControls() {
        hideTask?.cancel()
        controlsShown.toggle()
        guard controlsShown else { return }
        hideTask = Task {
            try? await Task.sleep(for: Self.controlsLinger)
            // Paused, the player keeps its controls up.
            guard !Task.isCancelled, player?.timeControlStatus != .paused else { return }
            controlsShown = false
        }
    }
}

/// The app's audio while a video is up: playback, as Photos does, so its sound plays with the
/// silent switch on and the player's mute button works (with the default, ambient audio the switch
/// silenced it and the button showed muted whatever it was set to). Counted, as pages come and go
/// out of order while swiping between videos.
enum VideoAudio {
    private static var users = 0

    static func begin() {
        users += 1
        guard users == 1 else { return }
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .moviePlayback)
        try? session.setActive(true)
    }

    static func end() {
        users = max(users - 1, 0)
        guard users == 0 else { return }
        let session = AVAudioSession.sharedInstance()
        // Other apps' audio (music) picks up again.
        try? session.setActive(false, options: .notifyOthersOnDeactivation)
        try? session.setCategory(.ambient)
    }
}

/// A toolbar-style glass circle around an icon.
private struct GlassIcon: View {
    let symbol: String

    var body: some View {
        Image(systemName: symbol)
            .font(Typography.action)
            // White here only: set on the bar, it reached the menu's items too, so a disabled one
            // kept a white icon beside its dimmed label.
            .foregroundStyle(.white)
            .frame(width: 44, height: 44)
            .glassBackground(in: .circle)
            .contentShape(.circle)
    }
}

/// The viewer's decoded photos, by ID.
@Observable
nonisolated final class LoadedPhotos<ID: Hashable> {
    var byID: [ID: UIImage] = [:]
}

/// One photo, fitted to the screen. Pinch or double-tap to zoom; at normal size, swiping down
/// closes it (`onDragDown` reports how far, 0–1), and so does a tap on the black around it.
/// The same view before and after its photo has loaded (a spinner until then), so a photo arriving
/// mid-swipe changes only what's drawn, not the page.
private struct FullImage<ID: Hashable>: View {
    let images: LoadedPhotos<ID>
    let id: ID
    let onDragDown: (CGFloat) -> Void
    let onClose: () -> Void

    var body: some View {
        ZoomableImage(image: images.byID[id], onDragDown: onDragDown, onClose: onClose)
            // The whole screen, under the notch and the home indicator: a tall photo fills its
            // height, a wide one its width.
            .ignoresSafeArea()
    }
}

/// A `UIScrollView` for the zooming, plus a pan that only starts for a downward swipe at normal size,
/// so it leaves sideways swipes to the page view and pans of a zoomed photo to the scroll view.
private struct ZoomableImage: UIViewRepresentable {
    let image: UIImage?
    let onDragDown: (CGFloat) -> Void
    let onClose: () -> Void

    func makeUIView(context: Context) -> ZoomView {
        let view = ZoomView()
        view.image = image
        view.onDragDown = onDragDown
        view.onClose = onClose
        return view
    }

    func updateUIView(_ view: ZoomView, context: Context) {
        if view.image !== image { view.image = image }
        view.onDragDown = onDragDown
        view.onClose = onClose
    }

    final class ZoomView: UIScrollView, UIScrollViewDelegate, UIGestureRecognizerDelegate {
        var onDragDown: (CGFloat) -> Void = { _ in }
        var onClose: () -> Void = {}
        private let imageView = UIImageView()
        private let spinner = UIActivityIndicatorView(style: .medium)
        private let dismissPan = UIPanGestureRecognizer()
        /// The drag a swipe-down needs to close the photo, and the drag that fully fades the backdrop.
        private let closeDistance: CGFloat = 120
        private let fadeDistance: CGFloat = 300

        /// Nil while it loads, with a spinner in its place.
        var image: UIImage? {
            get { imageView.image }
            set {
                imageView.image = newValue
                newValue == nil ? spinner.startAnimating() : spinner.stopAnimating()
                setZoomScale(minimumZoomScale, animated: false)
                setNeedsLayout()
            }
        }

        init() {
            super.init(frame: .zero)
            delegate = self
            minimumZoomScale = 1
            maximumZoomScale = 4
            showsHorizontalScrollIndicator = false
            showsVerticalScrollIndicator = false
            contentInsetAdjustmentBehavior = .never
            backgroundColor = .clear
            imageView.contentMode = .scaleAspectFit
            addSubview(imageView)
            spinner.color = .white
            spinner.hidesWhenStopped = true
            spinner.startAnimating()
            addSubview(spinner)

            let doubleTap = UITapGestureRecognizer(target: self, action: #selector(doubleTapped(_:)))
            doubleTap.numberOfTapsRequired = 2
            addGestureRecognizer(doubleTap)
            let tap = UITapGestureRecognizer(target: self, action: #selector(tapped(_:)))
            tap.require(toFail: doubleTap)
            addGestureRecognizer(tap)

            dismissPan.addTarget(self, action: #selector(panned(_:)))
            dismissPan.delegate = self
            addGestureRecognizer(dismissPan)
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

        override func layoutSubviews() {
            super.layoutSubviews()
            guard zoomScale == minimumZoomScale, imageView.transform == .identity else { return }
            imageView.frame = CGRect(origin: .zero, size: fittedSize())
            contentSize = imageView.frame.size
            centerContent()
            spinner.center = CGPoint(x: bounds.midX - contentInset.left, y: bounds.midY - contentInset.top)
        }

        /// The image's size fitted inside the bounds. Never past them, even by a rounding error: a
        /// photo a fraction wider than the screen made this scroll view take sideways swipes from
        /// the pager.
        private func fittedSize() -> CGSize {
            guard let size = imageView.image?.size, size.width > 0, size.height > 0 else { return .zero }
            let scale = min(bounds.width / size.width, bounds.height / size.height)
            return CGSize(width: min(size.width * scale, bounds.width), height: min(size.height * scale, bounds.height))
        }

        /// Centers the photo with insets while it's smaller than the screen in either direction.
        private func centerContent() {
            let x = max(0, (bounds.width - contentSize.width) / 2)
            let y = max(0, (bounds.height - contentSize.height) / 2)
            contentInset = UIEdgeInsets(top: y, left: x, bottom: y, right: x)
        }

        // MARK: Zoom

        func viewForZooming(in scrollView: UIScrollView) -> UIView? { imageView }

        func scrollViewDidZoom(_ scrollView: UIScrollView) {
            centerContent()
        }

        @objc private func doubleTapped(_ gesture: UITapGestureRecognizer) {
            if zoomScale > minimumZoomScale {
                setZoomScale(minimumZoomScale, animated: true)
            } else {
                let point = gesture.location(in: imageView)
                let scale = maximumZoomScale / 2
                let size = CGSize(width: bounds.width / scale, height: bounds.height / scale)
                zoom(to: CGRect(origin: CGPoint(x: point.x - size.width / 2, y: point.y - size.height / 2), size: size), animated: true)
            }
        }

        @objc private func tapped(_ gesture: UITapGestureRecognizer) {
            // Only taps on the black around the photo close it.
            if !imageView.frame.contains(gesture.location(in: self)) { onClose() }
        }

        // MARK: Swipe down to close

        override func gestureRecognizerShouldBegin(_ gesture: UIGestureRecognizer) -> Bool {
            guard gesture === dismissPan else { return super.gestureRecognizerShouldBegin(gesture) }
            guard zoomScale == minimumZoomScale else { return false }
            let velocity = dismissPan.velocity(in: self)
            return velocity.y > 0 && velocity.y > abs(velocity.x)
        }

        @objc private func panned(_ gesture: UIPanGestureRecognizer) {
            let translation = gesture.translation(in: self)
            switch gesture.state {
            case .changed:
                let y = max(0, translation.y)
                // Shrinks a little as it's pulled down, like Photos.
                let scale = 1 - min(y / fadeDistance, 1) * 0.25
                imageView.transform = CGAffineTransform(translationX: translation.x, y: y).scaledBy(x: scale, y: scale)
                onDragDown(min(y / fadeDistance, 1))
            case .ended, .cancelled:
                let velocity = gesture.velocity(in: self).y
                if gesture.state == .ended, translation.y > closeDistance || velocity > 800 {
                    onClose()
                } else {
                    UIView.animate(springDuration: 0.35, bounce: 0.15) {
                        imageView.transform = .identity
                    }
                    onDragDown(0)
                }
            default:
                break
            }
        }
    }
}

/// Lets the user move an entry to another date and time, past or future.
struct DateEditSheet: View {
    @Binding var date: Date
    @Environment(\.dismiss) private var dismiss
    /// The picker's height, so the sheet opens tall enough to show the time row too.
    @State private var pickerHeight: CGFloat = 420

    var body: some View {
        NavigationStack {
            DatePicker("Entry date", selection: $date, displayedComponents: [.date, .hourAndMinute])
                .datePickerStyle(.graphical)
                .tint(Theme.primaryText)
                .padding(.horizontal)
                .fixedSize(horizontal: false, vertical: true)
                .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { pickerHeight = $0 }
                .frame(maxHeight: .infinity, alignment: .top)
                // The app's background, like every other sheet, not the system's grey.
                .background(Theme.background)
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
