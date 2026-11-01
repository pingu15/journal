import UIKit

/// Presents the system share sheet over whatever is on screen (the Settings sheet, the editor).
enum ShareSheet {
    static func present(_ item: Any) async {
        guard let root = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)?
            .rootViewController
        else { return }
        // Wait out any dismissal still in flight (a dialog or menu), so the presentation isn't dropped.
        for _ in 0..<20 {
            var top = root
            while let presented = top.presentedViewController, !presented.isBeingDismissed { top = presented }
            if top.presentedViewController == nil {
                let controller = UIActivityViewController(activityItems: [item], applicationActivities: nil)
                controller.popoverPresentationController?.sourceView = top.view
                top.present(controller, animated: true)
                return
            }
            try? await Task.sleep(for: .milliseconds(50))
        }
    }
}
