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

/// The entry's time and place, as one quiet line ("3:57 PM · Mission District"; tags already show
/// in the excerpt).
struct EntryMetaLine: View {
    let entry: Entry
    /// Off where the row already shows the time (a calendar day's entries).
    var showsTime = true

    var body: some View {
        let parts = [
            showsTime ? entry.createdAt.formatted(date: .omitted, time: .shortened) : nil,
            entry.placeName,
        ].compactMap(\.self)
        if !parts.isEmpty {
            Text(parts.joined(separator: " · "))
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
    /// carries no title of its own. A grabber at the card's top drags it up to full screen, just
    /// below the notch, over the title and the bar (or back down); a tap on it does the same.
    /// `title` replaces the journal name (e.g. "Recently Deleted", which has no year span);
    /// `isFullScreen` holds the card up there without a grabber (while searching, with the search
    /// field at the card's top).
    func pageTitle(_ title: String? = nil, isFullScreen: Bool = false) -> some View {
        modifier(PageTitle(title: title, isHeldFullScreen: isFullScreen))
    }

    /// Content scrolls out at the top edge as is, without iOS 26's soft fade there.
    @ViewBuilder
    func hidesTopScrollEdgeEffect() -> some View {
        if #available(iOS 26.0, *) {
            scrollEdgeEffectHidden(true, for: .top)
        } else {
            self
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

private struct PageTitle: ViewModifier {
    let title: String?
    let isHeldFullScreen: Bool

    @AppStorage(JournalName.storageKey) private var journalName = JournalName.default
    @Query(filter: #Predicate<Entry> { $0.deletedAt == nil }, sort: \Entry.createdAt)
    private var entries: [Entry]

    /// Dragged (or tapped) up to full screen.
    @State private var isExpanded = false
    /// The card is up at full screen (the bar is hidden).
    @State private var isUp = false
    @State private var isTitleHidden = false
    /// How far the card's top is moved from where the layout puts it: up over the title (negative)
    /// when full screen, and following the finger during a drag.
    @State private var lift: CGFloat = 0
    /// The title's height with the space below it, and the bar's, measured while they show.
    @State private var titleHeight: CGFloat = 0
    @State private var barHeight: CGFloat = 0

    func body(content: Content) -> some View {
        let name = title ?? JournalName.display(journalName)

        VStack(spacing: 0) {
            // Stays in the layout while the card covers it, so the card can follow a drag over it.
            LargePageTitle(name, subtitle: title == nil ? yearSpan : nil)
                .padding(.horizontal, Spacing.m)
                .padding(.bottom, Spacing.m)
                .onGeometryChange(for: CGFloat.self, of: \.size.height) { titleHeight = $0 }
                // Where it sits with the bar, even while the bar is hidden.
                .offset(y: isUp ? barHeight : 0)
                .opacity(isTitleHidden ? 0 : 1)
                .accessibilityHidden(isTitleHidden)
            content
                // The scroll bar starts below the card's rounded corners.
                .contentMargins(.top, Self.cornerRadius, for: .scrollIndicators)
                .background(Theme.background)
                .overlay(alignment: .top) {
                    if !isHeldFullScreen {
                        grabber
                    }
                }
                .clipShape(UnevenRoundedRectangle(
                    topLeadingRadius: Self.cornerRadius,
                    topTrailingRadius: Self.cornerRadius,
                    style: .continuous
                ))
                // Negative padding grows the card up over the title.
                .padding(.top, lift)
                .ignoresSafeArea(edges: .bottom)
        }
        .onGeometryChange(for: CGFloat.self) { $0.frame(in: .global).minY } action: { top in
            if !isUp { barHeight = max(0, top - Self.windowTop) }
        }
        .background(Theme.accent)
        // Full screen, the card takes the bar's place too, so it starts just below the notch.
        .toolbar(isUp ? .hidden : .visible, for: .navigationBar)
        .onChange(of: isHeldFullScreen) { _, held in move(up: held || isExpanded) }
        .onChange(of: titleHeight) { if isUp { lift = restingLift } }
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

    /// The top of the screen's safe area: just below the notch.
    private static var windowTop: CGFloat {
        UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.keyWindow }
            .first?.safeAreaInsets.top ?? 0
    }

    /// From the card's resting place up to just below the notch.
    private var fullScreenDistance: CGFloat { titleHeight + barHeight }

    /// A short bar centered at the card's top, like a sheet's, in a strip as tall as the space above
    /// the pages' first content; dragging it moves the card, and a tap toggles it.
    private var grabber: some View {
        Capsule()
            // Solid, so it still shows over the Map tab's map.
            .fill(Theme.secondaryText)
            .frame(width: 36, height: 5)
            .padding(.top, Spacing.s)
            .frame(maxWidth: .infinity, minHeight: Spacing.l, alignment: .top)
            .contentShape(.rect)
            .onTapGesture { setExpanded(!isExpanded) }
            .gesture(
                // On screen, not on the card, which moves under the finger.
                DragGesture(minimumDistance: 4, coordinateSpace: .global)
                    .onChanged { drag in lift = restingLift + followed(drag.translation.height) }
                    .onEnded { drag in
                        let travel = drag.predictedEndTranslation.height
                        let third = fullScreenDistance / 3
                        setExpanded(isExpanded ? travel < third : travel < -third)
                    }
            )
            .accessibilityElement()
            .accessibilityLabel(isExpanded ? "Show title" : "Expand to full screen")
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { setExpanded(!isExpanded) }
    }

    /// Where the card rests: up over the title at full screen (the bar's space is already gone).
    private var restingLift: CGFloat { isUp ? -titleHeight : 0 }

    /// Follows the finger between the two places, with a little give past either.
    private func followed(_ translation: CGFloat) -> CGFloat {
        let distance = fullScreenDistance
        // Down from full screen, or up from resting: the way it can go.
        let toward = isUp ? translation : -translation
        let moved = toward < 0 ? toward / 6 : toward <= distance ? toward : distance + (toward - distance) / 6
        return isUp ? moved : -moved
    }

    private func setExpanded(_ expanded: Bool) {
        isExpanded = expanded
        move(up: expanded || isHeldFullScreen)
    }

    /// Moves the card up to full screen or back down. Hiding or showing the bar shifts the page by
    /// its height at once, so the card is shifted back by as much, unanimated, to hold it where it
    /// is: going up, the bar goes first and the card rises on the next turn; coming down, the card
    /// settles with the bar still hidden, and the bar returns once the card has cleared its row.
    private func move(up: Bool) {
        var still = Transaction()
        still.disablesAnimations = true
        if up {
            if !isUp {
                withTransaction(still) {
                    isUp = true
                    lift += barHeight
                }
            }
            DispatchQueue.main.async {
                withAnimation(.snappy) {
                    lift = -titleHeight
                    isTitleHidden = true
                }
            }
        } else if isUp {
            withAnimation(.snappy) {
                lift = barHeight
                isTitleHidden = false
            } completion: {
                // Unless it was sent back up meanwhile.
                guard !(isExpanded || isHeldFullScreen) else { return }
                withTransaction(still) {
                    isUp = false
                    lift = 0
                }
            }
        } else {
            withAnimation(.snappy) { lift = 0 }
        }
    }

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

/// A search field that grows sideways from a circle like the bar's search button, at the top of the
/// full-screen card (the bar steps aside), widening to fill the row, with a close button at the far
/// end.
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
                        TextField(prompt, text: $text, prompt: Text(prompt).foregroundStyle(Theme.secondaryText))
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
