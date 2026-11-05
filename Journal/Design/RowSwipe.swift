import SwiftUI
import UIKit

/// A button revealed by swiping a row: an icon in a circle, with one short word under it.
struct RowSwipeAction {
    let title: String
    /// For VoiceOver, when `title` needs more to stand on its own.
    var accessibilityTitle: String?
    let symbol: String
    let tint: Color
    /// Off for an action that leaves the row where it is, which then just closes. On, `perform` waits
    /// for the row to go, and should take it out of the list with an animation.
    var removesRow = true
    let perform: () -> Void
}

extension View {
    /// Buttons revealed by swiping a row left, in the order given: captioned circles (the system's
    /// swipe actions are a fixed-size capsule), moving like the system's. Only
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

extension EnvironmentValues {
    /// Whether the row around this is being swiped, or is swiped open.
    @Entry var rowIsSwiped = false
}

/// A row softly highlighted while it's touched, and, if it can be swiped, on through a swipe, which
/// cancels the touch, until it closes again. A press also shrinks it a little, like a button's; a quick
/// tap only does that, the highlight is for a touch held.
struct SwipeRowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        PressableRow(label: configuration.label, isPressed: configuration.isPressed)
    }
}

private struct PressableRow<Label: View>: View {
    let label: Label
    let isPressed: Bool

    @Environment(\.rowIsSwiped) private var isSwiped
    /// The press as shown: held a moment after a quick tap, which a list delivers as a press and a
    /// release together, so it still shows.
    @State private var showsPress = false
    @State private var pressStart = Date.distantPast

    /// The least time a press is shown for.
    private static var minimumPress: TimeInterval { 0.12 }

