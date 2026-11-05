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
        ) { attachment.imageData.flatMap(UIImage.init(data:)) }
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
                        VideoPage(url: video, isCurrent: selection == photo.id)
                            .tag(photo.id)
                    } else {
                    FullImage(load: photo.load, onDragDown: { progress in
                        // A cancelled swipe springs back; bring the backdrop back with it.
                        if progress == 0 {
                            withAnimation(.snappy) { dismissProgress = 0 }
                        } else {
                            dismissProgress = progress
                        }
                    }) { dismiss() }
                        .tag(photo.id)
                    }
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
            .opacity(1 - min(1, dismissProgress * 3))
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

/// A video, playing while it's the page shown, paused when swiped away. Its controls are its own —
/// play/pause, ten seconds back and forward, and a scrubber with the times — with none of the system
/// player's AirPlay or mute buttons. A tap shows or hides them; they hide by themselves while it plays.
private struct VideoPage: View {
    let url: () -> URL?
    let isCurrent: Bool

    @State private var player: AVPlayer?
    @State private var isPlaying = false
    @State private var time: Double = 0
    @State private var duration: Double = 0
    @State private var isScrubbing = false
    @State private var showsControls = true
    @State private var hideTask: Task<Void, Never>?
    @State private var observer: Any?

    var body: some View {
        ZStack {
            Color.black
            if let player {
                PlayerLayerView(player: player)
            }
            if showsControls {
                controls
                    .transition(.opacity)
            }
        }
        .ignoresSafeArea()
        .contentShape(.rect)
        .onTapGesture {
            withAnimation(.easeOut(duration: 0.2)) { showsControls.toggle() }
            scheduleHide()
        }
        .task {
            guard player == nil, let url = url() else { return }
            let player = AVPlayer(url: url)
            player.allowsExternalPlayback = false
            self.player = player
            duration = (try? await player.currentItem?.asset.load(.duration).seconds) ?? 0
            observer = player.addPeriodicTimeObserver(forInterval: CMTime(value: 1, timescale: 10), queue: .main) { now in
                MainActor.assumeIsolated {
                    if !isScrubbing { time = now.seconds }
                    isPlaying = player.timeControlStatus != .paused
                    if duration > 0, now.seconds >= duration - 0.05, player.timeControlStatus == .paused {
                        withAnimation(.easeOut(duration: 0.2)) { showsControls = true }
                    }
                }
            }
            if isCurrent { play() }
        }
        .onChange(of: isCurrent) { _, current in
            if current { play() } else { player?.pause() }
        }
        .onDisappear {
            player?.pause()
            if let observer { player?.removeTimeObserver(observer) }
            observer = nil
        }
    }

