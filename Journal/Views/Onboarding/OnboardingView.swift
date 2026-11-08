import SwiftData
import SwiftUI

/// Whether the first-launch introduction has been seen.
enum Onboarding {
    static let completedKey = "onboardingCompleted"

    /// On first launch only, and never over a journal that already has entries (one from before the
    /// introduction existed, say): that counts as seen, and is remembered.
    static var isNeeded: Bool {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-showOnboarding") { return true }
        #endif
        guard !UserDefaults.standard.bool(forKey: completedKey) else { return false }
        let entries = (try? ICloudSync.shared.container.mainContext.fetchCount(FetchDescriptor<Entry>())) ?? 0
        guard entries == 0 else {
            UserDefaults.standard.set(true, forKey: completedKey)
            return false
        }
        return true
    }
}

/// The first-launch introduction, over the tabs: the handwritten logo, then the journal's name, then
/// its options (places, the daily reminder, iCloud, the lock), then the journal being prepared, ending
/// on "You're All Set". Moved through with its buttons only (no swiping): Back at the top beside a line
/// for each page, Continue at the bottom. Nothing is asked of iOS until a switch is turned on, and every
/// choice can be changed later in Settings.
struct OnboardingView: View {
    let finish: () -> Void

    @AppStorage(JournalName.storageKey) private var journalName = JournalName.default
    /// The name as typed. There's no default: the first page can't be left without one.
    @State private var nameDraft = ""
    @State private var page = Page.name
    /// Which way the pages slide: on to the next, or back.
    @State private var forward = true
    /// The handwritten logo, until it has been written and faded away.
    @State private var showsIntro = true
    /// The preparing page has finished, and says so: Start Writing can be pressed.
    @State private var ready = false
    @FocusState private var nameFocused: Bool

    enum Page: Int, CaseIterable {
        case name, preferences, preparing
    }

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()

