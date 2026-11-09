import Foundation
import Testing
@testable import SpringwaterSyntax

// MARK: - Valid documents (canonical examples)

@Test func minimalDocument() throws {
    let document = try SpringwaterParser.parse("^Springwater\n^Springwater/\n")
    #expect(document.root.name == "Springwater")
    #expect(document.root.children.isEmpty)
}

@Test func minimalDocumentWithoutTrailingNewline() throws {
    let document = try SpringwaterParser.parse("^Springwater\n^Springwater/")
    #expect(document.root.children.isEmpty)
}

@Test func singleContainer() throws {
    let document = try SpringwaterParser.parse(
        "^Springwater\n^document\nHello, world!\n^document/\n^Springwater/\n"
    )
    guard case .element(let element) = document.root.children[0] else {
        Issue.record("Expected element child")
        return
    }
    #expect(element.name == "document")
    #expect(element.children == [
        .content(.init(text: "Hello, world!", lineEnding: .lf))
    ])
}

@Test func nestedStructure() throws {
    // Tags indented (cosmetic), content flush. Explicit escapes keep the
    // multiline-literal indentation from leaking into the content line.
    let source = "^Springwater\n^book\n  ^chapter\n    ^title\nChapter One\n    ^title/\n  ^chapter/\n^book/\n^Springwater/\n"
    let document = try SpringwaterParser.parse(source)
    guard case .element(let book) = document.root.children[0],
          case .element(let chapter) = book.children[0],
          case .element(let title) = chapter.children[0] else {
        Issue.record("Expected book > chapter > title")
        return
    }
    #expect(book.name == "book")
    #expect(chapter.name == "chapter")
    #expect(title.name == "title")
    #expect(title.children == [
        .content(.init(text: "Chapter One", lineEnding: .lf))
    ])
}

@Test func mixedContentPreservesOrdering() throws {
    // The canonical mixed-content example. Ordering of content lines and
    // child elements must reflect physical line order.
    let source = """
    ^Springwater
    ^paragraph
    The word
    ^emphasis
    important
    ^emphasis/
    appears in this sentence.
    ^paragraph/
    ^Springwater/
    """
    let document = try SpringwaterParser.parse(source)
    guard case .element(let paragraph) = document.root.children[0] else {
        Issue.record("Expected paragraph")
        return
    }
    #expect(paragraph.children.count == 3)
    guard case .content(let before) = paragraph.children[0],
          case .element(let emphasis) = paragraph.children[1],
          case .content(let after) = paragraph.children[2] else {
        Issue.record("Expected content, element, content")
        return
    }
    #expect(before.text == "The word")
    #expect(emphasis.name == "emphasis")
    #expect(after.text == "appears in this sentence.")
}

@Test func codeAnnotationsAreContent() throws {
    // The reason the tag character is ^. Every line here is content.
    let source = """
    ^Springwater
    ^code
    @State var count = 0
    @Observable class Model {}
    #include <stdio.h>
    $PATH
    john@example.com
    ^code/
    ^Springwater/
    """
    let document = try SpringwaterParser.parse(source)
    guard case .element(let code) = document.root.children[0] else {
        Issue.record("Expected code element")
        return
    }
    #expect(code.children.count == 5)
    for child in code.children {
        guard case .content = child else {
            Issue.record("Expected only content lines")
            return
        }
    }
}

@Test func contentIndentationIsPreserved() throws {
    let source = "^Springwater\n^code\n    indented line\n^code/\n^Springwater/\n"
    let document = try SpringwaterParser.parse(source)
    guard case .element(let code) = document.root.children[0],
          case .content(let line) = code.children[0] else {
        Issue.record("Expected content line")
        return
    }
    #expect(line.text == "    indented line")
}

@Test func blankLinesArePreservedAsContent() throws {
    let source = "^Springwater\n^poem\nFirst\n\nThird\n^poem/\n^Springwater/\n"
    let document = try SpringwaterParser.parse(source)
    guard case .element(let poem) = document.root.children[0] else {
        Issue.record("Expected poem")
        return
    }
    #expect(poem.children == [
        .content(.init(text: "First", lineEnding: .lf)),
        .content(.init(text: "", lineEnding: .lf)),
        .content(.init(text: "Third", lineEnding: .lf)),
    ])
}

@Test func indentedTagLinesAreStructural() throws {
    let source = "^Springwater\n  ^section\n  content\n  ^section/\n^Springwater/\n"
    let document = try SpringwaterParser.parse(source)
    guard case .element(let section) = document.root.children[0] else {
        Issue.record("Indented tag line must be structural")
        return
    }
    #expect(section.name == "section")
    // Content indentation is content.
    #expect(section.children == [
        .content(.init(text: "  content", lineEnding: .lf))
    ])
}