    private var controls: some View {
        ZStack {
            // Darkened a little, so the white controls read over a bright frame.
            Color.black.opacity(0.25)
                .allowsHitTesting(false)
            HStack(spacing: Spacing.l * 2) {
                controlButton("gobackward.10", label: "Back 10 Seconds", size: 26) { skip(-10) }
                controlButton(isPlaying ? "pause.fill" : "play.fill", label: isPlaying ? "Pause" : "Play", size: 40) {
                    isPlaying ? player?.pause() : play()
                    isPlaying.toggle()
                    scheduleHide()
                }
                controlButton("goforward.10", label: "Forward 10 Seconds", size: 26) { skip(10) }
            }
            VStack {
                Spacer()
                HStack(spacing: Spacing.s) {
                    Text(VideoProcessing.formatted(time))
                    Slider(value: $time, in: 0...max(duration, 0.1)) { editing in
                        isScrubbing = editing
                        if editing {
                            hideTask?.cancel()
                        } else {
                            player?.seek(to: CMTime(seconds: time, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
                            scheduleHide()
                        }
                    }
                    .tint(.white)
                    Text("-" + VideoProcessing.formatted(max(duration - time, 0)))
                }
                .font(Typography.caption.monospacedDigit())
                .foregroundStyle(.white.opacity(0.85))
                .padding(.horizontal, Spacing.l)
                .padding(.bottom, Spacing.l * 2)
            }
        }
    }

    private func controlButton(_ symbol: String, label: String, size: CGFloat, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: size + 30, height: size + 30)
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private func play() {
        guard let player else { return }
        // From the start again once it has played through.
        if duration > 0, player.currentTime().seconds >= duration - 0.05 {
            player.seek(to: .zero)
        }
        player.play()
        isPlaying = true
        scheduleHide()
    }

    private func skip(_ seconds: Double) {
        guard let player else { return }
        let target = min(max(player.currentTime().seconds + seconds, 0), duration)
        time = target
        player.seek(to: CMTime(seconds: target, preferredTimescale: 600))
        scheduleHide()
    }

    /// Controls hide a moment after the last touch while the video plays.
    private func scheduleHide() {
        hideTask?.cancel()
        hideTask = Task {
            try? await Task.sleep(for: .seconds(2.5))
            guard !Task.isCancelled, isPlaying, !isScrubbing else { return }
            withAnimation(.easeOut(duration: 0.3)) { showsControls = false }
        }
    }
}

/// Just the picture, fitted to the screen.
private struct PlayerLayerView: UIViewRepresentable {
    let player: AVPlayer

    func makeUIView(context: Context) -> PlayerView {
        let view = PlayerView()
        view.playerLayer.player = player
        view.playerLayer.videoGravity = .resizeAspect
        return view
    }

    func updateUIView(_ view: PlayerView, context: Context) {
        view.playerLayer.player = player
    }

    final class PlayerView: UIView {
        override static var layerClass: AnyClass { AVPlayerLayer.self }
        var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
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

/// One photo, fitted to the screen. Pinch or double-tap to zoom; at normal size, swiping down
/// closes it (`onDragDown` reports how far, 0–1), and so does a tap on the black around it.
private struct FullImage: View {
    let load: () async -> UIImage?
    let onDragDown: (CGFloat) -> Void
    let onClose: () -> Void
    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                ZoomableImage(image: image, onDragDown: onDragDown, onClose: onClose)
                    // The whole screen, under the notch and the home indicator: a tall photo fills
                    // its height, a wide one its width.
                    .ignoresSafeArea()
            } else {
                ProgressView().tint(.white)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(.rect)
                    .onTapGesture(perform: onClose)
            }
        }
        .task {
            image = await load()
        }
    }
}

/// A `UIScrollView` for the zooming, plus a pan that only starts for a downward swipe at normal size,
/// so it leaves sideways swipes to the page view and pans of a zoomed photo to the scroll view.
private struct ZoomableImage: UIViewRepresentable {
    let image: UIImage
    let onDragDown: (CGFloat) -> Void
    let onClose: () -> Void

    func makeUIView(context: Context) -> ZoomView {
        let view = ZoomView(image: image)
        view.onDragDown = onDragDown
        view.onClose = onClose
        return view
    }

    func updateUIView(_ view: ZoomView, context: Context) {
        view.onDragDown = onDragDown
        view.onClose = onClose
    }

    final class ZoomView: UIScrollView, UIScrollViewDelegate, UIGestureRecognizerDelegate {
        var onDragDown: (CGFloat) -> Void = { _ in }
        var onClose: () -> Void = {}
        private let imageView: UIImageView
        private let dismissPan = UIPanGestureRecognizer()
        /// The drag a swipe-down needs to close the photo, and the drag that fully fades the backdrop.
        private let closeDistance: CGFloat = 120
        private let fadeDistance: CGFloat = 300

        init(image: UIImage) {
            imageView = UIImageView(image: image)
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
        }

        /// The image's size fitted inside the bounds.
        private func fittedSize() -> CGSize {
            guard let size = imageView.image?.size, size.width > 0, size.height > 0 else { return bounds.size }
            let scale = min(bounds.width / size.width, bounds.height / size.height)
            return CGSize(width: size.width * scale, height: size.height * scale)
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
