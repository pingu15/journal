import SwiftUI
import UIKit

extension View {
    /// A delete action revealed by swiping the row left: a red rounded rectangle as tall as the row
    /// (the system's swipe actions are a fixed-size capsule). Swiping most of the way across deletes
    /// outright, like a full swipe. Only one row is open at a time (`openRow`); the list closes it
    /// when it scrolls, and a tap on the row should close it rather than open the row.
    /// `trailingInset`: how far in from the row's trailing edge its content ends, so the button does too.
    func swipeToDelete<ID: Hashable>(
        id: ID,
        openRow: Binding<ID?>,
        trailingInset: CGFloat = 0,
        onDelete: @escaping () -> Void
    ) -> some View {
        modifier(SwipeToDelete(id: id, openRow: openRow, trailingInset: trailingInset, onDelete: onDelete))
    }
}

private struct SwipeToDelete<ID: Hashable>: ViewModifier {
    let id: ID
    @Binding var openRow: ID?
    let trailingInset: CGFloat
    let onDelete: () -> Void

    @State private var offset: CGFloat = 0
    @State private var dragStart: CGFloat?
    @State private var width: CGFloat = 0
    @State private var pastFullSwipe = false
    @State private var isDeleting = false

    private static var buttonWidth: CGFloat { 72 }
    private static var gap: CGFloat { Spacing.s }
    private static var cornerRadius: CGFloat { 12 }
    private var openOffset: CGFloat { -(Self.buttonWidth + Self.gap) }

    func body(content: Content) -> some View {
        content
            .offset(x: offset)
            .background(alignment: .trailing) { button }
            .onGeometryChange(for: CGFloat.self, of: \.size.width) { width = $0 }
            .gesture(SidewaysPan(onChange: drag(by:), onEnd: release(velocity:)))
            .onChange(of: openRow) { _, row in
                if row != id && !isDeleting && dragStart == nil { close() }
            }
            .sensoryFeedback(.impact(weight: .medium), trigger: pastFullSwipe) { _, past in past }
            .accessibilityAction(named: "Delete", delete)
    }

    private var button: some View {
        let revealed = max(0, -offset - Self.gap)
        return Image(systemName: "trash")
            .font(.title3.weight(.medium))
            .foregroundStyle(Theme.onAccent)
            .opacity(min(1, revealed / Self.buttonWidth))
            .frame(width: revealed)
            .frame(maxHeight: .infinity)
            .background(Theme.destructive, in: .rect(cornerRadius: Self.cornerRadius, style: .continuous))
            .contentShape(.rect)
            .onTapGesture(perform: delete)
            .padding(.trailing, trailingInset)
            .accessibilityHidden(true)
    }

    private func drag(by translation: CGFloat) {
        if dragStart == nil {
            dragStart = offset
            openRow = id
        }
        let proposed = (dragStart ?? 0) + translation
        // Only a little give to the right; to the left, as far as the row is wide.
        offset = proposed > 0 ? proposed / 5 : max(proposed, -width)
        pastFullSwipe = offset < -width * 0.6
    }

    private func release(velocity: CGFloat) {
        dragStart = nil
        if pastFullSwipe {
            delete()
            return
        }
        let opens = velocity < -300 || (velocity < 300 && offset < openOffset / 2)
        withAnimation(.snappy) { offset = opens ? openOffset : 0 }
        if !opens && openRow == id { openRow = nil }
    }

    private func close() {
        pastFullSwipe = false
        guard offset != 0 else { return }
        withAnimation(.snappy) { offset = 0 }
    }

    private func delete() {
        isDeleting = true
        withAnimation(.snappy) { offset = -width }
        if openRow == id { openRow = nil }
        onDelete()
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
