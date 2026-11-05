import SwiftData
import SwiftUI

/// Small uppercase tracked label used for dates, section headers and stat captions, optionally led by
/// an icon (the day sheet's cards).
struct MetaLabel: View {
    let text: String
    var systemImage: String?
    var color = Theme.secondaryText

    init(_ text: String, systemImage: String? = nil, color: Color = Theme.secondaryText) {
        self.text = text
        self.systemImage = systemImage
        self.color = color
    }

    var body: some View {
        HStack(spacing: Spacing.xs + 2) {
            if let systemImage {
                Image(systemName: systemImage)
                    .accessibilityHidden(true)
            }
            Text(text.uppercased())
                .tracking(Typography.metaTracking)
        }
        .font(Typography.meta)
        .foregroundStyle(color)
    }
}

/// The sand capsule for the one primary action on a screen (the lock screen's Unlock), shrinking a
/// little when pressed.
struct AccentButtonStyle: PrimitiveButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        TapPressButton(configuration: configuration, scale: 0.96) {
            configuration.label
                .font(Typography.action)
                .padding(.horizontal, Spacing.l)
                .padding(.vertical, Spacing.m - 2)
                .foregroundStyle(Theme.onAccent)
                .background(Theme.accent, in: .capsule)
        }
    }
}

extension PrimitiveButtonStyle where Self == AccentButtonStyle {
    static var accent: AccentButtonStyle { AccentButtonStyle() }
}

/// A button that shrinks a little when pressed and springs back, like a key. A quick tap's press
/// barely shows before what it does takes over the screen, so a tap shows it for a moment
/// (`duration`) and its action goes ahead after that.
struct TapPressStyle: PrimitiveButtonStyle {
    var scale: CGFloat = 0.92

    /// A whole row's: less, as it's wide.
    static let rowScale: CGFloat = 0.97

    /// How long a tap's press shows before its action.
    static var duration: Duration { .milliseconds(110) }

    func makeBody(configuration: Configuration) -> some View {
        TapPressButton(configuration: configuration, scale: scale) { configuration.label }
    }
}

private struct TapPressButton<Label: View>: View {
    let configuration: PrimitiveButtonStyleConfiguration
    let scale: CGFloat
    @ViewBuilder let label: Label

    @State private var taps = 0
    @State private var isActing = false

    var body: some View {
        Button {
            guard !isActing else { return }
            taps += 1
            isActing = true
            Task {
                try? await Task.sleep(for: TapPressStyle.duration)
                isActing = false
                configuration.trigger()
            }
        } label: {
            label
        }
        .buttonStyle(HeldPressStyle(scale: scale, taps: taps))
    }
}

/// Shrinks while pressed, and for a moment after each tap (`taps`).
private struct HeldPressStyle: ButtonStyle {
    let scale: CGFloat
    let taps: Int

    func makeBody(configuration: Configuration) -> some View {
        HeldPress(label: configuration.label, isPressed: configuration.isPressed, scale: scale, taps: taps)
    }
}

private struct HeldPress<Label: View>: View {
    let label: Label
    let isPressed: Bool
    let scale: CGFloat
    let taps: Int

    @State private var showsTap = false

    var body: some View {
        let isShrunk = isPressed || showsTap
        label
            .scaleEffect(isShrunk ? scale : 1)
            .animation(.spring(duration: 0.25, bounce: 0.3), value: isShrunk)
            .onChange(of: taps) {
                showsTap = true
                Task {
                    try? await Task.sleep(for: TapPressStyle.duration)
                    showsTap = false
                }
            }
    }
}

/// The entry's time and place, as one quiet line ("3:57 PM · Mission District").
struct EntryMetaLine: View {
    let entry: Entry

    var body: some View {
        let parts = [entry.createdAt.formatted(date: .omitted, time: .shortened), entry.placeName]
        HStack(spacing: 0) {
            Text(parts.compactMap(\.self).joined(separator: " · "))
                .lineLimit(1)
            // The weather stays whole; a long place name gives way first.
            if let weather = entry.weather {
                Text(" · \(Image(systemName: weather.symbol)) \(weather.formattedTemperature)")
                    .fixedSize()
                    .accessibilityLabel("Weather: \(weather.formattedTemperature), \(weather.condition)")
            }
        }
        .font(Typography.caption)
        .foregroundStyle(Theme.secondaryText)
        .accessibilityElement(children: .combine)
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
    /// below the notch, over the title and the bar, or back down.
    /// `title` replaces the journal name (e.g. "Recently Deleted", which has no year span);
    /// `isFullScreen` holds the card up there without a grabber (while searching, with the search
    /// field at the card's top).
    func pageTitle(_ title: String? = nil, isFullScreen: Bool = false) -> some View {
        modifier(PageTitle(title: title, isHeldFullScreen: isFullScreen))
    }

    /// A softly colored rounded rectangle around a section of content.
    func surfaceCard() -> some View {
        padding(Spacing.m)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.surface, in: .rect(cornerRadius: Radius.card))
    }

