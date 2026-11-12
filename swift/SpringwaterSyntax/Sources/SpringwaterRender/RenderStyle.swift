import SpringwaterSyntax

/// The rendering style for one tag, read from a presentation's `^rendering_rules`.
///
/// A presentation is a Springwater document; its `^rendering_rules` block maps each
/// tag to presentation properties (indent, spacing, alignment, transform,
/// …). `SpringwaterRender` reads those properties and nothing about validity,
/// so it depends only on `SpringwaterSyntax`.
public struct RenderStyle: Sendable, Equatable {
    public var transform: String?        // "uppercase"
    public var indent: String?           // e.g. "3.7in"
    public var textIndent: String?       // first-line indentation (CSS length)
    public var lineHeight: String?       // unitless line-height multiplier
    public var maxWidth: String?         // e.g. "3.5in"
    public var fontWeight: String?       // "regular" | "bold"
    public var fontStyle: String?        // "italic" | "regular"
    public var align: String?            // "left" | "center" | "right"
    public var spacingBefore: String?    // e.g. "2 lines"
    public var spacingAfter: String?     // e.g. "1 line"
    public var pageBreakBefore: Bool
    public var pageBreakAfter: Bool
    public var content: String?          // literal label (montage/intercut/markers)
    public var hidden: Bool              // held in the document, not rendered

    public init(
        transform: String? = nil, indent: String? = nil, textIndent: String? = nil,
        lineHeight: String? = nil, maxWidth: String? = nil,
        fontWeight: String? = nil, fontStyle: String? = nil, align: String? = nil,
        spacingBefore: String? = nil, spacingAfter: String? = nil,
        pageBreakBefore: Bool = false, pageBreakAfter: Bool = false,
        content: String? = nil, hidden: Bool = false
    ) {
        self.transform = transform; self.indent = indent; self.maxWidth = maxWidth
        self.textIndent = textIndent; self.lineHeight = lineHeight
        self.fontWeight = fontWeight; self.fontStyle = fontStyle; self.align = align
        self.spacingBefore = spacingBefore; self.spacingAfter = spacingAfter
        self.pageBreakBefore = pageBreakBefore; self.pageBreakAfter = pageBreakAfter
        self.content = content; self.hidden = hidden
    }

    /// True when no property is set (renders to an empty CSS rule body).
    public var isEmpty: Bool {
        transform == nil && indent == nil && textIndent == nil && lineHeight == nil && maxWidth == nil && fontWeight == nil
            && fontStyle == nil && align == nil && spacingBefore == nil
            && spacingAfter == nil && !pageBreakBefore && !pageBreakAfter && content == nil
    }
}

/// The render styles for a document type: tag → `RenderStyle`, built from a
/// parsed presentation document's `^rendering_rules`.
public struct RenderStyles: Sendable, Equatable {
    public let styles: [String: RenderStyle]

    public init(styles: [String: RenderStyle]) { self.styles = styles }

    /// Reads `^presentation` → `^rendering_rules` → `^render` blocks from a presentation
    /// document. Lenient: it takes the rules that are present.
    public init(parsing presentationDocument: SpringwaterDocument) {
        var out: [String: RenderStyle] = [:]
        let presentationEl = presentationDocument.root.renderChildElements.first { $0.name == "presentation" }
        let rr = presentationEl?.renderChildElements.first { $0.name == "rendering_rules" }
        for render in rr?.renderChildElements ?? [] where render.name == "render" {
            var tag: String?
            var style = RenderStyle()
            for p in render.renderChildElements {
                let v = p.scalarValue
                switch p.name {
                case "tag": tag = v
                case "transform": style.transform = v
                case "indent": style.indent = v
                case "text_indent": style.textIndent = v
                case "line_height": style.lineHeight = v
                case "max_width": style.maxWidth = v
                case "font_weight": style.fontWeight = v
                case "font_style": style.fontStyle = v
                case "align": style.align = v
                case "spacing_before": style.spacingBefore = v
                case "spacing_after": style.spacingAfter = v
                case "page_break_before": style.pageBreakBefore = (v == "true")
                case "page_break_after": style.pageBreakAfter = (v == "true")
                case "content": style.content = v
                case "hidden": style.hidden = (v == "true")
                default: break
                }
            }
            if let tag { out[tag] = style }
        }
        self.styles = out
    }

    public subscript(_ tag: String) -> RenderStyle? { styles[tag] }
}

// MARK: - Element helpers (module-local; render depends only on SpringwaterSyntax)

extension SpringwaterDocument.Element {
    var renderChildElements: [SpringwaterDocument.Element] {
        children.compactMap { if case .element(let e) = $0 { e } else { nil } }
    }

    /// Content lines joined with LF, with only surrounding blank lines trimmed —
    /// internal newlines and leading spaces are preserved (Springwater content
    /// preservation), which matters for multi-line dialogue and indented notices.
    var renderContent: String {
        let text = children.compactMap { child -> String? in
            if case .content(let line) = child { line.text } else { nil }
        }.joined(separator: "\n")
        return trimNewlinesOnly(text)
    }

    /// A single scalar value: content joined and fully trimmed — for presentation
    /// property values such as "3.7in" or "uppercase".
    var scalarValue: String {
        let text = children.compactMap { child -> String? in
            if case .content(let line) = child { line.text } else { nil }
        }.joined(separator: "\n")
        return fullTrim(text)
    }
}

func trimNewlinesOnly(_ s: String) -> String {
    var scalars = Substring(s).unicodeScalars
    while scalars.first == "\n" { scalars = scalars.dropFirst() }
    while scalars.last == "\n" { scalars = scalars.dropLast() }
    return String(scalars)
}

func fullTrim(_ s: String) -> String {
    let ws: Set<Unicode.Scalar> = [" ", "\t", "\r", "\n"]
    var scalars = Substring(s).unicodeScalars
    while let f = scalars.first, ws.contains(f) { scalars = scalars.dropFirst() }
    while let l = scalars.last, ws.contains(l) { scalars = scalars.dropLast() }
    return String(scalars)
}
