import AppIntents

/// "New Journal Entry" — available in Shortcuts, Spotlight, Siri, and the Action button.
nonisolated struct NewEntryIntent: AppIntent {
    static let title: LocalizedStringResource = "New Journal Entry"
    static let description = IntentDescription("Opens Journal to a blank page.")
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
            phrases: [
                "New entry in \(.applicationName)",
                "Write in \(.applicationName)",
            ],
            shortTitle: "New Entry",
            systemImageName: "square.and.pencil"
        )
    }
}
