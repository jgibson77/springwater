import Testing
import SpringwaterSyntax
@testable import SpringwaterSchema

// MARK: - Helpers

private func makeSchema(_ text: String) throws -> Schema {
    try Schema(parsing: try SpringwaterParser.parse(text))
}

private func validate(_ document: String, against schema: Schema) throws -> [ValidationIssue] {
    SchemaValidator.validate(try SpringwaterParser.parse(document), against: schema)
}

// A small "memo" schema exercising the common predicates. Tag-line indentation
// is cosmetic and content values are trimmed by the builder, so indentation
// here is purely for readability.
private let memoSchema = """
^Springwater
^schema
  ^metadata
    ^name
    Memo
    ^name/
    ^version
    1.0
    ^version/
    ^description
    test
    ^description/
    ^strictness
    absolute
    ^strictness/
  ^metadata/
  ^required_root
  memo
  ^required_root/
  ^structure_rules
    ^rule
      ^tag
      memo
      ^tag/
      ^must_contain
      title
      ^must_contain/
      ^may_contain
      body, note, ext
      ^may_contain/
      ^cannot_contain
      secret
      ^cannot_contain/
    ^rule/
    ^rule
      ^tag
      title
      ^tag/
      ^text_only
      true
      ^text_only/
      ^cannot_be_empty
      true
      ^cannot_be_empty/
      ^parent_must_be
      memo
      ^parent_must_be/
    ^rule/
    ^rule
      ^tag
      body
      ^tag/
      ^may_contain
      para
      ^may_contain/
      ^parent_must_be
      memo
      ^parent_must_be/
    ^rule/
    ^rule
      ^tag
      para
      ^tag/
      ^text_only
      true
      ^text_only/
      ^parent_must_be
      body
      ^parent_must_be/
    ^rule/
    ^rule
      ^tag
      note
      ^tag/
      ^parent_must_be
      memo
      ^parent_must_be/
    ^rule/
    ^rule
      ^tag
      ext
      ^tag/
      ^allows_unknown_children
      true
      ^allows_unknown_children/
      ^parent_must_be
      memo
      ^parent_must_be/
    ^rule/
  ^structure_rules/
  ^validation
    ^empty_tags
    error
    ^empty_tags/
    ^unknown_tags
    error
    ^unknown_tags/
    ^invalid_nesting
    error
    ^invalid_nesting/
    ^missing_required
    error
    ^missing_required/
  ^validation/
^schema/
^Springwater/
"""

// MARK: - Schema parsing

@Test func schemaParsesRequiredRootAndRules() throws {
    let schema = try makeSchema(memoSchema)
    #expect(schema.requiredRoot == "memo")
    #expect(schema.rules["memo"]?.mustContain == ["title"])
    #expect(schema.rules["memo"]?.mayContain == ["body", "note", "ext"])
    #expect(schema.rules["memo"]?.cannotContain == ["secret"])
    #expect(schema.rules["title"]?.textOnly == true)
    #expect(schema.rules["title"]?.cannotBeEmpty == true)
    #expect(schema.rules["ext"]?.allowsUnknownChildren == true)
}

@Test func noSchemaRootThrows() {
    #expect(throws: SchemaError.noSchemaRoot) {
        try Schema(parsing: try SpringwaterParser.parse("^Springwater\n^notaschema\n^notaschema/\n^Springwater/\n"))
    }
}

// MARK: - Valid documents

@Test func validMemoHasNoIssues() throws {
    let schema = try makeSchema(memoSchema)
    let doc = "^Springwater\n^memo\n^title\nHello\n^title/\n^body\n^para\nx\n^para/\n^body/\n^note\n^note/\n^memo/\n^Springwater/\n"
    #expect(try validate(doc, against: schema).isValid)
}

@Test func emptyNoteIsAllowed() throws {
    // note has no cannot_be_empty, so an empty marker is fine.
    let schema = try makeSchema(memoSchema)
    let doc = "^Springwater\n^memo\n^title\nH\n^title/\n^note\n^note/\n^memo/\n^Springwater/\n"
    #expect(try validate(doc, against: schema).isValid)
}

