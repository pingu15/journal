import SwiftData
import SwiftUI
import WeatherKit

struct SettingsView: View {
    @Environment(AppLock.self) private var lock
    @Environment(ICloudSync.self) private var sync
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase

    @AppStorage(AppLock.enabledKey) private var lockEnabled = false
    @AppStorage(JournalName.storageKey) private var journalName = JournalName.default
    @AppStorage(Appearance.storageKey) private var appearance = Appearance.system
    @AppStorage(ReminderScheduler.enabledKey) private var reminderEnabled = false
    @AppStorage(ReminderScheduler.minutesKey) private var reminderMinutes = ReminderScheduler.defaultMinutes
    @AppStorage(OnThisDayScheduler.enabledKey) private var onThisDayEnabled = false
    @AppStorage(OnThisDayScheduler.minutesKey) private var onThisDayMinutes = OnThisDayScheduler.defaultMinutes
    @AppStorage(LocationService.autoTagKey) private var autoTagLocation = false
    @AppStorage(PlaceTracker.enabledKey) private var trackPlaces = false
    @AppStorage(ICloudSync.enabledKey) private var syncEnabled = false
    @State private var notificationsDenied = false
    /// Notifications haven't been asked for yet, so the note can ask rather than send the user away.
    @State private var notificationsCanAsk = false
    @State private var locationDenied = false
    /// For the Location note: tracking on without access says so, like the reminder without notifications.
    // Read live: iOS's answer comes a moment after its prompt closes or Settings is left.
    private var locationAllowed: Bool { LocationService.shared.isAuthorized }
    private var locationCanAsk: Bool { LocationService.shared.canAsk }
    private var locationAlways: Bool { LocationService.shared.allowsAlways }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(JournalName.default, text: $journalName)
                        .submitLabel(.done)
                        .onSubmit {
                            journalName = JournalName.display(journalName)
                        }
                        .onChange(of: journalName) { _, name in
                            if name.count > JournalName.maxLength {
                                journalName = String(name.prefix(JournalName.maxLength))
                            }
                        }
                } header: {
                    Text("Journal Name")
                } footer: {
                    Text("Shown at the top of your journal.")
                }

                Section {
                    NavigationLink {
                        ThemeList(selection: $appearance)
                    } label: {
                        LabeledContent {
                            Text(appearance.label)
                        } label: {
                            Label("Theme", systemImage: "paintpalette")
                        }
                    }
                } header: {
                    Text("Appearance")
                }

                // Each on its own page, like Theme, saying here whether it's on.
                Section {
                    notificationRow("Daily Reminder", systemImage: "bell", isOn: reminderEnabled) {
                        notificationPage("Daily Reminder", isOn: reminderBinding, time: reminderTime)
                    }
                    notificationRow("On This Day", systemImage: "calendar", isOn: onThisDayEnabled) {
                        notificationPage("On This Day", isOn: onThisDayBinding, time: onThisDayTime)
                    }
                } header: {
                    Text("Notifications")
                } footer: {
                    notificationsNote
                }

                Section {
                    Toggle("Add Current Location", systemImage: "location", isOn: autoTagBinding)
                        .tint(Theme.accent)
                    Toggle("Track Visited Places", systemImage: "figure.walk", isOn: trackPlacesBinding)
                        .tint(Theme.accent)
                } header: {
                    Text("Location")
                } footer: {
                    // Tracking stays on without access, like the reminder without notifications, and
                    // says so here until it's allowed: location off altogether, or only While Using,
                    // short of the Always tracking needs (which only iOS's Settings can give once
                    // it's been asked).
                    if (locationDenied || trackPlaces) && !locationAllowed {
                        Button {
                            if locationCanAsk {
                                Task {
                                    if trackPlaces {
                                        await PlaceTracker.shared.enable()
                                    } else {
                                        _ = await LocationService.shared.requestAuthorization()
                                    }
                                    refreshLocationAccess()
                                }
                            } else if let url = URL(string: UIApplication.openSettingsURLString) {
                                openURL(url)
                            }
                        } label: {
                            Text("Location access is off. ") + Text(AccessLink.title(canAsk: locationCanAsk)).underline()
                        }
                        // A button takes the body size; set like the other footers.
                        .font(.footnote)
                        .foregroundStyle(Theme.secondaryText)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .buttonStyle(.borderless)
                    } else if trackPlaces && !locationAlways {
                        Button {
                            if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                        } label: {
                            Text("Location tracking is off. ") + Text("Open Settings").underline()
                        }
                        .font(.footnote)
                        .foregroundStyle(Theme.secondaryText)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .buttonStyle(.borderless)
                    }
                }

                Section {
                    Toggle("Sync to iCloud", systemImage: "icloud", isOn: Binding {
                        syncEnabled
                    } set: { on in
                        sync.setEnabled(on)
                    })
                    .tint(Theme.accent)
                } header: {
                    Text("iCloud")
                } footer: {
                    syncNote
                }

                Section {
                    Toggle("Require \(lock.biometryName)", systemImage: lock.biometrySymbol, isOn: lockBinding)
                        .tint(Theme.accent)
                        .disabled(!lock.isAvailable && !lockEnabled)
                } header: {
                    Text("Privacy")
                } footer: {
                    if !lock.isAvailable {
                        Text("Set a device passcode to lock your journal.")
                    }
                }

                Section {
                    ExportRow(journalName: JournalName.display(journalName))
                } header: {
                    Text("Export")
                }

                Section {
                    LabeledContent {
                        Text(Bundle.main.shortVersion)
                    } label: {
                        Label("Version", systemImage: "info.circle")
                    }
                } footer: {
                    WeatherAttributionNote()
                }
            }
            .tint(Theme.primaryText)
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .navigationTitle("Settings")
            // Including on the way back from iOS's Settings.
            .task(id: scenePhase) {
                guard scenePhase == .active else { return }
                notificationsDenied = (reminderEnabled || onThisDayEnabled) ? !(await ReminderScheduler.isAllowed()) : false
                notificationsCanAsk = await ReminderScheduler.canAsk()
                refreshLocationAccess()
                await sync.refreshAccountStatus()
            }
            // Notifications are titled with the name and their words are fixed when scheduled, so a
            // rename schedules them again once typing pauses.
            .task(id: JournalName.display(journalName)) {
                guard (try? await Task.sleep(for: .seconds(1))) != nil else { return }
                await ReminderScheduler.refresh()
                await OnThisDayScheduler.refresh(in: context)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    /// Under Sync to iCloud: what it does while off; while on, when it last synced, or why it can't.
    private var syncNote: Text {
        guard syncEnabled else {
            return Text("Keep your entries and photos in your private iCloud, available on all your devices.")
        }
        if !sync.accountAvailable {
            return Text("Sign in to iCloud in Settings to sync your journal.")
        }
        if sync.isFailing() {
            return Text("Couldn't sync just now.")
        }
        guard let lastSynced = sync.lastSynced else {
            return Text("Your entries and photos sync to your private iCloud.")
        }
        return Text("Last synced \(lastSynced.formatted(.relative(presentation: .named))).")
    }

    /// Turning the lock on requires a successful authentication first,
    /// so nobody can lock themselves out with a biometry that doesn't work.
    private var lockBinding: Binding<Bool> {
        Binding {
            lockEnabled
        } set: { enable in
            guard enable else {
                lockEnabled = false
                return
            }
            Task {
                if await lock.unlock() { lockEnabled = true }
            }
        }
    }

    private var reminderBinding: Binding<Bool> {
        Binding {
            reminderEnabled
        } set: { enable in
            guard enable else {
                reminderEnabled = false
                if !onThisDayEnabled { notificationsDenied = false }
                ReminderScheduler.cancel()
                return
            }
            // On whatever iOS says; with notifications off, the note says so and it's scheduled
            // once they're on (`ReminderScheduler.refresh`).
            withAnimation { reminderEnabled = true }
            Task { await askForNotifications() }
        }
    }

    /// Like the daily reminder: on whatever iOS says, with the note when notifications are off.
    private var onThisDayBinding: Binding<Bool> {
        Binding {
            onThisDayEnabled
        } set: { enable in
            guard enable else {
                onThisDayEnabled = false
                if !reminderEnabled { notificationsDenied = false }
                Task { await OnThisDayScheduler.cancel() }
                return
            }
            withAnimation { onThisDayEnabled = true }
            Task { await askForNotifications() }
        }
    }

    /// Asks iOS (it shows its prompt only the first time) and schedules what's on if allowed.
    private func askForNotifications() async {
        let allowed = await ReminderScheduler.requestAuthorization()
        notificationsDenied = !allowed
        notificationsCanAsk = await ReminderScheduler.canAsk()
        if allowed {
            if reminderEnabled { await ReminderScheduler.schedule(minutesAfterMidnight: reminderMinutes) }
            await OnThisDayScheduler.refresh(in: context)
        }
    }

    /// Turning it on asks for location access first; it stays off if that's refused.
    private var autoTagBinding: Binding<Bool> {
        Binding {
            autoTagLocation
        } set: { enable in
            guard enable else {
                autoTagLocation = false
                return
            }
            Task {
                guard await LocationService.shared.requestAuthorization() else {
                    locationDenied = true
                    return
                }
                locationDenied = false
                autoTagLocation = true
            }
        }
    }

    /// Like the daily reminder: it turns on whatever iOS says, asking for location if it hasn't
    /// yet; without access, the note says so and tracking starts once it's allowed.
    private var trackPlacesBinding: Binding<Bool> {
        Binding {
            trackPlaces
        } set: { enable in
            guard enable else {
                PlaceTracker.shared.disable()
                return
            }
            withAnimation { trackPlaces = true }
            Task {
                await PlaceTracker.shared.enable()
                refreshLocationAccess()
            }
        }
    }

    private func refreshLocationAccess() {
        if locationAllowed { locationDenied = false }
    }

    private var reminderTime: Binding<Date> {
        Binding {
            Calendar.current.date(bySettingHour: reminderMinutes / 60, minute: reminderMinutes % 60, second: 0, of: .now) ?? .now
        } set: { date in
            let components = Calendar.current.dateComponents([.hour, .minute], from: date)
            reminderMinutes = (components.hour ?? 21) * 60 + (components.minute ?? 0)
            Task { await ReminderScheduler.schedule(minutesAfterMidnight: reminderMinutes) }
        }
    }

    /// A notification's row in Settings: its name, and On or Off, opening its page.
    private func notificationRow<Page: View>(
        _ title: String, systemImage: String, isOn: Bool, @ViewBuilder page: @escaping () -> Page
    ) -> some View {
        NavigationLink {
            page()
        } label: {
            LabeledContent {
                Text(isOn ? "On" : "Off")
            } label: {
                Label(title, systemImage: systemImage)
            }
        }
    }

    /// A notification's own page: its switch, then, while it's on, its time, and the note when
    /// notifications are off in iOS. Built in Settings' body, so it follows Settings' state.
    private func notificationPage(
        _ title: String, isOn: Binding<Bool>, time: Binding<Date>
    ) -> some View {
        Form {
            Section {
                // The page's title says which; the switch is whether it comes as a notification.
                Toggle("System Notification", systemImage: "bell.badge", isOn: isOn)
                    .tint(Theme.accent)
                if isOn.wrappedValue {
                    DatePicker(selection: time, displayedComponents: .hourAndMinute) {
                        Label("Time", systemImage: "clock")
                    }
                }
            } footer: {
                // Only for this one: the other may be the one that's on.
                if isOn.wrappedValue { notificationsNote }
            }
        }
        .tint(Theme.primaryText)
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }

    /// "Notifications are off." while one is on but iOS won't show it, asking in place while it can.
    @ViewBuilder
    private var notificationsNote: some View {
        if notificationsDenied {
            Button {
                if notificationsCanAsk {
                    Task { await askForNotifications() }
                } else {
                    openURL(.notificationSettings)
                }
            } label: {
                Text("Notifications are off. ") + Text(AccessLink.title(canAsk: notificationsCanAsk)).underline()
            }
            // A button takes the body size; set like the other footers.
            .font(.footnote)
            .foregroundStyle(Theme.secondaryText)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .buttonStyle(.borderless)
        }
    }

    private var onThisDayTime: Binding<Date> {
        Binding {
            Calendar.current.date(bySettingHour: onThisDayMinutes / 60, minute: onThisDayMinutes % 60, second: 0, of: .now) ?? .now
        } set: { date in
            let components = Calendar.current.dateComponents([.hour, .minute], from: date)
            onThisDayMinutes = (components.hour ?? 9) * 60 + (components.minute ?? 0)
            Task { await OnThisDayScheduler.refresh(in: context) }
        }
    }
}