            // Built as the logo fades, so the first page rises in as it goes rather than behind it.
            if !showsIntro {
                VStack(spacing: 0) {
                    topBar
                        .rise(delay: 0.1)

                    ZStack {
                        pageView
                            .id(page)
                            .transition(.asymmetric(
                                insertion: .move(edge: forward ? .trailing : .leading).combined(with: .opacity),
                                removal: .move(edge: forward ? .leading : .trailing).combined(with: .opacity)
                            ))
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                    bottomButton
                        .rise(delay: 0.3)
                }
            }
        }
        .overlay {
            if showsIntro {
                IntroLogo {
                    withAnimation(.easeInOut(duration: 0.7)) { showsIntro = false }
                    Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(800))
                        if page == .name { nameFocused = true }
                    }
                }
                .transition(.opacity)
            }
        }
    }

    @ViewBuilder
    private var pageView: some View {
        switch page {
        case .name: NamePage(draft: $nameDraft, focused: $nameFocused, submit: advance)
        case .preferences: PreferencesPage()
        case .preparing:
            PreparingPage {
                withAnimation(.smooth(duration: 0.6)) { ready = true }
            }
        }
    }

    /// A line for each page, filled up to this one. Gone while the journal is prepared.
    private var topBar: some View {
        ProgressLines(count: Page.allCases.count, current: page.rawValue)
            .frame(height: 44)
            .padding(.horizontal, Spacing.page + Spacing.l)
            .opacity(page == .preparing ? 0 : 1)
            .accessibilityHidden(page == .preparing)
            .animation(.easeInOut(duration: 0.3), value: page)
    }

    /// Continue, with Back under it on the options (its room kept while the journal is prepared, so
    /// Start Writing lands where Continue was); while the journal is prepared Continue waits out of sight, then rises as
    /// Start Writing.
    private var bottomButton: some View {
        let waiting = page == .preparing && !ready
        let blocked = page == .name && enteredName.isEmpty
        let canGoBack = page == .preferences
        return VStack(spacing: Spacing.s + 2) {
            Button(action: advance) {
                Text(page == .preparing ? "Start Writing" : "Continue")
                    .frame(maxWidth: .infinity)
                    .contentTransition(.opacity)
            }
            .buttonStyle(.solid)
            .opacity(waiting ? 0 : 1)
            .offset(y: waiting ? 24 : 0)
            .disabled(waiting || blocked)
            // Faded until a name has been given.
            .opacity(blocked ? 0.4 : 1)
            .accessibilityHidden(waiting)

            // Not on the name, so Continue sits right above the keyboard there.
            if page != .name {
                // Outlined, under the filled Continue.
                Button {
                    go(to: page.rawValue - 1)
                } label: {
                    Text("Back")
                        .font(Typography.action)
                        .foregroundStyle(Theme.primaryText)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Spacing.m - 2)
                        .overlay(Capsule().strokeBorder(Theme.secondaryText.opacity(0.45), lineWidth: 1))
                        .contentShape(.capsule)
                }
                .buttonStyle(.borderless)
                .opacity(canGoBack ? 1 : 0)
                .disabled(!canGoBack)
                .accessibilityHidden(!canGoBack)
                .transition(.opacity)
            }
        }
        // Clear of the keyboard on the name page, where it sits right above it.
        .padding(.bottom, page == .name ? Spacing.m : 0)
        .padding(.horizontal, Spacing.page)
        .padding(.top, Spacing.m)
        .animation(.smooth(duration: 0.5), value: waiting)
        .animation(.easeInOut(duration: 0.2), value: blocked)
        .animation(.easeInOut(duration: 0.25), value: canGoBack)
        .animation(.smooth(duration: 0.45), value: page == .name)
    }

    private var enteredName: String {
        nameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func advance() {
        switch page {
        case .name:
            // Return with nothing typed keeps the field, rather than going on.
            guard !enteredName.isEmpty else {
                nameFocused = true
                return
            }
            journalName = enteredName
            go(to: Page.preferences.rawValue)
        case .preferences:
            go(to: Page.preparing.rawValue)
        case .preparing:
            guard ready else { return }
            finish()
        }
    }

    private func go(to index: Int) {
        guard let next = Page(rawValue: index) else { return }
        nameFocused = false
        // The direction first, so the page leaving slides the right way too.
        forward = index > page.rawValue
        Task { @MainActor in
            withAnimation(.smooth(duration: 0.45)) { page = next }
            // Back at the name, it's ready to type once the page is in.
            if next == .name {
                try? await Task.sleep(for: .milliseconds(450))
                if page == .name { nameFocused = true }
            }
        }
    }
}

// MARK: - Pages

/// A blank screen, then the journal's name written out by hand, as on the app's icon; a moment after
/// it's written (`done`) it fades away to the first page.
private struct IntroLogo: View {
    let done: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var written = false

    var body: some View {
        Image("Signature")
            .resizable()
            .scaledToFit()
            .foregroundStyle(Theme.primaryText)
            .frame(width: 260)
            // Wiped in from the left, as if being written.
            .mask(alignment: .leading) {
                GeometryReader { proxy in
                    Rectangle().frame(width: written ? proxy.size.width : 0)
                }
            }
            .accessibilityLabel("Welcome to Today")
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.background.ignoresSafeArea())
            .task {
                if reduceMotion {
                    written = true
                    try? await Task.sleep(for: .seconds(1))
                } else {
                    try? await Task.sleep(for: .milliseconds(400))
                    withAnimation(.easeInOut(duration: 1.4)) { written = true }
                    try? await Task.sleep(for: .milliseconds(2000))
                }
                done()
            }
    }
}

/// The journal's name: a title over a field.
private struct NamePage: View {
    @Binding var draft: String
    var focused: FocusState<Bool>.Binding
    let submit: () -> Void
    @AppStorage(JournalName.storageKey) private var journalName = JournalName.default

