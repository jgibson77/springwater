import Testing
import Foundation
import SpringwaterSyntax
@testable import SpringwaterSchema

private let repoRoot: URL = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()   // SpringwaterSchemaTests/
    .deletingLastPathComponent()   // Tests/
    .deletingLastPathComponent()   // SpringwaterSyntax/
    .deletingLastPathComponent()   // swift/
    .deletingLastPathComponent()   // <repo root>

private let selfContained = repoRoot.appendingPathComponent("examples/genesis_1_3.self_contained.springwater")
private let plain = repoRoot.appendingPathComponent("examples/genesis_1_3.springwater")

private let repositoryAvailable: Bool = FileManager.default.fileExists(atPath: selfContained.path)

private func parseFile(_ url: URL) throws -> SpringwaterDocument {
    try SpringwaterParser.parse(try Data(contentsOf: url))
}

@Suite(.enabled(if: repositoryAvailable))
struct CarriedDocumentsInRepository {

    @Test func workIsValidAgainstTheSchemaItCarries() throws {
        let document = try parseFile(selfContained)
        let schema = try #require(CarriedDocuments.schema(in: document))
        #expect(schema.requiredRoot == "parallel_text")
        #expect(SchemaValidator.validate(document, against: schema).isEmpty)
    }

    @Test func carriedSchemasAreValidAgainstTheCarriedSchemaForSchemas() throws {
        let document = try parseFile(selfContained)
        let metaDocument = try #require(CarriedDocuments.schemaDocument(in: document, for: "schema"))
        let meta = try Schema(parsing: metaDocument)
        let work = try #require(CarriedDocuments.schemaDocument(in: document, for: "parallel_text"))
        #expect(SchemaValidator.validate(work, against: meta).isEmpty)
        #expect(SchemaValidator.validate(metaDocument, against: meta).isEmpty)
    }

    @Test func documentWithoutACarriedSchemaReportsNone() throws {
        #expect(CarriedDocuments.schema(in: try parseFile(plain)) == nil)
    }
}

@Test func carriedSchemaIsFoundByTheRootItRequires() throws {
    let text = """
    ^Springwater
    ^memo
    ^title
    Hello
    ^title/
    ^memo/
    ^schema
    ^required_root
    letter
    ^required_root/
    ^schema/
    ^schema
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
    ^rule/
    ^rule
    ^tag
    title
    ^tag/
    ^text_only
    true
    ^text_only/
    ^rule/
    ^structure_rules/
    ^schema/
    ^Springwater/

    """
    let document = try SpringwaterParser.parse(text)
    let schema = try #require(CarriedDocuments.schema(in: document))
    #expect(schema.requiredRoot == "memo")
    #expect(schema.rules["memo"]?.mustContain == ["title"])
    #expect(SchemaValidator.validate(document, against: schema).isEmpty)
}

@Test func onlySchemaAndPresentationMayBeCarried() throws {
    let text = "^Springwater\n^memo\n^memo/\n^notes\n^notes/\n^presentation\n^presentation/\n^Springwater/\n"
    let document = try SpringwaterParser.parse(text)
    let schema = Schema(requiredRoot: "memo", rules: ["memo": Rule(tag: "memo")])
    let messages = SchemaValidator.validate(document, against: schema).map(\.message)
    #expect(messages.contains { $0.contains("unexpected top-level element <notes>") })
    #expect(!messages.contains { $0.contains("<presentation>") })
    #expect(!messages.contains { $0.contains("<schema>") })
}

@Test func carriedPresentationIsFoundByItsTargetSchema() throws {
    let text = """
    ^Springwater
    ^memo
    ^memo/
    ^presentation
    ^metadata
    ^target_schema
    memo
    ^target_schema/
    ^metadata/
    ^presentation/
    ^Springwater/

    """
    let document = try SpringwaterParser.parse(text)
    let carried = try #require(CarriedDocuments.presentationDocument(in: document, for: "memo"))
    #expect(carried.root.childElements.first?.name == "presentation")
    #expect(CarriedDocuments.presentationDocument(in: document, for: "letter") == nil)
}
