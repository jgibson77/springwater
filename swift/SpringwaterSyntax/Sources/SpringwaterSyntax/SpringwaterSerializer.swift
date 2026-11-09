/// Serializes a document tree back to Springwater source text.
///
/// Two writers are offered, both conforming (each produces a document that
/// parses back to the given tree):
///
/// - `serialize(_:)` emits canonical form, as defined by the DOCUMENT
///   IDENTITY section of the canonical syntax: every tag line has no
///   leading or trailing whitespace and ends with a single LF, and every
///   content line is reproduced verbatim with its stored ending. Canonical
///   form is uniquely determined by the tree, so two tree-equal documents
///   have identical canonical forms, and `serialize` is a fixed point:
///   serializing a reparsed canonical document reproduces it exactly.
///
/// - `prettyPrinted(_:indentWidth:)` indents tag lines for readability.
///   The result is tree-equal to the input but is not canonical form,
///   because canonical form carries no tag-line indentation. Content lines
///   are still reproduced verbatim; only cosmetic tag-line whitespace is
///   added, and it is discarded on the next parse.
///
/// Neither writer alters a content line. Content text and content line
/// endings are significant to tree equality and are always preserved.
public enum SpringwaterSerializer {

    /// Emits the document in canonical form (flat, LF-terminated tag lines;
    /// content verbatim). See the type documentation.
    public static func serialize(_ document: SpringwaterDocument) -> String {
        var output = "^Springwater\n"
        for child in document.root.children {
            appendCanonical(child, to: &output)
        }
        output += "^Springwater/\n"
        return output
    }

    /// Emits the document with tag lines indented `indentWidth` spaces per
    /// nesting level. Tree-equal to the input, but not canonical form.
    public static func prettyPrinted(
        _ document: SpringwaterDocument,
        indentWidth: Int = 2
    ) -> String {
        var output = "^Springwater\n"
        for child in document.root.children {
            appendPretty(child, depth: 1, indentWidth: indentWidth, to: &output)
        }
        output += "^Springwater/\n"
        return output
    }

    // MARK: - Canonical

    private static func appendCanonical(
        _ child: SpringwaterDocument.Child,
        to output: inout String
    ) {
        switch child {
        case .content(let line):
            output += line.text
            output += ending(line.lineEnding)
        case .element(let element):
            output += "^" + element.name + "\n"
            for grandchild in element.children {
                appendCanonical(grandchild, to: &output)
            }
            output += "^" + element.name + "/\n"
        }
    }

    // MARK: - Pretty

    private static func appendPretty(
        _ child: SpringwaterDocument.Child,
        depth: Int,
        indentWidth: Int,
        to output: inout String
    ) {
        switch child {
        case .content(let line):
            // Content is never indented: its leading whitespace is content.
            output += line.text
            output += ending(line.lineEnding)
        case .element(let element):
            let indent = String(repeating: " ", count: depth * indentWidth)
            output += indent + "^" + element.name + "\n"
            for grandchild in element.children {
                appendPretty(grandchild, depth: depth + 1, indentWidth: indentWidth, to: &output)
            }
            output += indent + "^" + element.name + "/\n"
        }
    }

    private static func ending(_ lineEnding: SpringwaterDocument.ContentLineEnding) -> String {
        switch lineEnding {
        case .lf: "\n"
        case .crlf: "\r\n"
        case .cr: "\r"
        }
    }
}
