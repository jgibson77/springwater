import SpringwaterSyntax

/// Validates a parsed Springwater document against a `Schema`.
///
/// Implements the VALIDATION ALGORITHM of SCHEMA_SPEC.txt, step for step.
///
/// Returns every issue found (empty means valid), rather than throwing on the
/// first: a document can violate a schema in several places at once, and a
/// writer or editor wants the whole list. The order of the issues carries no
/// meaning.
public enum SchemaValidator {

    public static func validate(
        _ document: SpringwaterDocument,
        against schema: Schema
    ) -> [ValidationIssue] {
        var issues: [ValidationIssue] = []
        let top = document.root.childElements
        let roots = top.filter { $0.name == schema.requiredRoot }

        // 1a
        if roots.isEmpty {
            issues.append(.init(
                kind: .missingRoot, element: schema.requiredRoot,
                message: "missing required root <\(schema.requiredRoot)> at document root"
            ))
        }
        // 1b. A document may carry its own schema and presentation beside the
        // work. They are not part of the work and are not judged by its schema.
        for element in top
        where element.name != schema.requiredRoot && !CarriedDocuments.names.contains(element.name) {
            issues.append(.init(
                kind: .unexpectedTop, element: element.name,
                message: "unexpected top-level element <\(element.name)> (only <\(schema.requiredRoot)> allowed at document root)"
            ))
        }
        // 1c
        for root in roots {
            check(root, parent: "Springwater", schema: schema, into: &issues)
        }
        return issues
    }

    private static func check(
        _ element: SpringwaterDocument.Element,
        parent: String,
        schema: Schema,
        into issues: inout [ValidationIssue]
    ) {
        let name = element.name

        // 2a
        guard let rule = schema.rules[name] else {
            issues.append(.init(
                kind: .unknownTag, element: name, other: parent,
                message: "unknown tag <\(name)> (no rule) under <\(parent)>"
            ))
            return
        }

        // 2b
        if !rule.parentMustBe.isEmpty, !rule.parentMustBe.contains(parent) {
            issues.append(.init(
                kind: .wrongParent, element: name, other: parent,
                message: "invalid nesting: <\(name)> under <\(parent)>; parent must be one of \(rule.parentMustBe)"
            ))
        }

        let kids = element.childElements
        let kidNames = kids.map(\.name)

        // 2c
        if rule.textOnly, !kids.isEmpty {
            issues.append(.init(
                kind: .notTextOnly, element: name,
                message: "invalid nesting: <\(name)> is text_only but contains child elements \(kidNames)"
            ))
        }

        // 2d
        if rule.cannotBeEmpty, element.isStructurallyEmpty {
            issues.append(.init(
                kind: .empty, element: name,
                message: "empty: <\(name)> cannot be empty"
            ))
        }

        // 2e
        if let expected = rule.mustEqual {
            let actual = element.contentValue
            if actual != expected {
                issues.append(.init(
                    kind: .notEqual, element: name,
                    message: "<\(name)> must equal '\(expected)', got '\(actual)'"
                ))
            }
        }

        // 2f
        if rule.mustBeBoolean {
            let actual = element.contentValue
            if actual != "true", actual != "false" {
                issues.append(.init(
                    kind: .notBoolean, element: name,
                    message: "<\(name)> must be boolean (true/false), got '\(actual)'"
                ))
            }
        }

        // 2g
        var allowed = Set(rule.mustContain)
        allowed.formUnion(rule.mayContain)
        allowed.formUnion(rule.mustContainOneOf)
        if let count = rule.mustContainCount { allowed.insert(count.tag) }
        for child in kids {
            if rule.cannotContain.contains(child.name) {
                issues.append(.init(
                    kind: .forbiddenChild, element: name, other: child.name,
                    message: "forbidden child <\(child.name)> in <\(name)> (cannot_contain)"
                ))
            } else if !rule.allowsUnknownChildren, !allowed.contains(child.name) {
                issues.append(.init(
                    kind: .childNotAllowed, element: name, other: child.name,
                    message: "disallowed child <\(child.name)> in <\(name)> (allowed: \(allowed.sorted()))"
                ))
            }
        }

        // 2h
        for required in rule.mustContain where !kidNames.contains(required) {
            issues.append(.init(
                kind: .missingChild, element: name, other: required,
                message: "missing required child <\(required)> in <\(name)>"
            ))
        }

        // 2i
        if !rule.mustContainOneOf.isEmpty,
           !kidNames.contains(where: { rule.mustContainOneOf.contains($0) }) {
            issues.append(.init(
                kind: .missingOneOf, element: name,
                message: "<\(name)> must contain one of \(rule.mustContainOneOf)"
            ))
        }

        // 2j
        if let count = rule.mustContainCount {
            let found = kidNames.filter { $0 == count.tag }.count
            if found != count.count {
                issues.append(.init(
                    kind: .wrongCount, element: name, other: count.tag,
                    message: "<\(name)> must contain exactly \(count.count) <\(count.tag)>, found \(found)"
                ))
            }
        }

        // 2k. An open element's descendants are not checked at all.
        if !rule.allowsUnknownChildren {
            for child in kids {
                check(child, parent: name, schema: schema, into: &issues)
            }
        }
    }
}

/// One schema-validation finding, as SCHEMA_SPEC.txt defines it.
public struct ValidationIssue: Sendable, Equatable {

    /// What kind of issue this is. The raw value is the name the
    /// specification gives it.
    public enum Kind: String, Sendable, Equatable, CaseIterable {
        case missingRoot = "missing_root"
        case unexpectedTop = "unexpected_top"
        case unknownTag = "unknown_tag"
        case wrongParent = "wrong_parent"
        case notTextOnly = "not_text_only"
        case empty = "empty"
        case notEqual = "not_equal"
        case notBoolean = "not_boolean"
        case forbiddenChild = "forbidden_child"
        case childNotAllowed = "child_not_allowed"
        case missingChild = "missing_child"
        case missingOneOf = "missing_one_of"
        case wrongCount = "wrong_count"
    }

    /// The four categories a schema names in its `validation` element, and
    /// `mismatch`, which the specification adds for values.
    public enum Category: Sendable, Equatable {
        case unknownTag        // unknown_tags
        case invalidNesting    // invalid_nesting
        case missingRequired   // missing_required
        case emptyTag          // empty_tags
        case mismatch          // a value that is not what the rule requires
    }

    public let kind: Kind
    /// The tag name the issue is about: the ELEMENT part.
    public let element: String
    /// A second tag name, for the kinds that have one: the OTHER part.
    public let other: String?
    /// A description for a person. Its wording is not specified.
    public let message: String

    public init(kind: Kind, element: String, other: String? = nil, message: String) {
        self.kind = kind
        self.element = element
        self.other = other
        self.message = message
    }

    public var category: Category {
        switch kind {
        case .missingRoot, .missingChild, .missingOneOf, .wrongCount: .missingRequired
        case .unexpectedTop, .unknownTag, .childNotAllowed: .unknownTag
        case .wrongParent, .notTextOnly, .forbiddenChild: .invalidNesting
        case .empty: .emptyTag
        case .notEqual, .notBoolean: .mismatch
        }
    }

    /// The tag a reader would look for: the child for the two kinds that are
    /// about a child in the wrong place, the element otherwise.
    public var tag: String {
        switch kind {
        case .forbiddenChild, .childNotAllowed: other ?? element
        default: element
        }
    }
}

extension Array where Element == ValidationIssue {
    /// True when there are no issues.
    public var isValid: Bool { isEmpty }
}