    var body: some View {
        // Centered in the page (above the keyboard while it's up), scrolling only if it can't fit.
        GeometryReader { proxy in
            ScrollView {
                content
                    .frame(maxWidth: .infinity, minHeight: proxy.size.height)
            }
            .scrollBounceBehavior(.basedOnSize)
            .scrollDismissesKeyboard(.interactively)
        }
        .onAppear {
            if draft.isEmpty && journalName != JournalName.default { draft = journalName }
        }
        .onChange(of: draft) { _, name in
            if name.count > JournalName.maxLength {
                draft = String(name.prefix(JournalName.maxLength))
            }
        }
    }

    private var content: some View {
            VStack(spacing: Spacing.l + Spacing.s) {
                PageHeading(
                    title: "Name Your Journal",
                    message: "Shown at the top of your journal. You can change it any time in Settings."
                )
                .rise(delay: 0.05)

                NameField(draft: $draft, focused: focused, submit: submit)
                    .rise(delay: 0.15)
            }
            .padding(.horizontal, Spacing.page)
            .padding(.vertical, Spacing.l)
    }
}

/// The name as typed, in a field like iOS's own, with a count under it as it nears the limit.
private struct NameField: View {
    @Binding var draft: String
    var focused: FocusState<Bool>.Binding
    let submit: () -> Void

    var body: some View {
        VStack(spacing: Spacing.s + 2) {
            // Like iOS's own: body text in a rounded box, with a clear button while
            // there's something to clear. Leading-aligned, as a centered field ignored trailing
            // spaces and stopped following the caret once the name outgrew the box.
            HStack(spacing: Spacing.s) {
                // A prompt, in the system's placeholder grey: not a default name.
                TextField("Journal name", text: $draft)
                    .font(Typography.body)
                    .foregroundStyle(Theme.primaryText)
                    .tint(Theme.primaryText)
                    // A name: words capitalized, nothing "corrected" into another word.
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                    .submitLabel(.continue)
                    .onSubmit(submit)
                    .focused(focused)
                    .accessibilityLabel("Journal Name")
                if !draft.isEmpty {
                    Button {
                        draft = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(Typography.body)
                            .foregroundStyle(Theme.secondaryText.opacity(0.6))
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Clear")
                }
            }
            .padding(.horizontal, Spacing.m)
            .frame(minHeight: 52)
            // The page's own color, outlined so it still reads as a field.
            .background(Theme.background, in: .rect(cornerRadius: Radius.card))
            .overlay {
                RoundedRectangle(cornerRadius: Radius.card).strokeBorder(Theme.hairline, lineWidth: 1)
            }
            .contentShape(.rect)
            .onTapGesture { focused.wrappedValue = true }

            Text("\(draft.count)/\(JournalName.maxLength)")
                .font(Typography.caption)
                .monospacedDigit()
                .foregroundStyle(Theme.secondaryText)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .opacity(draft.count > JournalName.maxLength - 10 ? 1 : 0)
                .animation(.easeInOut(duration: 0.2), value: draft.count > JournalName.maxLength - 10)
                .accessibilityHidden(true)
                .padding(.horizontal, Spacing.xs)
        }
    }
}

/// The journal's options, each a card with its switch.
private struct PreferencesPage: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.l) {
                PageHeading(title: "Make It Yours", message: "Settings can be changed at any time.")
                    .rise(delay: 0.05)

                VStack(spacing: Spacing.s + Spacing.xs) {
                    // One after another, slowly, each finishing as the next is well under way.
                    PlacesOption().rise(delay: 0.25, duration: 0.9, distance: 28)
                    ReminderOption().rise(delay: 0.55, duration: 0.9, distance: 28)
                    SyncOption().rise(delay: 0.85, duration: 0.9, distance: 28)
                    LockOption().rise(delay: 1.15, duration: 0.9, distance: 28)
                }
            }
            .padding(.horizontal, Spacing.page)
            .padding(.top, Spacing.m)
            .padding(.bottom, Spacing.l)
        }
        .scrollBounceBehavior(.basedOnSize)
    }
}

