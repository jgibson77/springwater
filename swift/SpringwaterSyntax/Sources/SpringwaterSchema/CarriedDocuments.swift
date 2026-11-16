import SpringwaterSyntax

/// Reads the schema and presentation a document carries inside itself.
///
/// A self-contained document holds, beside its work, the schema that says
/// what the work is and optionally the presentation that says how it looks,
/// as further top-level elements (see CONVENTIONS.md, "Self-contained
/// documents"). A schema and a presentation are Springwater, so carrying them
/// needs nothing new: their tags are ordinary tags.
///
/// Nothing here decides whether a carried schema is a good one. A carried
/// schema is a document like any other and can be validated against the
/// schema for schemas, which a document may also carry.
public enum CarriedDocuments {

    /// The element names a document may carry at its top level beside the work.
    public static let names: Set<String> = ["schema", "presentation"]

    /// The name of the document's work: its first top-level element.
    public static func workName(of document: SpringwaterDocument) -> String? {
        document.root.childElements.first?.name
    }

    /// The schema the document carries for elements named `name`, as a
    /// document of its own: the first top-level `schema` whose
    /// `required_root` is `name`. Nil when it carries none.
    public static func schemaDocument(
        in document: SpringwaterDocument,
        for name: String
    ) -> SpringwaterDocument? {
        let element = document.root.childElements.first { element in
            element.name == "schema" && element.childElements.contains {
                $0.name == "required_root" && $0.contentValue == name
            }
        }
        return element.map(standalone)
    }

    /// The presentation the document carries for elements named `name`, as a
    /// document of its own: the first top-level `presentation` whose
    /// `target_schema` is `name`. Nil when it carries none.
    public static func presentationDocument(
        in document: SpringwaterDocument,
        for name: String
    ) -> SpringwaterDocument? {
        let element = document.root.childElements.first { element in
            element.name == "presentation" && element.childElements.contains { metadata in
                metadata.name == "metadata" && metadata.childElements.contains {
                    $0.name == "target_schema" && $0.contentValue == name
                }
            }
        }
        return element.map(standalone)
    }

    /// The schema the document carries for its own work. Nil when it carries
    /// none, or when the carried schema cannot be read as a schema.
    public static func schema(in document: SpringwaterDocument) -> Schema? {
        guard let name = workName(of: document),
              let carried = schemaDocument(in: document, for: name) else { return nil }
        return try? Schema(parsing: carried)
    }

    /// Wraps one element in a document root, so it can be handed to anything
    /// that reads a whole document.
    private static func standalone(_ element: SpringwaterDocument.Element) -> SpringwaterDocument {
        SpringwaterDocument(root: .init(name: "Springwater", children: [.element(element)]))
    }
}
