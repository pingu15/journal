import SwiftData
import SwiftUI

@main
struct JournalApp: App {
    @State private var lock = AppLock()
    @State private var router = AppRouter.shared

    init() {
        Theme.applyNavigationBarAppearance()
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
        // The setter also runs when the open tab is tapped again.
        TabView(selection: Binding(get: { router.selectedTab }, set: { tab in
            if tab == .calendar { router.calendarTabTaps += 1 }
            router.selectedTab = tab
        })) {
            // Icons only; the names stay as accessibility labels.
            Tab(value: .journal) {
                EntriesView()
            } label: {
                TabIcon(name: "Journal", symbol: "book.closed")
            }
            Tab(value: .calendar) {
                CalendarView()
            } label: {
                TabIcon(name: "Calendar", symbol: "calendar")
            }
            Tab(value: .insights) {
                InsightsView()
            } label: {
                TabIcon(name: "Insights", symbol: "chart.bar.xaxis")
            }
        }
        .tint(Theme.primaryText)
        .task {
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("-seedSampleData") {
                SampleData.populate(context)
            }
            #endif
            Entry.purgeExpiredTrash(in: context)
            Entry.deleteBlankEntries(in: context, keeping: [])
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

private struct TabIcon: View {
    let name: String
    let symbol: String

    var body: some View {
        Image(systemName: symbol)
            .accessibilityLabel(name)
    }
}