/// Track Visited Places, turned on as in Settings: on whatever iOS says, asking for location the
/// first time, with a note while it's off.
private struct PlacesOption: View {
    @Environment(\.openURL) private var openURL
    @AppStorage(PlaceTracker.enabledKey) private var trackPlaces = false
    // Read live: iOS's answer comes a moment after its prompt closes.
    private var allowed: Bool { LocationService.shared.isAuthorized }
    private var canAsk: Bool { LocationService.shared.canAsk }
    private var always: Bool { LocationService.shared.allowsAlways }

    var body: some View {
        OptionCard(
            symbol: "figure.walk", title: "Track Visited Places",
            message: "Location data stays on this iPhone.",
            isOn: binding
        ) {
            note
        }
        .animation(.smooth, value: LocationService.shared.authorizationStatus)
    }

    @ViewBuilder
    private var note: some View {
        if trackPlaces && !allowed {
            AccessOffNote("Location access", canAsk: canAsk) {
                if canAsk {
                    Task { await PlaceTracker.shared.enable() }
                } else {
                    openURL(.appSettings)
                }
            }
            .buttonStyle(.borderless)
        } else if trackPlaces && !always {
            Button {
                openURL(.appSettings)
            } label: {
                Text("Location tracking is off. ") + Text("Open Settings").underline()
            }
            .font(Typography.note)
            .foregroundStyle(Theme.secondaryText)
            .multilineTextAlignment(.leading)
            .buttonStyle(.borderless)
        }
    }

    private var binding: Binding<Bool> {
        Binding {
            trackPlaces
        } set: { enable in
            guard enable else {
                withAnimation(.smooth) { PlaceTracker.shared.disable() }
                return
            }
            withAnimation(.smooth) { trackPlaces = true }
            Task { await PlaceTracker.shared.enable() }
        }
    }
}

/// The daily reminder, turned on as in Settings: on whatever iOS says, asking for notifications the
/// first time, with a note when they're off.
private struct ReminderOption: View {
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(ReminderScheduler.enabledKey) private var reminderEnabled = false
    @AppStorage(ReminderScheduler.minutesKey) private var reminderMinutes = ReminderScheduler.defaultMinutes
    @State private var denied = false
    @State private var canAsk = false

