import SwiftUI
import UIKit

/// Marks a page's card, for `SheetBackdrop` to find the one on screen.
struct PageCardMarker: UIViewRepresentable {
    fileprivate static let cards = NSHashTable<UIView>.weakObjects()

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.isUserInteractionEnabled = false
        Self.cards.add(view)
        return view
    }

    func updateUIView(_ view: UIView, context: Context) {}
}

/// Darkens the page's card behind a sheet further than the system's dimming, which can't be set,
/// leaving the title above it, and fades in and out with the sheet: a layer under the sheet, from the
/// card's top down over the tab bar. Over the whole window when no card is showing (an open entry).
struct SheetBackdrop: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> Controller { Controller() }
    func updateUIViewController(_ controller: Controller, context: Context) {}

    final class Controller: UIViewController {
        private let backdrop = UIView()

        override func viewDidLoad() {
            super.viewDidLoad()
            view.isUserInteractionEnabled = false
            backdrop.backgroundColor = UITheme.sheetBackdrop
            backdrop.isUserInteractionEnabled = false
            backdrop.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            backdrop.alpha = 0
        }

        override func viewIsAppearing(_ animated: Bool) {
            super.viewIsAppearing(animated)
            guard let window = view.window else { return }
            if backdrop.superview == nil {
                // What holds the sheet in the window (a SwiftUI sheet's `containerView` is nil).
                var container: UIView = view
                while let next = container.superview, next !== window { container = next }
                backdrop.frame = container.bounds
                if let card = PageCardMarker.cards.allObjects.first(where: { $0.window === window }) {
                    let top = card.convert(card.bounds, to: container).minY
                    backdrop.frame.origin.y = top
                    backdrop.frame.size.height -= top
                    backdrop.layer.cornerRadius = Radius.page
                    backdrop.layer.cornerCurve = .continuous
                    backdrop.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
                }
                container.insertSubview(backdrop, at: 0)
            }
            fade(to: 1)
        }

        override func viewWillDisappear(_ animated: Bool) {
            super.viewWillDisappear(animated)
            fade(to: 0)
        }

        override func viewDidDisappear(_ animated: Bool) {
            super.viewDidDisappear(animated)
            backdrop.removeFromSuperview()
        }

        /// With the sheet's transition, following a finger dragging it closed.
        private func fade(to alpha: CGFloat) {
            guard backdrop.alpha != alpha else { return }
            let backdrop = backdrop
            let animated = transitionCoordinator?.animate(alongsideTransition: { _ in
                backdrop.alpha = alpha
            }, completion: nil)
            if animated != true {
                UIView.animate(withDuration: 0.3) { backdrop.alpha = alpha }
            }
        }
    }
}
