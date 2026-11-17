import Testing
import Foundation
import SpringwaterSyntax
@testable import SpringwaterSchema

// Runs tools/schema_conformance_vectors.json: the cases every validator must
// agree on, written by hand from SCHEMA_SPEC.txt.

private let vectorsURL: URL = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()   // SpringwaterSchemaTests/
    .deletingLastPathComponent()   // Tests/
    .deletingLastPathComponent()   // SpringwaterSyntax/
    .deletingLastPathComponent()   // swift/
    .deletingLastPathComponent()   // <repo root>
    .appendingPathComponent("tools/schema_conformance_vectors.json")

private let vectorsAvailable: Bool = FileManager.default.fileExists(atPath: vectorsURL.path)

/// One issue as "kind|element|other", for comparing as a sorted list.
private func key(kind: String, element: String, other: String?) -> String {
    "\(kind)|\(element)|\(other ?? "")"
}

@Suite(.enabled(if: vectorsAvailable))
struct SchemaConformanceVectors {

    @Test func everyVectorAgrees() throws {
        let json = try JSONSerialization.jsonObject(with: Data(contentsOf: vectorsURL))
        let file = try #require(json as? [String: Any])
        let vectors = try #require(file["vectors"] as? [[String: Any]])
        #expect(vectors.count >= 72)

        for vector in vectors {
            let name = try #require(vector["name"] as? String)
            let schemaText = try #require(vector["schema"] as? String)
            let documentText = try #require(vector["document"] as? String)
            let expect = try #require(vector["expect"] as? [String: Any])

            let schemaDocument = try SpringwaterParser.parse(schemaText)
            let document = try SpringwaterParser.parse(documentText)

            if expect["unusable_schema"] as? Bool == true {
                #expect(throws: SchemaError.self, "\(name): the schema should be unusable") {
                    _ = try Schema(parsing: schemaDocument)
                }
                continue
            }

            let wanted = try #require(expect["issues"] as? [[String: Any]])
            let want = wanted.map {
                key(kind: $0["kind"] as? String ?? "", element: $0["element"] as? String ?? "",
                    other: $0["other"] as? String)
            }.sorted()

            let schema = try Schema(parsing: schemaDocument)
            let got = SchemaValidator.validate(document, against: schema).map {
                key(kind: $0.kind.rawValue, element: $0.element, other: $0.other)
            }.sorted()

            #expect(got == want, "\(name)")
        }
    }
}
