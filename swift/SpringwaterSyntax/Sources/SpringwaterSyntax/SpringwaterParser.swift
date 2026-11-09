import Foundation

/// The strict canonical Springwater v1.0 parser.
///
/// Implements the PARSING ALGORITHM section of the canonical syntax
/// exactly. No recovery. No invented nodes. No silent correction.
/// Tolerant analysis for editors is a separate system and does not
/// belong here.
public enum SpringwaterParser {

    /// Parses a UTF-8 byte stream into a document tree.
    public static func parse(_ data: Data) throws(SpringwaterError) -> SpringwaterDocument {
        // Step 2: reject a leading UTF-8 BOM byte sequence.
        if data.starts(with: [0xEF, 0xBB, 0xBF]) {
            throw .leadingBOM
        }
        // Step 3: the byte stream must be valid UTF-8.
        guard let string = String(data: data, encoding: .utf8) else {
            throw .invalidUTF8
        }
        return try parseDecoded(string)
    }

    /// Parses a string by encoding it as UTF-8 and running the canonical
    /// byte-stream path. A string beginning with U+FEFF is therefore
    /// rejected as a leading BOM, matching the byte-level rule.
    public static func parse(_ string: String) throws(SpringwaterError) -> SpringwaterDocument {
        try parse(Data(string.utf8))
    }

    // MARK: - Core algorithm

    private static func parseDecoded(_ string: String) throws(SpringwaterError) -> SpringwaterDocument {
        // Step 4: divide into physical lines, preserving each line's
        // original ending sequence.
        let lines = physicalLines(of: string)

        // Step 5: zero physical lines is an empty document.
        guard !lines.isEmpty else {
            throw .emptyDocument
        }

        // Step 6: the first physical line must be the root opening tag.
        let firstTrimmed = trimmed(lines[0].text)
        guard firstTrimmed == "^Springwater" else {
            throw .missingRootOpen(found: String(firstTrimmed))
        }

        // Step 7: the stack begins with the root frame.
        var stack: [Frame] = [Frame(name: "Springwater", openedAt: 1)]
        var parsedRoot: SpringwaterDocument.Element?

        // Step 8: classify and consume each subsequent physical line.
        for index in 1..<lines.count {
            let lineNumber = index + 1
            let line = lines[index]

            switch classify(trimmed(line.text)) {
            case .content:
                guard let ending = SpringwaterDocument.ContentLineEnding(line.ending) else {
                    // The ending is .none, which only the final physical
                    // line carries. A content line as the final physical
                    // line means the required final root-close line is
                    // absent, so the document has no root close.
                    throw .missingRootClose
                }
                let contentLine = SpringwaterDocument.ContentLine(
                    text: String(line.text),
                    lineEnding: ending
                )
                stack[stack.count - 1].children.append(.content(contentLine))

            case .openingTag(let name):
                guard name != "Springwater" else {
                    throw .reservedRootName(line: lineNumber)
                }
                stack.append(Frame(name: name, openedAt: lineNumber))

            case .closingTag(let name):
                if stack.count == 1 {
                    // Only the root frame remains. This must be the root
                    // closing tag, and it must be the last physical line.
                    guard name == "Springwater" else {
                        throw .mismatchedClosingTag(
                            line: lineNumber, found: name,
                            open: "Springwater", openedAt: 1
                        )
                    }
                    guard index == lines.count - 1 else {
                        throw .trailingLinesAfterRootClose(line: lineNumber)
                    }
                    let rootFrame = stack.removeLast()
                    parsedRoot = SpringwaterDocument.Element(
                        name: rootFrame.name, children: rootFrame.children
                    )
                } else {
                    let top = stack[stack.count - 1]
                    guard top.name == name else {
                        throw .mismatchedClosingTag(
                            line: lineNumber, found: name,
                            open: top.name, openedAt: top.openedAt
                        )
                    }
                    let frame = stack.removeLast()
                    let element = SpringwaterDocument.Element(
                        name: frame.name, children: frame.children
                    )
                    stack[stack.count - 1].children.append(.element(element))
                }

            case .invalidCaretLine:
                throw .invalidCaretLine(
                    line: lineNumber, text: String(trimmed(line.text))
                )
            }
        }

        // Step 9: the root close must have been encountered.
        guard let root = parsedRoot else {
            if stack.count > 1 {
                let top = stack[stack.count - 1]
                throw .unclosedTag(name: top.name, openedAt: top.openedAt)
            }
            throw .missingRootClose
        }
        return SpringwaterDocument(root: root)
    }

