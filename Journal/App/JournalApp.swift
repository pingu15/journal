import SwiftData
import SwiftUI
import UIKit

@main
struct JournalApp: App {
    @State private var lock = AppLock()
    @State private var router = AppRouter.shared
    @State private var sync = ICloudSync.shared

    init() {
        Theme.applyNavigationBarAppearance()
        // Here, as iOS can relaunch the app in the background, with no scene, for a move.
        PlaceTracker.shared.resume()
        // Registers "New Journal Entry" and its Siri phrases with the system as soon as the app has run.
        JournalShortcuts.updateAppShortcutParameters()
        // Following the keyboard from the start, for views centered above it.
        _ = Keyboard.shared
        NotificationPresenter.shared.install()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(lock)
                .environment(router)
                .environment(sync)
                // The store mirrored to iCloud or not; a new one when sync is switched.
                .modelContainer(sync.container)
        }
    }
}

/// Hosts the tabs, applies the appearance, and drives the privacy lock.
struct RootView: View {
    @Environment(AppLock.self) private var lock
    @Environment(AppRouter.self) private var router
    @Environment(ICloudSync.self) private var sync
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(AppLock.enabledKey) private var lockEnabled = false
    @AppStorage(Appearance.storageKey) private var appearance = Appearance.system

    @State private var shield = PrivacyShield()
    @State private var showsOnboarding = Onboarding.isNeeded
    /// One automatic Face ID prompt per trip to the foreground; after that the user taps Unlock.
    @State private var hasPromptedSinceForeground = false
    /// Set on going to the background, so the widgets refresh when the app is opened again (not
    /// after Face ID or a look at the app switcher, which only make it inactive).
    @State private var refreshWidgetsOnOpen = false

    /// Locked, or leaving the app (inactive covers the app switcher) — but not merely because one of
    /// our own permission prompts made the scene inactive.
    private var isShielded: Bool {
        guard lockEnabled else { return false }
        switch scenePhase {
        case .active: return !lock.isUnlocked
        case .inactive: return !lock.isUnlocked || !SystemPrompts.shared.isPresenting
        default: return true
        }
    }

    private var tabs: some View {
        TabView(selection: Binding(get: { router.selectedTab }, set: { router.selectedTab = $0 })) {
            // Icons only (their names are for VoiceOver), each scaled to look the same size (`TabLabel`).
            Tab(value: .journal) {
                EntriesView()
            } label: {
                TabLabel(name: "Journal", symbol: "book.closed", optical: 0.94)
            }
            Tab(value: .calendar) {
                CalendarView()
            } label: {
                TabLabel(name: "Calendar", symbol: "calendar")
            }
            Tab(value: .media) {
                MediaView()
            } label: {
                TabLabel(name: "Media", symbol: "photo.on.rectangle", optical: 1.04)
            }
            Tab(value: .map) {
                MapView()
            } label: {
                TabLabel(name: "Map", symbol: "map")
            }
        }
    }

    var body: some View {
        Group {
            // Out while sync swaps the store (`ICloudSync.applySetting`), so no query outlives it.
            if sync.isSwapping {
                Theme.background.ignoresSafeArea()
            } else {
                tabs
            }
        }
        .tint(Theme.primaryText)
        .accessibilityHidden(showsOnboarding)
        .overlay {
            // Over the tabs from the first frame, rather than a cover sliding up over them.
            if showsOnboarding {
                OnboardingView {
                    UserDefaults.standard.set(true, forKey: Onboarding.completedKey)
                    sync.applySetting()
                    withAnimation(.easeInOut(duration: 0.35)) { showsOnboarding = false }
                }
                .transition(.opacity)
            }
        }
        .task {
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("-seedSampleData") {
                SampleData.seed(context)
            }
            if ProcessInfo.processInfo.arguments.contains("-seedSamplePlaces") {
                SampleData.seedPlaces()
            }
            #endif
            Entry.purgeExpiredTrash(in: context)
            Entry.deleteBlankEntries(in: context, keeping: [])
            WidgetSync.update(in: context)
            // So the map can open on it at once.
            LocationService.shared.refreshLastKnownLocation()
        }
        .onChange(of: appearance, initial: true) { old, new in
            new.apply(animated: old != new)
        }
        .onChange(of: isShielded, initial: true) { _, shielded in
            shield.setVisible(shielded, lock: lock)
        }
        .onAppear { shield.watch(lock: lock) }
        // The widgets' links: the day sheet on a day (today unless one is named), or a blank entry.
        .onOpenURL { url in
            guard url.scheme == WidgetSnapshot.newEntryURL.scheme else { return }
            if url.host() == WidgetSnapshot.dayHost {
                router.openDay(WidgetSnapshot.day(from: url) ?? .now)
                return
            }
            router.selectedTab = .journal
            if url.host() == WidgetSnapshot.newEntryURL.host() {
                router.pendingNewEntry = true
            }
        }
        .onChange(of: scenePhase, initial: true) { _, phase in
            if phase != .active {
                // Never leave writing only in memory when the app might be suspended or killed.
                try? context.save()
            }
            if phase == .background {
                // The widgets show what was written.
                WidgetSync.update(in: context)
            }
            switch phase {
            case .background:
                // Once the app has been left for the home screen or another app. Only inactive in the
                // app switcher (or under Control Center), so a look there doesn't lock it.
                lock.lock()
                hasPromptedSinceForeground = false
                refreshWidgetsOnOpen = true
            case .active:
                // Permissions may have changed in Settings meanwhile.
                CalendarEvents.refreshStatus()
                PhotoLibrary.refreshStatus()
                // Opened again: the widgets catch up (on launch, `task` does it after its cleanup).
                if refreshWidgetsOnOpen {
                    refreshWidgetsOnOpen = false
                    WidgetSync.update(in: context)
                }
                Task {
                    await ReminderScheduler.refresh()
                    // The coming month's, with whatever was written or deleted since.
                    await OnThisDayScheduler.refresh(in: context)
                }
                if lockEnabled && !lock.isUnlocked && !hasPromptedSinceForeground {
                    hasPromptedSinceForeground = true
                    Task { await lock.unlock() }
                }
            default:
                break
            }
        }
    }
}

