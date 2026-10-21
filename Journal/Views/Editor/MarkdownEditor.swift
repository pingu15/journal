import SwiftUI
import UIKit

/// A Markdown writing surface: literal Markdown, styled live, with photos inline.
/// `header` scrolls with the text, so the whole page moves as one.
struct MarkdownEditor<Header: View>: UIViewRepresentable {
    @Binding var text: String
    /// True while the keyboard is up; the screen shows `MarkdownToolbar` above it.
    @Binding var isEditing: Bool
    let controller: MarkdownEditorController
    var autofocus = false
    let image: (UUID) -> UIImage?
    let onImageTap: (UUID) -> Void
    /// A photo token pasted from elsewhere: returns the id to use in this entry (copying the photo
    /// in if it belongs to another entry) and its image, or nil if the photo no longer exists.
    let resolvePastedImage: (UUID) -> (id: UUID, image: UIImage)?
    /// Images pasted from another app.
    let onPasteImages: ([UIImage]) -> Void
    @ViewBuilder let header: () -> Header

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> MarkdownTextView {
        let textView = MarkdownTextView()
        textView.delegate = context.coordinator
        textView.textStorage.delegate = context.coordinator
        textView.textDragDelegate = context.coordinator
        textView.pasteHandler = context.coordinator
        controller.textView = textView
        controller.didEdit = { [weak coordinator = context.coordinator, weak textView] in
            guard let coordinator, let textView else { return }
            coordinator.textDidChange(in: textView)
        }

        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
        tap.delegate = context.coordinator
        textView.addGestureRecognizer(tap)

        load(text, into: textView, coordinator: context.coordinator)
        setHeader(on: textView)

        if autofocus {
            textView.focusWhenReady()
        }
        return textView
    }

    func updateUIView(_ textView: MarkdownTextView, context: Context) {
        context.coordinator.parent = self
        let toolbarClearance: CGFloat = isEditing ? MarkdownToolbar.height : 0
        if textView.contentInset.bottom != toolbarClearance {
            textView.contentInset.bottom = toolbarClearance
            textView.verticalScrollIndicatorInsets.bottom = toolbarClearance
        }
        setHeader(on: textView)
        if text != context.coordinator.lastMarkdown {
            load(text, into: textView, coordinator: context.coordinator)
        }
    }

    private func setHeader(on textView: MarkdownTextView) {
        textView.headerHost.rootView = AnyView(
            header()
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { [weak textView] height in
                    textView?.headerHeight = height
                }
                .frame(maxHeight: .infinity, alignment: .top)
        )
    }

    private func load(_ markdown: String, into textView: MarkdownTextView, coordinator: Coordinator) {
        let selection = textView.selectedRange
        textView.textStorage.setAttributedString(MarkdownDocument.attributed(from: markdown, image: image))
        MarkdownStyler.style(textView.textStorage)
        coordinator.pendingStyleRange = nil
        textView.typingAttributes = MarkdownStyler.typingAttributes
        if NSMaxRange(selection) <= textView.textStorage.length {
            textView.selectedRange = selection
        }
        coordinator.lastMarkdown = markdown
    }

