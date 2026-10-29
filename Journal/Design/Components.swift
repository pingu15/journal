import SwiftData
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
/// `height` nil fills whatever height it's given (the entry row sizes it to the text beside it).
struct PhotoThumbnail: View {
    let attachment: Attachment
    var width: CGFloat = 72
    var height: CGFloat?

    var body: some View {
        Color.clear
            .overlay {
                if let image = ThumbnailCache.image(for: attachment) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    Theme.surface
                }
            }
            .frame(width: width)
            .frame(height: height)
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

extension View {
    /// A tab's page: the journal's name and year span (`LargePageTitle`) stay in place on a sand
    /// band, and the page's content scrolls in a card with rounded top corners below it; the bar
    /// carries no title of its own. `title` replaces the journal name (e.g. "Recently Deleted",
    /// which has no year span); `isHidden` lifts the title away (while searching, so results start
    /// under the bar).
    func pageTitle(_ title: String? = nil, isHidden: Bool = false) -> some View {
        modifier(PageTitle(title: title, isHidden: isHidden))
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

private struct PageTitle: ViewModifier {
    let title: String?
    let isHidden: Bool

    @AppStorage(JournalName.storageKey) private var journalName = JournalName.default
    @Query(filter: #Predicate<Entry> { $0.deletedAt == nil }, sort: \Entry.createdAt)
    private var entries: [Entry]

    func body(content: Content) -> some View {
        let name = title ?? JournalName.display(journalName)

        VStack(spacing: 0) {
            if !isHidden {
                LargePageTitle(name, subtitle: title == nil ? yearSpan : nil)
                    .padding(.horizontal, Spacing.m)
                    .padding(.bottom, Spacing.m)
                    .transition(.opacity)
            }
            content
                // The scroll bar starts below the card's rounded corners.
                .contentMargins(.top, Self.cornerRadius, for: .scrollIndicators)
                .background(Theme.background)
                .clipShape(UnevenRoundedRectangle(
                    topLeadingRadius: Self.cornerRadius,
                    topTrailingRadius: Self.cornerRadius,
                    style: .continuous
                ))
                .ignoresSafeArea(edges: .bottom)
        }
        .background(Theme.accent)
        .navigationTitle(name)
        .navigationBarTitleDisplayMode(.inline)
        // The bar sits on sand in both modes, so its buttons are white. The sand is the page's own
        // background showing through, not the bar's, so it slides away with the page when an
        // entry's edge swipe brings it back. (The status bar picks its own color from it.)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .principal) {
                // Keeps the system from drawing the navigation title in the bar.
                Color.clear.frame(width: 1, height: 1)
            }
        }
    }

    static let cornerRadius: CGFloat = 28

    /// "2025 – 2026", or a single year, spanning the first and latest entries.
    private var yearSpan: String? {
        guard let oldest = entries.first?.createdAt, let newest = entries.last?.createdAt else { return nil }
        let calendar = Calendar.current
        let first = calendar.component(.year, from: oldest)
        let last = calendar.component(.year, from: newest)
        return first == last ? String(first) : "\(first) – \(last)"
    }
}

/// A tab's large serif title (and optional meta line), in white on the sand band above the page's
/// content (see `pageTitle`) — every tab puts it in the same place, a little below the toolbar row.
struct LargePageTitle: View {
    let title: String
    var subtitle: String?

    init(_ title: String, subtitle: String? = nil) {
        self.title = title
        self.subtitle = subtitle
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s - 2) {
            Text(title)
                .font(.system(.largeTitle, design: .serif).weight(.bold))
                .foregroundStyle(Theme.onAccent)
                .lineLimit(2)
                .minimumScaleFactor(0.7)
                .accessibilityAddTraits(.isHeader)
            if let subtitle {
                // White rather than stone: stone is too faint on sand.
                Text(subtitle.uppercased())
                    .font(Typography.meta)
                    .tracking(Typography.metaTracking)
                    .foregroundStyle(Theme.onAccent.opacity(0.85))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, Spacing.s)
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
    @Environment(\.colorScheme) private var colorScheme
    private let size: CGFloat = 44

    var body: some View {
        GeometryReader { geometry in
            HStack(spacing: Spacing.s) {
                HStack(spacing: 0) {
                    Image(systemName: "magnifyingglass")
                        .font(.body.weight(.medium))
                        .foregroundStyle(expanded ? Theme.onAccent.opacity(0.6) : Theme.onAccent)
                        .frame(width: size, height: size)
                    if expanded {
                        TextField(prompt, text: $text, prompt: Text(prompt).foregroundStyle(Theme.onAccent.opacity(0.5)))
                            .focused(isFocused)
                            .submitLabel(.search)
                            .onSubmit { isFocused.wrappedValue = false }
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                            .foregroundStyle(Theme.onAccent)
                            // The keyboard follows the app's appearance, not the light bar.
                            .environment(\.colorScheme, colorScheme)
                            .transition(.opacity)
                        if !text.isEmpty {
                            Button("Clear", systemImage: "xmark.circle.fill") { text = "" }
                                .labelStyle(.iconOnly)
                                .foregroundStyle(Theme.onAccent.opacity(0.6))
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
                        .foregroundStyle(Theme.onAccent)
                        .buttonStyle(.plain)
                        .frame(width: size, height: size)
                        .contentShape(.circle)
                        .glassBackground(in: .circle)
                        .transition(.scale(scale: 0.4).combined(with: .opacity))
                }
            }
        }
        .frame(height: size)
        // It sits on the sand band in both modes, white like the bar's own buttons.
        .environment(\.colorScheme, .dark)
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

extension View {
    /// Turns off the back button's long-press menu (which lists the previous screens by title —
    /// for the editor, the journal's name) on the screen this is applied to.
    func hidesBackButtonMenu() -> some View {
        background(BackMenuRemover().frame(width: 0, height: 0))
    }
}

private struct BackMenuRemover: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> Controller { Controller() }
    func updateUIViewController(_ controller: Controller, context: Context) {}

    final class Controller: UIViewController {
        override func viewWillAppear(_ animated: Bool) {
            super.viewWillAppear(animated)
            // The back button belongs to the screen below this one.
            guard let stack = navigationController?.viewControllers, stack.count > 1 else { return }
            let below = stack[stack.count - 2]
            if !(below.navigationItem.backBarButtonItem is MenuFreeBackItem) {
                below.navigationItem.backBarButtonItem = MenuFreeBackItem(title: "", style: .plain, target: nil, action: nil)
            }
        }
    }

    /// UIKit fills in a back item's `menu` with the stack's titles; refusing it leaves no menu.
    final class MenuFreeBackItem: UIBarButtonItem {
        override var menu: UIMenu? {
            get { nil }
            set {}
        }
    }
}
