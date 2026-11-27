import LocalAuthentication
import Observation
import SwiftUI
import UIKit

/// Gates the app behind Face ID / passcode when the user has enabled it.
@Observable
final class AppLock {
    static let enabledKey = "lockEnabled"

    private(set) var isUnlocked = false
    private(set) var isAuthenticating = false

    /// False when the device has no passcode, in which case there's nothing to lock with.
    var isAvailable: Bool {
        LAContext().canEvaluatePolicy(.deviceOwnerAuthentication, error: nil)
    }

    /// The symbol for `biometryName`.
    var biometrySymbol: String {
        let context = LAContext()
        _ = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
        switch context.biometryType {
        case .faceID: return "faceid"
        case .touchID: return "touchid"
        case .opticID: return "opticid"
        default: return "lock"
        }
    }

    var biometryName: String {
        let context = LAContext()
        _ = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
        switch context.biometryType {
        case .faceID: return "Face ID"
        case .touchID: return "Touch ID"
        case .opticID: return "Optic ID"
        default: return "Passcode"
        }
    }

    func lock() {
        isUnlocked = false
    }

    /// Must be called while the app is active — LocalAuthentication refuses to prompt otherwise.
    @discardableResult
    func unlock() async -> Bool {
        guard !isAuthenticating else { return isUnlocked }
        isAuthenticating = true
        defer { isAuthenticating = false }

        let context = LAContext()
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: nil) else {
            // Passcode was removed after enabling the lock; don't strand the user's entries.
            isUnlocked = true
            return true
        }
        do {
            isUnlocked = try await SystemPrompts.shared.during {
                try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "Unlock your journal")
            }
        } catch {
            isUnlocked = false
        }
        return isUnlocked
    }
}

/// Tracks permission prompts the app itself is showing (location, notifications, Face ID).
/// They make the scene inactive; the privacy shield shouldn't flash up behind them.
@Observable
final class SystemPrompts {
    static let shared = SystemPrompts()
    private(set) var activeCount = 0

    var isPresenting: Bool { activeCount > 0 }

    func during<T>(_ work: () async throws -> T) async rethrows -> T {
        activeCount += 1
        // The prompt's result arrives before the app is active again (Face ID's checkmark stays up a
        // moment); hold on until it is, or the shield shows for that moment.
        defer {
            Task { @MainActor in
                let deadline = ContinuousClock.now + .seconds(3)
                while UIApplication.shared.applicationState != .active, ContinuousClock.now < deadline {
                    try? await Task.sleep(for: .milliseconds(50))
                }
                try? await Task.sleep(for: .milliseconds(150))
                activeCount -= 1
            }
        }
        return try await work()
    }
}

/// Covers the whole app — including sheets and full-screen covers — with a blur and the logo while
/// locked or in the app switcher, so iOS's own Face ID prompt is the only lock UI. Lives in its own
/// window above everything else in the scene.
final class PrivacyShield {
    private var window: UIWindow?

    func setVisible(_ visible: Bool, lock: AppLock) {
        if visible {
            let window = window ?? makeWindow(lock: lock)
            self.window = window
            window?.layer.removeAllAnimations()
            window?.alpha = 1
            window?.isHidden = false
        } else if let window, !window.isHidden {
            UIView.animate(withDuration: 0.25, animations: { window.alpha = 0 }) { finished in
                if finished { window.isHidden = true }
            }
        }
    }

    private func makeWindow(lock: AppLock) -> UIWindow? {
        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first
        else { return nil }
        let window = UIWindow(windowScene: scene)
        window.windowLevel = .alert + 1
        window.overrideUserInterfaceStyle = Appearance.current.userInterfaceStyle
        let host = UIHostingController(rootView: LockCover().environment(lock))
        // Clear, so the blur shows the app beneath.
        host.view.backgroundColor = .clear
        window.backgroundColor = .clear
        window.rootViewController = host
        return window
    }
}

/// The app blurred past reading, with a lock over the handwritten logo in the middle, behind Face ID
/// and in the app switcher. A tap asks again after Face ID was cancelled or failed.
private struct LockCover: View {
    @Environment(AppLock.self) private var lock

    var body: some View {
        ZStack {
            CoverBlur()
            VStack(spacing: Spacing.l) {
                Image(systemName: "lock.fill")
                    .font(Typography.icon)
                Image("Signature")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 200)
            }
            .foregroundStyle(Theme.primaryText)
            .accessibilityHidden(true)
        }
        .ignoresSafeArea()
        .contentShape(.rect)
        .onTapGesture {
            Task { await lock.unlock() }
        }
        .accessibilityElement()
        .accessibilityLabel("Locked")
        .accessibilityHint("Unlocks with \(lock.biometryName)")
        .accessibilityAddTraits(.isButton)
    }
}

/// UIKit's blur, which blurs the app's windows beneath the shield's.
private struct CoverBlur: UIViewRepresentable {
    func makeUIView(context: Context) -> UIVisualEffectView {
        UIVisualEffectView(effect: UIBlurEffect(style: .systemThickMaterial))
    }

    func updateUIView(_ view: UIVisualEffectView, context: Context) {}
}