    final class Coordinator: NSObject, UITextViewDelegate, UIGestureRecognizerDelegate,
                             NSTextStorageDelegate, UITextDragDelegate, MarkdownPasteHandler {
        var parent: MarkdownEditor
        var lastMarkdown = ""
        /// Characters changed since the last restyle (post-edit coordinates).
        var pendingStyleRange: NSRange?

        init(parent: MarkdownEditor) {
            self.parent = parent
        }

        func textViewDidChange(_ textView: UITextView) {
            textDidChange(in: textView)
        }

        func textViewDidBeginEditing(_ textView: UITextView) {
            parent.isEditing = true
        }

        func textViewDidEndEditing(_ textView: UITextView) {
            parent.isEditing = false
        }

        func textStorage(
            _ textStorage: NSTextStorage,
            didProcessEditing editedMask: NSTextStorage.EditActions,
            range editedRange: NSRange,
            changeInLength delta: Int
        ) {
            guard editedMask.contains(.editedCharacters) else { return }
            if let pending = pendingStyleRange {
                let start = min(pending.location, editedRange.location)
                let end = max(NSMaxRange(pending) + max(delta, 0), NSMaxRange(editedRange))
                pendingStyleRange = NSRange(location: start, length: end - start)
            } else {
                pendingStyleRange = editedRange
            }
        }

        func textDidChange(in textView: UITextView) {
            // Restyling during IME composition would break the marked text; the range is kept
            // and styled once the composition is committed.
            if textView.markedTextRange == nil, let range = pendingStyleRange {
                pendingStyleRange = nil
                MarkdownStyler.style(textView.textStorage, in: range)
                textView.typingAttributes = MarkdownStyler.typingAttributes
            }
            let markdown = MarkdownDocument.markdown(from: textView.textStorage)
            lastMarkdown = markdown
            if parent.text != markdown {
                parent.text = markdown
            }
        }

        /// Return continues a list (or ends it on an empty item).
        func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
            guard text == "\n", range.length == 0, let textView = textView as? MarkdownTextView else { return true }
            let ns = textView.textStorage.string as NSString
            let lineStart = ns.lineRange(for: NSRange(location: range.location, length: 0)).location
            let beforeCaret = ns.substring(with: NSRange(location: lineStart, length: range.location - lineStart))
            let local = NSRange(location: 0, length: (beforeCaret as NSString).length)
            guard let match = MarkdownStyler.listContinuation.firstMatch(in: beforeCaret, range: local) else { return true }

            let prefix = (beforeCaret as NSString).substring(with: match.range)
            let content = (beforeCaret as NSString).substring(from: match.range.length)
            if content.trimmingCharacters(in: .whitespaces).isEmpty {
                textView.replace(NSRange(location: lineStart, length: local.length), with: "")
            } else {
                var next = prefix
                let indent = (beforeCaret as NSString).substring(with: match.range(at: 1))
                if match.range(at: 3).location != NSNotFound,
                   let number = Int((beforeCaret as NSString).substring(with: match.range(at: 3))) {
                    next = "\(indent)\(number + 1)\((beforeCaret as NSString).substring(with: match.range(at: 4))) "
                } else if prefix.contains("[") {
                    next = "\(indent)- [ ] "
                }
                textView.replace(range, with: "\n" + next)
            }
            textDidChange(in: textView)
            return false
        }

        /// Set when a tap lands on a photo, so that tap opens the viewer without starting editing.
        private var tapIsOnPhoto = false

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            if let textView = gestureRecognizer.view as? MarkdownTextView {
                tapIsOnPhoto = imageID(at: touch.location(in: textView), in: textView) != nil
            }
            return true
        }

        func textViewShouldBeginEditing(_ textView: UITextView) -> Bool {
            !tapIsOnPhoto
        }

        private func imageID(at point: CGPoint, in textView: MarkdownTextView) -> UUID? {
            guard let position = textView.closestPosition(to: point) else { return nil }
            let index = textView.offset(from: textView.beginningOfDocument, to: position)
            let storage = textView.textStorage
            for candidate in [index, index - 1] where candidate >= 0 && candidate < storage.length {
                if let attachment = storage.attribute(.attachment, at: candidate, effectiveRange: nil) as? ImageAttachment,
                   let rect = textView.rect(for: NSRange(location: candidate, length: 1)), rect.contains(point) {
                    return attachment.imageID
                }
            }
            return nil
        }

        /// Tap a photo to view it; tap a checkbox to tick it.
        @objc func handleTap(_ recognizer: UITapGestureRecognizer) {
            // Cleared after this event, once the text view has also consulted it.
            defer { DispatchQueue.main.async { self.tapIsOnPhoto = false } }
            guard let textView = recognizer.view as? MarkdownTextView,
                  let position = textView.closestPosition(to: recognizer.location(in: textView))
            else { return }
            let point = recognizer.location(in: textView)
            let index = textView.offset(from: textView.beginningOfDocument, to: position)
            let storage = textView.textStorage

            if let id = imageID(at: point, in: textView) {
                parent.onImageTap(id)
                return
            }

            let ns = storage.string as NSString
            guard index <= ns.length else { return }
            let lineRange = ns.lineRange(for: NSRange(location: index, length: 0))
            let line = ns.substring(with: lineRange)
            guard let match = MarkdownStyler.checklistLine.firstMatch(in: line, range: NSRange(location: 0, length: (line as NSString).length))
            else { return }
            let box = NSRange(location: lineRange.location + match.range(at: 1).location, length: 1)
            guard abs(index - box.location) <= 2 else { return }
            let isDone = ns.substring(with: box) != " "
            textView.replace(box, with: isDone ? " " : "x")
            textDidChange(in: textView)
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
            true
        }

        // MARK: Drag — photos travel by copy/paste, never by drag (a drop would lose them)

        func textDraggableView(_ textDraggableView: UIView & UITextDraggable, itemsForDrag dragRequest: UITextDragRequest) -> [UIDragItem] {
            guard let textView = textDraggableView as? MarkdownTextView,
                  let range = textView.nsRange(for: dragRequest.dragRange)
            else { return dragRequest.suggestedItems }
            var hasPhoto = false
            textView.textStorage.enumerateAttribute(.attachment, in: range) { value, _, stop in
                if value != nil { hasPhoto = true; stop.pointee = true }
            }
            return hasPhoto ? [] : dragRequest.suggestedItems
        }

        // MARK: MarkdownPasteHandler

        func resolvePastedImage(_ id: UUID) -> (id: UUID, image: UIImage)? {
            parent.resolvePastedImage(id)
        }

        func pasteImages(_ images: [UIImage]) {
            parent.onPasteImages(images)
        }

        func didEditText(in textView: MarkdownTextView) {
            textDidChange(in: textView)
        }
    }
}

