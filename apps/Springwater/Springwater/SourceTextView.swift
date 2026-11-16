import SwiftUI
import SpringwaterSyntax

// The source editor is the platform's own text view, not SwiftUI's TextEditor.
//
// Two things require it. First, a Springwater file must hold exactly what the
// writer typed, and only the platform text views can switch off smart quotes,
// smart dashes, text replacement, and autocorrection, each of which rewrites
// characters after they are typed. Second, TextEditor's selection binding, in
// a document window, put the insertion point before each typed character, so
// "int" arrived as "tni". The platform text view owns its own insertion point.
//
// The text view is the editing surface only. The document's text remains the
// single source of truth: every change is written straight to the binding,
// and the view's text is replaced only when the binding changes from outside
// (opening, reverting, choosing a starter).

#if os(macOS)
import AppKit

struct SourceTextView: NSViewRepresentable {
    @Binding var text: String

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        scrollView.drawsBackground = false
        guard let textView = scrollView.documentView as? NSTextView else { return scrollView }

        textView.delegate = context.coordinator
        textView.string = text
        textView.font = .monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        textView.isRichText = false
        textView.allowsUndo = true
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 6, height: 10)
        textView.usesFindBar = true
        textView.isIncrementalSearchingEnabled = true

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
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.text = $text
        guard let textView = scrollView.documentView as? NSTextView, textView.string != text else {
            return
        }
        // The document changed from outside the editor.
        textView.string = text
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var text: Binding<String>

        init(text: Binding<String>) {
            self.text = text
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            text.wrappedValue = textView.string
        }
    }
}

#else
import UIKit

struct SourceTextView: UIViewRepresentable {
    @Binding var text: String

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.delegate = context.coordinator
        textView.text = text
        let size = UIFont.preferredFont(forTextStyle: .body).pointSize
        textView.font = UIFontMetrics(forTextStyle: .body)
            .scaledFont(for: .monospacedSystemFont(ofSize: size, weight: .regular))
        textView.adjustsFontForContentSizeCategory = true
        textView.backgroundColor = .clear
        textView.alwaysBounceVertical = true
        textView.keyboardDismissMode = .interactive
        textView.textContainerInset = UIEdgeInsets(top: 12, left: 8, bottom: 12, right: 8)

        // Nothing may change a character after it is typed.
        textView.autocorrectionType = .no
        textView.autocapitalizationType = .none
        textView.spellCheckingType = .no
        textView.smartQuotesType = .no
        textView.smartDashesType = .no
        textView.smartInsertDeleteType = .no

        context.coordinator.textView = textView
        textView.inputAccessoryView = context.coordinator.makeKeyBar()
        return textView
    }

    func updateUIView(_ textView: UITextView, context: Context) {
        context.coordinator.text = $text
        if textView.text != text {
            // The document changed from outside the editor.
            textView.text = text
        }
    }

    @MainActor
    final class Coordinator: NSObject, UITextViewDelegate {
        var text: Binding<String>
        weak var textView: UITextView?

        init(text: Binding<String>) {
            self.text = text
        }

        func textViewDidChange(_ textView: UITextView) {
            text.wrappedValue = textView.text
        }

        /// The keys above the keyboard. The caret sits two keyboard pages deep
        /// on iPhone, and every tag begins with one.
        func makeKeyBar() -> UIToolbar {
            let caret = UIBarButtonItem(
                title: "^", style: .plain, target: self, action: #selector(insertCaret)
            )
            caret.accessibilityLabel = "Caret"
            let close = UIBarButtonItem(
                title: "^/", style: .plain, target: self, action: #selector(closeInnermostElement)
            )
            close.accessibilityLabel = "Close Tag"
            let done = UIBarButtonItem(
                image: UIImage(systemName: "keyboard.chevron.compact.down"),
                style: .plain, target: self, action: #selector(hideKeyboard)
            )
            done.accessibilityLabel = "Hide Keyboard"

            let font = UIFont.monospacedSystemFont(ofSize: 20, weight: .regular)
            for item in [caret, close] {
                item.setTitleTextAttributes([.font: font], for: .normal)
                item.setTitleTextAttributes([.font: font], for: .highlighted)
            }

            let bar = UIToolbar(frame: CGRect(x: 0, y: 0, width: 320, height: 44))
            bar.items = [caret, close, .flexibleSpace(), done]
            bar.sizeToFit()
            return bar
        }

        /// Types a caret at the insertion point, replacing any selected text.
        @objc private func insertCaret() {
            textView?.insertText("^")
        }

        /// Writes the closing tag for the innermost element open at the
        /// insertion point, on a line of its own. Does nothing when none is
        /// open there or when the element is already closed further down, as
        /// every element in a starter document is.
        @objc private func closeInnermostElement() {
            guard let textView else { return }
            let full: String = textView.text
            guard let range = Range(textView.selectedRange, in: full) else { return }
            let before = full[..<range.lowerBound]
            let after = full[range.upperBound...]
            guard let name = SpringwaterEditorSupport.elementToClose(
                before: String(before), after: String(after)
            ) else { return }

            var insertion = "^\(name)/"
            if let previous = before.last, !previous.isNewline {
                insertion = "\n" + insertion
            }
            if after.first?.isNewline != true {
                insertion += "\n"
            }
            textView.insertText(insertion)
        }

        @objc private func hideKeyboard() {
            textView?.resignFirstResponder()
        }
    }
}
#endif
