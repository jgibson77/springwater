import Testing
import Foundation
import SpringwaterSyntax
@testable import SpringwaterSchema

// Validates the repository's own canon as an integration test:
//   1. every schema in schemas/ conforms to the meta-schema, and
//   2. every document in examples/ and profiles/ validates against the schema
//      whose required_root it uses.
//
// It reads the real repository files rather than copied fixtures, so there is a
// single source of truth. That couples the suite to the package living at
// <repo>/swift/SpringwaterSyntax; the files are located relative to this
// source file via #filePath. When the package is built outside the repository
// (no schemas/ directory above it), the suite is skipped, not failed.

private let repoRoot: URL = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()   // SpringwaterSchemaTests/
    .deletingLastPathComponent()   // Tests/
    .deletingLastPathComponent()   // SpringwaterSyntax/
    .deletingLastPathComponent()   // swift/
    .deletingLastPathComponent()   // <repo root>

private let schemasDir = repoRoot.appendingPathComponent("schemas")
private let examplesDir = repoRoot.appendingPathComponent("examples")
private let profilesDir = repoRoot.appendingPathComponent("profiles")

private let repositoryAvailable: Bool =
    FileManager.default.fileExists(atPath: schemasDir.path)

private func springwaterFiles(in directory: URL) throws -> [URL] {
    guard FileManager.default.fileExists(atPath: directory.path) else { return [] }
    return try FileManager.default
        .contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        .filter { $0.pathExtension == "springwater" }
        .sorted { $0.lastPathComponent < $1.lastPathComponent }
}

private func parseFile(_ url: URL) throws -> SpringwaterDocument {
    try SpringwaterParser.parse(try Data(contentsOf: url))
}

private func rootChildName(_ document: SpringwaterDocument) -> String? {
    document.root.childElements.first?.name
}

@Suite(.enabled(if: repositoryAvailable))
struct RepositoryConformance {

    /// The meta-schema plus all five document schemas must each conform to the
    /// meta-schema. (The meta-schema is self-validating — it is just another
    /// schema, checked against itself.)
    @Test func everySchemaConformsToTheMetaSchema() throws {
        let meta = try Schema(parsing: parseFile(schemasDir.appendingPathComponent("schema.schema.springwater")))

        let schemaFiles = try springwaterFiles(in: schemasDir)
        #expect(!schemaFiles.isEmpty, "no schema files found under \(schemasDir.path)")

        for file in schemaFiles {
            let issues = SchemaValidator.validate(try parseFile(file), against: meta)
            #expect(issues.isValid,
                    "\(file.lastPathComponent) does not conform to the meta-schema: \(issues.map(\.message))")
        }
    }

    /// Every example document and authoring profile must validate against the
    /// schema whose `required_root` matches the document's root element.
    @Test func everyDocumentValidatesAgainstItsSchema() throws {
        // Map required_root -> schema for every non-meta schema.
        var byRoot: [String: (name: String, schema: Schema)] = [:]
        for file in try springwaterFiles(in: schemasDir)
        where file.lastPathComponent != "schema.schema.springwater" {
            let schema = try Schema(parsing: parseFile(file))
            byRoot[schema.requiredRoot] = (file.lastPathComponent, schema)
        }
        #expect(!byRoot.isEmpty, "no document schemas found")

        let documents = try springwaterFiles(in: examplesDir) + springwaterFiles(in: profilesDir)
        #expect(!documents.isEmpty, "no example/profile documents found")

        for file in documents {
            let document = try parseFile(file)
            guard let root = rootChildName(document) else {
                Issue.record("\(file.lastPathComponent) has no root element")
                continue
            }
            guard let mapped = byRoot[root] else {
                Issue.record("\(file.lastPathComponent): no schema with required_root <\(root)>")
                continue
            }
            let issues = SchemaValidator.validate(document, against: mapped.schema)
            #expect(issues.isValid,
                    "\(file.lastPathComponent) is invalid against \(mapped.name): \(issues.map(\.message))")
        }
    }
}
