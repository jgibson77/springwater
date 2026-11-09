/// Every way a byte stream can fail to be a Springwater document.
///
/// Line numbers are 1-based physical line numbers. Error identity and
/// messages are diagnostic aids; the canonical syntax defines validity,
/// not error wording.
public enum SpringwaterError: Error, Sendable, Equatable {

    /// The byte stream is not valid UTF-8.
    case invalidUTF8

    /// The byte stream begins with the UTF-8 BOM byte sequence EF BB BF.
    case leadingBOM

    /// The document contains zero physical lines.
    case emptyDocument

    /// The first physical line is not `^Springwater`.
    case missingRootOpen(found: String)

    /// The document ended without a root closing tag.
    case missingRootClose

    /// An opening tag named `Springwater` appeared after the first line.
    /// The name is reserved for the single document root.
    case reservedRootName(line: Int)

    /// The root closing tag appeared before the last physical line.
    case trailingLinesAfterRootClose(line: Int)

    /// A line's trimmed text begins with `^` but is not a valid tag line.
    case invalidCaretLine(line: Int, text: String)

    /// A closing tag does not match the most recently opened tag.
    case mismatchedClosingTag(line: Int, found: String, open: String, openedAt: Int)

    /// An opening tag was never closed.
    case unclosedTag(name: String, openedAt: Int)
}

extension SpringwaterError: CustomStringConvertible {
    public var description: String {
        switch self {
        case .invalidUTF8:
            "Byte stream is not valid UTF-8"
        case .leadingBOM:
            "Byte stream begins with a UTF-8 BOM, which is rejected"
        case .emptyDocument:
            "Document is empty"
        case .missingRootOpen(let found):
            "Line 1: Document must begin with ^Springwater, found: \(found)"
        case .missingRootClose:
            "Document must end with ^Springwater/"
        case .reservedRootName(let line):
            "Line \(line): The tag name Springwater is reserved for the document root"
        case .trailingLinesAfterRootClose(let line):
            "Line \(line): ^Springwater/ must be the last physical line"
        case .invalidCaretLine(let line, let text):
            "Line \(line): Invalid ^ line: \(text)"
        case .mismatchedClosingTag(let line, let found, let open, let openedAt):
            "Line \(line): Tag mismatch: ^\(open) opened on line \(openedAt), but ^\(found)/ closes here"
        case .unclosedTag(let name, let openedAt):
            "Line \(openedAt): Unclosed tag ^\(name)"
        }
    }
}
