import SwiftData
import SwiftUI

struct SettingsView: View {
    @Environment(AppLock.self) private var lock
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase

    @AppStorage(AppLock.enabledKey) private var lockEnabled = false
    @AppStorage(JournalName.storageKey) private var journalName = JournalName.default
    @AppStorage(Appearance.storageKey) private var appearance = Appearance.system
    @AppStorage(ReminderScheduler.enabledKey) private var reminderEnabled = false
    @AppStorage(ReminderScheduler.minutesKey) private var reminderMinutes = ReminderScheduler.defaultMinutes
    @AppStorage(LocationService.autoTagKey) private var autoTagLocation = false
    @AppStorage(PlaceTracker.enabledKey) private var trackPlaces = false
    @State private var notificationsDenied = false
    /// Notifications haven't been asked for yet, so the note can ask rather than send the user away.
    @State private var notificationsCanAsk = false
    @State private var locationDenied = false

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

                Section {
                    Toggle("Daily Reminder", systemImage: "bell", isOn: reminderBinding)
                        .tint(Theme.accent)
                    if reminderEnabled {
                        DatePicker(selection: reminderTime, displayedComponents: .hourAndMinute) {
                            Label("Time", systemImage: "clock")
                        }
                    }
                } header: {
                    Text("Reminders")
                } footer: {
                    if notificationsDenied {
                        Button {
                            if notificationsCanAsk {
                                Task { await askForNotifications() }
                            } else if let url = URL(string: UIApplication.openSettingsURLString) {
                                openURL(url)
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

                Section {
                    Toggle("Add Current Location", systemImage: "location", isOn: autoTagBinding)
                        .tint(Theme.accent)
                    Toggle("Track Visited Places", systemImage: "figure.walk", isOn: trackPlacesBinding)
                        .tint(Theme.accent)
                } header: {
                    Text("Location")
                } footer: {
                    if locationDenied {
                        Button {
                            if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                        } label: {
                            Text("Location access is off. ") + Text("Open Settings").underline()
                        }
                        // A button takes the body size; set like the other footers.
                        .font(.footnote)
                        .foregroundStyle(Theme.secondaryText)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .buttonStyle(.borderless)
                    }
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
                }
            }
            .tint(Theme.primaryText)
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .navigationTitle("Settings")
            // Including on the way back from iOS's Settings.
            .task(id: scenePhase) {
                guard scenePhase == .active else { return }
                notificationsDenied = reminderEnabled ? !(await ReminderScheduler.isAllowed()) : false
                notificationsCanAsk = await ReminderScheduler.canAsk()
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
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
                notificationsDenied = false
                ReminderScheduler.cancel()
                return
            }
            // On whatever iOS says; with notifications off, the note says so and it's scheduled
            // once they're on (`ReminderScheduler.refresh`).
            withAnimation { reminderEnabled = true }
            Task { await askForNotifications() }
        }
    }

    /// Asks iOS (it shows its prompt only the first time) and schedules the reminder if allowed.
    private func askForNotifications() async {
        let allowed = await ReminderScheduler.requestAuthorization()
        notificationsDenied = !allowed
        notificationsCanAsk = await ReminderScheduler.canAsk()
        if allowed {
            await ReminderScheduler.schedule(minutesAfterMidnight: reminderMinutes)
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

    /// Like "Add current location": stays off if location access is refused.
    private var trackPlacesBinding: Binding<Bool> {
        Binding {
            trackPlaces
        } set: { enable in
            guard enable else {
                PlaceTracker.shared.disable()
                return
            }
            Task { locationDenied = !(await PlaceTracker.shared.enable()) }
        }
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
            choosingFormat = true
        } label: {
            HStack {
                Label("Export Journal", systemImage: "square.and.arrow.up")
                Spacer()
                if exporting != nil {
                    ProgressView()
                }
            }
        }
        .disabled(entries.isEmpty || exporting != nil)
        .opacity(entries.isEmpty ? 0.4 : 1)
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
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Form {
            ForEach(Appearance.allCases) { option in
                Button {
                    selection = option
                    dismiss()
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

private extension Bundle {
    var shortVersion: String {
        infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
    }
}

#Preview {
    SettingsView()
        .modelContainer(.preview)
        .environment(AppLock())
}
