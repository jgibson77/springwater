import SpringwaterSyntax

/// Validates a parsed Springwater document against a `Schema`.
///
/// Returns every issue found (empty means valid), rather than throwing on the
/// first — a document can violate a schema in several places at once, and a
/// writer or editor wants the whole list. The four `^validation` severities in
/// a schema are all `error` in practice, so every issue is reported uniformly;
/// `ValidationIssue.category` records which of the four kinds it is.
public enum SchemaValidator {

    public static func validate(
        _ document: SpringwaterDocument,
        against schema: Schema
    ) -> [ValidationIssue] {
        var issues: [ValidationIssue] = []
        let top = document.root.childElements
        let roots = top.filter { $0.name == schema.requiredRoot }
        if roots.isEmpty {
            issues.append(.init(
                category: .missingRequired, tag: schema.requiredRoot,
                message: "missing required root <\(schema.requiredRoot)> at document root"
            ))
        }
        for element in top where element.name != schema.requiredRoot {
            issues.append(.init(
                category: .unknownTag, tag: element.name,
                message: "unexpected top-level element <\(element.name)> (only <\(schema.requiredRoot)> allowed at document root)"
            ))
        }
        for root in roots {
            validate(root, parent: "Springwater", schema: schema, into: &issues)
        }
        return issues
    }

    private static func validate(
        _ element: SpringwaterDocument.Element,
        parent: String,
        schema: Schema,
        into issues: inout [ValidationIssue]
    ) {
        guard let rule = schema.rules[element.name] else {
            issues.append(.init(
                category: .unknownTag, tag: element.name,
                message: "unknown tag <\(element.name)> (no rule) under <\(parent)>"
            ))
            return
        }

        // parent_must_be
        if !rule.parentMustBe.isEmpty, !rule.parentMustBe.contains(parent) {
            issues.append(.init(
                category: .invalidNesting, tag: element.name,
                message: "invalid nesting: <\(element.name)> under <\(parent)>; parent must be one of \(rule.parentMustBe)"
            ))
        }

        let kids = element.childElements
        let kidNames = kids.map(\.name)
        let hasContent = element.children.contains { child in
            if case .content(let line) = child { return !valueTrim(line.text).isEmpty }
            return false
        }

        // text_only
        if rule.textOnly, !kids.isEmpty {
            issues.append(.init(
                category: .invalidNesting, tag: element.name,
                message: "invalid nesting: <\(element.name)> is text_only but contains child elements \(kidNames)"
            ))
        }

        // cannot_be_empty
        if rule.cannotBeEmpty, !hasContent, kids.isEmpty {
            issues.append(.init(
                category: .emptyTag, tag: element.name,
                message: "empty: <\(element.name)> cannot be empty"
            ))
        }

        // must_equal
        if let expected = rule.mustEqual {
            let actual = element.contentValue
            if actual != expected {
                issues.append(.init(
                    category: .mismatch, tag: element.name,
                    message: "<\(element.name)> must equal '\(expected)', got '\(actual)'"
                ))
            }
        }

        // must_be_boolean
        if rule.mustBeBoolean {
            let actual = element.contentValue
            if actual != "true", actual != "false" {
                issues.append(.init(
                    category: .mismatch, tag: element.name,
                    message: "<\(element.name)> must be boolean (true/false), got '\(actual)'"
                ))
            }
        }

        // child membership
        var allowed = Set(rule.mustContain)
        allowed.formUnion(rule.mayContain)
        allowed.formUnion(rule.mustContainOneOf)
        if let count = rule.mustContainCount { allowed.insert(count.tag) }
        for child in kids {
            if rule.cannotContain.contains(child.name) {
                issues.append(.init(
                    category: .invalidNesting, tag: child.name,
                    message: "forbidden child <\(child.name)> in <\(element.name)> (cannot_contain)"
                ))
            } else if !rule.allowsUnknownChildren, !allowed.contains(child.name) {
                issues.append(.init(
                    category: .unknownTag, tag: child.name,
                    message: "disallowed child <\(child.name)> in <\(element.name)> (allowed: \(allowed.sorted()))"
                ))
            }
        }

        // must_contain
        for required in rule.mustContain where !kidNames.contains(required) {
            issues.append(.init(
                category: .missingRequired, tag: element.name,
                message: "missing required child <\(required)> in <\(element.name)>"
            ))
        }

        // must_contain_one_of
        if !rule.mustContainOneOf.isEmpty,
           !kidNames.contains(where: { rule.mustContainOneOf.contains($0) }) {
            issues.append(.init(
                category: .missingRequired, tag: element.name,
                message: "<\(element.name)> must contain one of \(rule.mustContainOneOf)"
            ))
        }

        // must_contain_count
        if let count = rule.mustContainCount {
            let found = kidNames.filter { $0 == count.tag }.count
            if found != count.count {
                issues.append(.init(
                    category: .missingRequired, tag: element.name,
                    message: "<\(element.name)> must contain exactly \(count.count) <\(count.tag)>, found \(found)"
                ))
            }
        }

        // Recurse, unless this is an open container (its subtree is unconstrained).
        if !rule.allowsUnknownChildren {
            for child in kids {
                validate(child, parent: element.name, schema: schema, into: &issues)
            }
        }
    }
}

/// One schema-validation finding.
public struct ValidationIssue: Sendable, Equatable {
    /// Which of the schema's four validation categories this falls under.
    public enum Category: Sendable, Equatable {
        case unknownTag        // unknown_tags
        case invalidNesting    // invalid_nesting
        case missingRequired   // missing_required
        case emptyTag          // empty_tags
        case mismatch          // must_equal / must_be_boolean value mismatch
    }

    public let category: Category
    /// The tag the issue concerns.
    public let tag: String
    /// A human-readable description. Diagnostic aid; the schema defines validity.
    public let message: String

    public init(category: Category, tag: String, message: String) {
        self.category = category
        self.tag = tag
        self.message = message
    }
}

extension Array where Element == ValidationIssue {
    /// True when there are no issues.
    public var isValid: Bool { isEmpty }
}
