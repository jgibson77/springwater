import SwiftUI

// One block of the page, editable in place.
//
// Each block is the platform's own text view, for the same reasons the source
// editor is: nothing may rewrite a character after it is typed, and the text
// view must own its insertion point. A platform text view is also the only
// place Return, Tab, and Delete can be caught before they change the text,
// which is what lets them mean "next block", "another kind", and "remove this
// block" on the page.
//
// The text view edits one block's text and nothing else. Every change is
// handed straight back, and the view's text is replaced only when the
// document says something different from what it shows.

/// How one block is set: the face, where it sits, and whether it is dimmed.
struct BlockLook: Equatable {
    enum Alignment: Equatable {
        case leading, center, trailing
    }

    /// An installed font family, or nil for the system's serif face.
    var family: String?
    var size: CGFloat
    var bold = false
    var italic = false
    var alignment: Alignment = .leading
    /// Letters are capitalized as they are typed. What is stored is what shows.
    var uppercase = false
    /// Held in the document but not printed, such as a note.
    var dimmed = false
}

/// A request to put the insertion point in a block.
struct BlockFocus: Equatable {
    /// The block's position on the page.
    var index: Int
    /// Changes with every request, so the same block can be asked for twice.
    var token: Int
    /// Where in the text, counted in UTF-16 units. Nil means the end.
    var location: Int?
}

/// What a block tells the page.
struct BlockActions {
    /// The text changed.
    var change: @MainActor (String) -> Void
    /// Return: the text before and after the insertion point. False when
    /// nothing may follow this block.
    var split: @MainActor (_ before: String, _ after: String) -> Bool
    /// Tab or Shift-Tab, with the insertion point's location. False when the
    /// block can be nothing else.
    var changeKind: @MainActor (_ forward: Bool, _ location: Int) -> Bool
    /// Delete in an empty block. False when the block must stay.
    var deleteEmpty: @MainActor () -> Bool
    /// Up at the very start, or Down at the very end. False at the first or
    /// last block.
    var move: @MainActor (_ up: Bool) -> Bool
    /// The block now has the insertion point.
    var focused: @MainActor () -> Void
    /// A request to take the insertion point was carried out.
    var focusApplied: @MainActor () -> Void
}

/// What a block's text may be.
enum BlockText {
    /// False when a line of the text would begin with a caret. In Springwater
    /// such a line is a tag, never content, and nothing can make it content,
    /// so the page does not let one be typed into a block.
    static func canHold(_ text: String) -> Bool {
        !text.split(whereSeparator: \.isNewline).contains { line in
            line.first(where: { !$0.isWhitespace }) == "^"
        }
    }
}

#if os(macOS)
import AppKit

struct BlockTextView: NSViewRepresentable {
    let text: String
    let look: BlockLook
    /// Set only when this block is the one asked to take the insertion point.
    let focus: BlockFocus?
    let actions: BlockActions

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> BlockNSTextView {
        let textView = BlockNSTextView(frame: .zero)
        let coordinator = context.coordinator
        textView.delegate = coordinator
        textView.string = text
        textView.isRichText = false
        // Undo belongs to the document, so that one Undo covers typing and
        // the blocks Return, Tab, and Delete add, change, and remove.
        textView.allowsUndo = false
        textView.drawsBackground = false
        textView.textContainerInset = .zero
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = true
        textView.isVerticallyResizable = false
        textView.isHorizontallyResizable = false
        textView.setContentHuggingPriority(.defaultLow, for: .horizontal)

        // Nothing may change a character after it is typed.
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isAutomaticTextCompletionEnabled = false
        textView.isAutomaticLinkDetectionEnabled = false
        textView.isAutomaticDataDetectionEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.isGrammarCheckingEnabled = false

        textView.onFocus = { [weak coordinator] in
            coordinator?.parent.actions.focused()
        }
        textView.onMoveToWindow = { [weak coordinator, weak textView] in
            Task { @MainActor in
                if let textView { coordinator?.applyFocus(to: textView) }
            }
        }
        coordinator.apply(look, to: textView)
        return textView
    }

    func updateNSView(_ textView: BlockNSTextView, context: Context) {
        let coordinator = context.coordinator
        coordinator.parent = self
        textView.isEditable = context.environment.isEnabled
        if textView.string != text {
            // The document says something different from what is shown.
            textView.string = text
            coordinator.apply(look, to: textView)
            textView.invalidateIntrinsicContentSize()
        } else if coordinator.look != look {
            coordinator.apply(look, to: textView)
            textView.invalidateIntrinsicContentSize()
        }
        if let focus, focus.token != coordinator.appliedToken {
            coordinator.pendingFocus = focus
            Task { @MainActor in coordinator.applyFocus(to: textView) }
        }
    }

