import SwiftData
import SwiftUI

struct SettingsView: View {
    @Environment(AppLock.self) private var lock
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    @AppStorage(AppLock.enabledKey) private var lockEnabled = false
    @AppStorage(JournalName.storageKey) private var journalName = JournalName.default
    @AppStorage(Appearance.storageKey) private var appearance = Appearance.system
    @AppStorage(ReminderScheduler.enabledKey) private var reminderEnabled = false
    @AppStorage(ReminderScheduler.minutesKey) private var reminderMinutes = ReminderScheduler.defaultMinutes
    @AppStorage(LocationService.autoTagKey) private var autoTagLocation = false
    @State private var notificationsDenied = false
    @State private var locationDenied = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(JournalName.default, text: $journalName)
                        .font(Typography.body)
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
                    MetaLabel("Journal name")
                } footer: {
                    Text("Shown at the top of your journal.")
                }

                Section {
                    Picker("Theme", selection: $appearance) {
                        ForEach(Appearance.allCases) { option in
                            Text(option.label).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)
                    .controlSize(.large)
                    .onAppear(perform: SegmentedFont.matchBody)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                } header: {
                    MetaLabel("Appearance")
                }

                Section {
                    Toggle("Daily reminder", isOn: reminderBinding)
                        .tint(Theme.secondaryText)
                    if reminderEnabled {
                        DatePicker("Time", selection: reminderTime, displayedComponents: .hourAndMinute)
                    }
                } header: {
                    MetaLabel("Reminders")
                } footer: {
                    if notificationsDenied {
                        Button {
                            if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                        } label: {
                            Text("Notifications are off for Journal. ") + Text("Open Settings").underline()
                        }
                        .font(Typography.note)
                        .foregroundStyle(Theme.secondaryText)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .buttonStyle(.plain)
                    }
                }

                Section {
                    Toggle("Add current location", isOn: autoTagBinding)
                        .tint(Theme.secondaryText)
                } header: {
                    MetaLabel("Location")
                } footer: {
                    if locationDenied {
                        Button {
                            if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                        } label: {
                            Text("Location access is off for Journal. ") + Text("Open Settings").underline()
                        }
                        .font(Typography.note)
                        .foregroundStyle(Theme.secondaryText)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .buttonStyle(.plain)
                    } else {
                        Text("New entries are tagged with where you are when you start writing.")
                    }
                }

                Section {
                    Toggle("Require \(lock.biometryName)", isOn: lockBinding)
                        .tint(Theme.secondaryText)
                        .disabled(!lock.isAvailable && !lockEnabled)
                } header: {
                    MetaLabel("Privacy")
                } footer: {
                    Text(lock.isAvailable
                         ? "Your journal is hidden whenever you leave the app."
                         : "Set a device passcode to lock your journal.")
                }

                Section {
                    ExportRow(journalName: JournalName.display(journalName))
                } header: {
                    MetaLabel("Export")
                } footer: {
                    Text("Entries are stored only on this device. Exports include text, dates, places and weather; the PDF includes photos too.")
                }

                Section {
                    LabeledContent("Version", value: Bundle.main.shortVersion)
                }
            }
            .tint(Theme.primaryText)
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .navigationTitle("Settings")
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
                ReminderScheduler.cancel()
                return
            }
            Task {
                guard await ReminderScheduler.requestAuthorization() else {
                    notificationsDenied = true
                    return
                }
                notificationsDenied = false
                withAnimation { reminderEnabled = true }
                await ReminderScheduler.schedule(minutesAfterMidnight: reminderMinutes)
            }
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

/// Segmented controls take their font from UIKit; this makes the appearance options the same
/// size as the rest of Settings (body text). It's the app's only segmented control.
private enum SegmentedFont {
    static func matchBody() {
        let appearance = UISegmentedControl.appearance()
        appearance.setTitleTextAttributes([.font: UIFont.preferredFont(forTextStyle: .body)], for: .normal)
        appearance.setTitleTextAttributes([.font: UIFont.preferredFont(forTextStyle: .body)], for: .selected)
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