/// Lets the text view hand pasted content back to the editor.
protocol MarkdownPasteHandler: AnyObject {
    func resolvePastedImage(_ id: UUID) -> (id: UUID, image: UIImage)?
    func pasteImages(_ images: [UIImage])
    func didEditText(in textView: MarkdownTextView)
}

/// Text view with a SwiftUI header pinned to the top of its scrolling content.
final class MarkdownTextView: UITextView {
    let headerHost = UIHostingController(rootView: AnyView(EmptyView()))
    weak var pasteHandler: MarkdownPasteHandler?
    var headerHeight: CGFloat = 120 {
        didSet { if oldValue != headerHeight { setNeedsLayout() } }
    }

    private let margin = Spacing.page
    private let headerTop: CGFloat = 12
    private let headerGap: CGFloat = 20

    init() {
        super.init(frame: .zero, textContainer: nil)
        headerHost.safeAreaRegions = []
        headerHost.view.backgroundColor = .clear
        addSubview(headerHost.view)

        backgroundColor = .clear
        textContainer.lineFragmentPadding = 0
        alwaysBounceVertical = true
        keyboardDismissMode = .interactive
        tintColor = UITheme.primaryText
        // Inline (ghost-text) predictions fight the live restyling; the suggestion bar remains.
        inlinePredictionType = .no
        // "---" and "--" are Markdown, not punctuation.
        smartDashesType = .no
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let width = bounds.width - margin * 2
        headerHost.view.frame = CGRect(x: margin, y: headerTop, width: max(width, 0), height: max(headerHeight, 1))
        let inset = UIEdgeInsets(top: headerTop + headerHeight + headerGap, left: margin, bottom: 160, right: margin)
        if textContainerInset != inset {
            textContainerInset = inset
        }
    }

    /// Takes the keyboard once the push transition settles. Retries, because a search field
    /// that is still resigning (e.g. "New entry" right after closing search) can refuse the hand-off.
    func focusWhenReady(attempt: Int = 0) {
        DispatchQueue.main.asyncAfter(deadline: .now() + (attempt == 0 ? 0.35 : 0.25)) { [weak self] in
            guard let self, self.window != nil, !self.isFirstResponder, attempt < 6 else { return }
            if !self.becomeFirstResponder() || !self.isFirstResponder {
                self.focusWhenReady(attempt: attempt + 1)
            }
        }
    }