    /// As wide as it is offered and exactly as tall as its text.
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: BlockNSTextView, context: Context) -> CGSize? {
        var width = proposal.width ?? 480
        if !width.isFinite || width <= 0 { width = 480 }
        return CGSize(width: width, height: nsView.height(forWidth: width))
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: BlockTextView
        var look: BlockLook?
        var pendingFocus: BlockFocus?
        var appliedToken: Int?

        init(parent: BlockTextView) {
            self.parent = parent
        }

        func apply(_ look: BlockLook, to textView: NSTextView) {
            self.look = look
            textView.font = Self.font(for: look)
            textView.textColor = look.dimmed ? .secondaryLabelColor : .labelColor
            switch look.alignment {
            case .leading: textView.alignment = .natural
            case .center: textView.alignment = .center
            case .trailing: textView.alignment = .right
            }
        }

        private static func font(for look: BlockLook) -> NSFont {
            var traits: NSFontTraitMask = []
            if look.bold { traits.insert(.boldFontMask) }
            if look.italic { traits.insert(.italicFontMask) }
            if let family = look.family,
               let font = NSFontManager.shared.font(withFamily: family, traits: traits, weight: 5, size: look.size) {
                return font
            }
            let base = NSFont.systemFont(ofSize: look.size)
            var descriptor = base.fontDescriptor.withDesign(.serif) ?? base.fontDescriptor
            var symbolic: NSFontDescriptor.SymbolicTraits = []
            if look.bold { symbolic.insert(.bold) }
            if look.italic { symbolic.insert(.italic) }
            if !symbolic.isEmpty { descriptor = descriptor.withSymbolicTraits(symbolic) }
            return NSFont(descriptor: descriptor, size: look.size) ?? base
        }

        /// Puts the insertion point in this block, once the view is in a window.
        func applyFocus(to textView: NSTextView) {
            guard let focus = pendingFocus, let window = textView.window else { return }
            pendingFocus = nil
            appliedToken = focus.token
            window.makeFirstResponder(textView)
            let length = (textView.string as NSString).length
            let location = min(focus.location ?? length, length)
            textView.setSelectedRange(NSRange(location: location, length: 0))
            parent.actions.focusApplied()
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            textView.invalidateIntrinsicContentSize()
            parent.actions.change(textView.string)
        }

        /// Capitalizes letters as they are typed in a block that is set in capitals.
        func textView(
            _ textView: NSTextView,
            shouldChangeTextIn affectedCharRange: NSRange,
            replacementString: String?
        ) -> Bool {
            guard let typed = replacementString else { return true }
            let result = (textView.string as NSString).replacingCharacters(in: affectedCharRange, with: typed)
            guard BlockText.canHold(result) else {
                NSSound.beep()
                return false
            }
            guard parent.look.uppercase, !textView.hasMarkedText() else { return true }
            let capitals = typed.uppercased()
            if capitals == typed { return true }
            textView.insertText(capitals, replacementRange: affectedCharRange)
            return false
        }

        func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            let range = textView.selectedRange()
            let full = textView.string as NSString
            switch commandSelector {
            case #selector(NSResponder.insertNewline(_:)):
                let before = full.substring(to: range.location)
                let after = full.substring(from: NSMaxRange(range))
                if !parent.actions.split(before, after) { NSSound.beep() }
                return true
            case #selector(NSResponder.insertTab(_:)):
                if !parent.actions.changeKind(true, range.location) { NSSound.beep() }
                return true
            case #selector(NSResponder.insertBacktab(_:)):
                if !parent.actions.changeKind(false, range.location) { NSSound.beep() }
                return true
            case #selector(NSResponder.deleteBackward(_:)):
                return full.length == 0 && parent.actions.deleteEmpty()
            case #selector(NSResponder.moveUp(_:)):
                return range.length == 0 && range.location == 0 && parent.actions.move(true)
            case #selector(NSResponder.moveDown(_:)):
                return range.length == 0 && range.location == full.length && parent.actions.move(false)
            default:
                return false
            }
        }
    }
}

/// A text view that reports when it takes the insertion point and measures
/// its own height.
final class BlockNSTextView: NSTextView {
    var onFocus: (() -> Void)?
    var onMoveToWindow: (() -> Void)?

    override func becomeFirstResponder() -> Bool {
        let became = super.becomeFirstResponder()
        if became { onFocus?() }
        return became
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil { onMoveToWindow?() }
    }

