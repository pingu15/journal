import SwiftUI
import UIKit

/// The writing surface: formatted text (no visible Markdown syntax), stored as Markdown, with photos inline.
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
            // A new entry starts on its title.
            if text.isEmpty { controller.setTextStyle(.title) }
            textView.focusWhenReady()
        }
        return textView
    }

    func updateUIView(_ textView: MarkdownTextView, context: Context) {
        context.coordinator.parent = self
        // The keyboard bar floats a little above the keyboard; the last line stays well clear of it.
        let toolbarClearance: CGFloat = isEditing ? MarkdownToolbar.height + Spacing.s + Spacing.l : 0
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
        let document = MarkdownDocument.attributed(from: markdown) { id in
            ImageAttachment.cached(imageID: id) ?? ImageAttachment(imageID: id, image: image(id))
        }
        textView.textStorage.setAttributedString(document)
        MarkdownStyler.style(textView.textStorage)
        coordinator.pendingStyleRange = nil
        if NSMaxRange(selection) <= textView.textStorage.length {
            textView.selectedRange = selection
        }
        controller.updateTypingAttributes()
        coordinator.lastMarkdown = markdown
    }

    final class Coordinator: NSObject, UITextViewDelegate, UIGestureRecognizerDelegate,
                             NSTextStorageDelegate, UITextDragDelegate, MarkdownPasteHandler {
        var parent: MarkdownEditor
        var lastMarkdown = ""
        /// Characters changed since the last restyle (post-edit coordinates).
        var pendingStyleRange: NSRange?
        /// A word the keyboard is replacing (autocorrect, a suggestion), with the formatting it had
        /// and its paragraph's style, so the replacement keeps them instead of falling back to plain
        /// text. The paragraph's style is read from its first character, so a replaced first word
        /// would otherwise turn a whole title to body text.
        private var pendingReplacement: (range: NSRange, inline: InlineStyle, link: Any?, block: BlockStyle?)?

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

        func textViewDidChangeSelection(_ textView: UITextView) {
            guard !isProcessing else { return }
            parent.controller.updateTypingAttributes()
            parent.controller.refreshState()
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

        /// True while the editor makes its own edits, so they aren't processed twice.
        private var isProcessing = false

        func textDidChange(in textView: UITextView) {
            guard !isProcessing, let textView = textView as? MarkdownTextView else { return }
            if let replacement = pendingReplacement {
                pendingReplacement = nil
                let storage = textView.textStorage
                if NSMaxRange(replacement.range) <= storage.length {
                    storage.removeAttribute(.inlineStyle, range: replacement.range)
                    storage.removeAttribute(.linkURL, range: replacement.range)
                    if !replacement.inline.isEmpty {
                        storage.addAttribute(.inlineStyle, value: replacement.inline.rawValue, range: replacement.range)
                    }
                    if let link = replacement.link {
                        storage.addAttribute(.linkURL, value: link, range: replacement.range)
                    }
                    let paragraph = (storage.string as NSString).paragraphRange(for: replacement.range)
                    if let block = replacement.block {
                        storage.addAttribute(.blockStyle, value: block.rawValue, range: paragraph)
                    } else {
                        storage.removeAttribute(.blockStyle, range: paragraph)
                    }
                    pendingStyleRange = pendingStyleRange.map { NSUnionRange($0, paragraph) } ?? paragraph
                }
            }
            // Restyling during IME composition would break the marked text; the range is kept
            // and styled once the composition is committed.
            if textView.markedTextRange == nil, let range = pendingStyleRange {
                isProcessing = true
                let caretParagraph = (textView.textStorage.string as NSString)
                    .paragraphRange(for: NSRange(location: min(textView.selectedRange.location, textView.textStorage.length), length: 0))
                let edited = pendingStyleRange.map { NSUnionRange($0, range) } ?? range
                pendingStyleRange = nil
                MarkdownStyler.style(textView.textStorage, in: NSUnionRange(edited, caretParagraph))
                parent.controller.updateTypingAttributes()
                isProcessing = false
            }
            parent.controller.refreshState()
            let markdown = MarkdownDocument.markdown(from: textView.textStorage)
            lastMarkdown = markdown
            if parent.text != markdown {
                parent.text = markdown
            }
        }

        /// Return continues a list (or ends it on an empty item), leaves a title or heading for body
        /// text, and stays in a quote until an empty line.
        func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
            if range.length > 0, !text.isEmpty, text != "\n", !isProcessing, textView.markedTextRange == nil,
               NSMaxRange(range) <= textView.textStorage.length {
                let storage = textView.textStorage
                pendingReplacement = (
                    NSRange(location: range.location, length: (text as NSString).length),
                    storage.inlineStyle(at: range.location),
                    storage.attribute(.linkURL, at: range.location, effectiveRange: nil),
                    storage.blockStyle(at: (storage.string as NSString).paragraphRange(for: range).location)
                )
            }
            guard text == "\n", range.length == 0, !isProcessing,
                  let textView = textView as? MarkdownTextView, textView.markedTextRange == nil
            else { return true }
            let storage = textView.textStorage
            let ns = storage.string as NSString
            let paragraph = ns.paragraphRange(for: NSRange(location: range.location, length: 0))
            var contentEnd = NSMaxRange(paragraph)
            if paragraph.length > 0, ns.character(at: contentEnd - 1) == 0x0A { contentEnd -= 1 }
            let lineStart = paragraph.location
            let line = ns.substring(with: NSRange(location: lineStart, length: contentEnd - lineStart))
            let beforeCaret = ns.substring(with: NSRange(location: lineStart, length: range.location - lineStart))
            let block = parent.controller.contextBlock(at: range.location)

            isProcessing = true
            defer {
                isProcessing = false
                textDidChange(in: textView)
            }

            let local = NSRange(location: 0, length: (beforeCaret as NSString).length)
            if block == nil, let match = MarkdownDocument.listPrefix.firstMatch(in: beforeCaret, range: local) {
                let prefix = (beforeCaret as NSString).substring(with: match.range)
                let rest = (line as NSString).substring(from: match.range.length)
                if rest.trimmingCharacters(in: .whitespaces).isEmpty {
                    // Return on an empty item ends the list.
                    textView.replace(NSRange(location: lineStart, length: match.range.length), with: "")
                } else {
                    let indent = (beforeCaret as NSString).substring(with: match.range(at: 1))
                    var next = prefix
                    if match.range(at: 3).location != NSNotFound,
                       let number = Int((beforeCaret as NSString).substring(with: match.range(at: 3))) {
                        next = "\(indent)\(number + 1)\((beforeCaret as NSString).substring(with: match.range(at: 4))) "
                    } else if prefix.unicodeScalars.contains("\u{2611}") {
                        next = "\(indent)\(MarkdownDocument.unchecked) "
                    }
                    textView.replace(range, with: "\n" + next)
                }
                return false
            }

            if block == .quote, line.trimmingCharacters(in: .whitespaces).isEmpty {
                // Return on an empty quote line ends the quote.
                parent.controller.applyBlock(nil, toParagraphAt: range.location)
                parent.controller.updateTypingAttributes()
                return false
            }

            // Where the page was: the edit and the new selection make the text view scroll the caret
            // to the middle of the screen; it only needs to come into view.
            let offset = textView.contentOffset
            textView.replace(range, with: "\n")
            let caret = range.location + 1
            // Return at the end of a title or heading starts body text; splitting one keeps the style.
            let next: BlockStyle? = block?.isHeading == true && range.location == contentEnd ? nil : block
            parent.controller.applyBlock(next, toParagraphAt: caret)
            textView.selectedRange = NSRange(location: caret, length: 0)
            parent.controller.updateTypingAttributes()
            textView.keepCaretInView(from: offset)
            return false
        }

        /// Set when a tap lands on a photo (or, while not editing, a link), so that tap opens it
        /// without starting editing.
        private var tapOpensSomething = false

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            if let textView = gestureRecognizer.view as? MarkdownTextView {
                let point = touch.location(in: textView)
                tapOpensSomething = imageID(at: point, in: textView) != nil
                    || (!textView.isFirstResponder && link(at: point, in: textView) != nil)
            }
            return true
        }

        func textViewShouldBeginEditing(_ textView: UITextView) -> Bool {
            !tapOpensSomething
        }

        /// The link under `point`. While editing, a tap on a link just places the caret, so its text can be changed.
        private func link(at point: CGPoint, in textView: MarkdownTextView) -> URL? {
            guard let position = textView.closestPosition(to: point) else { return nil }
            let index = textView.offset(from: textView.beginningOfDocument, to: position)
            let storage = textView.textStorage
            for candidate in [index, index - 1] where candidate >= 0 && candidate < storage.length {
                if let string = storage.attribute(.linkURL, at: candidate, effectiveRange: nil) as? String,
                   let rect = textView.rect(for: NSRange(location: candidate, length: 1)),
                   rect.insetBy(dx: -4, dy: -6).contains(point) {
                    return URL(string: string)
                }
            }
            return nil
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

        /// Tap a photo to view it, a link to open it, a checkbox to tick it.
        @objc func handleTap(_ recognizer: UITapGestureRecognizer) {
            // Cleared after this event, once the text view has also consulted it.
            defer { DispatchQueue.main.async { self.tapOpensSomething = false } }
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
            if !textView.isFirstResponder, let url = link(at: point, in: textView) {
                UIApplication.shared.open(url)
                return
            }

            let ns = storage.string as NSString
            guard index <= ns.length else { return }
            let lineRange = ns.lineRange(for: NSRange(location: index, length: 0))
            let line = ns.substring(with: lineRange)
            guard let match = MarkdownDocument.markerLine.firstMatch(in: line, range: NSRange(location: 0, length: (line as NSString).length))
            else { return }
            let box = NSRange(location: lineRange.location + match.range(at: 2).location, length: match.range(at: 2).length)
            let marker = ns.substring(with: box)
            guard marker != MarkdownDocument.bullet, abs(index - box.location) <= 2 else { return }
            textView.replace(box, with: MarkdownDocument.isChecked(marker) ? MarkdownDocument.unchecked : MarkdownDocument.checked)
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

    /// Takes the keyboard once the push transition has finished, so it rises from the bottom rather
    /// than sliding in with the page. Retries, because a search field that is still resigning (e.g.
    /// "New entry" right after closing search) can refuse the hand-off.
    func focusWhenReady(attempt: Int = 0) {
        DispatchQueue.main.asyncAfter(deadline: .now() + (attempt == 0 ? 0.05 : 0.25)) { [weak self] in
            self?.focusAfterTransition(attempt: attempt)
        }
    }

    private func focusAfterTransition(attempt: Int) {
        guard window != nil, !isFirstResponder, attempt < 8 else { return }
        if let transition = navigationTransition {
            transition.animate(alongsideTransition: nil) { [weak self] _ in
                // On the next turn, once the stack has settled.
                DispatchQueue.main.async { self?.focusAfterTransition(attempt: attempt + 1) }
            }
            return
        }
        if !becomeFirstResponder() || !isFirstResponder {
            focusWhenReady(attempt: attempt + 1)
        }
    }

    /// The push or pop under way in the navigation stack showing this view, if any.
    private var navigationTransition: UIViewControllerTransitionCoordinator? {
        var responder: UIResponder? = self
        while let next = responder?.next {
            if let controller = next as? UIViewController, let coordinator = controller.navigationController?.transitionCoordinator {
                return coordinator
            }
            responder = next
        }
        return nil
    }

    /// Taps on the header belong to the header's controls, not the text.
    /// The empty line at the very end of the text takes the paragraph style of the line above, so
    /// after a photo or video (whose line is centered) the caret sat centered. It starts at the
    /// left margin, like any empty line, and is as tall as on a line with text.
    override func caretRect(for position: UITextPosition) -> CGRect {
        var rect = super.caretRect(for: position)
        let text = textStorage.string as NSString
        let offset = self.offset(from: beginningOfDocument, to: position)
        if offset == text.length, text.length >= 2,
           text.character(at: text.length - 1) == 0x0A,
           text.character(at: text.length - 2) == 0xFFFC {
            rect.origin.x = textContainerInset.left + textContainer.lineFragmentPadding
        }
        // On an empty line the caret also took in the line spacing below the text, so it stood
        // taller than on a line with text.
        let isEmptyLine = (offset == 0 || text.character(at: offset - 1) == 0x0A)
            && (offset == text.length || text.character(at: offset) == 0x0A)
        // Only when it did: right after a return the line isn't laid out yet and the caret is the
        // plain height, which trimming made too short.
        if isEmptyLine, let style = typingAttributes[.paragraphStyle] as? NSParagraphStyle,
           let font = typingAttributes[.font] as? UIFont,
           rect.height - style.lineSpacing >= font.lineHeight {
            rect.size.height -= style.lineSpacing
        }
        return rect
    }

    /// Puts the page back where it was (`offset`), then scrolls only as far as the caret needs to
    /// be in view, above the keyboard bar, rather than to the middle.
    func keepCaretInView(from offset: CGPoint) {
        layoutIfNeeded()
        let caret = caretRect(for: selectedTextRange?.end ?? endOfDocument)
        let inset = adjustedContentInset
        let visibleTop = offset.y + inset.top
        let visibleBottom = offset.y + bounds.height - inset.bottom
        var y = offset.y
        if caret.maxY > visibleBottom {
            y += caret.maxY - visibleBottom
        } else if caret.minY < visibleTop {
            y -= visibleTop - caret.minY
        }
        let maxY = max(-inset.top, contentSize.height + inset.bottom - bounds.height)
        y = min(max(y, -inset.top), maxY)
        setContentOffset(CGPoint(x: offset.x, y: y), animated: false)
        // The text view's own scroll to the caret comes on the next turn; hold the page there too.
        DispatchQueue.main.async { [weak self] in
            guard let self, abs(self.contentOffset.y - y) > 0.5 else { return }
            self.setContentOffset(CGPoint(x: offset.x, y: y), animated: false)
        }
    }

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
        let selected = textStorage.attributedSubstring(from: selection)
        // A selection starting mid-paragraph still carries its paragraph's style.
        let markdown = MarkdownDocument.markdown(from: selected)
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

    /// Pasted text is read as Markdown, so formatting carries over. Text alone goes in through the
    /// undoable path; photos (copied into this entry if they came from another one) are rebuilt
    /// inline, each on a line of its own.
    private func pasteMarkdown(_ string: String) {
        let selection = selectedRange
        let pasted = MarkdownDocument.attributed(from: string) { [weak self] id in
            self?.pasteHandler?.resolvePastedImage(id).map { ImageAttachment(imageID: $0.id, image: $0.image) }
        }
        let hasAttachments = pasted.string.contains("\u{FFFC}")

        if !hasAttachments {
            replace(selection, with: pasted.string)
            let inserted = NSRange(location: selection.location, length: pasted.length)
            if NSMaxRange(inserted) <= textStorage.length {
                for key in [NSAttributedString.Key.inlineStyle, .linkURL, .blockStyle] {
                    textStorage.removeAttribute(key, range: inserted)
                }
                pasted.enumerateAttributes(in: NSRange(location: 0, length: pasted.length)) { attributes, run, _ in
                    let target = NSRange(location: inserted.location + run.location, length: run.length)
                    for key in [NSAttributedString.Key.inlineStyle, .linkURL, .blockStyle] {
                        if let value = attributes[key] { textStorage.addAttribute(key, value: value, range: target) }
                    }
                }
            }
            pasteHandler?.didEditText(in: self)
            return
        }

        isolateAttachments(in: pasted, replacing: selection)
        pasted.addAttributes(MarkdownStyler.typingAttributes, range: NSRange(location: 0, length: pasted.length))
        textStorage.replaceCharacters(in: selection, with: pasted)
        // Direct storage edits aren't undoable; drop the stack rather than let it go stale.
        undoManager?.removeAllActions()
        selectedRange = NSRange(location: selection.location + pasted.length, length: 0)
        scrollRangeToVisible(selectedRange)
        pasteHandler?.didEditText(in: self)
    }

    /// Photos are always paragraphs of their own: break the line around any that land mid-line,
    /// dropping the spaces that the break replaces.
    private func isolateAttachments(in pasted: NSMutableAttributedString, replacing selection: NSRange) {
        let existing = textStorage.string as NSString
        var index = 0
        while index < pasted.length {
            guard pasted.attribute(.attachment, at: index, effectiveRange: nil) != nil else {
                index += 1
                continue
            }
            var text = pasted.string as NSString
            // Before: trailing spaces go, then a break unless the line already ends here.
            var start = index
            while start > 0, text.character(at: start - 1) == 0x20 { start -= 1 }
            if start < index {
                pasted.deleteCharacters(in: NSRange(location: start, length: index - start))
                index = start
            }
            text = pasted.string as NSString
            let lineEndsBefore = index > 0
                ? text.character(at: index - 1) == 0x0A
                : selection.location == 0 || existing.character(at: selection.location - 1) == 0x0A
            if !lineEndsBefore {
                pasted.insert(NSAttributedString(string: "\n"), at: index)
                index += 1
            }
            // After: leading spaces go, then a break unless one follows.
            text = pasted.string as NSString
            var end = index + 1
            while end < text.length, text.character(at: end) == 0x20 { end += 1 }
            if end > index + 1 {
                pasted.deleteCharacters(in: NSRange(location: index + 1, length: end - index - 1))
            }
            text = pasted.string as NSString
            let breakFollows = index + 1 < text.length
                ? text.character(at: index + 1) == 0x0A
                : NSMaxRange(selection) < existing.length && existing.character(at: NSMaxRange(selection)) == 0x0A
            if !breakFollows {
                pasted.insert(NSAttributedString(string: "\n"), at: index + 1)
            }
            index += 1
        }
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

/// The text styles offered by the toolbar's text-style menu.
enum TextStyle: String, CaseIterable, Identifiable {
    case title, heading, regular

    var id: String { rawValue }

    var label: String {
        switch self {
        case .title: "Title"
        case .heading: "Heading"
        case .regular: "Regular"
        }
    }

    var block: BlockStyle? {
        switch self {
        case .title: .title
        case .heading: .heading
        case .regular: nil
        }
    }
}

/// Formatting commands for the keyboard toolbar, and the formatting at the caret (so the toolbar
/// can show which styles are on).
@Observable
final class MarkdownEditorController {
    /// Inline styles on at the caret (or across the whole selection).
    private(set) var activeInline: InlineStyle = []
    private(set) var activeBlock: BlockStyle?
    private(set) var isLink = false

    var textStyle: TextStyle {
        switch activeBlock {
        case .title: .title
        case .heading, .subheading: .heading
        case .quote, nil: .regular
        }
    }

    @ObservationIgnored weak var textView: MarkdownTextView?
    @ObservationIgnored var didEdit: (() -> Void)?
    /// The paragraph style chosen for an empty last line, which has no characters to carry it.
    @ObservationIgnored private var emptyLineBlock: (location: Int, block: BlockStyle?)?

    func endEditing() {
        textView?.resignFirstResponder()
    }

    /// Finishes any in-progress composition so a command never splits a half-typed word.
    private func prepare() -> MarkdownTextView? {
        textView?.unmarkText()
        return textView
    }

    // MARK: Formatting at the caret

    /// The paragraph style where text typed at `location` would go.
    func contextBlock(at location: Int) -> BlockStyle? {
        context(at: location).block
    }

    private func context(at location: Int) -> (inline: InlineStyle, block: BlockStyle?) {
        guard let storage = textView?.textStorage else { return ([], nil) }
        let ns = storage.string as NSString
        if location > 0, location <= ns.length, ns.character(at: location - 1) != 0x0A {
            return (storage.inlineStyle(at: location - 1), storage.blockStyle(at: location - 1))
        }
        if location < ns.length {
            // Start of a paragraph: its first character (or, for an empty one, its line break).
            let isEmpty = ns.character(at: location) == 0x0A
            return (isEmpty ? [] : storage.inlineStyle(at: location), storage.blockStyle(at: location))
        }
        if let pending = emptyLineBlock, pending.location == location {
            return ([], pending.block)
        }
        return ([], nil)
    }

    /// Typing continues the formatting around the caret (never a link).
    func updateTypingAttributes(clearInline: Bool = false) {
        guard let textView, textView.selectedRange.length == 0 else { return }
        let (inline, block) = context(at: textView.selectedRange.location)
        textView.typingAttributes = MarkdownStyler.typingAttributes(block: block, inline: clearInline ? [] : inline)
    }

    func refreshState() {
        guard let textView else { return }
        let storage = textView.textStorage
        let ns = storage.string as NSString
        let selection = textView.selectedRange
        var inline: InlineStyle
        var link = false

        if selection.length == 0 {
            inline = InlineStyle(rawValue: textView.typingAttributes[.inlineStyle] as? Int ?? 0)
            let location = selection.location
            if location > 0, location <= ns.length, ns.character(at: location - 1) != 0x0A {
                link = storage.attribute(.linkURL, at: location - 1, effectiveRange: nil) != nil
            }
        } else {
            var common: InlineStyle?
            var allLinked = true
            storage.enumerateAttributes(in: selection) { attributes, run, _ in
                guard attributes[.attachment] == nil,
                      ns.substring(with: run).contains(where: { !$0.isNewline }) else { return }
                let style = InlineStyle(rawValue: attributes[.inlineStyle] as? Int ?? 0)
                common = common.map { $0.intersection(style) } ?? style
                if attributes[.linkURL] == nil { allLinked = false }
            }
            inline = common ?? []
            link = common != nil && allLinked
        }

        let block = context(at: selection.location).block
        if activeInline != inline { activeInline = inline }
        if activeBlock != block { activeBlock = block }
        if isLink != link { isLink = link }
    }

    // MARK: Commands

    /// Bold, italic, underline, strikethrough or code: on the selection, or for what's typed next.
    func toggle(_ style: InlineStyle) {
        guard let textView = prepare() else { return }
        let selection = textView.selectedRange
        if selection.length == 0 {
            var attributes = textView.typingAttributes
            let current = InlineStyle(rawValue: attributes[.inlineStyle] as? Int ?? 0)
            let block = (attributes[.blockStyle] as? Int).flatMap(BlockStyle.init(rawValue:))
            attributes = MarkdownStyler.typingAttributes(block: block, inline: current.symmetricDifference(style))
            textView.typingAttributes = attributes
            refreshState()
            return
        }
        let turnOn = !activeInline.contains(style)
        editAttributes(in: selection) { storage in
            storage.enumerateAttributes(in: selection) { attributes, run, _ in
                guard attributes[.attachment] == nil else { return }
                var current = InlineStyle(rawValue: attributes[.inlineStyle] as? Int ?? 0)
                if turnOn { current.insert(style) } else { current.remove(style) }
                if current.isEmpty {
                    storage.removeAttribute(.inlineStyle, range: run)
                } else {
                    storage.addAttribute(.inlineStyle, value: current.rawValue, range: run)
                }
            }
        }
        textView.selectedRange = selection
        refreshState()
    }

    func setTextStyle(_ style: TextStyle) {
        setBlock(style.block)
    }

    func toggleQuote() {
        setBlock(activeBlock == .quote ? nil : .quote)
    }

    /// Applies a paragraph style to every paragraph the selection touches.
    private func setBlock(_ block: BlockStyle?) {
        guard let textView = prepare() else { return }
        let storage = textView.textStorage
        let ns = storage.string as NSString
        let selection = textView.selectedRange
        let paragraphs = ns.paragraphRange(for: selection)
        if paragraphs.length > 0 {
            editAttributes(in: paragraphs) { storage in
                if let block {
                    storage.addAttribute(.blockStyle, value: block.rawValue, range: paragraphs)
                } else {
                    storage.removeAttribute(.blockStyle, range: paragraphs)
                }
            }
        }
        if NSMaxRange(selection) == ns.length, ns.length == 0 || ns.character(at: ns.length - 1) == 0x0A {
            // The caret sits on an empty last line, which has nothing to carry the style yet.
            emptyLineBlock = (ns.length, block)
        }
        textView.selectedRange = selection
        updateTypingAttributes()
        refreshState()
    }

    /// Sets the paragraph style of the paragraph containing `location`, without an undo step
    /// (it's part of an edit that has one).
    func applyBlock(_ block: BlockStyle?, toParagraphAt location: Int) {
        guard let storage = textView?.textStorage else { return }
        let ns = storage.string as NSString
        let paragraph = ns.paragraphRange(for: NSRange(location: min(location, ns.length), length: 0))
        if paragraph.length == 0 {
            emptyLineBlock = (location, block)
            return
        }
        if let block {
            storage.addAttribute(.blockStyle, value: block.rawValue, range: paragraph)
        } else {
            storage.removeAttribute(.blockStyle, range: paragraph)
        }
        MarkdownStyler.style(storage, in: paragraph)
    }

    /// Asks for an address, then links the selection to it (or inserts it as a link).
    func promptForLink() {
        guard let textView = prepare() else { return }
        let selection = textView.selectedRange
        var presenter = textView.window?.rootViewController
        while let presented = presenter?.presentedViewController { presenter = presented }
        guard let presenter else { return }

        let existing = selection.length > 0 && selection.location < textView.textStorage.length
            ? textView.textStorage.attribute(.linkURL, at: selection.location, effectiveRange: nil) as? String
            : nil
        let alert = UIAlertController(title: existing == nil ? "Add Link" : "Edit Link", message: nil, preferredStyle: .alert)
        alert.addTextField { field in
            field.placeholder = "https://"
            field.text = existing
            field.keyboardType = .URL
            field.autocapitalizationType = .none
            field.autocorrectionType = .no
        }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { [weak textView] _ in
            textView?.becomeFirstResponder()
            textView?.selectedRange = selection
        })
        if existing != nil {
            alert.addAction(UIAlertAction(title: "Remove Link", style: .destructive) { [weak self, weak textView] _ in
                textView?.becomeFirstResponder()
                textView?.selectedRange = selection
                self?.setLink(nil, on: selection)
            })
        }
        alert.addAction(UIAlertAction(title: "Done", style: .default) { [weak self, weak textView, weak alert] _ in
            textView?.becomeFirstResponder()
            textView?.selectedRange = selection
            let raw = alert?.textFields?.first?.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !raw.isEmpty else { return }
            let url = raw.contains("://") || raw.hasPrefix("mailto:") ? raw : "https://" + raw
            self?.setLink(url, on: selection, text: raw)
        })
        presenter.present(alert, animated: true)
    }

    private func setLink(_ url: String?, on selection: NSRange, text: String? = nil) {
        guard let textView else { return }
        var range = selection
        if range.length == 0 {
            guard let url, let text else { return }
            textView.replace(selection, with: text)
            range = NSRange(location: selection.location, length: (text as NSString).length)
            textView.textStorage.addAttribute(.linkURL, value: url, range: range)
            MarkdownStyler.style(textView.textStorage, in: range)
            textView.selectedRange = NSRange(location: NSMaxRange(range), length: 0)
            updateTypingAttributes()
            didEdit?()
        } else {
            editAttributes(in: range) { storage in
                if let url {
                    storage.addAttribute(.linkURL, value: url, range: range)
                } else {
                    storage.removeAttribute(.linkURL, range: range)
                }
            }
            textView.selectedRange = range
        }
        refreshState()
    }

    /// A divider on its own line at the caret.
    func insertDivider() {
        guard let textView = prepare() else { return }
        let storage = textView.textStorage
        let selection = textView.selectedRange
        let ns = storage.string as NSString
        let insertion = NSMutableAttributedString()
        if selection.location > 0, ns.character(at: selection.location - 1) != 0x0A {
            insertion.append(NSAttributedString(string: "\n"))
        }
        insertion.append(NSAttributedString(attachment: DividerAttachment()))
        insertion.append(NSAttributedString(string: "\n"))
        insertion.addAttributes(MarkdownStyler.typingAttributes, range: NSRange(location: 0, length: insertion.length))
        storage.replaceCharacters(in: selection, with: insertion)
        // Direct storage edits aren't undoable; drop the stack rather than let it go stale.
        textView.undoManager?.removeAllActions()
        textView.selectedRange = NSRange(location: selection.location + insertion.length, length: 0)
        textView.scrollRangeToVisible(textView.selectedRange)
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

    /// Changes formatting (never text) in `range` as one undoable step.
    private func editAttributes(in range: NSRange, _ change: (NSTextStorage) -> Void) {
        guard let textView, range.length > 0, NSMaxRange(range) <= textView.textStorage.length else { return }
        let storage = textView.textStorage
        let before = storage.attributedSubstring(from: range)
        change(storage)
        MarkdownStyler.style(storage, in: range)
        registerUndo(restoring: before, in: range)
        didEdit?()
    }

    private func registerUndo(restoring previous: NSAttributedString, in range: NSRange) {
        guard let textView, let undoManager = textView.undoManager else { return }
        let current = textView.textStorage.attributedSubstring(from: range)
        undoManager.registerUndo(withTarget: self) { controller in
            MainActor.assumeIsolated {
                guard let storage = controller.textView?.textStorage, NSMaxRange(range) <= storage.length,
                      storage.attributedSubstring(from: range).string == previous.string
                else { return }
                storage.replaceCharacters(in: range, with: previous)
                controller.registerUndo(restoring: current, in: range)
                MarkdownStyler.style(storage, in: range)
                controller.didEdit?()
                controller.updateTypingAttributes()
                controller.refreshState()
            }
        }
    }
}

/// The bar above the keyboard: a rounded glass bar floating just clear of it, holding the formatting
/// tools (lit while on at the caret); it scrolls sideways when they don't fit. Finishing is the
/// editor's sand checkmark in the navigation bar.
struct MarkdownToolbar: View {
    static let height: CGFloat = 52

    let controller: MarkdownEditorController
    @State private var choosingTextStyle = false
    let onImage: () -> Void

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 4) {
                tool("Insert Photo", "photo", action: onImage)
                textStyleMenu
                tool("Bold", "bold", isOn: controller.activeInline.contains(.bold)) { controller.toggle(.bold) }
                tool("Italic", "italic", isOn: controller.activeInline.contains(.italic)) { controller.toggle(.italic) }
                tool("Underline", "underline", isOn: controller.activeInline.contains(.underline)) { controller.toggle(.underline) }
                tool("Strikethrough", "strikethrough", isOn: controller.activeInline.contains(.strikethrough)) {
                    controller.toggle(.strikethrough)
                }
                tool("Quote", "text.quote", isOn: controller.activeBlock == .quote) { controller.toggleQuote() }
                tool("Link", "link", isOn: controller.isLink) { controller.promptForLink() }
                tool("Divider", "minus") { controller.insertDivider() }
            }
            .padding(.horizontal, Spacing.s)
        }
        .scrollIndicators(.hidden)
        .foregroundStyle(Theme.primaryText)
        .frame(height: Self.height)
        .clipShape(.capsule)
        .glassBackground(in: .capsule)
        .buttonStyle(.borderless)
        .padding(.horizontal, Spacing.s)
        .padding(.bottom, Spacing.s)
    }

    /// Title / Heading / Regular, each shown in its own font, with the current one checked. A popover
    /// rather than a menu, since menu items can't take custom fonts. The button itself never lights up.
    private var textStyleMenu: some View {
        Button {
            choosingTextStyle = true
        } label: {
            ToolIcon(symbol: "textformat.size", isOn: false)
        }
        .accessibilityLabel("Text Style")
        .accessibilityValue(controller.textStyle.label)
        .popover(isPresented: $choosingTextStyle, arrowEdge: .bottom) {
            VStack(spacing: 0) {
                ForEach(TextStyle.allCases) { style in
                    Button {
                        controller.setTextStyle(style)
                        choosingTextStyle = false
                    } label: {
                        HStack(spacing: Spacing.m) {
                            Text(style.label)
                                .font(Font(MarkdownStyler.font(for: style.block)))
                                .foregroundStyle(Theme.primaryText)
                            Spacer(minLength: 0)
                            Image(systemName: "checkmark")
                                .font(Typography.action)
                                .foregroundStyle(Theme.accent)
                                .opacity(controller.textStyle == style ? 1 : 0)
                        }
                        // One height for every row, whatever its font, so they sit evenly apart (sized
                        // to their text, Title's row ran taller than the others), and in from the
                        // popover's rounded corners.
                        .padding(.horizontal, Spacing.m + 4)
                        .frame(height: 50)
                        .contentShape(.rect)
                    }
                    .buttonStyle(.borderless)
                    .accessibilityAddTraits(controller.textStyle == style ? .isSelected : [])
                }
            }
            // A little more above: Title's taller letters otherwise sit nearer the top edge than
            // Regular's do the bottom.
            .padding(.top, Spacing.s + 3)
            .padding(.bottom, Spacing.s)
            .frame(width: 184)
            .presentationCompactAdaptation(.popover)
        }
    }

    private func tool(_ label: String, _ symbol: String, isOn: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            ToolIcon(symbol: symbol, isOn: isOn)
        }
        .accessibilityLabel(label)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

private struct ToolIcon: View {
    let symbol: String
    let isOn: Bool

    var body: some View {
        Image(systemName: symbol)
            .font(Typography.icon.weight(isOn ? .semibold : .regular))
            .foregroundStyle(Theme.primaryText)
            .frame(width: 46, height: 40)
            .background {
                if isOn {
                    Color.clear.glassBackground(in: .capsule)
                }
            }
            .frame(width: 50, height: MarkdownToolbar.height)
            .contentShape(.rect)
            .animation(.easeOut(duration: 0.15), value: isOn)
    }
}