    var body: some View {
        // The real press, not the one held for a quick tap.
        let isHighlighted = isPressed || isSwiped

        label
            .contentShape(.rect)
            .background {
                RoundedRectangle(cornerRadius: Radius.row, style: .continuous)
                    .fill(Theme.surface)
                    .opacity(isHighlighted ? 1 : 0)
                    .animation(.easeOut(duration: 0.15), value: isHighlighted)
            }
            .scaleEffect(showsPress && !isSwiped ? 0.98 : 1)
            .animation(.spring(duration: 0.25, bounce: 0.3), value: showsPress && !isSwiped)
            .onChange(of: isPressed) { _, isPressed in
                if isPressed {
                    pressStart = .now
                    showsPress = true
                } else {
                    let left = Self.minimumPress - Date.now.timeIntervalSince(pressStart)
                    guard left > 0 else { showsPress = false; return }
                    Task {
                        try? await Task.sleep(for: .seconds(left))
                        if !self.isPressed { showsPress = false }
                    }
                }
            }
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

    /// Between the row and the buttons.
    private static var gap: CGFloat { Spacing.m }
    /// A row leaving the list slides and fades away over this, before the list closes up behind it.
    private static var fadeDuration: Double { 0.2 }

    /// How far the row moves before the first button starts to come out.
    private var lead: CGFloat { trailingInset + Self.gap }

    private var openOffset: CGFloat {
        -(SwipeButtons.width(of: actions.count) + lead)
    }

    func body(content: Content) -> some View {
        content
            .environment(\.rowIsSwiped, offset != 0 || dragStart != nil)
            .offset(x: offset)
            .background(alignment: .trailing) {
                SwipeButtons(revealed: max(0, -offset - lead), actions: actions, perform: act)
                    .padding(.trailing, trailingInset)
            }
            .opacity(isActing ? 0 : 1)
            .animation(.easeOut(duration: Self.fadeDuration), value: isActing)
            .onGeometryChange(for: CGFloat.self, of: \.size.width) { width = $0 }
            .gesture(SidewaysPan(onChange: drag(by:), onEnd: release(velocity:)))
            .onChange(of: openRow) { _, row in
                if row != id && !isActing && dragStart == nil { settle(at: 0) }
            }
            .accessibilityActions {
                ForEach(actions, id: \.title) { action in
                    Button(action.accessibilityTitle ?? action.title) { act(action) }
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

    /// Runs `action`. One that takes the row out of the list waits while the row slides and fades.
    private func act(_ action: RowSwipeAction) {
        guard !isActing else { return }
        isActing = action.removesRow
        settle(at: action.removesRow ? -width : 0)
        if openRow == id { openRow = nil }
        guard action.removesRow else { return action.perform() }
        Task {
            try? await Task.sleep(for: .seconds(Self.fadeDuration))
            action.perform()
        }
    }
}

/// The buttons, each coming out from under the row once the one to its right is fully out, and
/// going back in the reverse order. Animatable so that this is worked out from the row's position
/// on every frame: from the final position alone, all of them would animate to their sizes at once.
private struct SwipeButtons: View, @MainActor Animatable {
    /// How much room the row has left beside it.
    var revealed: CGFloat
    let actions: [RowSwipeAction]
    let perform: (RowSwipeAction) -> Void

    var animatableData: CGFloat {
        get { revealed }
        set { revealed = newValue }
    }

    private static var buttonWidth: CGFloat { 44 }
    private static var buttonGap: CGFloat { Spacing.m }

    static func width(of count: Int) -> CGFloat {
        CGFloat(count) * buttonWidth + CGFloat(count - 1) * buttonGap
    }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(actions.enumerated()), id: \.element.title) { index, action in
                let fromRight = actions.count - 1 - index
                let full = CGFloat(fromRight) * (Self.buttonWidth + Self.buttonGap)
                button(action, width: clamp(revealed - full, to: Self.buttonWidth))
                if fromRight > 0 {
                    Color.clear.frame(width: clamp(revealed - full + Self.buttonGap, to: Self.buttonGap))
                }
            }
        }
    }

    private func clamp(_ value: CGFloat, to limit: CGFloat) -> CGFloat {
        min(max(value, 0), limit)
    }

    private func button(_ action: RowSwipeAction, width: CGFloat) -> some View {
        Button {
            perform(action)
        } label: {
            Image(systemName: action.symbol)
        }
        .buttonStyle(CircleStyle(title: action.title, tint: action.tint, width: width))
        .accessibilityHidden(true)
    }

    /// The icon in a circle, which lights up slightly while pressed, over the button's word. The whole
    /// height of the row can be tapped.
    private struct CircleStyle: ButtonStyle {
        let title: String
        let tint: Color
        /// How far out the button has come.
        let width: CGFloat

        func makeBody(configuration: Configuration) -> some View {
            let growth = width / SwipeButtons.buttonWidth
            // The icon and caption arrive over the second half of the way out.
            let arrival = min(max(growth - 0.5, 0), 0.5) * 2

            VStack(spacing: Spacing.xs) {
                configuration.label
                    .font(Typography.smallIcon)
                    .foregroundStyle(Theme.onAccent)
                    .opacity(arrival)
                    .frame(width: SwipeButtons.buttonWidth, height: SwipeButtons.buttonWidth)
                    .background(tint, in: .circle)
                    .overlay {
                        Circle()
                            .fill(Theme.onAccent.opacity(configuration.isPressed ? 0.2 : 0))
                            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
                    }
                Text(title)
                    .font(Typography.caption)
                    .foregroundStyle(Theme.secondaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .opacity(arrival)
                    // A word can be wider than its circle, into the gap beside it.
                    .frame(width: SwipeButtons.buttonWidth + SwipeButtons.buttonGap)
            }
            .frame(width: SwipeButtons.buttonWidth)
            .scaleEffect(growth)
            .frame(width: width)
            .frame(maxHeight: .infinity)
            .contentShape(.rect)
        }
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

        /// Not blocked by the hold for the context menu, for a finger that rests before it swipes.
        /// The list's scrolling stays exclusive.
        func gestureRecognizer(
            _ gesture: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
        ) -> Bool {
            !(other is UIPanGestureRecognizer)
        }
    }
}
