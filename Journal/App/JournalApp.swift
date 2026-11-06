import SwiftData
import SwiftUI
import UIKit

@main
struct JournalApp: App {
    @State private var lock = AppLock()
    @State private var router = AppRouter.shared

    init() {
        Theme.applyNavigationBarAppearance()
        // Here, as iOS can relaunch the app in the background, with no scene, for a move.
        PlaceTracker.shared.resume()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(lock)
                .environment(router)
        }
        .modelContainer(for: [Entry.self, Attachment.self])
    }
}

/// Hosts the tabs, applies the appearance, and drives the privacy lock.
struct RootView: View {
    @Environment(AppLock.self) private var lock
    @Environment(AppRouter.self) private var router
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(AppLock.enabledKey) private var lockEnabled = false
    @AppStorage(Appearance.storageKey) private var appearance = Appearance.system

    @State private var shield = PrivacyShield()
    /// One automatic Face ID prompt per trip to the foreground; after that the user taps Unlock.
    @State private var hasPromptedSinceForeground = false

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

    var body: some View {
        TabView(selection: Binding(get: { router.selectedTab }, set: { router.selectedTab = $0 })) {
            // Each with its name under its icon, as iOS lays them out (smaller icons, room around each).
            Tab(value: .journal) {
                EntriesView()
            } label: {
                TabLabel(name: "Journal", symbol: "book.closed")
            }
            Tab(value: .calendar) {
                CalendarView()
            } label: {
                TabLabel(name: "Calendar", symbol: "calendar")
            }
            Tab(value: .media) {
                MediaView()
            } label: {
                TabLabel(name: "Media", symbol: "photo.on.rectangle")
            }
            Tab(value: .map) {
                MapView()
            } label: {
                TabLabel(name: "Map", symbol: "map")
            }
        }
        .tint(Theme.primaryText)
        .task {
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("-seedSampleData") {
                SampleData.populate(context)
            }
            if ProcessInfo.processInfo.arguments.contains("-seedSamplePlaces") {
                PlaceTracker.seedSampleDays()
            }
            #endif
            Entry.purgeExpiredTrash(in: context)
            Entry.deleteBlankEntries(in: context, keeping: [])
            // So the map can open on it at once.
            LocationService.shared.refreshLastKnownLocation()
        }
        .onChange(of: appearance, initial: true) { old, new in
            new.apply(animated: old != new)
        }
        .onChange(of: isShielded, initial: true) { _, shielded in
            shield.setVisible(shielded, lock: lock)
        }
        .onChange(of: scenePhase, initial: true) { _, phase in
            if phase != .active {
                // Never leave writing only in memory when the app might be suspended or killed.
                try? context.save()
            }
            switch phase {
            case .background:
                lock.lock()
                hasPromptedSinceForeground = false
            case .active:
                Task { await ReminderScheduler.refresh() }
                // On the first open (while iOS hasn't been asked for location), not over the lock
                // screen: asks for what place tracking needs, and turns it on if it's allowed.
                if !lockEnabled || lock.isUnlocked {
                    Task { await PlaceTracker.shared.enableOnFirstOpen() }
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

/// A tab's name under its icon. The tab bar draws every icon at one size, so the icon is drawn a
/// size smaller inside a clear square of that size, leaving room around it.
private struct TabLabel: View {
    let name: String
    let symbol: String

    var body: some View {
        Label {
            Text(name)
        } icon: {
            Image(uiImage: Self.icon(symbol))
        }
    }

    private static func icon(_ symbol: String) -> UIImage {
        let configuration = UIImage.SymbolConfiguration(pointSize: 18, weight: .medium)
        guard let glyph = UIImage(systemName: "\(symbol).fill", withConfiguration: configuration)
            ?? UIImage(systemName: symbol, withConfiguration: configuration)
        else { return UIImage() }
        let side: CGFloat = 30
        let canvas = CGSize(width: side, height: side)
        let image = UIGraphicsImageRenderer(size: canvas).image { _ in
            glyph.draw(at: CGPoint(x: (side - glyph.size.width) / 2, y: (side - glyph.size.height) / 2))
        }
        return image.withRenderingMode(.alwaysTemplate)
    }
}
