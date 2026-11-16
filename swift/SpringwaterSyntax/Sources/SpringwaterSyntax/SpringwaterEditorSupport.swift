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
}
