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
            // Every phrase has to name the app (the build refuses one that doesn't). Said with the
            // alternative name Today Journal (`INAlternativeAppNames`), the first is just "New
            // Today Journal entry".
            phrases: [
                "New \(.applicationName) entry",
                "New journal entry in \(.applicationName)",
                "Start a journal entry in \(.applicationName)",
                "Write a journal entry in \(.applicationName)",
            ],
            shortTitle: "New Entry",
            systemImageName: "square.and.pencil"
        )
    }
}