    var body: some View {
        OptionCard(
            symbol: "bell", title: "Daily Reminder",
            message: "Choose a time to build a routine.", isOn: binding
        ) {
            if reminderEnabled {
                DatePicker("Time", selection: reminderTime, displayedComponents: .hourAndMinute)
                    .font(Typography.body)
                    .foregroundStyle(Theme.primaryText)
            }
            if denied {
                AccessOffNote("Notifications", canAsk: canAsk) {
                    if canAsk {
                        Task { await ask() }
                    } else {
                        openURL(.notificationSettings)
                    }
                }
                .buttonStyle(.borderless)
            }
        }
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            denied = reminderEnabled ? !(await ReminderScheduler.isAllowed()) : false
            canAsk = await ReminderScheduler.canAsk()
        }
    }

    private var binding: Binding<Bool> {
        Binding {
            reminderEnabled
        } set: { enable in
            guard enable else {
                withAnimation(.smooth) {
                    reminderEnabled = false
                    denied = false
                }
                ReminderScheduler.cancel()
                return
            }
            withAnimation(.smooth) { reminderEnabled = true }
            Task { await ask() }
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

    private func ask() async {
        let allowed = await ReminderScheduler.requestAuthorization()
        withAnimation(.smooth) { denied = !allowed }
        canAsk = await ReminderScheduler.canAsk()
        if allowed && reminderEnabled {
            await ReminderScheduler.schedule(minutesAfterMidnight: reminderMinutes)
        }
    }
}

/// iCloud sync, switched as in Settings (`ICloudSync.setEnabled`), with a note when there's no
/// iCloud account to sync to.
private struct SyncOption: View {
    @Environment(ICloudSync.self) private var sync
    @AppStorage(ICloudSync.enabledKey) private var syncEnabled = false

    var body: some View {
        OptionCard(
            symbol: "icloud", title: "iCloud Sync",
            message: "Back up your journal securely. Access it on all your devices.",
            isOn: Binding { syncEnabled } set: { on in sync.setEnabled(on) }
        ) {
            if syncEnabled && !sync.accountAvailable {
                Text("Sign in to iCloud in Settings to sync your journal.")
                    .font(Typography.note)
                    .foregroundStyle(Theme.secondaryText)
            }
        }
        .task { await sync.refreshAccountStatus() }
    }
}

/// The lock, turned on as in Settings: only once Face ID (or the passcode) has worked, so nobody locks
/// themselves out.
private struct LockOption: View {
    @Environment(AppLock.self) private var lock
    @AppStorage(AppLock.enabledKey) private var lockEnabled = false

    var body: some View {
        OptionCard(
            symbol: lock.biometrySymbol, title: "Lock with \(lock.biometryName)",
            message: lock.isAvailable || lockEnabled
                ? "Only you can open your journal."
                : "Set a device passcode to lock your journal.",
            isOn: binding
        ) {
            EmptyView()
        }
        .disabled(!lock.isAvailable && !lockEnabled)
    }

    private var binding: Binding<Bool> {
        Binding {
            lockEnabled
        } set: { enable in
            guard enable else {
                withAnimation(.smooth) { lockEnabled = false }
                return
            }
            Task {
                if await lock.unlock() {
                    withAnimation(.smooth) { lockEnabled = true }
                }
            }
        }
    }
}

/// The journal being made ready: the logo on a sand circle over a list of what's set up (privacy,
/// iCloud and the reminder when turned on, Shortcuts and Siri, then a note on widgets), each step's
/// icon pulsing while it's worked on and turning primary text when done; with iCloud on and a journal
/// already there, a last step downloads it all, counting entries as they arrive, and isn't done until
/// they're all here. Then the logo gives way to a check and the heading to "You're All Set", the list
/// staying. `ready` once it has said so.
private struct PreparingPage: View {
    let ready: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(ICloudSync.self) private var sync
    @AppStorage(ReminderScheduler.enabledKey) private var reminderEnabled = false
    @AppStorage(ICloudSync.enabledKey) private var syncEnabled = false

    struct Step: Identifiable {
        let id: Int
        let symbol: String
        let title: String
    }

    @State private var steps: [Step] = []
    /// The download from iCloud, when there's a journal there: its step, how many entries iCloud has
    /// and how many are here so far.
    @State private var syncStepID: Int?
    @State private var remoteCount = 0
    @State private var syncedCount = 0
    /// Downloading stalled on an error: it carries on in the background, and the step says so.
    @State private var syncContinuesLater = false
    /// With iCloud on, the ring keeps a last slice for the download from the start (so it never goes
    /// back when that step appears), filled as entries arrive, or at once when there's nothing to fetch.
    @State private var reservesSync = false
    @State private var firstSteps = 0
    @State private var syncResolved = false

    /// How much of the ring is filled: each step done, and the download by entries arrived.
    private var progress: Double {
        if finished { return 1 }
        let slots = Double(firstSteps + (reservesSync ? 1 : 0))
        guard slots > 0 else { return 0 }
        var filled = Double(min(done, firstSteps))
        if reservesSync {
            if syncResolved || done > firstSteps {
                filled += 1
            } else if syncStepID != nil, remoteCount > 0 {
                filled += Double(min(syncedCount, remoteCount)) / Double(remoteCount)
            }
        }
        return min(1, filled / slots)
    }
    /// How many steps are showing, the last of them in progress unless it's also `done`.
    @State private var shown = 0
    @State private var done = 0
    @State private var finished = false

    private let emblemSide: CGFloat = 104

    var body: some View {
        VStack(spacing: Spacing.l + Spacing.s) {
            Spacer(minLength: Spacing.l)

            Emblem(side: emblemSide, progress: progress, finished: finished)
                .padding(.bottom, Spacing.s)

            // One heading in the other's place.
            ZStack {
                heading("Preparing Your Journal", shown: !finished)
                heading("You're All Set", shown: finished)
            }

            checklist
                .frame(minHeight: 200, alignment: .top)

            Spacer(minLength: Spacing.l)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, Spacing.page)
        .sensoryFeedback(.selection, trigger: done)
        .sensoryFeedback(.success, trigger: finished)
        .task { await run() }
    }

    private func heading(_ text: String, shown: Bool) -> some View {
        Text(text)
            .font(Typography.onboardingTitle)
            .foregroundStyle(Theme.primaryText)
            .multilineTextAlignment(.center)
            .opacity(shown ? 1 : 0)
            .offset(y: shown || reduceMotion ? 0 : (finished ? -10 : 10))
            .blur(radius: shown || reduceMotion ? 0 : 4)
            .accessibilityHidden(!shown)
            .accessibilityAddTraits(.isHeader)
    }

    private var checklist: some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            ForEach(steps.prefix(shown)) { step in
                let complete = step.id < done
                HStack(spacing: Spacing.m - 2) {
                    Image(systemName: step.symbol)
                        .font(Typography.body.weight(.medium))
                        .foregroundStyle(complete ? Theme.primaryText : Theme.secondaryText)
                        .symbolEffect(.pulse, options: .repeating, isActive: !complete && !reduceMotion)
                        .symbolEffect(.bounce, value: complete)
                        .frame(width: 26)
                    Text(title(of: step))
                        .font(Typography.body)
                        .foregroundStyle(complete ? Theme.primaryText : Theme.secondaryText)
                        .contentTransition(.numericText())
                        .animation(.snappy, value: syncedCount)
                }
                .animation(.smooth(duration: 0.35), value: complete)
                .transition(.opacity.combined(with: .offset(y: 10)))
            }
        }
        .frame(maxWidth: 320, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private func title(of step: Step) -> String {
        guard step.id == syncStepID else { return step.title }
        if syncContinuesLater { return "Syncing from iCloud continues in the background" }
        return "Syncing from iCloud (\(min(syncedCount, remoteCount))/\(remoteCount))"
    }

    private func makeSteps() -> [Step] {
        var items = [("lock.shield", "Your data is fully private")]
        if syncEnabled { items.append(("icloud", "iCloud sync is active")) }
        if reminderEnabled { items.append(("bell", "Daily reminder scheduled")) }
        items.append(("waveform", "Shortcuts and \u{201C}Hey Siri\u{201D} commands are enabled"))
        items.append(("square.grid.2x2", "Widgets available to be added"))
        return items.enumerated().map { Step(id: $0.offset, symbol: $0.element.0, title: $0.element.1) }
    }

    private func run() async {
        guard steps.isEmpty else { return }
        steps = makeSteps()
        firstSteps = steps.count
        reservesSync = syncEnabled
        // With iCloud on: start syncing now (the tabs behind are rebuilt on the syncing store), and
        // find out meanwhile whether there's a journal there to download.
        let startedAt = Date.now
        var remote: Task<Int?, Never>?
        if syncEnabled {
            sync.applySetting()
            remote = Task.detached { await ICloudSync.remoteEntryCount() }
        }
        let pace = reduceMotion ? 0.35 : 1.0
        try? await Task.sleep(for: .seconds(0.6 * pace))
        for index in steps.indices {
            withAnimation(.smooth(duration: 0.4)) { shown = index + 1 }
            try? await Task.sleep(for: .seconds(0.85 * pace))
            withAnimation(.spring(duration: 0.4, bounce: 0.4)) { done = index + 1 }
            try? await Task.sleep(for: .seconds(0.3 * pace))
        }
        if let count = await remote?.value, count > 0 {
            await download(count, since: startedAt)
        } else {
            syncResolved = true
            // Time to see the ring's last slice fill.
            if reservesSync { try? await Task.sleep(for: .seconds(0.5 * pace)) }
        }
        try? await Task.sleep(for: .seconds(0.35 * pace))
        withAnimation(.spring(duration: 0.7, bounce: 0.3)) { finished = true }
        try? await Task.sleep(for: .seconds(0.6 * pace))
        ready()
    }

    /// The last step: every entry iCloud has, downloaded. Done once they're all in the store and iCloud
    /// has reported a download finishing; if it fails and nothing more arrives for a while, the step
    /// says it carries on in the background (it does) rather than holding the journal shut.
    private func download(_ count: Int, since start: Date) async {
        let id = steps.count
        steps.append(Step(id: id, symbol: "arrow.down.circle", title: ""))
        #if DEBUG
        // `-fakeICloudEntries N`: a made-up journal of N entries arriving, to see the step without
        // an iCloud account.
        let fakes = UserDefaults.standard.object(forKey: "fakeICloudEntries") != nil
        #else
        let fakes = false
        #endif
        remoteCount = count
        syncedCount = fakes ? 0 : sync.localEntryCount()
        syncStepID = id
        withAnimation(.smooth(duration: 0.4)) { shown = steps.count }
        var lastProgress = Date.now
        while !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(fakes ? 120 : 400))
            let now = fakes ? min(count, syncedCount + Int.random(in: 0...3)) : sync.localEntryCount()
            if now != syncedCount {
                syncedCount = now
                lastProgress = .now
            }
            let imported = fakes || (sync.lastImportEnded.map { $0 > start } ?? false)
            if syncedCount >= count && imported { break }
            if sync.lastError != nil && Date.now.timeIntervalSince(lastProgress) > 20 {
                withAnimation { syncContinuesLater = true }
                break
            }
        }
        withAnimation(.spring(duration: 0.4, bounce: 0.4)) { done = steps.count }
        try? await Task.sleep(for: .seconds(0.3))
    }
}

