import AppIntents

/// "New Journal Entry" — available in Shortcuts, Spotlight, Siri, and the Action button.
nonisolated struct NewEntryIntent: AppIntent {
    static let title: LocalizedStringResource = "New Journal Entry"
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        AppRouter.shared.selectedTab = .journal
        AppRouter.shared.pendingNewEntry = true
        return .result()
    }
}

nonisolated struct JournalShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: NewEntryIntent(),
            // Said with the app's name before "entry" ("New Today entry"): after "in", Today reads
            // as a time ("…in today"). Siri also takes the alternative names, Today Journal and
            // Daily Journal (`INAlternativeAppNames`).
            phrases: [
                "New \(.applicationName) entry",
                "Start a \(.applicationName) entry",
                "Write a \(.applicationName) entry",
            ],
            shortTitle: "New Entry",
            systemImageName: "square.and.pencil"
        )
    }
}