/// Exports the journal as Markdown or PDF through the share sheet. Its own view with its own query,
/// so Settings doesn't re-render as entries change.
private struct ExportRow: View {
    let journalName: String

    @Query(filter: #Predicate<Entry> { $0.deletedAt == nil }) private var entries: [Entry]
    @State private var choosingFormat = false
    @State private var exporting: JournalExport.Format?
    @State private var failed = false

    var body: some View {
        Button {
            // Ignored mid-export, rather than disabled: a disabled row dims its spinner too.
            guard exporting == nil else { return }
            choosingFormat = true
        } label: {
            HStack {
                Label("Export Journal", systemImage: "square.and.arrow.up")
                Spacer()
                // From choosing a format until the share sheet is up: typesetting, then the sheet loading.
                // At full strength at once: a fade-in froze partway while typesetting held the main thread.
                if exporting != nil {
                    ProgressView()
                        .tint(Theme.primaryText)
                }
            }
        }
        // Always available: an empty journal exports as just its title.
        .confirmationDialog("Export Journal", isPresented: $choosingFormat, titleVisibility: .visible) {
            ForEach(JournalExport.Format.allCases) { format in
                Button(format.label) { export(format) }
            }
        } message: {
            Text(entries.count == 1 ? "1 entry" : "\(entries.count) entries")
        }
        .alert("Couldn't export your journal", isPresented: $failed) {
            Button("OK", role: .cancel) {}
        }
    }

    private func export(_ format: JournalExport.Format) {
        exporting = format
        Task {
            // Let the format dialog finish closing before typesetting (which blocks briefly) and sharing.
            try? await Task.sleep(for: .milliseconds(350))
            defer { exporting = nil }
            do {
                let url = try JournalExport.write(format, entries: entries, journalName: journalName)
                await ShareSheet.present(url)
            } catch {
                failed = true
            }
        }
    }
}

/// Settings' theme choices, with a checkmark on the current one. Not a navigation-link `Picker`, whose
/// page has a background of its own.
private struct ThemeList: View {
    @Binding var selection: Appearance

