import SwiftUI
import UIKit

/// A button revealed by swiping a row: an icon, with its title for VoiceOver.
struct RowSwipeAction {
    let title: String
    let symbol: String
    let tint: Color
    /// Off for an action that leaves the row where it is, which then just closes.
    var removesRow = true
    let perform: () -> Void
}

extension View {
    /// Buttons revealed by swiping a row left, in the order given: rounded rectangles as tall as the
    /// row (the system's swipe actions are a fixed-size capsule), moving like the system's. Only
    /// tapping one acts on it — there's no full swipe. Only one row is open at a time (`openRow`); the
    /// list closes it when it scrolls, and a tap on the row should close it rather than act on the row.
    /// `trailingInset`: how far in from the row's trailing edge its content ends, so the buttons do too.
    func rowSwipeActions<ID: Hashable>(
        id: ID,
        openRow: Binding<ID?>,
        trailingInset: CGFloat = 0,
        actions: [RowSwipeAction]
    ) -> some View {
        modifier(RowSwipe(id: id, openRow: openRow, trailingInset: trailingInset, actions: actions))
    }
}

private struct RowSwipe<ID: Hashable>: ViewModifier {
    let id: ID
    @Binding var openRow: ID?
    let trailingInset: CGFloat
    let actions: [RowSwipeAction]

    @State private var offset: CGFloat = 0
    @State private var dragStart: CGFloat?
    @State private var width: CGFloat = 0
    @State private var isActing = false

    private static var buttonWidth: CGFloat { 64 }
    private static var buttonGap: CGFloat { Spacing.s }
    /// Between the row and the buttons.
    private static var gap: CGFloat { Spacing.m }
    private static var cornerRadius: CGFloat { 12 }

    private var buttonsWidth: CGFloat {
        CGFloat(actions.count) * Self.buttonWidth + CGFloat(actions.count - 1) * Self.buttonGap
    }
    private var openOffset: CGFloat { -(buttonsWidth + Self.gap) }

    func body(content: Content) -> some View {
        content
            .offset(x: offset)
            .background(alignment: .trailing) {
                buttons.padding(.trailing, trailingInset)
            }
            .onGeometryChange(for: CGFloat.self, of: \.size.width) { width = $0 }
            .gesture(SidewaysPan(onChange: drag(by:), onEnd: release(velocity:)))
            .onChange(of: openRow) { _, row in
                if row != id && !isActing && dragStart == nil { settle(at: 0) }
            }
            .accessibilityActions {
                ForEach(actions, id: \.title) { action in
                    Button(action.title) { act(action) }
                }
            }
    }

    /// Grows with the swipe, buttons and gaps alike.
    private var buttons: some View {
        let revealed = max(0, -offset - Self.gap) / buttonsWidth
        return HStack(spacing: Self.buttonGap * revealed) {
            ForEach(actions, id: \.title) { action in
                Image(systemName: action.symbol)
                    .font(Typography.icon)
                    .foregroundStyle(Theme.onAccent)
                    .opacity(min(1, revealed))
                    .frame(width: Self.buttonWidth * revealed)
                    .frame(maxHeight: .infinity)
                    .background(action.tint)
                    .clipShape(.rect(cornerRadius: Self.cornerRadius, style: .continuous))
                    .contentShape(.rect)
                    .onTapGesture { act(action) }
                    .accessibilityHidden(true)
            }
        }
    }

    private func drag(by translation: CGFloat) {
        if dragStart == nil {
            dragStart = offset
            openRow = id
        }
        let proposed = (dragStart ?? 0) + translation
        // A little give past either end.
        offset = proposed > 0 ? proposed / 5
            : proposed < openOffset ? openOffset + (proposed - openOffset) / 5
            : proposed
    }

    /// Settles on whichever place the row would coast to.
    private func release(velocity: CGFloat) {
        dragStart = nil
        let coast = offset + velocity * 0.2
        let opens = abs(coast - openOffset) < abs(coast)
        settle(at: opens ? openOffset : 0, velocity: velocity)
        if !opens && openRow == id { openRow = nil }
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

    /// Runs `action`, sliding the row off if that takes it out of the list.
    private func act(_ action: RowSwipeAction) {
        isActing = action.removesRow
        settle(at: action.removesRow ? -width : 0)
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