    /// The height of the text set at this width, and never less than one line.
    func height(forWidth width: CGFloat) -> CGFloat {
        guard let container = textContainer, let manager = layoutManager else { return 0 }
        container.containerSize = NSSize(width: width, height: .greatestFiniteMagnitude)
        manager.ensureLayout(for: container)
        let line = manager.defaultLineHeight(for: font ?? .systemFont(ofSize: NSFont.systemFontSize))
        return max(ceil(manager.usedRect(for: container).height), ceil(line))
    }
}

#else
import UIKit

struct BlockTextView: UIViewRepresentable {
    let text: String
    let look: BlockLook
    /// Set only when this block is the one asked to take the insertion point.
    let focus: BlockFocus?
    let actions: BlockActions

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> BlockUITextView {
        let textView = BlockUITextView()
        let coordinator = context.coordinator
        textView.delegate = coordinator
        textView.text = text
        textView.backgroundColor = .clear
        textView.isScrollEnabled = false
        textView.textContainerInset = .zero
        textView.textContainer.lineFragmentPadding = 0
        textView.adjustsFontForContentSizeCategory = true
        textView.setContentHuggingPriority(.defaultLow, for: .horizontal)
        textView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        // Nothing may change a character after it is typed.
        textView.autocorrectionType = .no
        textView.spellCheckingType = .no
        textView.smartQuotesType = .no
        textView.smartDashesType = .no
        textView.smartInsertDeleteType = .no

        textView.onDeleteWhenEmpty = { [weak coordinator] in
            coordinator?.parent.actions.deleteEmpty() ?? false
        }
        textView.onTab = { [weak coordinator, weak textView] forward in
            guard let textView else { return }
            _ = coordinator?.parent.actions.changeKind(forward, textView.selectedRange.location)
        }
        textView.onMoveToWindow = { [weak coordinator, weak textView] in
            Task { @MainActor in
                if let textView { coordinator?.applyFocus(to: textView) }
            }
        }
        coordinator.textView = textView
        coordinator.apply(look, to: textView)
        return textView
    }

    func updateUIView(_ textView: BlockUITextView, context: Context) {
        let coordinator = context.coordinator
        coordinator.parent = self
        textView.isEditable = context.environment.isEnabled
        if textView.text != text {
            // The document says something different from what is shown.
            textView.text = text
            coordinator.apply(look, to: textView)
            textView.invalidateIntrinsicContentSize()
        } else if coordinator.look != look {
            coordinator.apply(look, to: textView)
            textView.invalidateIntrinsicContentSize()
        }
        if let focus, focus.token != coordinator.appliedToken {
            coordinator.pendingFocus = focus
            Task { @MainActor in coordinator.applyFocus(to: textView) }
        }
    }

    /// As wide as it is offered and exactly as tall as its text.
    func sizeThatFits(_ proposal: ProposedViewSize, uiView: BlockUITextView, context: Context) -> CGSize? {
        var width = proposal.width ?? 320
        if !width.isFinite || width <= 0 { width = 320 }
        let fitted = uiView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
        return CGSize(width: width, height: ceil(fitted.height))
    }

    @MainActor
    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: BlockTextView
        var look: BlockLook?
        var pendingFocus: BlockFocus?
        var appliedToken: Int?
        weak var textView: BlockUITextView?

        init(parent: BlockTextView) {
            self.parent = parent
        }

        func apply(_ look: BlockLook, to textView: UITextView) {
            self.look = look
            textView.font = Self.font(for: look)
            textView.textColor = look.dimmed ? .secondaryLabel : .label
            switch look.alignment {
            case .leading: textView.textAlignment = .natural
            case .center: textView.textAlignment = .center
            case .trailing: textView.textAlignment = .right
            }
            // A block set in capitals starts every key in capitals.
            textView.autocapitalizationType = look.uppercase ? .allCharacters : .sentences
        }

        private static func font(for look: BlockLook) -> UIFont {
            var descriptor: UIFontDescriptor
            if let family = look.family {
                descriptor = UIFontDescriptor(fontAttributes: [.family: family])
            } else {
                let body = UIFontDescriptor.preferredFontDescriptor(withTextStyle: .body)
                descriptor = body.withDesign(.serif) ?? body
            }
            var traits: UIFontDescriptor.SymbolicTraits = []
            if look.bold { traits.insert(.traitBold) }
            if look.italic { traits.insert(.traitItalic) }
            if !traits.isEmpty, let styled = descriptor.withSymbolicTraits(traits) {
                descriptor = styled
            }
            let font = UIFont(descriptor: descriptor, size: look.size)
            return UIFontMetrics(forTextStyle: .body).scaledFont(for: font)
        }