// MARK: - Pieces

/// A page's title and the line under it, centered.
private struct PageHeading: View {
    let title: String
    let message: String

    var body: some View {
        // Title and line close together, the same on every page.
        VStack(spacing: Spacing.xs) {
            Text(title)
                .font(Typography.onboardingTitle)
                .foregroundStyle(Theme.primaryText)
                .accessibilityAddTraits(.isHeader)
            // The app's explanatory size (as under an empty state's title).
            Text(message)
                .font(Typography.note)
                .foregroundStyle(Theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
    }
}

/// A symbol on a square: in the page's color on primary text (white on ink, ink on paper) while its
/// switch is on, faint while it's off.
private struct IconTile: View {
    let symbol: String
    let isOn: Bool

    @ScaledMetric(relativeTo: .body) private var side: CGFloat = 36

    var body: some View {
        Image(systemName: symbol)
            .font(Typography.smallIcon)
            .foregroundStyle(isOn ? Theme.background : Theme.secondaryText)
            .symbolEffect(.bounce, value: isOn)
            .frame(width: side, height: side)
            .background(isOn ? Theme.primaryText : Theme.hairline.opacity(0.5), in: .rect(cornerRadius: side / 4))
            .animation(.smooth(duration: 0.35), value: isOn)
            .accessibilityHidden(true)
    }
}

/// A switch as a card: its icon, name, a line about it and the switch, then anything it adds while on
/// (the reminder's time, a note that access is off).
private struct OptionCard<Extra: View>: View {
    let symbol: String
    let title: String
    let message: String
    let isOn: Binding<Bool>
    @ViewBuilder let extra: Extra

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.m - 4) {
            HStack(spacing: Spacing.m - 4) {
                IconTile(symbol: symbol, isOn: isOn.wrappedValue)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(Typography.rowTitle)
                        .foregroundStyle(Theme.primaryText)
                    Text(message)
                        .font(Typography.note)
                        .foregroundStyle(Theme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityHidden(true)
                Toggle(title, isOn: isOn)
                    .labelsHidden()
                    .tint(Theme.accent)
                    .accessibilityHint(message)
            }
            extra
                .frame(maxWidth: .infinity, alignment: .leading)
                .transition(.opacity.combined(with: .offset(y: -6)))
        }
        .padding(Spacing.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card, in: .rect(cornerRadius: Radius.card))
    }
}

/// Where you are in the pages: a line for each, filled up to this one.
private struct ProgressLines: View {
    let count: Int
    let current: Int

