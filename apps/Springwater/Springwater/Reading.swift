import SpringwaterSchema
import SpringwaterSyntax

/// What the app understands about a document's text at one moment.
///
/// There are two separate questions. Is it Springwater? That is decided by
/// the seven rules alone. Is it a valid document of its kind? That is decided
/// by a schema, if the app has one for the document's root element.
struct Reading {
    enum Syntax {
        case valid(SpringwaterDocument)
        case invalid(SpringwaterError)
    }

    enum Kind {
        /// The document has no top-level element, so it has no kind.
        case none
        /// The app has no schema for this root element.
        case unknown(root: String)
        /// The document was checked against the schema for this root element.
        case checked(root: String, issues: [ValidationIssue])
    }

    let syntax: Syntax
    let kind: Kind

    /// True when the document was checked against a schema it carries inside
    /// itself, not one that ships with the app.
    let usesCarriedSchema: Bool

    /// The schema the document was checked against, when there is one.
    let schema: Schema?

    init(text: String, library: Library) {
        let document: SpringwaterDocument
        do {
            document = try SpringwaterParser.parse(text)
        } catch {
            syntax = .invalid(error)
            kind = .none
            usesCarriedSchema = false
            schema = nil
            return
        }
        syntax = .valid(document)

        guard let root = CarriedDocuments.workName(of: document) else {
            kind = .none
            usesCarriedSchema = false
            schema = nil
            return
        }
        // A document's own schema speaks for it. The app's schemas are for
        // documents that carry none.
        let carried = CarriedDocuments.schema(in: document)
        usesCarriedSchema = carried != nil
        schema = carried ?? library.kinds[root]?.schema
        guard let schema else {
            kind = .unknown(root: root)
            return
        }
        kind = .checked(root: root, issues: SchemaValidator.validate(document, against: schema))
    }

    var document: SpringwaterDocument? {
        if case .valid(let document) = syntax { document } else { nil }
    }

    /// The root element name, when the document has one.
    var root: String? {
        switch kind {
        case .none: nil
        case .unknown(let root), .checked(let root, _): root
        }
    }

    var issues: [ValidationIssue] {
        if case .checked(_, let issues) = kind { issues } else { [] }
    }

    var hasProblems: Bool {
        if case .invalid = syntax { return true }
        return !issues.isEmpty
    }
}
