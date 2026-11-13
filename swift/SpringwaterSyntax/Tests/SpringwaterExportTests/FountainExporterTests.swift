import Testing
import SpringwaterSyntax
@testable import SpringwaterExport

// The golden below was captured from the reference exporter (the Python mirror).
// It pins the exact Fountain projection the Swift exporter must reproduce; it is
// not a round-trip assertion (no Fountain importer ships with this package).

private let tinyDoc = "^Springwater\n^screenplay\n^metadata\n^title\nLOW WATER\n^title/\n^written_by\nJG\n^written_by/\n^metadata/\n^act1\n^transition\nFADE IN:\n^transition/\n^scene\n^slugline\nEXT. DAM - DAY\n^slugline/\n^action\nWater falls.\n^action/\n^action\n    NORTH: INLET\n    SOUTH: RACE\n^action/\n^dialogue\n^character\nMcKAY\n^character/\n^extension\n(V.O.)\n^extension/\n^lines\nUse *17* here.\n^lines/\n^dialogue/\n^dual_dialogue\n^dialogue\n^character\nEVAN\n^character/\n^lines\nOpen.\n^lines/\n^dialogue/\n^dialogue\n^character\nLIAN\n^character/\n^lines\nHolding.\n^lines/\n^dialogue/\n^dual_dialogue/\n^transition\nCUT TO:\n^transition/\n^scene/\n^act1/\n^screenplay/\n^Springwater/\n"

private let expected = "Title: LOW WATER\nCredit: JG\n\n# ACT I\n\n>FADE IN:\n\nEXT. DAM - DAY\n\nWater falls.\n\n!    NORTH: INLET\n    SOUTH: RACE\n\n@McKAY (V.O.)\nUse \\*17\\* here.\n\nEVAN\nOpen.\n\nLIAN ^\nHolding.\n\nCUT TO:\n"

private func exported(_ text: String) throws -> String {
    FountainExporter.export(try SpringwaterParser.parse(text))
}

@Test func exportsExpectedFountain() throws {
    #expect(try exported(tinyDoc) == expected)
}

@Test func forcesMixedCaseCharacterCue() throws {
    // McKAY is not all-uppercase → must be forced with @ so it re-reads as a cue.
    #expect(try exported(tinyDoc).contains("@McKAY (V.O.)"))
    // EVAN / LIAN are all-caps → no @.
    #expect(try exported(tinyDoc).contains("\nEVAN\n"))
}

@Test func forcesAllCapsActionBlock() throws {
    // An all-caps multi-line action (a wall diagram) must be forced with ! so it
    // is not re-read as a character cue, and its indentation is preserved.
    #expect(try exported(tinyDoc).contains("!    NORTH: INLET\n    SOUTH: RACE"))
}

@Test func escapesLiteralEmphasis() throws {
    // Literal * must be escaped as \\* or the importer would strip it as emphasis.
    #expect(try exported(tinyDoc).contains("Use \\*17\\* here."))
}

@Test func marksSecondDualCue() throws {
    #expect(try exported(tinyDoc).contains("LIAN ^\nHolding."))
}

@Test func forcedVsAutoTransition() throws {
    let out = try exported(tinyDoc)
    #expect(out.contains(">FADE IN:"))     // not "...TO:" → forced
    #expect(out.contains("\nCUT TO:\n"))   // "...TO:" → auto, no '>'
}

@Test func forcesNonStandardSlugline() throws {
    let doc = "^Springwater\n^screenplay\n^act1\n^scene\n^slugline\nCRAWLER CAMERA - TUNNEL\n^slugline/\n^action\nx\n^action/\n^scene/\n^act1/\n^screenplay/\n^Springwater/\n"
    #expect(try exported(doc).contains(".CRAWLER CAMERA - TUNNEL"))
}

@Test func emitsSceneNumbersAndNestedSequences() throws {
    let doc = "^Springwater\n^screenplay\n^act1\n^sequence\n^label\nSequence 1 - The count\n^label/\n^scene\n^number\n1\n^number/\n^slugline\nEXT. DAM - DAY\n^slugline/\n^action\nx\n^action/\n^scene/\n^sequence\n^label\nSub\n^label/\n^scene\n^number\n2\n^number/\n^slugline\nINT. HALL - DAY\n^slugline/\n^action\ny\n^action/\n^scene/\n^sequence/\n^sequence/\n^act1/\n^screenplay/\n^Springwater/\n"
    #expect(try exported(doc) == "# ACT I\n\n## Sequence 1 - The count\n\nEXT. DAM - DAY #1#\n\nx\n\n### Sub\n\nINT. HALL - DAY #2#\n\ny\n")
}
