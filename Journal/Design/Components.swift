import SwiftUI

/// Small uppercase tracked label used for dates, section headers and stat captions.
struct MetaLabel: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text.uppercased())
            .font(Typography.meta)
            .tracking(Typography.metaTracking)
            .foregroundStyle(Theme.secondaryText)
    }
}

/// The sand capsule used for the one primary action on a screen.
struct AccentButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.medium))
            .padding(.horizontal, Spacing.l)
            .padding(.vertical, Spacing.m - 2)
            .foregroundStyle(Theme.onAccent)
            .background(Theme.accent, in: .capsule)
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.spring(duration: 0.25), value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == AccentButtonStyle {
    static var accent: AccentButtonStyle { AccentButtonStyle() }
}

/// The entry's place, as one quiet line (tags already show in the excerpt).
struct EntryMetaLine: View {
    let entry: Entry

    var body: some View {
        if let place = entry.placeName {
            Text(place)
                .lineLimit(1)
                .font(.caption)
                .foregroundStyle(Theme.secondaryText)
        }
    }
}

/// Rounded portrait thumbnail from an attachment's inline thumbnail data.
struct PhotoThumbnail: View {
    let attachment: Attachment
    var width: CGFloat = 72
    var height: CGFloat = 90

    var body: some View {
        Group {
            if let image = ThumbnailCache.image(for: attachment) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Theme.surface
            }
        }
        .frame(width: width, height: height)
        .clipShape(.rect(cornerRadius: 5, style: .continuous))
    }
}

/// Decoded list/calendar thumbnails, so scrolling doesn't re-decode JPEGs.
enum ThumbnailCache {
    private static let cache = NSCache<NSUUID, UIImage>()

    static func image(for attachment: Attachment) -> UIImage? {
        let key = attachment.identifier as NSUUID
        if let cached = cache.object(forKey: key) { return cached }
        guard let data = attachment.thumbnailData, let image = UIImage(data: data) else { return nil }
        cache.setObject(image, forKey: key)
        return image
    }
}

/// How far the page has scrolled through its title transition: 0 at rest, 1 once the large title
/// has gone under the bar. Driven continuously by scroll position (like a system large title), and
/// kept in its own observable so only the title views re-render while scrolling.
@Observable
final class TitleScroll {
    var progress: Double = 0
}

extension View {
    /// Apply to the page's scroll view. `range` is the scroll offset over which the title hands off —
    /// by default, while a `LargePageTitle` at the top of the content slides under the bar.
    func tracksTitleScroll(_ scroll: TitleScroll, range: ClosedRange<CGFloat> = 24...64) -> some View {
        onScrollGeometryChange(for: Double.self) { geometry in
            let offset = geometry.contentOffset.y + geometry.contentInsets.top
            let raw = Double((offset - range.lowerBound) / (range.upperBound - range.lowerBound))
            // Quantized so scrolling outside the hand-off never touches state.
            return (min(max(raw, 0.0), 1.0) * 24.0).rounded() / 24.0
        } action: { _, progress in
            if scroll.progress != progress { scroll.progress = progress }
        }
    }

    /// The small centered title that fades in once the page's `LargePageTitle` has scrolled away.
    func inlinePageTitle(
        _ title: String,
        navigationTitle: String? = nil,
        scroll: TitleScroll,
        isHidden: Bool = false
    ) -> some View {
        self
            .navigationTitle(navigationTitle ?? title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    if isHidden {
                        // Leaves the bar free for a wide leading item without the system drawing its own title.
                        Color.clear.frame(width: 1, height: 1)
                    } else {
                        InlineTitle(title: title, scroll: scroll)
                    }
                }
            }
    }

    /// Liquid Glass on iOS 26, a material before it — for custom controls that sit in the bar.
    @ViewBuilder
    func glassBackground(in shape: some Shape) -> some View {
        if #available(iOS 26.0, *) {
            glassEffect(.regular.interactive(), in: shape)
        } else {
            background(.regularMaterial, in: shape)
        }
    }
}

/// A tab's large serif title (and optional meta line), at the top of its scrolling content — every
/// tab puts it in the same place, a little below the toolbar row.
struct LargePageTitle: View {
    let title: String
    var subtitle: String?
    var topPadding: CGFloat

