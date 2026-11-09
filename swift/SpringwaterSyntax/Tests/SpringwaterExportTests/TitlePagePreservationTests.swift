import Foundation
import Testing
import SpringwaterSyntax
import SpringwaterSchema
import SpringwaterExport

private let repositoryRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent()
    .deletingLastPathComponent().deletingLastPathComponent()
    .deletingLastPathComponent()
private let schemaURL = repositoryRoot.appendingPathComponent("schemas/screenplay.schema.springwater")

// Like RepositoryConformance, these tests use the real schema, not a copied
// approximation. Skip only when the package is distributed outside its repo.
@Suite(.enabled(if: FileManager.default.fileExists(atPath: schemaURL.path)))
struct TitlePagePreservationTests {
    private func document(field: String, value: String) throws -> SpringwaterDocument {
        let source = """
        ^Springwater
        ^screenplay
        ^title_page
        ^title
        PRESERVATION AUDIT
        ^title/
        ^\(field)
        \(value)
        ^\(field)/
        ^title_page/
        ^act1
        ^scene
        ^slugline
        INT. ARCHIVE - DAY
        ^slugline/
        ^action
        A document waits.
        ^action/
        ^scene/
        ^act1/
        ^screenplay/
        ^Springwater/
        """
        return try SpringwaterParser.parse(source)
    }

    private func validatedExport(field: String, value: String) throws -> String {
        let input = try document(field: field, value: value)
        let schema = try Schema(parsing: SpringwaterParser.parse(Data(contentsOf: schemaURL)))
        let issues = SchemaValidator.validate(input, against: schema)
        try #require(issues.isValid, "The reproduction must be schema-valid: \(issues.map(\.message))")
        let canonical = SpringwaterSerializer.serialize(input)
        #expect(canonical.contains("^\(field)\n\(value)\n^\(field)/"))
        #expect(try SpringwaterParser.parse(canonical) == input)
        let output = FountainExporter.export(input)
        #expect(output.contains("Title: PRESERVATION AUDIT"))
        #expect(output.contains("INT. ARCHIVE - DAY"))
        #expect(output.contains("A document waits."))
        return output
    }

    @Test func authorContentSurvivesExport() throws {
        let value = "Ada Preservation Sentinel"
        let output = try validatedExport(field: "author", value: value)
        // title_page.author now maps to the Fountain Author key (written_by -> Credit).
        #expect(output.contains("Author: \(value)"))
    }

    @Test func revisionContentSurvivesExport() throws {
        let value = "Blue Revision Sentinel 2026"
        let output = try validatedExport(field: "revision", value: value)
        #expect(output.contains("Revision: \(value)"))
    }
}