    /// Taps on the header belong to the header's controls, not the text.
    override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        if gestureRecognizer !== panGestureRecognizer,
           headerHost.view.frame.contains(gestureRecognizer.location(in: self)) {
            return false
        }
        return super.gestureRecognizerShouldBegin(gestureRecognizer)
    }

    // MARK: Clipboard — Markdown in, Markdown out, so photos survive copy/paste

    override func copy(_ sender: Any?) {
        let selection = selectedRange
        guard selection.length > 0 else { return }
        let markdown = MarkdownDocument.markdown(from: textStorage.attributedSubstring(from: selection))
        UIPasteboard.general.string = markdown
    }

    override func cut(_ sender: Any?) {
        let selection = selectedRange
        guard selection.length > 0 else { return }
        copy(sender)
        replace(selection, with: "")
        pasteHandler?.didEditText(in: self)
    }

    override func paste(_ sender: Any?) {
        let pasteboard = UIPasteboard.general
        if pasteboard.hasStrings, let string = pasteboard.string {
            pasteMarkdown(string)
        } else if pasteboard.hasImages, let images = pasteboard.images, !images.isEmpty {
            pasteHandler?.pasteImages(images)
        }
    }

    override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
        if action == #selector(paste(_:)) {
            return isEditable && (UIPasteboard.general.hasStrings || UIPasteboard.general.hasImages)
        }
        return super.canPerformAction(action, withSender: sender)
    }

    /// Plain text goes in through the undoable path; text containing photo tokens is rebuilt
    /// with the photos inline (copied into this entry if they came from another one).
    private func pasteMarkdown(_ string: String) {
        let selection = selectedRange
        let ns = string as NSString
        let matches = Markdown.imagePattern.matches(in: string, range: NSRange(location: 0, length: ns.length))
        guard !matches.isEmpty else {
            replace(selection, with: string)
            pasteHandler?.didEditText(in: self)
            return
        }

        // Photos are always paragraphs of their own, so break the line around any pasted mid-line.
        let existing = textStorage.string as NSString
        let pasted = NSMutableAttributedString()
        func endsLine() -> Bool {
            if pasted.length > 0 { return pasted.string.hasSuffix("\n") }
            return selection.location == 0 || existing.character(at: selection.location - 1) == 0x0A
        }
        var cursor = 0
        for match in matches {
            pasted.append(NSAttributedString(string: ns.substring(with: NSRange(location: cursor, length: match.range.location - cursor))))
            cursor = NSMaxRange(match.range)
            if let id = UUID(uuidString: ns.substring(with: match.range(at: 1))),
               let resolved = pasteHandler?.resolvePastedImage(id) {
                if !endsLine() {
                    // "text ![](…)" → "text" / photo: the space before the break goes.
                    while pasted.string.hasSuffix(" ") {
                        pasted.deleteCharacters(in: NSRange(location: pasted.length - 1, length: 1))
                    }
                    pasted.append(NSAttributedString(string: "\n"))
                }
                pasted.append(NSAttributedString(attachment: ImageAttachment(imageID: resolved.id, image: resolved.image)))
                while cursor < ns.length, ns.character(at: cursor) == 0x20 { cursor += 1 }
                let followedByBreak = cursor < ns.length
                    ? ns.character(at: cursor) == 0x0A
                    : NSMaxRange(selection) < existing.length && existing.character(at: NSMaxRange(selection)) == 0x0A
                if !followedByBreak { pasted.append(NSAttributedString(string: "\n")) }
            }
        }
        pasted.append(NSAttributedString(string: ns.substring(from: cursor)))
        pasted.addAttributes(MarkdownStyler.typingAttributes, range: NSRange(location: 0, length: pasted.length))

        textStorage.replaceCharacters(in: selection, with: pasted)
        // Direct storage edits aren't undoable; drop the stack rather than let it go stale.
        undoManager?.removeAllActions()
        selectedRange = NSRange(location: selection.location + pasted.length, length: 0)
        scrollRangeToVisible(selectedRange)
        pasteHandler?.didEditText(in: self)
    }

    func nsRange(for textRange: UITextRange) -> NSRange? {
        let location = offset(from: beginningOfDocument, to: textRange.start)
        let length = offset(from: textRange.start, to: textRange.end)
        guard location >= 0, length >= 0 else { return nil }
        return NSRange(location: location, length: length)
    }

    func textRange(for range: NSRange) -> UITextRange? {
        guard let start = position(from: beginningOfDocument, offset: range.location),
              let end = position(from: start, offset: range.length)
        else { return nil }
        return textRange(from: start, to: end)
    }

    func rect(for range: NSRange) -> CGRect? {
        textRange(for: range).map { firstRect(for: $0) }
    }

    /// Edits through UITextInput so they join the undo stack.
    func replace(_ range: NSRange, with string: String) {
        guard let textRange = textRange(for: range) else { return }
        // Tell the keyboard the text moved under it, so autocorrect state stays in sync.
        inputDelegate?.textWillChange(self)
        replace(textRange, withText: string)
        inputDelegate?.textDidChange(self)
    }
}

