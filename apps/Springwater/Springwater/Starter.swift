import SpringwaterSchema

extension Library.Kind {
    /// The smallest document of this kind, derived from the schema itself.
    ///
    /// It holds every element the schema requires and nothing else. Elements
    /// that need the writer's words are left as one empty line, so the document
    /// is valid Springwater at once and the issue list says what is still to be
    /// filled in. Nothing is invented on the writer's behalf.
    var starterText: String {
        var lines = ["^Springwater"]
        appendElement(root, ancestors: [], to: &lines)
        lines.append("^Springwater/")
        return lines.joined(separator: "\n") + "\n"
    }

    private func appendElement(_ tag: String, ancestors: [String], to lines: inout [String]) {
        lines.append("^\(tag)")
        defer { lines.append("^\(tag)/") }

        // An element nested inside itself would never end. Stop at the repeat.
        guard let rule = schema.rules[tag], !ancestors.contains(tag) else {
            lines.append("")
            return
        }

        var children = rule.mustContain
        if let first = rule.mustContainOneOf.first,
           !children.contains(where: { rule.mustContainOneOf.contains($0) }) {
            children.append(first)
        }
        if let exact = rule.mustContainCount {
            let present = children.count(where: { $0 == exact.tag })
            if present < exact.count {
                children.append(contentsOf: Array(repeating: exact.tag, count: exact.count - present))
            }
        }
        if tag == root, !children.contains("validated_by"), rule.mayContain.contains("validated_by") {
            children.insert("validated_by", at: 0)
        }

        if !children.isEmpty {
            for child in children {
                appendElement(child, ancestors: ancestors + [tag], to: &lines)
            }
        } else if tag == "validated_by" {
            lines.append(reference)
        } else if let value = rule.mustEqual {
            lines.append(value)
        } else if rule.mustBeBoolean {
            lines.append("false")
        } else {
            lines.append("")
        }
    }
}