    var body: some View {
        HStack(spacing: Spacing.s - 2) {
            ForEach(0..<count, id: \.self) { index in
                Capsule()
                    .fill(Theme.secondaryText.opacity(0.25))
                    .overlay(alignment: .leading) {
                        // Filling from the left as the page arrives.
                        Capsule()
                            .fill(Theme.primaryText)
                            .scaleEffect(x: index <= current ? 1 : 0.001, anchor: .leading)
                    }
                    .frame(height: 4)
            }
        }
        .animation(.smooth(duration: 0.5), value: current)
        .accessibilityElement()
        .accessibilityLabel("Page \(current + 1) of \(count)")
    }
}

/// How far the journal's preparation has got, as a thick ring filling from the top, clockwise, from
/// empty to full (never spinning, never going back). Once finished, the ring fills into a sand circle,
/// a check is drawn on it, and it swells and settles.
private struct Emblem: View {
    let side: CGFloat
    /// 0 to 1.
    let progress: Double
    let finished: Bool

    private let lineWidth: CGFloat = 10

    var body: some View {
        ZStack {
            Circle()
                .stroke(Theme.hairline, lineWidth: lineWidth)
                .frame(width: side, height: side)
                .opacity(finished ? 0 : 1)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(Theme.accent, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .frame(width: side, height: side)
                .animation(.easeInOut(duration: 0.6), value: progress)
                .opacity(finished ? 0 : 1)

            // Done: the ring fills in.
            Circle()
                .fill(Theme.accent)
                .frame(width: side + lineWidth, height: side + lineWidth)
                .scaleEffect(finished ? 1 : 0.6)
                .opacity(finished ? 1 : 0)
                .shadow(color: Theme.accent.opacity(finished ? 0.45 : 0), radius: 24, y: 6)

            Checkmark()
                .trim(from: 0, to: finished ? 1 : 0)
                .stroke(Theme.onAccent, style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
                .frame(width: side * 0.4, height: side * 0.3)
                .animation(.easeOut(duration: 0.45).delay(0.2), value: finished)
        }
        .scaleEffect(finished ? 1.08 : 1)
        .accessibilityHidden(true)
    }
}

/// A check, drawn from its short arm to the tip of its long one.
nonisolated private struct Checkmark: Shape {
    func path(in rect: CGRect) -> Path {
        Path { path in
            path.move(to: CGPoint(x: rect.minX, y: rect.midY + rect.height * 0.05))
            path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.36, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        }
    }
}

/// Fades in while rising a little, `delay` after it appears (at once with Reduce Motion, unmoved).
private struct Rise: ViewModifier {
    let delay: Double
    var duration = 0.6
    var distance: CGFloat = 16
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown || reduceMotion ? 0 : distance)
            .onAppear {
                withAnimation(.smooth(duration: duration).delay(reduceMotion ? 0 : delay)) { shown = true }
            }
    }
}

private extension View {
    func rise(delay: Double = 0, duration: Double = 0.6, distance: CGFloat = 16) -> some View {
        modifier(Rise(delay: delay, duration: duration, distance: distance))
    }
}

#Preview {
    OnboardingView {}
        .environment(AppLock())
        .environment(ICloudSync.shared)
        .modelContainer(for: [Entry.self, Attachment.self], inMemory: true)
}