/// Formatting commands for the keyboard toolbar.
final class MarkdownEditorController {
    enum Block {
        case bullet, numbered, checklist, quote
    }

    weak var textView: MarkdownTextView?
    var didEdit: (() -> Void)?

    private static let anyBlockPrefix = try! NSRegularExpression(
        pattern: #"^(#{1,6}[ \t]+|>[ \t]?|[ \t]*[-*+][ \t]+\[[ xX]\][ \t]+|[ \t]*[-*+][ \t]+|[ \t]*\d+[.)][ \t]+)"#
    )
    private static let headingPrefix = try! NSRegularExpression(pattern: #"^(#{1,6})[ \t]+"#)

    func endEditing() {
        textView?.resignFirstResponder()
    }

    /// Finishes any in-progress composition so a command never splits a half-typed word.
    private func prepare() -> MarkdownTextView? {
        textView?.unmarkText()
        return textView
    }

    /// Wraps the selection in `marker` (or unwraps it if already wrapped).
    func toggleWrap(_ marker: String) {
        guard let textView = prepare() else { return }
        let ns = textView.textStorage.string as NSString
        let selection = textView.selectedRange
        let length = (marker as NSString).length
        let before = NSRange(location: selection.location - length, length: length)
        let after = NSRange(location: NSMaxRange(selection), length: length)

        if before.location >= 0, NSMaxRange(after) <= ns.length,
           ns.substring(with: before) == marker, ns.substring(with: after) == marker,
           !isPartOfLongerRun(marker, before: before, after: after, in: ns) {
            textView.replace(after, with: "")
            textView.replace(before, with: "")
            textView.selectedRange = NSRange(location: before.location, length: selection.length)
        } else {
            // Insert the markers separately so an embedded photo inside the selection survives.
            textView.replace(NSRange(location: NSMaxRange(selection), length: 0), with: marker)
            textView.replace(NSRange(location: selection.location, length: 0), with: marker)
            textView.selectedRange = NSRange(location: selection.location + length, length: selection.length)
        }
        didEdit?()
    }

    /// `*` directly inside `**…**` belongs to the bold markers, not to an italic pair.
    private func isPartOfLongerRun(_ marker: String, before: NSRange, after: NSRange, in ns: NSString) -> Bool {
        guard (marker as NSString).length == 1 else { return false }
        let character = (marker as NSString).character(at: 0)
        var runBefore = 0
        var index = before.location
        while index >= 0, ns.character(at: index) == character { runBefore += 1; index -= 1 }
        var runAfter = 0
        index = after.location
        while index < ns.length, ns.character(at: index) == character { runAfter += 1; index += 1 }
        return runBefore % 2 == 0 || runAfter % 2 == 0
    }

    /// Plain → H1 → H2 → H3 → plain.
    func cycleHeading() {
        guard let textView = prepare() else { return }
        let lines = selectedLines(in: textView)
        guard let first = lines.first else { return }
        let ns = textView.textStorage.string as NSString
        let current = Self.headingPrefix.firstMatch(in: ns.substring(with: first), range: NSRange(location: 0, length: first.length))
            .map { $0.range(at: 1).length } ?? 0
        let next = (current + 1) % 4
        applyPrefixes(to: lines, in: textView) { _, _ in next == 0 ? "" : String(repeating: "#", count: next) + " " }
    }

    func toggleBlock(_ block: Block) {
        guard let textView = prepare() else { return }
        let lines = selectedLines(in: textView)
        let ns = textView.textStorage.string as NSString
        let allHaveIt = lines.allSatisfy { has(block, line: ns.substring(with: $0)) }
        applyPrefixes(to: lines, in: textView) { index, _ in
            guard !allHaveIt else { return "" }
            switch block {
            case .bullet: return "- "
            case .numbered: return "\(index + 1). "
            case .checklist: return "- [ ] "
            case .quote: return "> "
            }
        }
    }

    func insertLink() {
        guard let textView = prepare() else { return }
        let selection = textView.selectedRange
        if selection.length > 0 {
            textView.replace(NSRange(location: NSMaxRange(selection), length: 0), with: "](https://)")
            textView.replace(NSRange(location: selection.location, length: 0), with: "[")
            textView.selectedRange = NSRange(location: NSMaxRange(selection) + 3, length: 8)
        } else {
            textView.replace(selection, with: "[](https://)")
            textView.selectedRange = NSRange(location: selection.location + 1, length: 0)
        }
        didEdit?()
    }

    func insertTag() {
        insertAtCaret("#", spaced: true)
    }

    func insertDivider() {
        guard let textView = prepare() else { return }
        let ns = textView.textStorage.string as NSString
        let location = textView.selectedRange.location
        let atLineStart = location == 0 || ns.character(at: location - 1) == 0x0A
        textView.replace(textView.selectedRange, with: (atLineStart ? "" : "\n") + "---\n")
        didEdit?()
    }

    /// Inserts photos as their own paragraphs at the caret.
    func insertImages(_ images: [(id: UUID, image: UIImage)]) {
        guard let textView = prepare(), !images.isEmpty else { return }
        let storage = textView.textStorage
        let selection = textView.selectedRange
        let ns = storage.string as NSString

        let insertion = NSMutableAttributedString()
        if selection.location > 0, ns.character(at: selection.location - 1) != 0x0A {
            insertion.append(NSAttributedString(string: "\n"))
        }
        for item in images {
            insertion.append(NSAttributedString(attachment: ImageAttachment(imageID: item.id, image: item.image)))
            insertion.append(NSAttributedString(string: "\n"))
        }
        insertion.addAttributes(MarkdownStyler.typingAttributes, range: NSRange(location: 0, length: insertion.length))

        storage.replaceCharacters(in: selection, with: insertion)
        // Direct storage edits aren't undoable; drop the stack rather than let it go stale.
        textView.undoManager?.removeAllActions()
        textView.selectedRange = NSRange(location: selection.location + insertion.length, length: 0)
        textView.scrollRangeToVisible(textView.selectedRange)
        didEdit?()
    }

    /// Removes an embedded photo (and the line break that followed it) from the text.
    func removeImage(_ id: UUID) {
        guard let textView else { return }
        let storage = textView.textStorage
        var target: NSRange?
        storage.enumerateAttribute(.attachment, in: NSRange(location: 0, length: storage.length)) { value, range, stop in
            if (value as? ImageAttachment)?.imageID == id {
                target = range
                stop.pointee = true
            }
        }
        guard var range = target else { return }
        let ns = storage.string as NSString
        if NSMaxRange(range) < ns.length, ns.character(at: NSMaxRange(range)) == 0x0A {
            range.length += 1
        }
        storage.replaceCharacters(in: range, with: "")
        textView.undoManager?.removeAllActions()
        didEdit?()
    }

    // MARK: Helpers

    private func insertAtCaret(_ string: String, spaced: Bool) {
        guard let textView else { return }
        let ns = textView.textStorage.string as NSString
        let location = textView.selectedRange.location
        let needsSpace = spaced && location > 0
            && !CharacterSet.whitespacesAndNewlines.contains(UnicodeScalar(ns.character(at: location - 1)) ?? " ")
        textView.replace(textView.selectedRange, with: (needsSpace ? " " : "") + string)
        didEdit?()
    }

    private func has(_ block: Block, line: String) -> Bool {
        switch block {
        case .bullet:
            line.range(of: #"^[ \t]*[-*+][ \t]+(?!\[[ xX]\])"#, options: .regularExpression) != nil
        case .numbered:
            line.range(of: #"^[ \t]*\d+[.)][ \t]+"#, options: .regularExpression) != nil
        case .checklist:
            line.range(of: #"^[ \t]*[-*+][ \t]+\[[ xX]\]"#, options: .regularExpression) != nil
        case .quote:
            line.hasPrefix(">")
        }
    }

    /// Line ranges (without terminators) touched by the selection.
    private func selectedLines(in textView: MarkdownTextView) -> [NSRange] {
        let ns = textView.textStorage.string as NSString
        var lines: [NSRange] = []
        let paragraphs = ns.paragraphRange(for: textView.selectedRange)
        ns.enumerateSubstrings(in: paragraphs, options: [.byParagraphs, .substringNotRequired]) { _, range, _, _ in
            lines.append(range)
        }
        if lines.isEmpty {
            lines = [NSRange(location: paragraphs.location, length: 0)]
        }
        return lines
    }

    /// Replaces each line's existing block prefix with a new one, editing only the prefixes.
    private func applyPrefixes(to lines: [NSRange], in textView: MarkdownTextView, prefix: (Int, String) -> String) {
        let ns = textView.textStorage.string as NSString
        let selection = textView.selectedRange
        var firstDelta = 0
        var totalDelta = 0
        var edits: [(NSRange, String)] = []

        for (index, line) in lines.enumerated() {
            let text = ns.substring(with: line)
            guard !text.contains("\u{FFFC}") else { continue }
            let existing = Self.anyBlockPrefix.firstMatch(in: text, range: NSRange(location: 0, length: line.length))?.range.length ?? 0
            let replacement = prefix(index, text)
            edits.append((NSRange(location: line.location, length: existing), replacement))
            let delta = (replacement as NSString).length - existing
            if index == 0 { firstDelta = delta }
            totalDelta += delta
        }
        for (range, replacement) in edits.reversed() {
            textView.replace(range, with: replacement)
        }

        let start = max(lines.first?.location ?? 0, selection.location + firstDelta)
        let length = selection.length == 0 ? 0 : max(0, selection.length + totalDelta - firstDelta)
        textView.selectedRange = NSRange(location: min(start, textView.textStorage.length), length: length)
        didEdit?()
    }
}

/// The bar above the keyboard: every Markdown action, then a checkmark to finish.
struct MarkdownToolbar: View {
    static let height: CGFloat = 50

    let controller: MarkdownEditorController
    let onImage: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            ScrollView(.horizontal) {
                HStack(spacing: 0) {
                    tool("Insert Photo", "photo", action: onImage)
                    tool("Heading", "textformat.size") { controller.cycleHeading() }
                    tool("Bold", "bold") { controller.toggleWrap("**") }
                    tool("Italic", "italic") { controller.toggleWrap("*") }
                    tool("Strikethrough", "strikethrough") { controller.toggleWrap("~~") }
                    tool("Bulleted List", "list.bullet") { controller.toggleBlock(.bullet) }
                    tool("Numbered List", "list.number") { controller.toggleBlock(.numbered) }
                    tool("Checklist", "checklist") { controller.toggleBlock(.checklist) }
                    tool("Quote", "text.quote") { controller.toggleBlock(.quote) }
                    tool("Code", "chevron.left.forwardslash.chevron.right") { controller.toggleWrap("`") }
                    tool("Link", "link") { controller.insertLink() }
                    tool("Tag", "number") { controller.insertTag() }
                    tool("Divider", "minus") { controller.insertDivider() }
                }
                .padding(.horizontal, Spacing.xs)
            }
            .scrollIndicators(.hidden)

            Rectangle()
                .fill(Theme.hairline)
                .frame(width: 1, height: 24)

            Button {
                controller.endEditing()
            } label: {
                Image(systemName: "checkmark")
                    .font(.system(size: 17, weight: .semibold))
                    .frame(width: 54, height: 50)
                    .contentShape(.rect)
            }
            .accessibilityLabel("Done")
        }
        .foregroundStyle(Theme.primaryText)
        .frame(height: Self.height)
        .background(Theme.background)
        .overlay(alignment: .top) {
            Rectangle().fill(Theme.hairline).frame(height: 1)
        }
        .buttonStyle(.plain)
    }

    private func tool(_ label: String, _ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 16))
                .frame(width: 42, height: 50)
                .contentShape(.rect)
        }
        .accessibilityLabel(label)
    }
}
