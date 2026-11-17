import Testing
@testable import SpringwaterRender

// These cases were first run against a JavaScript prototype of the same rule.

private func marked(_ line: String) -> [String] {
    InlineMarks.runs(in: line).map { $0.isEmphasized ? "[\($0.text)]" : $0.text }
}

@Test func emphasisBetweenUnderscores() {
    #expect(marked("a _b_ c") == ["a ", "[b]", " c"])
    #expect(marked("_start_ and end _x_") == ["[start]", " and end ", "[x]"])
    #expect(marked("_a b_") == ["[a b]"])
    #expect(marked("it is _very_, yes") == ["it is ", "[very]", ", yes"])
    #expect(marked("_a_ _b_") == ["[a]", " ", "[b]"])
    #expect(marked("(_a_)") == ["(", "[a]", ")"])
    #expect(marked("_a_.") == ["[a]", "."])
    #expect(marked("_日本_") == ["[日本]"])
}

@Test func underscoresInsideWordsAreOrdinaryText() {
    #expect(marked("snake_case_name") == ["snake_case_name"])
    #expect(marked("_a_b") == ["_a_b"])
    #expect(marked("é_b_") == ["é_b_"])
    #expect(marked("x_ _y_") == ["x_ ", "[y]"])
    #expect(marked("_a__b_") == ["[a__b]"])
}

@Test func underscoresThatPairWithNothingAreOrdinaryText() {
    #expect(marked("_ not_") == ["_ not_"])
    #expect(marked("__") == ["__"])
    #expect(marked("___") == ["___"])
    #expect(marked("plain") == ["plain"])
    #expect(marked("") == [])
}

@Test func nothingButTheMarksIsRemoved() {
    for line in ["a _b_ c", "snake_case", "_x_ and _y_ and z_", "  _lead_  "] {
        let runs = InlineMarks.runs(in: line)
        let rebuilt = runs.map { $0.isEmphasized ? "_\($0.text)_" : $0.text }.joined()
        #expect(rebuilt == line)
    }
}