    private struct Frame {
        let name: String
        let openedAt: Int
        var children: [SpringwaterDocument.Child] = []
    }

    // MARK: - Line division

    /// Divides a decoded string into physical lines at LF, CRLF, or CR.
    ///
    /// U+2028 and U+2029 are content characters, not line breaks. Slice
    /// boundaries here are always grapheme-aligned: LF, CR, and CRLF are
    /// each complete grapheme clusters, so slicing the string at these
    /// scalar indices is safe.
    static func physicalLines(of string: String) -> [(text: Substring, ending: SpringwaterDocument.PhysicalLineEnding)] {
        var lines: [(Substring, SpringwaterDocument.PhysicalLineEnding)] = []
        let scalars = string.unicodeScalars
        var lineStart = scalars.startIndex
        var index = scalars.startIndex

        while index < scalars.endIndex {
            let scalar = scalars[index]
            if scalar == "\n" {
                lines.append((string[lineStart..<index], .lf))
                index = scalars.index(after: index)
                lineStart = index
            } else if scalar == "\r" {
                let afterCR = scalars.index(after: index)
                if afterCR < scalars.endIndex, scalars[afterCR] == "\n" {
                    lines.append((string[lineStart..<index], .crlf))
                    index = scalars.index(after: afterCR)
                } else {
                    lines.append((string[lineStart..<index], .cr))
                    index = afterCR
                }
                lineStart = index
            } else {
                index = scalars.index(after: index)
            }
        }
        if lineStart < scalars.endIndex {
            lines.append((string[lineStart...], .none))
        }
        return lines
    }

    // MARK: - Classification

    enum LineClassification: Equatable {
        case content
        case openingTag(String)
        case closingTag(String)
        case invalidCaretLine
    }

    /// Classifies a line's trimmed text per the LINE CLASSIFICATION
    /// algorithm. The line-ending sequence never participates.
    static func classify(_ trimmedText: Substring) -> LineClassification {
        let scalars = trimmedText.unicodeScalars
        guard scalars.first == "^" else {
            // Empty trimmed text, or text not beginning with the caret,
            // is content.
            return .content
        }
        var body = scalars[scalars.index(after: scalars.startIndex)...]
        var isClosing = false
        if body.last == "/" {
            isClosing = true
            body = body[..<body.index(before: body.endIndex)]
        }
        guard isValidTagName(body) else {
            return .invalidCaretLine
        }
        let name = String(Substring(body))
        return isClosing ? .closingTag(name) : .openingTag(name)
    }

    /// Removes leading and trailing U+0020 and U+0009 only, for
    /// classification. Deliberately not Unicode-aware: NBSP, em space,
    /// and all other Unicode whitespace are content characters.
    static func trimmed(_ text: Substring) -> Substring {
        let scalars = text.unicodeScalars
        var start = scalars.startIndex
        while start < scalars.endIndex {
            let scalar = scalars[start]
            guard scalar == " " || scalar == "\t" else { break }
            start = scalars.index(after: start)
        }
        var end = scalars.endIndex
        while end > start {
            let before = scalars.index(before: end)
            let scalar = scalars[before]
            guard scalar == " " || scalar == "\t" else { break }
            end = before
        }
        return Substring(scalars[start..<end])
    }

    /// Tag names are ASCII only: a leading letter, then letters, digits,
    /// and underscores.
    static func isValidTagName(_ scalars: Substring.UnicodeScalarView.SubSequence) -> Bool {
        guard let first = scalars.first, isASCIILetter(first) else {
            return false
        }
        return scalars.dropFirst().allSatisfy { scalar in
            isASCIILetter(scalar) || isASCIIDigit(scalar) || scalar == "_"
        }
    }

    private static func isASCIILetter(_ scalar: Unicode.Scalar) -> Bool {
        (0x41...0x5A).contains(scalar.value) || (0x61...0x7A).contains(scalar.value)
    }

    private static func isASCIIDigit(_ scalar: Unicode.Scalar) -> Bool {
        (0x30...0x39).contains(scalar.value)
    }
}
