import SpringwaterSyntax

/// Renders a Springwater document to a styled HTML page, driven entirely by a
/// schema's `^rendering_rules`. No document-type logic is hardcoded: the same
/// renderer produces a screenplay, a novel, or a manual purely from the render
/// styles its schema defines.
public enum HTMLRenderer {

    // MARK: - CSS

    /// The declarations inside one tag's CSS rule (the part between the braces),
    /// in a fixed order: margin-left, width, text-align, text-transform,
    /// font-weight, font-style, margin-top, margin-bottom, and page breaks.
    public static func cssDeclarations(_ s: RenderStyle) -> String {
        var d: [String] = []
        if let v = s.indent { d.append("margin-left:\(v)") }
        if let v = s.textIndent { d.append("text-indent:\(v)") }
        if let v = s.lineHeight { d.append("line-height:\(v)") }
        if let v = s.maxWidth { d.append("width:\(v)") }
        if let v = s.align { d.append("text-align:\(v)") }
        if s.transform == "uppercase" { d.append("text-transform:uppercase") }
        if let v = s.fontWeight { d.append("font-weight:\(v == "bold" ? "bold" : "normal")") }
        if let v = s.fontStyle, v != "regular" { d.append("font-style:\(v)") }
        if let v = s.spacingBefore { d.append("margin-top:\(linesToEm(v))") }
        if let v = s.spacingAfter { d.append("margin-bottom:\(linesToEm(v))") }
        if s.pageBreakBefore { d.append("break-before:page"); d.append("page-break-before:always") }
        if s.pageBreakAfter { d.append("break-after:page"); d.append("page-break-after:always") }
        return d.joined(separator: "; ")
    }

    /// One tag's full CSS rule, e.g. `.sw-character { margin-left:3.7in; … }`.
    public static func cssRule(_ tag: String, _ s: RenderStyle) -> String {
        ".sw-\(tag) { \(cssDeclarations(s)) }"
    }

    /// All non-empty render styles as CSS, one rule per line, tag-sorted.
    public static func css(_ styles: RenderStyles) -> String {
        let tags = styles.styles.keys.sorted()
        var rules = tags
            .filter { !(styles.styles[$0]?.isEmpty ?? true) }
            .map { cssRule($0, styles.styles[$0]!) }
        // Adjacent forced breaks describe one boundary. Safari otherwise adds
        // a blank sheet for an after-break followed by a before-break.
        for previous in tags where styles[previous]?.pageBreakAfter == true {
            for next in tags where styles[next]?.pageBreakBefore == true {
                rules.append(".sw-\(previous) + .sw-\(next) { break-before:auto; page-break-before:auto }")
            }
        }
        return rules.joined(separator: "\n")
    }

    static func linesToEm(_ v: String) -> String {
        let n = v.split(separator: " ").first.map(String.init) ?? v
        return "\(n)em"
    }

    // MARK: - Body

    /// The document body as HTML (the content of the single `.sw-page`), without
    /// the surrounding page/boilerplate.
    public static func bodyHTML(_ document: SpringwaterDocument, styles: RenderStyles) -> String {
        var out: [String] = []
        for child in document.root.renderChildElements {
            renderElement(child, styles, into: &out)
        }
        return out.joined()
    }

