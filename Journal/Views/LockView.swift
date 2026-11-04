import SwiftUI

struct LockView: View {
    @Environment(AppLock.self) private var lock
    @AppStorage(JournalName.storageKey) private var journalName = JournalName.default

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()

            VStack(spacing: Spacing.l) {
                Spacer()
                Image(systemName: "lock")
                    .font(Typography.largeIcon.weight(.light))
                    .foregroundStyle(Theme.secondaryText)
                Text(JournalName.display(journalName))
                    .font(Typography.pageTitle)
                    .foregroundStyle(Theme.primaryText)
                Spacer()
                Button("Unlock with \(lock.biometryName)") {
                    Task { await lock.unlock() }
                }
                .buttonStyle(.accent)
                .padding(.bottom, Spacing.l)
            }
        }
    }
}

#Preview {
    LockView()
        .environment(AppLock())
}