    init(_ title: String, subtitle: String? = nil, topPadding: CGFloat = Spacing.l) {
        self.title = title
        self.subtitle = subtitle
        self.topPadding = topPadding
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s - 2) {
            Text(title)
                .font(.system(.largeTitle, design: .serif).weight(.bold))
                .foregroundStyle(Theme.primaryText)
                .lineLimit(2)
                .minimumScaleFactor(0.7)
                .accessibilityAddTraits(.isHeader)
            if let subtitle {
                MetaLabel(subtitle)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, topPadding)
        .padding(.bottom, Spacing.xs)
    }
}

private struct InlineTitle: View {
    let title: String
    let scroll: TitleScroll

    var body: some View {
        let progress = scroll.progress
        Text(title)
            .font(.system(.headline, design: .serif).weight(.bold))
            .foregroundStyle(Theme.primaryText)
            .lineLimit(1)
            .frame(maxWidth: 200)
            .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
            .offset(y: 6 * (1 - progress))
            .opacity(progress)
            .accessibilityHidden(progress < 0.5)
    }
}

/// Gear button that opens Settings; shared by every tab.
struct SettingsButton: View {
    @State private var showing = false

    var body: some View {
        Button("Settings", systemImage: "gearshape") { showing = true }
            .sheet(isPresented: $showing) { SettingsView() }
    }
}

/// A search field that grows sideways out of the bar's search button. Shown over the bar, starting
/// as a circle exactly where the button sits (the button itself steps aside, with the bar's other
/// buttons), then widening to fill the row, with a close button at the far end.
struct ExpandingSearchBar: View {
    @Binding var text: String
    var isFocused: FocusState<Bool>.Binding
    let prompt: String
    var focusOnAppear = true
    /// Called once the field has shrunk back into the button.
    let onClose: () -> Void

    @State private var expanded = false
    private let size: CGFloat = 44

    var body: some View {
        GeometryReader { geometry in
            HStack(spacing: Spacing.s) {
                HStack(spacing: 0) {
                    Image(systemName: "magnifyingglass")
                        .font(.body.weight(.medium))
                        .foregroundStyle(expanded ? Theme.secondaryText : Theme.primaryText)
                        .frame(width: size, height: size)
                    if expanded {
                        TextField(prompt, text: $text)
                            .focused(isFocused)
                            .submitLabel(.search)
                            .onSubmit { isFocused.wrappedValue = false }
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                            .foregroundStyle(Theme.primaryText)
                            .transition(.opacity)
                        if !text.isEmpty {
                            Button("Clear", systemImage: "xmark.circle.fill") { text = "" }
                                .labelStyle(.iconOnly)
                                .foregroundStyle(Theme.secondaryText)
                                .buttonStyle(.plain)
                                .padding(.horizontal, 12)
                        }
                    }
                }
                .frame(
                    width: expanded ? max(geometry.size.width - size - Spacing.s, size) : size,
                    height: size,
                    alignment: .leading
                )
                // Keeps the placeholder inside the capsule while it widens.
                .clipShape(.capsule)
                .glassBackground(in: .capsule)

                if expanded {
                    Button("Close Search", systemImage: "xmark", action: close)
                        .labelStyle(.iconOnly)
                        .font(.body.weight(.medium))
                        .foregroundStyle(Theme.primaryText)
                        .buttonStyle(.plain)
                        .frame(width: size, height: size)
                        .contentShape(.circle)
                        .glassBackground(in: .circle)
                        .transition(.scale(scale: 0.4).combined(with: .opacity))
                }
            }
        }
        .frame(height: size)
        .onAppear {
            withAnimation(.snappy) { expanded = true }
            guard focusOnAppear else { return }
            // Once the field exists, so the focus request isn't dropped.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { isFocused.wrappedValue = true }
        }
    }

    private func close() {
        isFocused.wrappedValue = false
        text = ""
        withAnimation(.snappy(duration: 0.3)) {
            expanded = false
        } completion: {
            onClose()
        }
    }
}

/// The round sand "new entry" button that floats in the bottom-right corner.
struct NewEntryButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "square.and.pencil")
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(Theme.onAccent)
                .frame(width: 60, height: 60)
                .background(Theme.accent, in: .circle)
                .shadow(color: .black.opacity(0.14), radius: 14, y: 6)
                .contentShape(.circle)
        }
        .buttonStyle(PressScaleStyle())
        .accessibilityLabel("New entry")
    }
}

private struct PressScaleStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.92 : 1)
            .animation(.spring(duration: 0.25), value: configuration.isPressed)
    }
}
