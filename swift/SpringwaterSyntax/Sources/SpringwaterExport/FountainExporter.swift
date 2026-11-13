import SpringwaterSyntax

/// Exports a Springwater document to Fountain.
///
/// A one-way projection: it walks the document tree and emits valid Fountain,
/// inserting the forced markers (`!`, `@`, `.`, `>`) and escaping the emphasis
/// characters (`*`, `_`) so a Fountain reader interprets each element as intended.
/// Depends only on `SpringwaterSyntax`.
///
/// Fountain is an output format, not a lossless interchange: some schema-valid
/// content has no Fountain representation. Canonical Springwater is the
/// preservation form; no Fountain importer ships with this package.
public enum FountainExporter {

    static let romanAct: [String: String] = ["act1": "I", "act2": "II", "act3": "III"]

    /// The full Fountain text for a document.
    public static func export(_ document: SpringwaterDocument) -> String {
        var blocks: [String] = []
        guard let screenplay = document.root.exportChildElements.first else { return "\n" }
        for el in screenplay.exportChildElements {
            switch el.name {
            case "metadata":
                blocks.append(titlePageBlock(el))
            case "act1", "act2", "act3":
                blocks.append("# ACT " + (romanAct[el.name] ?? "I"))
                for child in el.exportChildElements { emit(child, into: &blocks) }
            default:
                emit(el, into: &blocks)
            }
        }
        return blocks.joined(separator: "\n\n") + "\n"
    }

    // MARK: - Blocks

    static func titlePageBlock(_ tp: SpringwaterDocument.Element) -> String {
        var lines: [String] = []
        let fields: [(String, String)] = [
            ("title", "Title"), ("written_by", "Credit"), ("author", "Author"),
            ("based_on", "Source"), ("revision", "Revision"), ("date", "Draft date")
        ]
        let byName = Dictionary(tp.exportChildElements.map { ($0.name, $0) }, uniquingKeysWith: { a, _ in a })
        for (key, label) in fields {
            if let el = byName[key] { lines.append("\(label): \(esc(el.exportScalar))") }
        }
        if let contact = byName["contact"] {
            lines.append("Contact:")
            for c in contact.exportContentLines { lines.append("    " + esc(c.trimmedEnds)) }
        }
        return lines.joined(separator: "\n")
    }

    static func emit(_ el: SpringwaterDocument.Element, into blocks: inout [String], dualSecond: Bool = false, seqDepth: Int = 1) {
        switch el.name {
        case "sequence":
            let label = el.exportChildElements.first { $0.name == "label" }?.exportScalar ?? ""
            let marker = String(repeating: "#", count: seqDepth + 1)   // depth 1 → ##, 2 → ###
            blocks.append(marker + (label.isEmpty ? "" : " " + esc(label)))
            for child in el.exportChildElements where child.name != "label" {
                emit(child, into: &blocks, seqDepth: seqDepth + 1)
            }
        case "scene":
            blocks.append(sceneHeading(el))
            for child in el.exportChildElements where child.name != "slugline" && child.name != "number" {
                emit(child, into: &blocks)
            }
        case "action":
            blocks.append(actionBlock(el.exportContent))
        case "dialogue":
            blocks.append(dialogueBlock(el, dualSecond: dualSecond))
        case "dual_dialogue":
            let ds = el.exportChildElements
            for (i, d) in ds.enumerated() { emit(d, into: &blocks, dualSecond: i == 1) }
        case "transition":
            blocks.append(transitionBlock(el.exportScalar))
        default:
            let t = el.exportContent
            if !t.isEmpty { blocks.append(actionBlock(t)) }
        }
    }

    static func sceneHeading(_ scene: SpringwaterDocument.Element) -> String {
        let slug = scene.exportChildElements.first { $0.name == "slugline" }?.exportScalar ?? ""
        let number = scene.exportChildElements.first { $0.name == "number" }?.exportScalar
        var head = isSceneHeading(slug) ? esc(slug) : "." + esc(slug)
        if let number, !number.isEmpty { head += " #\(number)#" }
        return head
    }

    static func actionBlock(_ text: String) -> String {
        var lines = esc(text).components(separatedBy: "\n")
        let first = lines.first ?? ""
        let t = trimST(first)
        let multi = lines.count >= 2
        let firstChar = t.first.map(String.init) ?? ""
        let need = isSceneHeading(t)
            || (looksLikeCue(first) && multi)
            || isAutoTransition(t)
            || ["!", "@", "~", "=", "#", ">", "."].contains(firstChar)
        if need, !lines.isEmpty { lines[0] = "!" + lines[0] }
        return lines.joined(separator: "\n")
    }