    /// A sheet's content, with the page behind it darkened (`SheetBackdrop`). Sheets that resize show
    /// the pages' own `Grabber` (not the system's drag indicator), as far down from the sheet's top as
    /// it sits below a page card's.
    func sheetBackdrop(grabber: Bool = false) -> some View {
        presentationDragIndicator(.hidden)
            .overlay(alignment: .top) {
                if grabber {
                    Grabber()
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
            .background { SheetBackdrop() }
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

    /// Places this at the top of the screen, just below the notch, with or without the bar there.
    func belowNotch() -> some View {
        padding(.top, PageTitle.windowTop)
            .frame(maxHeight: .infinity, alignment: .top)
            .ignoresSafeArea(.container, edges: .top)
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

/// What every tab's card has in common: they're all up at full screen or all down, and they share
/// the measurements for it, so a page first opened at full screen has them at once.
@Observable
private final class PageCards {
    static let shared = PageCards()

    /// Dragged up to full screen.
    var isExpanded = false
    /// The title's height with the space below it, and the bar's, measured while they show.
    var titleHeight: CGFloat = 0
    var barHeight: CGFloat = 0
}

private struct PageTitle: ViewModifier {
    let title: String?
    let isHeldFullScreen: Bool

    @AppStorage(JournalName.storageKey) private var journalName = JournalName.default
    @Query(filter: #Predicate<Entry> { $0.deletedAt == nil }, sort: \Entry.createdAt)
    private var entries: [Entry]

    /// The card is off its resting place, on its way up or at full screen (the bar is hidden).
    @State private var isUp = PageCards.shared.isExpanded
    /// How far the card's top is moved from where the layout puts it: up over the title (negative)
    /// when full screen, and following the finger during a drag.
    @State private var lift = PageCards.shared.isExpanded ? -PageCards.shared.titleHeight : 0

    private var cards: PageCards { .shared }
    private var isExpanded: Bool { cards.isExpanded }
    private var titleHeight: CGFloat { cards.titleHeight }
    private var barHeight: CGFloat { cards.barHeight }

    func body(content: Content) -> some View {
        let name = title ?? JournalName.display(journalName)

        VStack(spacing: 0) {
            // Stays in the layout, and opaque, so the card simply slides over it and off it again.
            LargePageTitle(name, subtitle: title == nil ? yearSpan : nil)
                .padding(.horizontal, Spacing.m)
                .padding(.bottom, Spacing.m)
                .onGeometryChange(for: CGFloat.self, of: \.size.height) { cards.titleHeight = $0 }
                // Where it sits with the bar, even while the bar is hidden.
                .offset(y: isUp ? barHeight : 0)
                .accessibilityHidden(isExpanded || isHeldFullScreen)
            content
                // The scroll bar starts below the card's rounded corners.
                .contentMargins(.top, Radius.page, for: .scrollIndicators)
                .background(Theme.background)
                .background { PageCardMarker() }
                .overlay(alignment: .bottom) {
                    // The page fades out around and below the floating tab bar.
                    LinearGradient(
                        stops: [
                            .init(color: Theme.background.opacity(0), location: 0),
                            .init(color: Theme.background.opacity(0.85), location: 0.6),
                            .init(color: Theme.background, location: 1),
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: Self.bottomFade)
                    .allowsHitTesting(false)
                }
                .overlay(alignment: .top) {
                    if !isHeldFullScreen {
                        grabber
                    }
                }
                .clipShape(UnevenRoundedRectangle(
                    topLeadingRadius: Radius.page,
                    topTrailingRadius: Radius.page,
                    style: .continuous
                ))
                // Negative padding grows the card up over the title.
                .padding(.top, lift)
                .ignoresSafeArea(edges: .bottom)
        }
        .onGeometryChange(for: CGFloat.self) { $0.frame(in: .global).minY } action: { top in
            if !isUp && top > Self.windowTop { cards.barHeight = top - Self.windowTop }
        }
        .background(Theme.accent)
        // Full screen, the card takes the bar's place too, so it starts just below the notch.
        .toolbar(isUp ? .hidden : .visible, for: .navigationBar)
        .onChange(of: isHeldFullScreen) { _, held in move(up: held || isExpanded) }
        .onChange(of: titleHeight) { if isUp { lift = -titleHeight } }
        .onAppear(perform: matchOtherPages)
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

    /// How far up from the bottom of the screen the page fades out.
    private static var bottomFade: CGFloat { 110 }

    /// The top of the screen's safe area: just below the notch.
    static var windowTop: CGFloat {
        UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.keyWindow }
            .first?.safeAreaInsets.top ?? 0
    }

    /// From the card's resting place up to just below the notch.
    private var fullScreenDistance: CGFloat { titleHeight + barHeight }

    /// A short bar centered at the card's top, like a sheet's, in a strip as tall as the space above
    /// the pages' first content; dragging it moves the card (VoiceOver gets an action instead).
    private var grabber: some View {
        Grabber()
            // No wider than it needs to be: touches beside it reach the page's content (the map's top).
            .frame(width: 120, height: Spacing.l, alignment: .top)
            .contentShape(.rect)
            .gesture(
                // On screen, not on the card, which moves under the finger.
                DragGesture(minimumDistance: 4, coordinateSpace: .global)
                    .onChanged { drag in follow(drag.translation.height) }
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

    /// Moves the card with the finger between its two places, with a little give past either. The
    /// bar is hidden whenever the card is off its resting place, so its buttons go as soon as the
    /// card leaves and return as soon as it's back, while the finger is still down.
    private func follow(_ translation: CGFloat) {
        let distance = fullScreenDistance
        let travel = (isExpanded ? distance : 0) - translation
        let moved = travel < 0 ? travel / 6 : travel <= distance ? travel : distance + (travel - distance) / 6
        withTransaction(Self.still) {
            isUp = travel > 0
            lift = (isUp ? barHeight : 0) - moved
        }
    }

    private func setExpanded(_ expanded: Bool) {
        cards.isExpanded = expanded
        move(up: expanded || isHeldFullScreen)
    }

    /// Takes up the place the card was left in on another tab, at once.
    private func matchOtherPages() {
        let up = isExpanded || isHeldFullScreen
        guard up != isUp else { return }
        withTransaction(Self.still) {
            isUp = up
            lift = up ? -titleHeight : 0
        }
    }

    /// Applies a change at once, inside whatever animation is running.
    private static var still: Transaction {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        return transaction
    }

    /// Moves the card up to full screen or back down. Hiding or showing the bar shifts the page by
    /// its height at once, so the card is shifted back by as much, unanimated, to hold it where it
    /// is: going up, the bar goes first and the card rises on the next turn; coming down, the card
    /// settles with the bar still hidden, and the bar returns the moment it's there.
    private func move(up: Bool) {
        if up {
            if !isUp {
                withTransaction(Self.still) {
                    isUp = true
                    lift += barHeight
                }
            }
            DispatchQueue.main.async {
                withAnimation(.snappy) { lift = -titleHeight }
            }
        } else if isUp {
            // Short and without a bounce, so there's no settling for the bar to wait out.
            withAnimation(.smooth(duration: 0.25)) {
                lift = barHeight
            } completion: {
                // Unless it was sent back up or picked up again meanwhile.
                guard lift == barHeight else { return }
                withTransaction(Self.still) {
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

/// A popup's title in its bar: the system's own inline title, one line, exactly as Settings has it.
extension View {
    func sheetTitle(_ title: String) -> some View {
        navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
    }
}

/// An entry as a row of a popup's inset-grouped list (the day sheet, a map group): highlighted while
/// touched like any list row.
/// A day sheet section's note when it can't show anything yet ("Photo access is off for Journal.
/// Open Settings"), worded like Settings' own. `action` opens iOS's Settings, or first asks, where
/// iOS has no switch to show until Journal has asked.
struct AccessOffNote: View {
    let subject: String
    let action: () -> Void

    init(_ subject: String, action: @escaping () -> Void) {
        self.subject = subject
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Text("\(subject) is off for Journal. ") + Text("Open Settings").underline()
        }
        .font(Typography.note)
        .foregroundStyle(Theme.secondaryText)
        .multilineTextAlignment(.leading)
    }
}

extension URL {
    /// Journal's page in iOS's Settings.
    static let appSettings = URL(string: UIApplication.openSettingsURLString)!
}

struct SheetEntryRow: View {
    let entry: Entry
    var dateStyle: EntryRow.DateStyle = .none
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            EntryRow(entry: entry, dateStyle: dateStyle)
                .padding(.vertical, Spacing.xs)
                .contentShape(.rect)
        }
        .buttonStyle(TapPressStyle(scale: TapPressStyle.rowScale))
    }
}

/// The short bar at the top of the page's card, showing that it drags.
struct Grabber: View {
    var body: some View {
        Capsule()
            // Solid, so it still shows over the Map tab's map.
            .fill(Theme.secondaryText)
            .frame(width: 44, height: 3)
            .padding(.top, Spacing.s)
    }
}

/// A tab's large title (and optional meta line), in white on the sand band above the page's
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
                .font(Typography.pageTitle)
                .foregroundStyle(Theme.onAccent)
                .lineLimit(2)
                .minimumScaleFactor(0.7)
                .accessibilityAddTraits(.isHeader)
            // White rather than stone: stone is too faint on sand. Always there, if only as a blank
            // line, so the card below rests at the same height on every page.
            Text(subtitle?.uppercased() ?? " ")
                .font(Typography.meta)
                .tracking(Typography.metaTracking)
                .foregroundStyle(Theme.onAccent.opacity(0.85))
                .accessibilityHidden(subtitle == nil)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, Spacing.s)
    }
}

/// What a page shows with nothing in it (the journal, Insights, Recently Deleted): an icon, a short
/// title and a note, centered in the page's card. Put it in an overlay, so it's centered whatever the
/// list or scroll view under it holds.
struct EmptyState: View {
    let title: String
    let systemImage: String
    let message: String

    var body: some View {
        ContentUnavailableView {
            Label {
                Text(title)
                    .font(Typography.title)
                    .foregroundStyle(Theme.primaryText)
            } icon: {
                Image(systemName: systemImage)
                    .foregroundStyle(Theme.secondaryText)
            }
        } description: {
            Text(message)
                .font(Typography.note)
                .foregroundStyle(Theme.secondaryText)
        }
        // Clear of the floating tab bar below.
        .padding(.bottom, Spacing.l)
        .allowsHitTesting(false)
    }
}

/// Gear button that opens Settings; shared by every tab.
struct SettingsButton: View {
    @State private var showing = false

    var body: some View {
        Button("Settings", systemImage: "gearshape") { showing = true }
            .sheet(isPresented: $showing) { SettingsView().sheetBackdrop() }
    }
}

/// A search field that grows sideways out of the bar's search button, a close button coming in at the
/// far end. Drawn over the page, `belowNotch()`: it starts as a circle exactly over the button, which
/// goes with the bar, and settles at the top of the card as the card rises to full screen, and on
/// closing it shrinks back onto the button as the card comes down.
struct ExpandingSearchBar: View {
    @Binding var text: String
    var isFocused: FocusState<Bool>.Binding
    let prompt: String
    /// Called as the field starts to shrink, when the card should start down.
    let onClosing: () -> Void
    /// Called once the field has shrunk back into the button.
    let onClose: () -> Void

    @State private var expanded = false
    private let size = Self.height

    private static let height: CGFloat = 44
    /// What the page leaves at the card's top for the field.
    static let room = height + Spacing.m

    var body: some View {
        GeometryReader { geometry in
            HStack(spacing: Spacing.s) {
                HStack(spacing: 0) {
                    Image(systemName: "magnifyingglass")
                        .font(Typography.action)
                        // White like the bar's, on the sand, as a circle.
                        .foregroundStyle(expanded ? Theme.secondaryText : Theme.onAccent)
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
                                .buttonStyle(.borderless)
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
                        .font(Typography.action)
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
        .padding(.top, expanded ? Spacing.m : 0)
        .onAppear {
            withAnimation(.snappy) { expanded = true }
            // Once it's up: the keyboard takes long enough to load that it holds up the card's rise.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                if expanded { isFocused.wrappedValue = true }
            }
        }
    }

    private func close() {
        isFocused.wrappedValue = false
        text = ""
        onClosing()
        // The card's own way down (`PageTitle.move(up:)`), so they land together.
        withAnimation(.smooth(duration: 0.25)) {
            expanded = false
        } completion: {
            // A moment longer than the card, as the bar takes a frame or two to come back.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { onClose() }
        }
    }
}

/// The round sand "new entry" button that floats in the bottom-right corner.
struct NewEntryButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "square.and.pencil")
                .font(Typography.icon.weight(.medium))
                .foregroundStyle(Theme.onAccent)
                .frame(width: 60, height: 60)
                .background(Theme.accent, in: .circle)
                .shadow(color: .black.opacity(0.14), radius: 14, y: 6)
                .contentShape(.circle)
        }
        .buttonStyle(TapPressStyle())
        .accessibilityLabel("New entry")
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