@Test func nonBreakingSpaceDoesNotTrim() throws {
    // U+00A0 is a content character. A line beginning with NBSP does not
    // begin with ^ after trimming, so it is content even if ^ follows.
    let source = "^Springwater\n^p\n\u{00A0}^chapter\n^p/\n^Springwater/\n"
    let document = try SpringwaterParser.parse(source)
    guard case .element(let paragraph) = document.root.children[0],
          case .content(let line) = paragraph.children[0] else {
        Issue.record("NBSP-prefixed line must be content")
        return
    }
    #expect(line.text == "\u{00A0}^chapter")
}

@Test func unicodeLineSeparatorIsContent() throws {
    // U+2028 does not divide physical lines.
    let source = "^Springwater\n^p\nfirst\u{2028}second\n^p/\n^Springwater/\n"
    let document = try SpringwaterParser.parse(source)
    guard case .element(let paragraph) = document.root.children[0],
          case .content(let line) = paragraph.children[0] else {
        Issue.record("Expected single content line")
        return
    }
    #expect(line.text == "first\u{2028}second")
}

// MARK: - Line endings

@Test func mixedLineEndingsArePreserved() throws {
    let source = "^Springwater\n^p\r\nalpha\r\nbeta\ngamma\r^p/\n^Springwater/\n"
    let document = try SpringwaterParser.parse(source)
    guard case .element(let paragraph) = document.root.children[0] else {
        Issue.record("Expected paragraph")
        return
    }
    #expect(paragraph.children == [
        .content(.init(text: "alpha", lineEnding: .crlf)),
        .content(.init(text: "beta", lineEnding: .lf)),
        .content(.init(text: "gamma", lineEnding: .cr)),
    ])
}

@Test func physicalLineDivision() {
    let lines = SpringwaterParser.physicalLines(of: "a\nb\r\nc\rd")
    #expect(lines.count == 4)
    #expect(lines[0].text == "a" && lines[0].ending == .lf)
    #expect(lines[1].text == "b" && lines[1].ending == .crlf)
    #expect(lines[2].text == "c" && lines[2].ending == .cr)
    #expect(lines[3].text == "d" && lines[3].ending == SpringwaterDocument.PhysicalLineEnding.none)
}

@Test func trailingLineBreakProducesNoExtraLine() {
    let lines = SpringwaterParser.physicalLines(of: "a\n")
    #expect(lines.count == 1)
}

// MARK: - Encoding

@Test func leadingBOMIsRejected() {
    var data = Data([0xEF, 0xBB, 0xBF])
    data.append(Data("^Springwater\n^Springwater/\n".utf8))
    #expect(throws: SpringwaterError.leadingBOM) {
        try SpringwaterParser.parse(data)
    }
}

@Test func interiorFEFFIsContent() throws {
    let source = "^Springwater\n^p\nbefore\u{FEFF}after\n^p/\n^Springwater/\n"
    let document = try SpringwaterParser.parse(source)
    guard case .element(let paragraph) = document.root.children[0],
          case .content(let line) = paragraph.children[0] else {
        Issue.record("Expected content line")
        return
    }
    #expect(line.text == "before\u{FEFF}after")
}

@Test func invalidUTF8IsRejected() {
    var data = Data("^Springwater\n".utf8)
    data.append(contentsOf: [0xFF, 0xFE, 0x80])
    data.append(Data("\n^Springwater/\n".utf8))
    #expect(throws: SpringwaterError.invalidUTF8) {
        try SpringwaterParser.parse(data)
    }
}

@Test func emptyDocumentIsRejected() {
    #expect(throws: SpringwaterError.emptyDocument) {
        try SpringwaterParser.parse(Data())
    }
}

// MARK: - Invalid documents (canonical examples)

@Test func wrongCaseRootIsRejected() {
    #expect(throws: SpringwaterError.missingRootOpen(found: "^springwater")) {
        try SpringwaterParser.parse("^springwater\n^springwater/\n")
    }
}

@Test func contentBeforeRootIsRejected() {
    #expect(throws: SpringwaterError.missingRootOpen(found: "Preamble")) {
        try SpringwaterParser.parse("Preamble\n^Springwater\n^Springwater/\n")
    }
}

@Test func contentAfterRootCloseIsRejected() {
    #expect(throws: SpringwaterError.trailingLinesAfterRootClose(line: 2)) {
        try SpringwaterParser.parse("^Springwater\n^Springwater/\nTrailing\n")
    }
}

@Test func nestedRootIsRejected() {
    #expect(throws: SpringwaterError.reservedRootName(line: 2)) {
        try SpringwaterParser.parse("^Springwater\n^Springwater\n^Springwater/\n^Springwater/\n")
    }
}

@Test func unclosedTagIsRejected() {
    // No root close at all: the innermost unclosed tag is reported.
    #expect(throws: SpringwaterError.unclosedTag(name: "paragraph", openedAt: 2)) {
        try SpringwaterParser.parse("^Springwater\n^paragraph\nContent\n")
    }
}

@Test func missingRootCloseIsRejected() {
    #expect(throws: SpringwaterError.missingRootClose) {
        try SpringwaterParser.parse("^Springwater\ncontent\n")
    }
}