    static func dialogueBlock(_ d: SpringwaterDocument.Element, dualSecond: Bool) -> String {
        var out: [String] = []
        var character = ""; var ext = ""
        var body: [String] = []
        for c in d.exportChildElements {
            switch c.name {
            case "character": character = c.exportScalar
            case "extension": ext = c.exportScalar
            case "parenthetical": body.append(esc(c.exportScalar))
            case "lines": body.append(esc(c.exportContent))
            default: break
            }
        }
        let letters = character.filter { $0.isLetter }
        var cue = (!letters.isEmpty && letters.allSatisfy { $0.isUppercase }) ? character : "@" + character
        if !ext.isEmpty { cue += " " + ext }
        if dualSecond { cue += " ^" }
        out.append(cue)
        out.append(contentsOf: body)
        return out.joined(separator: "\n")
    }

    static func transitionBlock(_ text: String) -> String {
        isAutoTransition(trimST(text)) ? esc(text) : ">" + esc(text)
    }

    // MARK: - Helpers

    static func esc(_ s: String) -> String {
        s.replacingOccurrences(of: "*", with: "\\*").replacingOccurrences(of: "_", with: "\\_")
    }

    static func trimST(_ s: String) -> String {
        var sub = Substring(s)
        while let f = sub.first, f == " " || f == "\t" { sub = sub.dropFirst() }
        while let l = sub.last, l == " " || l == "\t" { sub = sub.dropLast() }
        return String(sub)
    }

    static func isSceneHeading(_ line: String) -> Bool {
        let u = line.uppercased()
        for p in ["INT", "EXT", "EST"] where u.hasPrefix(p) {
            let after = u.dropFirst(p.count).first
            if after == "." || after == " " || after == "\t" || after == "/" { return true }
        }
        if u.hasPrefix("I/E") { return true }
        if line.hasPrefix("."), let second = line.dropFirst().first, second != ".", second != " " {
            return true
        }
        return false
    }

    /// Mirrors `^[A-Z0-9 ]+TO:\s*$`: an all-caps line ending in "TO:".
    static func isAutoTransition(_ t: String) -> Bool {
        guard t.hasSuffix("TO:"), t.count > 3 else { return false }
        return t.allSatisfy { $0.isUppercase || $0.isNumber || $0 == " " || $0 == ":" }
    }

    static func looksLikeCue(_ line: String) -> Bool {
        var t = trimST(line)
        if t.hasSuffix(")"), let open = t.lastIndex(of: "(") {
            t = trimST(String(t[..<open]))
        }
        if t.hasSuffix("^") { t = trimST(String(t.dropLast())) }
        let letters = t.filter { $0.isLetter }
        return !letters.isEmpty && letters.allSatisfy { $0.isUppercase }
    }
}

// MARK: - Element helpers (module-local)

extension SpringwaterDocument.Element {
    var exportChildElements: [SpringwaterDocument.Element] {
        children.compactMap { if case .element(let e) = $0 { e } else { nil } }
    }
    var exportContentLines: [String] {
        children.compactMap { if case .content(let l) = $0 { l.text } else { nil } }
    }
    /// Content with surrounding blank lines trimmed only (internal newlines and
    /// leading spaces preserved).
    var exportContent: String {
        var s = Substring(exportContentLines.joined(separator: "\n"))
        while s.first == "\n" { s = s.dropFirst() }
        while s.last == "\n" { s = s.dropLast() }
        return String(s)
    }
    /// Content fully trimmed — a scalar field value.
    var exportScalar: String {
        let ws: Set<Character> = [" ", "\t", "\r", "\n"]
        var s = Substring(exportContentLines.joined(separator: "\n"))
        while let f = s.first, ws.contains(f) { s = s.dropFirst() }
        while let l = s.last, ws.contains(l) { s = s.dropLast() }
        return String(s)
    }
}

extension String {
    var trimmedEnds: String {
        let ws: Set<Character> = [" ", "\t", "\r", "\n"]
        var s = Substring(self)
        while let f = s.first, ws.contains(f) { s = s.dropFirst() }
        while let l = s.last, ws.contains(l) { s = s.dropLast() }
        return String(s)
    }
}