@Test func openContainerAcceptsArbitrarySubtree() throws {
    // ext allows_unknown_children, so anything inside it is unconstrained.
    let schema = try makeSchema(memoSchema)
    let doc = "^Springwater\n^memo\n^title\nH\n^title/\n^ext\n^anything\n^deep\nz\n^deep/\n^anything/\n^ext/\n^memo/\n^Springwater/\n"
    #expect(try validate(doc, against: schema).isValid)
}

// MARK: - Invalid documents (one per violation kind)

private func hasCategory(_ issues: [ValidationIssue], _ category: ValidationIssue.Category) -> Bool {
    issues.contains { $0.category == category }
}

@Test func missingRequiredChildIsReported() throws {
    let schema = try makeSchema(memoSchema)
    let doc = "^Springwater\n^memo\n^body\n^para\nx\n^para/\n^body/\n^memo/\n^Springwater/\n"
    let issues = try validate(doc, against: schema)
    #expect(hasCategory(issues, .missingRequired))
    #expect(issues.contains { $0.message.contains("missing required child <title>") })
}

@Test func unknownChildIsReported() throws {
    let schema = try makeSchema(memoSchema)
    let doc = "^Springwater\n^memo\n^title\nH\n^title/\n^foo\n^foo/\n^memo/\n^Springwater/\n"
    #expect(hasCategory(try validate(doc, against: schema), .unknownTag))
}

@Test func forbiddenChildIsReported() throws {
    let schema = try makeSchema(memoSchema)
    let doc = "^Springwater\n^memo\n^title\nH\n^title/\n^secret\nx\n^secret/\n^memo/\n^Springwater/\n"
    #expect(try validate(doc, against: schema).contains { $0.message.contains("cannot_contain") })
}

@Test func invalidNestingIsReported() throws {
    // para's parent must be body, not memo.
    let schema = try makeSchema(memoSchema)
    let doc = "^Springwater\n^memo\n^title\nH\n^title/\n^para\nx\n^para/\n^memo/\n^Springwater/\n"
    #expect(hasCategory(try validate(doc, against: schema), .invalidNesting))
}

@Test func textOnlyWithChildIsReported() throws {
    let schema = try makeSchema(memoSchema)
    let doc = "^Springwater\n^memo\n^title\n^para\nx\n^para/\n^title/\n^memo/\n^Springwater/\n"
    #expect(try validate(doc, against: schema).contains { $0.message.contains("text_only") })
}

@Test func cannotBeEmptyIsReported() throws {
    let schema = try makeSchema(memoSchema)
    let doc = "^Springwater\n^memo\n^title\n^title/\n^memo/\n^Springwater/\n"
    #expect(hasCategory(try validate(doc, against: schema), .emptyTag))
}

@Test func wrongRootIsReported() throws {
    let schema = try makeSchema(memoSchema)
    let doc = "^Springwater\n^letter\n^letter/\n^Springwater/\n"
    let issues = try validate(doc, against: schema)
    #expect(hasCategory(issues, .missingRequired))
    #expect(issues.contains { $0.message.contains("missing required root <memo>") })
}

@Test func extraTopLevelElementIsReported() throws {
    let schema = try makeSchema(memoSchema)
    let doc = "^Springwater\n^memo\n^title\nH\n^title/\n^memo/\n^stray\n^stray/\n^Springwater/\n"
    #expect(try validate(doc, against: schema).contains { $0.message.contains("unexpected top-level element <stray>") })
}

// MARK: - one_of, count, must_equal, must_be_boolean

