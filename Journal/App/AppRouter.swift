import Observation
import SwiftData
import SwiftUI
import UIKit

enum AppTab: Hashable {
    case journal, calendar, insights
}

enum Appearance: String, CaseIterable, Identifiable {
    static let storageKey = "appearance"

    case system, light, dark

    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    var userInterfaceStyle: UIUserInterfaceStyle {
        switch self {
        case .system: .unspecified
        case .light: .light
        case .dark: .dark
        }
    }

    static var current: Appearance {
        UserDefaults.standard.string(forKey: storageKey).flatMap(Appearance.init(rawValue:)) ?? .system
    }

    /// Applies to every window in the app at once — main UI, sheets, and the lock window —
    /// so an open Settings sheet changes along with everything behind it.
    func apply(animated: Bool) {
        for scene in UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }) {
            for window in scene.windows where window.overrideUserInterfaceStyle != userInterfaceStyle {
                if animated {
                    UIView.transition(with: window, duration: 0.3, options: .transitionCrossDissolve) {
                        window.overrideUserInterfaceStyle = userInterfaceStyle
                    }
                } else {
                    window.overrideUserInterfaceStyle = userInterfaceStyle
                }
            }
        }
    }
}

/// App-wide navigation state, shared with App Intents so a shortcut can open a blank page.
@Observable
final class AppRouter {
    static let shared = AppRouter()

    var selectedTab: AppTab = .journal
    var journalPath: [Entry] = []
    /// Set by `NewEntryIntent`; the journal screen consumes it once it has a model context.
    var pendingNewEntry = false
    /// Set to open the journal tab searching for this text (e.g. a tag tapped in Insights).
    var pendingSearch: String?
    /// Entries with an editor on screen, so blank-entry cleanup never removes one mid-edit.
    var openEntries: Set<PersistentIdentifier> = []
    /// Bumped whenever the Calendar tab is tapped (even when it's already open), so the calendar
    /// scrolls back to this month.
    var calendarTabTaps = 0

    func search(for text: String) {
        pendingSearch = text
        selectedTab = .journal
    }
}
