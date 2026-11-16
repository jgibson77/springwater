/// Tolerant analysis for editors.
///
/// The parser is strict: a text is a Springwater document or it is not. An
/// editor also has to reason about text that is still being written. That
/// reasoning lives here, apart from the parser, and uses the same line
/// division and line classification so the two can never disagree about what
/// a line is.
public enum SpringwaterEditorSupport {

    /// The names of the elements still open at the end of `text`, outermost
    /// first. The last name is the element a writer would close next.
    ///
    /// `text` is normally everything before the insertion point. An opening
    /// tag opens an element. A closing tag closes the innermost open element
    /// when their names match; a closing tag that matches nothing, and a caret
    /// line that is not a valid tag, are passed over. Nothing is repaired and
    /// nothing is reported: this answers one question for an editor and makes
    /// no claim about validity.
    public static func openElementNames(in text: String) -> [String] {
        var open: [String] = []
        for line in SpringwaterParser.physicalLines(of: text) {
            switch SpringwaterParser.classify(SpringwaterParser.trimmed(line.text)) {
            case .openingTag(let name):
                open.append(name)
            case .closingTag(let name):
                if open.last == name { open.removeLast() }
            case .content, .invalidCaretLine:
                break
            }
        }
        return open
    }

    /// The name of the element a writer should close at a point in the text,
    /// or nil when there is nothing to close there.
    ///
    /// `before` is the text up to the insertion point and `after` is the rest.
    /// The answer is the innermost element open at that point, unless the text
    /// that follows already closes it. Without that check, closing an element
    /// that is closed further down would write a second closing tag and make
    /// the document invalid.
    public static func elementToClose(before: String, after: String) -> String? {
        var open = openElementNames(in: before)
        guard let innermost = open.last else { return nil }
        let depth = open.count
        for line in SpringwaterParser.physicalLines(of: after) {
            switch SpringwaterParser.classify(SpringwaterParser.trimmed(line.text)) {
            case .openingTag(let name):
                open.append(name)
            case .closingTag(let name):
                if open.last == name {
                    open.removeLast()
                    // The innermost element at the insertion point has been closed.
                    if open.count < depth { return nil }
                }
            case .content, .invalidCaretLine:
                break
            }
        }
        return innermost
    }
}