    static func renderElement(_ el: SpringwaterDocument.Element, _ styles: RenderStyles, into out: inout [String]) {
        let name = el.name
        let style = styles[name]
        let kids = el.renderChildElements
        let content = el.renderContent

        // held in the document but not rendered (metadata: scene number, sequence label)
        if style?.hidden == true { return }

        // page break marker
        if name == "page_break" {
            out.append(#"<div class="sw-pagebreak"></div>"#)
            return
        }

        // dual dialogue: two side-by-side columns
        if name == "dual_dialogue" {
            out.append(#"<div class="sw-dual">"#)
            for d in kids {
                out.append(#"<div class="sw-dualcol">"#)
                renderElement(d, styles, into: &out)
                out.append("</div>")
            }
            out.append("</div>")
            return
        }

        // a leaf with its own render rule → styled block of its content
        if let style, kids.isEmpty {
            let label = style.content
            let text = (label != nil && content.isEmpty) ? label! : content
            out.append(#"<div class="sw-\#(name)">\#(esc(text))</div>"#)
            return
        }

        // element with a literal content label AND children (e.g. montage container)
        if let style, let label = style.content {
            out.append(#"<div class="sw-\#(name)">\#(esc(label))</div>"#)
            for k in kids { renderElement(k, styles, into: &out) }
            return
        }

        // container (incl. title_page, acts, scene, dialogue, root): recurse
        // A style on a container must not suppress its descendants.
        if !kids.isEmpty {
            out.append(#"<div class="sw-container sw-\#(name)">"#)
            for k in kids { renderElement(k, styles, into: &out) }
            out.append("</div>")
            // the title page is semantically its own page (renderer convention,
            // not schema-driven; a title_page render rule with page_break_after
            // would move this into canon).
            if name == "title_page" {
                out.append(#"<div class="sw-pagebreak"></div>"#)
            }
            return
        }

        // fallback: styled leaf even without a rule
        if !content.isEmpty {
            out.append(#"<div class="sw-\#(name)">\#(esc(content))</div>"#)
        }
    }

    // MARK: - Full page

    /// A complete standalone HTML page: boilerplate + the CSS generated from the
    /// schema's render styles + the rendered body.
    public static func render(
        _ document: SpringwaterDocument,
        schema schemaDocument: SpringwaterDocument,
        title: String = "Springwater"
    ) -> String {
        let styles = RenderStyles(parsing: schemaDocument)
        let rulesCSS = css(styles)
        let geometry = PageStyle(parsing: schemaDocument)
        let body = #"<div class="sw-page">"# + bodyHTML(document, styles: styles) + "</div>"
        return """
        <!doctype html>
        <html lang="en"><head><meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <title>\(esc(title))</title>
        <style>\(pageCSS(geometry))
        /* ---- generated from the schema's rendering_rules ---- */
        \(rulesCSS)
        </style></head>
        <body><div class="sw-doc">\(body)</div></body></html>

        """
    }

    static func pageCSS(_ page: PageStyle) -> String {
        """

        :root { color-scheme: light dark; }
        * { box-sizing: border-box; }
        body { margin: 0; background: #6b6b6e; font-family: "Courier Prime","Courier New",Courier,monospace; }
        @media (prefers-color-scheme: dark) { body { background:#2a2a2d; } }
        .sw-doc { }
        .sw-page {
          width: \(page.width); min-height: \(page.height); margin: 0.35in auto; background: #fff; color:#111;
          padding: \(page.margins);
          box-shadow: 0 2px 14px rgba(0,0,0,.45);
          font-size: 12pt; line-height: 1; white-space: pre-wrap;
        }
        .sw-container { }
        .sw-title_page { margin-bottom: 3em; }
        .sw-dual { display: flex; gap: .3in; }
        .sw-dualcol { flex: 1 1 0; }
        .sw-dualcol .sw-character, .sw-dualcol .sw-extension { margin-left: 0 !important; text-align:center; }
        .sw-dualcol .sw-lines, .sw-dualcol .sw-parenthetical { margin-left: 0 !important; width:auto !important; }
        .sw-pagebreak { break-before: page; page-break-before: always; height: 0; }
        @media screen { .sw-pagebreak { height: 0.7in; } }
        @page { size: \(page.width) \(page.height); margin: \(page.margins); }
        @media print {
          :root { color-scheme: light; }
          body { background: #fff; }
          .sw-page {
            width: auto; min-height: 0; margin: 0; padding: 0; box-shadow: none;
          }
        }
        """
    }
}

/// HTML-escapes text the same way Python's `html.escape` does (& < > " ').
func esc(_ s: String) -> String {
    var r = s.replacingOccurrences(of: "&", with: "&amp;")
    r = r.replacingOccurrences(of: "<", with: "&lt;")
    r = r.replacingOccurrences(of: ">", with: "&gt;")
    r = r.replacingOccurrences(of: "\"", with: "&quot;")
    r = r.replacingOccurrences(of: "'", with: "&#x27;")
    return r
}
