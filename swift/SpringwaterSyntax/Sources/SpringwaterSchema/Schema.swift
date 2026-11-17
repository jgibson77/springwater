import SpringwaterSyntax

/// A Springwater schema: the structural law for one document type.
///
/// A schema is itself a Springwater document (root element `schema`). This
/// type is the parsed rule model built from such a document. The meta-schema
/// (`schema.schema.springwater`) is just another schema, and a schema file is
/// just another document, so `SchemaValidator` checks "schema conforms to the
/// meta-schema" and "document conforms to its schema" with the same code.
public struct Schema: Sendable, Equatable {

    /// The tag name the document's single top-level element must have.
    public let requiredRoot: String

    /// Rules keyed by the tag name each governs.
    public let rules: [String: Rule]

    public init(requiredRoot: String, rules: [String: Rule]) {
        self.requiredRoot = requiredRoot
        self.rules = rules
    }

    /// Builds a schema model from a parsed schema document.
    ///
    /// Lenient by design: it reads the rules that are present. Whether the
    /// schema document is itself well-formed is a separate question, answered
    /// by validating it against the meta-schema with `SchemaValidator`.
    public init(parsing document: SpringwaterDocument) throws(SchemaError) {
        guard let schemaElement = document.root.childElements.first(where: { $0.name == "schema" }) else {
            throw .noSchemaRoot
        }
        var requiredRoot: String?
        var rules: [String: Rule] = [:]
        for child in schemaElement.childElements {
            switch child.name {
            case "required_root":
                requiredRoot = child.contentValue
            case "structure_rules":
                for ruleElement in child.childElements where ruleElement.name == "rule" {
                    if let rule = Rule(parsing: ruleElement) {
                        rules[rule.tag] = rule
                    }
                }
            default:
                break
            }
        }
        guard let root = requiredRoot, !root.isEmpty else {
            throw .missingRequiredRoot
        }
        self.requiredRoot = root
        self.rules = rules
    }
}

/// One structural rule, governing elements of a single tag name.
public struct Rule: Sendable, Equatable {
    public var tag: String
    public var mustContain: [String]
    public var mayContain: [String]
    public var cannotContain: [String]
    public var mustContainOneOf: [String]
    public var mustContainCount: CountConstraint?
    public var parentMustBe: [String]
    public var cannotBeEmpty: Bool
    public var textOnly: Bool
    public var mustEqual: String?
    public var mustBeBoolean: Bool
    public var allowsUnknownChildren: Bool
    /// Child names that may appear at most once.
    public var atMostOne: [String]
    /// Child names that, when present, come before every other child element
    /// and in this order.
    public var startsWith: [String]

    public init(
        tag: String,
        mustContain: [String] = [], mayContain: [String] = [],
        cannotContain: [String] = [], mustContainOneOf: [String] = [],
        mustContainCount: CountConstraint? = nil, parentMustBe: [String] = [],
        cannotBeEmpty: Bool = false, textOnly: Bool = false,
        mustEqual: String? = nil, mustBeBoolean: Bool = false,
        allowsUnknownChildren: Bool = false,
        atMostOne: [String] = [], startsWith: [String] = []
    ) {
        self.tag = tag
        self.mustContain = mustContain; self.mayContain = mayContain
        self.cannotContain = cannotContain; self.mustContainOneOf = mustContainOneOf
        self.mustContainCount = mustContainCount; self.parentMustBe = parentMustBe
        self.cannotBeEmpty = cannotBeEmpty; self.textOnly = textOnly
        self.mustEqual = mustEqual; self.mustBeBoolean = mustBeBoolean
        self.allowsUnknownChildren = allowsUnknownChildren
        self.atMostOne = atMostOne; self.startsWith = startsWith
    }

    /// An exact-count constraint: the element must contain exactly `count`
    /// child elements named `tag` (e.g. dual_dialogue → "dialogue, 2").
    public struct CountConstraint: Sendable, Equatable {
        public let tag: String
        public let count: Int
        public init(tag: String, count: Int) { self.tag = tag; self.count = count }
    }

    /// Builds a rule from a `^rule` element. Returns nil if it has no `^tag`.
    init?(parsing ruleElement: SpringwaterDocument.Element) {
        var tag: String?
        var r = Rule(tag: "")
        for p in ruleElement.childElements {
            let value = p.contentValue
            switch p.name {
            case "tag": tag = value
            case "must_contain": r.mustContain = Schema.csv(value)
            case "may_contain": r.mayContain = Schema.csv(value)
            case "cannot_contain": r.cannotContain = Schema.csv(value)
            case "must_contain_one_of": r.mustContainOneOf = Schema.csv(value)
            case "must_contain_count":
                let parts = Schema.csv(value)
                // One or more of the digits 0 to 9, and nothing else: no sign.
                if parts.count == 2, !parts[1].isEmpty,
                   parts[1].unicodeScalars.allSatisfy({ ("0"..."9").contains($0) }),
                   let n = Int(parts[1]) {
                    r.mustContainCount = CountConstraint(tag: parts[0], count: n)
                }
            case "parent_must_be": r.parentMustBe = Schema.csv(value)
            case "at_most_one": r.atMostOne = Schema.csv(value)
            case "starts_with": r.startsWith = Schema.csv(value)
            case "cannot_be_empty": r.cannotBeEmpty = (value == "true")
            case "text_only": r.textOnly = (value == "true")
            case "must_equal": r.mustEqual = value
            case "must_be_boolean": r.mustBeBoolean = (value == "true")
            case "allows_unknown_children": r.allowsUnknownChildren = (value == "true")
            default: break
            }
        }
        guard let tag, !tag.isEmpty else { return nil }
        r.tag = tag
        self = r
    }
}

/// Failure building a `Schema` from a document.
public enum SchemaError: Error, Sendable, Equatable {
    /// The document has no top-level `^schema` element.
    case noSchemaRoot
    /// The schema has no non-empty `^required_root`.
    case missingRequiredRoot
}

// MARK: - Shared helpers

extension Schema {
    /// Splits a comma-separated predicate value, trimming and dropping empties.
    static func csv(_ text: String) -> [String] {
        text.split(separator: ",").map { valueTrim(String($0)) }.filter { !$0.isEmpty }
    }
}

extension SpringwaterDocument.Element {
    /// The element's child elements, in order.
    var childElements: [SpringwaterDocument.Element] {
        children.compactMap { if case .element(let e) = $0 { e } else { nil } }
    }

    /// The element's content lines joined and trimmed — its scalar value, as a
    /// schema predicate or field. Whitespace (incl. newlines) is trimmed from
    /// the ends; interior content is kept.
    var contentValue: String {
        let text = children.compactMap { child -> String? in
            if case .content(let line) = child { line.text } else { nil }
        }.joined(separator: "\n")
        return valueTrim(text)
    }

    /// True when the element has no non-empty content and no child elements.
    var isStructurallyEmpty: Bool {
        if !childElements.isEmpty { return false }
        return !children.contains { child in
            if case .content(let line) = child { return !valueTrim(line.text).isEmpty }
            return false
        }
    }
}

/// Removes leading and trailing schema whitespace: space, tab, and line feed,
/// and nothing else (SCHEMA_SPEC.txt, TERMS). A no-break space is kept.
func valueTrim(_ s: String) -> String {
    var scalars = Substring(s).unicodeScalars
    let ws: Set<Unicode.Scalar> = [" ", "\t", "\n"]
    while let f = scalars.first, ws.contains(f) { scalars = scalars.dropFirst() }
    while let l = scalars.last, ws.contains(l) { scalars = scalars.dropLast() }
    return String(scalars)
}
