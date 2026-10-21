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
                    .font(.system(size: 28, weight: .light))
                    .foregroundStyle(Theme.secondaryText)
                Text(JournalName.display(journalName))
                    .font(.system(.largeTitle, design: .serif).weight(.semibold))
                    .foregroundStyle(Theme.primaryText)
                Spacer()
                Button {
                    Task { await lock.unlock() }
                } label: {
                    Text("Unlock with \(lock.biometryName)")
                        .font(.body.weight(.medium))
                        .padding(.horizontal, Spacing.l)
                        .padding(.vertical, Spacing.m - 2)
                        .foregroundStyle(Theme.onAccent)
                        .background(Theme.accent, in: .capsule)
                }
                .padding(.bottom, Spacing.l)
            }
        }
    }
}

#Preview {
    LockView()
        .environment(AppLock())
}
