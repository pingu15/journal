import SwiftUI
import UIKit

/// A button revealed by swiping a row.
struct RowSwipeAction {
    let title: String
    let symbol: String
    let tint: Color
    /// Wider for a label that needs two lines.
    var width: CGFloat = 76
    let perform: () -> Void
}

extension View {
    /// Buttons revealed by swiping a row: rounded rectangles as tall as the row (the system's swipe
    /// actions are a fixed-size capsule), moving like the system's. Only tapping one acts on it —
    /// there's no full swipe. Only one row is open at a time (`openRow`); the list closes it when it
    /// scrolls, and a tap on the row should close it rather than act on the row.
    /// `trailingInset`: how far in from the row's trailing edge its content ends, so the button does too.
    func rowSwipeActions<ID: Hashable>(
        id: ID,
        openRow: Binding<ID?>,
        trailingInset: CGFloat = 0,
        leading: RowSwipeAction? = nil,
        trailing: RowSwipeAction
    ) -> some View {
        modifier(RowSwipe(id: id, openRow: openRow, trailingInset: trailingInset, leading: leading, trailing: trailing))
    }
}

private struct RowSwipe<ID: Hashable>: ViewModifier {
    let id: ID
    @Binding var openRow: ID?
    let trailingInset: CGFloat
    let leading: RowSwipeAction?
    let trailing: RowSwipeAction

    /// Negative shows the trailing button, positive the leading one.
    @State private var offset: CGFloat = 0
    @State private var dragStart: CGFloat?
    @State private var width: CGFloat = 0
    @State private var isActing = false

    private static var gap: CGFloat { Spacing.m }
    private static var cornerRadius: CGFloat { 12 }
    private var trailingOpen: CGFloat { -(trailing.width + Self.gap) }
    private var leadingOpen: CGFloat { leading.map { $0.width + Self.gap } ?? 0 }

    func body(content: Content) -> some View {
        content
            .offset(x: offset)
            .background(alignment: .trailing) {
                button(trailing, revealed: max(0, -offset - Self.gap))
                    .padding(.trailing, trailingInset)
            }
            .background(alignment: .leading) {
                if let leading {
                    button(leading, revealed: max(0, offset - Self.gap), edge: .leading)
                }
            }
            .onGeometryChange(for: CGFloat.self, of: \.size.width) { width = $0 }
            .gesture(SidewaysPan(onChange: drag(by:), onEnd: release(velocity:)))
            .onChange(of: openRow) { _, row in
                if row != id && !isActing && dragStart == nil { settle(at: 0) }
            }
            .accessibilityAction(named: trailing.title) { act(trailing, edge: .trailing) }
            .accessibilityActions {
                if let leading {
                    Button(leading.title) { act(leading, edge: .leading) }
                }
            }
    }

    private func button(_ action: RowSwipeAction, revealed: CGFloat, edge: HorizontalEdge = .trailing) -> some View {
        VStack(spacing: Spacing.xs) {
            Image(systemName: action.symbol)
                .font(Typography.icon)
            Text(action.title)
                .font(Typography.note)
                .multilineTextAlignment(.center)
        }
        .foregroundStyle(Theme.onAccent)
        // Its full size even while only partly revealed, and clipped below.
        .frame(width: action.width - Spacing.s)
        .opacity(min(1, revealed / action.width))
        .frame(width: revealed)
        .frame(maxHeight: .infinity)
        .background(action.tint)
        .clipShape(.rect(cornerRadius: Self.cornerRadius, style: .continuous))
        .contentShape(.rect)
        .onTapGesture { act(action, edge: edge) }
        .accessibilityHidden(true)
    }

    private func drag(by translation: CGFloat) {
        if dragStart == nil {
            dragStart = offset
            openRow = id
        }
        let proposed = (dragStart ?? 0) + translation
        // A little give past either end.
        offset = proposed > leadingOpen ? leadingOpen + (proposed - leadingOpen) / 5
            : proposed < trailingOpen ? trailingOpen + (proposed - trailingOpen) / 5
            : proposed
    }

    /// Settles on whichever place the row would coast to.
    private func release(velocity: CGFloat) {
        dragStart = nil
        let coast = offset + velocity * 0.2
        let target = [trailingOpen, 0, leadingOpen].min { abs($0 - coast) < abs($1 - coast) } ?? 0
        settle(at: target, velocity: velocity)
        if target == 0 && openRow == id { openRow = nil }
    }

    /// Springs to `target`, carrying on at the finger's speed. Measured from the system's swipe
    /// actions: critically damped, with a response of 0.45 s. On the next turn: a change made in
    /// the gesture's callback isn't animated.
    private func settle(at target: CGFloat, velocity: CGFloat = 0) {
        let distance = target - offset
        guard distance != 0 else { return }
        let spring = Animation.interpolatingSpring(
            mass: 1, stiffness: 196, damping: 28, initialVelocity: min(max(velocity / distance, -20), 20)
        )
        DispatchQueue.main.async {
            withAnimation(spring) { offset = target }
        }
    }

    /// Runs `action` as the row slides off that way.
    private func act(_ action: RowSwipeAction, edge: HorizontalEdge) {
        isActing = true
        settle(at: edge == .trailing ? -width : width)
        if openRow == id { openRow = nil }
        action.perform()
    }
}

/// A pan that only starts when it's mostly sideways, so vertical drags still scroll the list.
private struct SidewaysPan: UIGestureRecognizerRepresentable {
    let onChange: (CGFloat) -> Void
    let onEnd: (CGFloat) -> Void

    func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator { Coordinator() }

    func makeUIGestureRecognizer(context: Context) -> UIPanGestureRecognizer {
        let pan = UIPanGestureRecognizer()
        pan.delegate = context.coordinator
        return pan
    }

    func handleUIGestureRecognizerAction(_ pan: UIPanGestureRecognizer, context: Context) {
        switch pan.state {
        case .began, .changed:
            onChange(pan.translation(in: pan.view).x)
        case .ended, .cancelled, .failed:
            onEnd(pan.velocity(in: pan.view).x)
        default:
            break
        }
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        func gestureRecognizerShouldBegin(_ gesture: UIGestureRecognizer) -> Bool {
            guard let pan = gesture as? UIPanGestureRecognizer else { return true }
            let velocity = pan.velocity(in: pan.view)
            return abs(velocity.x) > abs(velocity.y) * 1.5
        }
    }
}
