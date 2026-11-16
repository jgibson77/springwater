import Testing
@testable import SpringwaterSyntax

@Test func openElementsInEmptyText() {
    #expect(SpringwaterEditorSupport.openElementNames(in: "") == [])
}

@Test func openElementsListsOutermostFirst() {
    let text = "^Springwater\n^screenplay\n^act1\n^scene\n^slugline\nINT. HOUSE - DAY\n"
    #expect(SpringwaterEditorSupport.openElementNames(in: text)
        == ["Springwater", "screenplay", "act1", "scene", "slugline"])
}

@Test func closedElementsAreNotOpen() {
    let text = "^Springwater\n^scene\n^slugline\nINT. HOUSE - DAY\n^slugline/\n"
    #expect(SpringwaterEditorSupport.openElementNames(in: text) == ["Springwater", "scene"])
}

@Test func completeDocumentLeavesNothingOpen() {
    #expect(SpringwaterEditorSupport.openElementNames(in: "^Springwater\n^Springwater/\n") == [])
}

@Test func openingTagWithoutLineEndingCounts() {
    #expect(SpringwaterEditorSupport.openElementNames(in: "^Springwater\n^scene") == ["Springwater", "scene"])
}

@Test func indentedTagsAndMixedLineEndingsCount() {
    let text = "^Springwater\r\n  ^scene\r\t^action\n"
    #expect(SpringwaterEditorSupport.openElementNames(in: text) == ["Springwater", "scene", "action"])
}

@Test func mismatchedClosingTagIsPassedOver() {
    let text = "^Springwater\n^scene\n^action/\n"
    #expect(SpringwaterEditorSupport.openElementNames(in: text) == ["Springwater", "scene"])
}

@Test func invalidCaretLineAndContentArePassedOver() {
    let text = "^Springwater\n^scene\n^ not a tag\n^9lives\nplain ^caret inside\n"
    #expect(SpringwaterEditorSupport.openElementNames(in: text) == ["Springwater", "scene"])
}