@Test func caseMismatchIsRejected() {
    #expect(throws: SpringwaterError.mismatchedClosingTag(
        line: 4, found: "chapter", open: "Chapter", openedAt: 2
    )) {
        try SpringwaterParser.parse("^Springwater\n^Chapter\nContent\n^chapter/\n^Springwater/\n")
    }
}

@Test func improperNestingIsRejected() {
    #expect(throws: SpringwaterError.mismatchedClosingTag(
        line: 4, found: "outer", open: "inner", openedAt: 3
    )) {
        try SpringwaterParser.parse("^Springwater\n^outer\n^inner\n^outer/\n^inner/\n^Springwater/\n")
    }
}

@Test(arguments: [
    "^my-tag",          // hyphen
    "^123",             // starts with digit
    "^_name",           // starts with underscore
    "^",                // no name
    "^/",               // no name
    "^^tag",            // double caret
    "^tag  /",          // whitespace before slash
    "^tag /more",       // text after slash
    "^paragraph This is text. ^paragraph/", // inline tags
    "^john said hello", // structural-looking content
])
func invalidCaretLinesAreRejected(badLine: String) {
    #expect(throws: SpringwaterError.invalidCaretLine(line: 2, text: badLine)) {
        try SpringwaterParser.parse("^Springwater\n\(badLine)\n^Springwater/\n")
    }
}

// MARK: - Classification unit checks

@Test func classificationTable() {
    typealias C = SpringwaterParser.LineClassification
    func classify(_ line: String) -> C {
        SpringwaterParser.classify(SpringwaterParser.trimmed(Substring(line)))
    }
    #expect(classify("^chapter") == .openingTag("chapter"))
    #expect(classify("  ^chapter  ") == .openingTag("chapter"))
    #expect(classify("^chapter/") == .closingTag("chapter"))
    #expect(classify("  ^chapter/  ") == .closingTag("chapter"))
    #expect(classify("chapter") == .content)
    #expect(classify("text ^chapter") == .content)
    #expect(classify("Email: a@b.com") == .content)
    #expect(classify("") == .content)
    #expect(classify("   ") == .content)
    #expect(classify("^chapter text") == .invalidCaretLine)
    #expect(classify("^my-tag") == .invalidCaretLine)
    #expect(classify("\u{00A0}^chapter") == .content)
}

// MARK: - Serialization

@Test func serializationRoundTripIsStable() throws {
    let source = """
    ^Springwater
    ^screenplay
      ^scene
        ^slugline
        INT. OFFICE - DAY
        ^slugline/
        ^action
        JOHN enters the room.
        ^action/
      ^scene/
    ^screenplay/
    ^Springwater/
    """
    let document = try SpringwaterParser.parse(source)
    let serialized = SpringwaterSerializer.serialize(document)
    let reparsed = try SpringwaterParser.parse(serialized)
    #expect(reparsed == document)
    // Canonical output is a fixed point: serializing again is identical.
    #expect(SpringwaterSerializer.serialize(reparsed) == serialized)
}

@Test func canonicalFormHasNoIndentedTagLines() throws {
    // Canonical form carries no tag-line whitespace, whatever the source had.
    // Explicit escapes avoid multiline-literal indentation stripping.
    let source = "^Springwater\n  ^outer\n    ^inner\ncontent\n    ^inner/\n  ^outer/\n^Springwater/\n"
    let canonical = SpringwaterSerializer.serialize(try SpringwaterParser.parse(source))
    #expect(canonical == "^Springwater\n^outer\n^inner\ncontent\n^inner/\n^outer/\n^Springwater/\n")
}

@Test func prettyPrintIsTreeEqualButNotCanonical() throws {
    let document = try SpringwaterParser.parse(
        "^Springwater\n^a\n^b\ntext\n^b/\n^a/\n^Springwater/\n"
    )
    let pretty = SpringwaterSerializer.prettyPrinted(document)
    // Indented, so not canonical form.
    #expect(pretty != SpringwaterSerializer.serialize(document))
    #expect(pretty.contains("  ^a"))
    // But parses back to the same tree: a conforming writer.
    #expect(try SpringwaterParser.parse(pretty) == document)
    // Content is never indented, even when pretty-printing.
    #expect(pretty.contains("\ntext\n"))
}

@Test func canonicalPreservesContentLineEndings() throws {
    // Canonical form normalizes tag-line endings to LF but leaves content
    // endings untouched.
    let document = try SpringwaterParser.parse(
        "^Springwater\r\n^p\r\nalpha\r\nbeta\n^p/\r\n^Springwater/\r\n"
    )
    let canonical = SpringwaterSerializer.serialize(document)
    #expect(canonical.contains("alpha\r\n"))
    #expect(canonical.contains("beta\n"))
    #expect(canonical.hasPrefix("^Springwater\n"))  // tag ending is LF
}

@Test func contentFinalLineWithoutTerminatorIsRejected() {
    // The last physical line is content with no trailing break, so the
    // required root-close final line is absent.
    #expect(throws: SpringwaterError.missingRootClose) {
        try SpringwaterParser.parse("^Springwater\n^p\ntrailing")
    }
}