        /// Puts the insertion point in this block, once the view is in a window.
        func applyFocus(to textView: UITextView) {
            guard let focus = pendingFocus, textView.window != nil else { return }
            pendingFocus = nil
            appliedToken = focus.token
            textView.becomeFirstResponder()
            let length = ((textView.text ?? "") as NSString).length
            let location = min(focus.location ?? length, length)
            textView.selectedRange = NSRange(location: location, length: 0)
            parent.actions.focusApplied()
        }

        func textViewShouldBeginEditing(_ textView: UITextView) -> Bool {
            if textView.inputAccessoryView == nil {
                textView.inputAccessoryView = makeKeyBar()
            }
            return true
        }

        func textViewDidBeginEditing(_ textView: UITextView) {
            parent.actions.focused()
        }

        func textViewDidChange(_ textView: UITextView) {
            textView.invalidateIntrinsicContentSize()
            parent.actions.change(textView.text ?? "")
        }

        func textView(
            _ textView: UITextView,
            shouldChangeTextIn range: NSRange,
            replacementText text: String
        ) -> Bool {
            let full = (textView.text ?? "") as NSString
            if text == "\n" {
                let before = full.substring(to: range.location)
                let after = full.substring(from: NSMaxRange(range))
                _ = parent.actions.split(before, after)
                return false
            }
            guard BlockText.canHold(full.replacingCharacters(in: range, with: text)) else { return false }
            // Capitalizes letters as they are typed in a block set in capitals.
            guard parent.look.uppercase, textView.markedTextRange == nil else { return true }
            let capitals = text.uppercased()
            if capitals == text { return true }
            guard let start = textView.position(from: textView.beginningOfDocument, offset: range.location),
                  let end = textView.position(from: start, offset: range.length),
                  let textRange = textView.textRange(from: start, to: end) else { return true }
            textView.replace(textRange, withText: capitals)
            textViewDidChange(textView)
            return false
        }

        /// The keys above the keyboard. A touch keyboard has no Tab key, and
        /// Tab is how a block becomes another kind.
        private func makeKeyBar() -> UIToolbar {
            let previous = UIBarButtonItem(
                image: UIImage(systemName: "arrow.left.to.line"),
                style: .plain, target: self, action: #selector(previousKind)
            )
            previous.accessibilityLabel = "Previous Kind"
            let next = UIBarButtonItem(
                image: UIImage(systemName: "arrow.right.to.line"),
                style: .plain, target: self, action: #selector(nextKind)
            )
            next.accessibilityLabel = "Next Kind"
            let done = UIBarButtonItem(
                image: UIImage(systemName: "keyboard.chevron.compact.down"),
                style: .plain, target: self, action: #selector(hideKeyboard)
            )
            done.accessibilityLabel = "Hide Keyboard"

            let bar = UIToolbar(frame: CGRect(x: 0, y: 0, width: 320, height: 44))
            bar.items = [previous, next, .flexibleSpace(), done]
            bar.sizeToFit()
            return bar
        }

        @objc private func previousKind() {
            guard let textView else { return }
            _ = parent.actions.changeKind(false, textView.selectedRange.location)
        }

        @objc private func nextKind() {
            guard let textView else { return }
            _ = parent.actions.changeKind(true, textView.selectedRange.location)
        }

        @objc private func hideKeyboard() {
            textView?.resignFirstResponder()
        }
    }
}

/// A text view that reports Delete in an empty block and Tab on a hardware
/// keyboard, neither of which reaches a text view's delegate.
final class BlockUITextView: UITextView {
    var onDeleteWhenEmpty: (() -> Bool)?
    var onTab: ((_ forward: Bool) -> Void)?
    var onMoveToWindow: (() -> Void)?

    override func deleteBackward() {
        if text.isEmpty, onDeleteWhenEmpty?() == true { return }
        super.deleteBackward()
    }

    override var keyCommands: [UIKeyCommand]? {
        let forward = UIKeyCommand(input: "\t", modifierFlags: [], action: #selector(tabForward))
        let backward = UIKeyCommand(input: "\t", modifierFlags: .shift, action: #selector(tabBackward))
        forward.wantsPriorityOverSystemBehavior = true
        backward.wantsPriorityOverSystemBehavior = true
        return [forward, backward]
    }

    @objc private func tabForward() {
        onTab?(true)
    }

    @objc private func tabBackward() {
        onTab?(false)
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil { onMoveToWindow?() }
    }
}
#endif