private func tinySchema(root: String, rules: String) -> String {
    """
    ^Springwater
    ^schema
    ^metadata
    ^name
    T
    ^name/
    ^version
    1
    ^version/
    ^description
    d
    ^description/
    ^strictness
    absolute
    ^strictness/
    ^metadata/
    ^required_root
    \(root)
    ^required_root/
    ^structure_rules
    \(rules)
    ^structure_rules/
    ^validation
    ^empty_tags
    error
    ^empty_tags/
    ^unknown_tags
    error
    ^unknown_tags/
    ^invalid_nesting
    error
    ^invalid_nesting/
    ^missing_required
    error
    ^missing_required/
    ^validation/
    ^schema/
    ^Springwater/
    """
}

@Test func mustContainOneOf() throws {
    let rules = """
    ^rule
    ^tag
    root
    ^tag/
    ^must_contain_one_of
    a, b
    ^must_contain_one_of/
    ^may_contain
    a, b
    ^may_contain/
    ^rule/
    ^rule
    ^tag
    a
    ^tag/
    ^text_only
    true
    ^text_only/
    ^parent_must_be
    root
    ^parent_must_be/
    ^rule/
    ^rule
    ^tag
    b
    ^tag/
    ^text_only
    true
    ^text_only/
    ^parent_must_be
    root
    ^parent_must_be/
    ^rule/
    """
    let schema = try makeSchema(tinySchema(root: "root", rules: rules))
    #expect(try validate("^Springwater\n^root\n^a\nx\n^a/\n^root/\n^Springwater/\n", against: schema).isValid)
    #expect(try validate("^Springwater\n^root\n^root/\n^Springwater/\n", against: schema)
        .contains { $0.message.contains("must contain one of") })
}

@Test func mustContainCount() throws {
    let rules = """
    ^rule
    ^tag
    dd
    ^tag/
    ^must_contain_count
    pair, 2
    ^must_contain_count/
    ^rule/
    ^rule
    ^tag
    pair
    ^tag/
    ^text_only
    true
    ^text_only/
    ^parent_must_be
    dd
    ^parent_must_be/
    ^rule/
    """
    let schema = try makeSchema(tinySchema(root: "dd", rules: rules))
    #expect(schema.rules["dd"]?.mustContainCount == .init(tag: "pair", count: 2))
    #expect(try validate("^Springwater\n^dd\n^pair\nx\n^pair/\n^pair\ny\n^pair/\n^dd/\n^Springwater/\n", against: schema).isValid)
    #expect(try validate("^Springwater\n^dd\n^pair\nx\n^pair/\n^dd/\n^Springwater/\n", against: schema)
        .contains { $0.message.contains("exactly 2") })
}

@Test func mustEqualAndMustBeBoolean() throws {
    let rules = """
    ^rule
    ^tag
    cfg
    ^tag/
    ^may_contain
    mode, flag
    ^may_contain/
    ^rule/
    ^rule
    ^tag
    mode
    ^tag/
    ^text_only
    true
    ^text_only/
    ^must_equal
    fast
    ^must_equal/
    ^parent_must_be
    cfg
    ^parent_must_be/
    ^rule/
    ^rule
    ^tag
    flag
    ^tag/
    ^text_only
    true
    ^text_only/
    ^must_be_boolean
    true
    ^must_be_boolean/
    ^parent_must_be
    cfg
    ^parent_must_be/
    ^rule/
    """
    let schema = try makeSchema(tinySchema(root: "cfg", rules: rules))
    #expect(try validate("^Springwater\n^cfg\n^mode\nfast\n^mode/\n^cfg/\n^Springwater/\n", against: schema).isValid)
    #expect(try validate("^Springwater\n^cfg\n^mode\nslow\n^mode/\n^cfg/\n^Springwater/\n", against: schema)
        .contains { $0.category == .mismatch })
    #expect(try validate("^Springwater\n^cfg\n^flag\ntrue\n^flag/\n^cfg/\n^Springwater/\n", against: schema).isValid)
    #expect(try validate("^Springwater\n^cfg\n^flag\nyes\n^flag/\n^cfg/\n^Springwater/\n", against: schema)
        .contains { $0.category == .mismatch })
}