    var body: some View {
        Form {
            ForEach(Appearance.allCases) { option in
                // Stays on this page, so the new theme can be seen and another tried.
                Button {
                    selection = option
                } label: {
                    HStack {
                        Text(option.label)
                            .foregroundStyle(.primary)
                        Spacer()
                        if selection == option {
                            Image(systemName: "checkmark")
                                .fontWeight(.semibold)
                                .foregroundStyle(Theme.accent)
                        }
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .navigationTitle("Theme")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Apple's required credit for the weather on entries, set like the other footers. WeatherKit also
/// requires a link to its legal attribution page (the other data sources): the line itself is it.
private struct WeatherAttributionNote: View {
    @State private var legalPage: URL?

    /// Apple's legal attribution page, until (or if) the attribution can't be fetched.
    private static let fallbackLegalURL = URL(string: "https://weatherkit.apple.com/legal-attribution.html")!

    var body: some View {
        Link(destination: legalPage ?? Self.fallbackLegalURL) {
            // U+F8FF is the Apple logo in Apple's system fonts.
            Text("Weather data from \u{F8FF} Weather")
        }
        // A link takes the body size and the tint; set like the other footers.
        .font(.footnote)
        .foregroundStyle(Theme.secondaryText)
        .accessibilityLabel("Weather data from Apple Weather")
        .task {
            legalPage = try? await WeatherService.shared.attribution.legalPageURL
        }
    }
}

private extension Bundle {
    var shortVersion: String {
        infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
    }
}

#if DEBUG
#Preview {
    SettingsView()
        .modelContainer(.preview)
        .environment(AppLock())
        .environment(ICloudSync.shared)
}
#endif