/// A tab's icon, its name only for VoiceOver. The tab bar draws every icon at one size, so each is
/// drawn inside a clear square of that size, scaled to look the same size as the others (`visualSize`):
/// at one point size the wide ones (photos, map) looked bigger than the tall book.
private struct TabLabel: View {
    let name: String
    let symbol: String
    /// A correction by eye on top of `visualSize(of:)`, which still left the solid, tall book looking
    /// biggest and the flat photos smallest.
    var optical: CGFloat = 1

    var body: some View {
        Image(uiImage: Self.icon(symbol, optical: optical))
            .accessibilityLabel(name)
    }

    /// The square the tab bar draws an icon in.
    private static let side: CGFloat = 30
    /// How big every icon looks, in points (`visualSize(of:)`).
    private static let size: CGFloat = 23.5

    /// How big ink of this shape looks: between the side of a square of the same area (which made the
    /// narrow book look tallest) and its longest side (which made it look smallest).
    private static func visualSize(of ink: CGRect) -> CGFloat {
        ((ink.width * ink.height).squareRoot() * max(ink.width, ink.height)).squareRoot()
    }

    private static func icon(_ symbol: String, optical: CGFloat) -> UIImage {
        // Large, so its ink is measured finely; scaled down to size below.
        let configuration = UIImage.SymbolConfiguration(pointSize: 60, weight: .medium)
        guard let glyph = UIImage(systemName: "\(symbol).fill", withConfiguration: configuration)
            ?? UIImage(systemName: symbol, withConfiguration: configuration),
            let ink = inkBounds(of: glyph)
        else { return UIImage() }
        let scale = size * optical / visualSize(of: ink)
        let image = UIGraphicsImageRenderer(size: CGSize(width: side, height: side)).image { _ in
            // The ink centered, not the symbol's own box, which pads some sides more than others.
            let origin = CGPoint(
                x: (side - ink.width * scale) / 2 - ink.minX * scale,
                y: (side - ink.height * scale) / 2 - ink.minY * scale
            )
            glyph.draw(in: CGRect(origin: origin, size: CGSize(width: glyph.size.width * scale, height: glyph.size.height * scale)))
        }
        return image.withRenderingMode(.alwaysTemplate)
    }

    /// Where an image actually draws, in its points: the box round its opaque pixels.
    private static func inkBounds(of image: UIImage) -> CGRect? {
        let width = Int(image.size.width.rounded(.up)), height = Int(image.size.height.rounded(.up))
        guard width > 0, height > 0,
              let context = CGContext(
                data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width,
                space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.alphaOnly.rawValue
              )
        else { return nil }
        // Flipped to UIKit's coordinates, so row 0 in memory is the top.
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: 1, y: -1)
        UIGraphicsPushContext(context)
        image.draw(at: .zero)
        UIGraphicsPopContext()
        guard let data = context.data?.assumingMemoryBound(to: UInt8.self) else { return nil }
        var minX = width, minY = height, maxX = -1, maxY = -1
        for y in 0..<height {
            for x in 0..<width where data[y * width + x] > 32 {
                minX = min(minX, x); maxX = max(maxX, x)
                minY = min(minY, y); maxY = max(maxY, y)
            }
        }
        guard maxX >= minX, maxY >= minY else { return nil }
        return CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
    }
}
