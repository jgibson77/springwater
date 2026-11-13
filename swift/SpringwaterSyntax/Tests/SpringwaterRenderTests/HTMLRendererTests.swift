import Testing
import SpringwaterSyntax
@testable import SpringwaterRender

// Golden fragments below were captured from the verified reference renderer
// (the Python mirror) so the Swift renderer is checked against the exact output
// it must reproduce.

private let tinySchema = "^Springwater\n^presentation\n^rendering_rules\n^render\n^tag\nslugline\n^tag/\n^transform\nuppercase\n^transform/\n^indent\n0in\n^indent/\n^spacing_after\n1 line\n^spacing_after/\n^render/\n^render\n^tag\ncharacter\n^tag/\n^transform\nuppercase\n^transform/\n^indent\n3.7in\n^indent/\n^render/\n^rendering_rules/\n^presentation/\n^Springwater/\n"

private let tinyDoc = "^Springwater\n^screenplay\n^scene\n^slugline\nint. room - day\n^slugline/\n^dialogue\n^character\nada\n^character/\n^lines\nHello.\n^lines/\n^dialogue/\n^scene/\n^screenplay/\n^Springwater/\n"

private func styles(_ text: String) throws -> RenderStyles {
    RenderStyles(parsing: try SpringwaterParser.parse(text))
}

// MARK: - Reading render styles from the schema

@Test func parsesRenderStylesFromSchema() throws {
    let s = try styles(tinySchema)
    #expect(s["slugline"]?.indent == "0in")
    #expect(s["slugline"]?.transform == "uppercase")
    #expect(s["slugline"]?.spacingAfter == "1 line")
    #expect(s["character"]?.indent == "3.7in")
    #expect(s["lines"] == nil)            // no render rule → no style
}

// MARK: - CSS generated from the rules

@Test func cssRuleMatchesSchemaRules() throws {
    let s = try styles(tinySchema)
    #expect(HTMLRenderer.cssRule("slugline", s["slugline"]!)
            == ".sw-slugline { margin-left:0in; text-transform:uppercase; margin-bottom:1em }")
    #expect(HTMLRenderer.cssRule("character", s["character"]!)
            == ".sw-character { margin-left:3.7in; text-transform:uppercase }")
}

@Test func cssListsRulesTagSorted() throws {
    let css = HTMLRenderer.css(try styles(tinySchema))
    // "character" sorts before "slugline"
    #expect(css == ".sw-character { margin-left:3.7in; text-transform:uppercase }\n.sw-slugline { margin-left:0in; text-transform:uppercase; margin-bottom:1em }")
}

// MARK: - Body HTML

@Test func bodyHTMLMatchesExpected() throws {
    let body = HTMLRenderer.bodyHTML(try SpringwaterParser.parse(tinyDoc), styles: try styles(tinySchema))
    #expect(body == #"<div class="sw-container sw-screenplay"><div class="sw-container sw-scene"><div class="sw-slugline">int. room - day</div><div class="sw-container sw-dialogue"><div class="sw-character">ada</div><div class="sw-lines">Hello.</div></div></div></div>"#)
}

@Test func dualDialogueRendersTwoColumns() throws {
    let doc = "^Springwater\n^screenplay\n^scene\n^dual_dialogue\n^dialogue\n^character\nA\n^character/\n^lines\nx\n^lines/\n^dialogue/\n^dialogue\n^character\nB\n^character/\n^lines\ny\n^lines/\n^dialogue/\n^dual_dialogue/\n^scene/\n^screenplay/\n^Springwater/\n"
    let body = HTMLRenderer.bodyHTML(try SpringwaterParser.parse(doc), styles: RenderStyles(styles: [:]))
    #expect(body.contains(#"<div class="sw-dual">"#))
    #expect(body.components(separatedBy: #"<div class="sw-dualcol">"#).count - 1 == 2)
    #expect(body.contains(#"<div class="sw-character">A</div>"#))
    #expect(body.contains(#"<div class="sw-character">B</div>"#))
}

@Test func screenplayMetadataIsAnOrdinaryContainer() throws {
    let doc = "^Springwater\n^screenplay\n^metadata\n^title\nT\n^title/\n^metadata/\n^screenplay/\n^Springwater/\n"
    let body = HTMLRenderer.bodyHTML(try SpringwaterParser.parse(doc), styles: RenderStyles(styles: [:]))
    #expect(body.contains(#"<div class="sw-container sw-metadata"><div class="sw-title">T</div></div>"#))
    #expect(!body.contains("sw-pagebreak"))
}

@Test func escapesContent() throws {
    let doc = "^Springwater\n^screenplay\n^scene\n^action\na < b & c \"q\"\n^action/\n^scene/\n^screenplay/\n^Springwater/\n"
    let body = HTMLRenderer.bodyHTML(try SpringwaterParser.parse(doc), styles: RenderStyles(styles: [:]))
    #expect(body.contains("a &lt; b &amp; c &quot;q&quot;"))
}

// MARK: - Full page

@Test func fullPageWrapsBodyAndCSS() throws {
    let page = HTMLRenderer.render(
        try SpringwaterParser.parse(tinyDoc),
        presentation: try SpringwaterParser.parse(tinySchema),
        title: "My Script"
    )
    #expect(page.hasPrefix("<!doctype html>"))
    #expect(page.contains("<title>My Script</title>"))
    #expect(page.contains(".sw-slugline { margin-left:0in; text-transform:uppercase; margin-bottom:1em }"))
    #expect(page.contains(#"<div class="sw-slugline">int. room - day</div>"#))
}

@Test func hiddenElementsAreHeldButNotRendered() throws {
    // A render rule with `hidden true` means the element stays in the document
    // (round-trips) but is not rendered — the "structure in the document,
    // invisible on the page" mechanism (scene numbers, sequence labels).
    let schema = "^Springwater\n^presentation\n^rendering_rules\n^render\n^tag\nnote\n^tag/\n^hidden\ntrue\n^hidden/\n^render/\n^rendering_rules/\n^presentation/\n^Springwater/\n"
    let s = try styles(schema)
    #expect(s["note"]?.hidden == true)
    let doc = "^Springwater\n^screenplay\n^scene\n^note\nsecret\n^note/\n^slugline\nX\n^slugline/\n^scene/\n^screenplay/\n^Springwater/\n"
    let body = HTMLRenderer.bodyHTML(try SpringwaterParser.parse(doc), styles: s)
    #expect(!body.contains("secret"))          // hidden content is not rendered
    #expect(!body.contains("sw-note"))
    #expect(!HTMLRenderer.css(s).contains("sw-note"))  // and carries no CSS rule
}

@Test func styledNovelMetadataRendersItsChildrenInOrder() throws {
    let doc = try SpringwaterParser.parse("""
    ^Springwater
    ^novel
    ^metadata
    ^title
    The Sun Also Rises
    ^title/
    ^author
    Ernest Hemingway
    ^author/
    ^year
    1926
    ^year/
    ^publisher
    Charles Scribner's Sons
    ^publisher/
    ^metadata/
    ^novel/
    ^Springwater/
    """)
    // The novel schema styles metadata itself as well as its leaf children.
    let renderStyles = RenderStyles(styles: [
        "metadata": RenderStyle(pageBreakAfter: true),
        "title": RenderStyle(fontWeight: "bold", align: "center"),
        "author": RenderStyle(align: "center"),
        "year": RenderStyle(align: "center"),
        "publisher": RenderStyle(align: "center")
    ])
    let body = HTMLRenderer.bodyHTML(doc, styles: renderStyles)
    #expect(body == #"<div class="sw-container sw-novel"><div class="sw-container sw-metadata"><div class="sw-title">The Sun Also Rises</div><div class="sw-author">Ernest Hemingway</div><div class="sw-year">1926</div><div class="sw-publisher">Charles Scribner&#x27;s Sons</div></div></div>"#)
}

@Test func paragraphStylesDistinguishFirstLineFromBlockIndent() throws {
    let schema = "^Springwater\n^presentation\n^rendering_rules\n^render\n^tag\nparagraph\n^tag/\n^text_indent\n0.5in\n^text_indent/\n^line_height\n1.5\n^line_height/\n^spacing_after\n0 lines\n^spacing_after/\n^render/\n^rendering_rules/\n^presentation/\n^Springwater/\n"
    let parsed = try styles(schema)
    let paragraph = try #require(parsed["paragraph"])
    #expect(paragraph.textIndent == "0.5in")
    #expect(paragraph.lineHeight == "1.5")
    #expect(paragraph.indent == nil)
    #expect(HTMLRenderer.cssRule("paragraph", paragraph) == ".sw-paragraph { text-indent:0.5in; line-height:1.5; margin-bottom:0em }")
    #expect(!RenderStyle(textIndent: "0.5in").isEmpty)
    #expect(!RenderStyle(lineHeight: "1.5").isEmpty)
    // Existing screenplay block indentation retains its meaning.
    #expect(HTMLRenderer.cssDeclarations(RenderStyle(indent: "1in")) == "margin-left:1in")
}

@Test func pageBreakRulesApplyToContainersAndLeavesWithoutDroppingContent() throws {
    let doc = "^Springwater\n^novel\n^metadata\n^title\nTitle\n^title/\n^metadata/\n^chapter\n^paragraph\nFirst paragraph\n^paragraph/\n^paragraph\nSecond paragraph\n^paragraph/\n^chapter/\n^novel/\n^Springwater/\n"
    let schema = "^Springwater\n^presentation\n^rendering_rules\n^render\n^tag\nmetadata\n^tag/\n^page_break_after\ntrue\n^page_break_after/\n^render/\n^render\n^tag\nchapter\n^tag/\n^page_break_before\ntrue\n^page_break_before/\n^render/\n^render\n^tag\nparagraph\n^tag/\n^page_break_after\ntrue\n^page_break_after/\n^render/\n^rendering_rules/\n^presentation/\n^Springwater/\n"
    let parsed = try styles(schema)
    #expect(parsed["metadata"]?.pageBreakAfter == true)
    #expect(parsed["chapter"]?.pageBreakBefore == true)
    let page = HTMLRenderer.render(try SpringwaterParser.parse(doc), presentation: try SpringwaterParser.parse(schema))
    #expect(page.contains(".sw-metadata { break-after:page; page-break-after:always }"))
    #expect(page.contains(".sw-chapter { break-before:page; page-break-before:always }"))
    #expect(page.contains(".sw-metadata + .sw-chapter { break-before:auto; page-break-before:auto }"))
    #expect(page.contains(".sw-paragraph { break-after:page; page-break-after:always }"))
    #expect(page.contains(#"<div class="sw-container sw-metadata"><div class="sw-title">Title</div></div>"#))
    #expect(page.contains(#"<div class="sw-paragraph">First paragraph</div><div class="sw-paragraph">Second paragraph</div>"#))
    #expect(page.contains("@page { size: 8.5in 11in; margin: 1in 1in 1in 1.5in; }"))
    #expect(page.contains("width: auto; min-height: 0; margin: 0; padding: 0; box-shadow: none;"))
}


@Test func schemaPageGeometryDrivesScreenAndPrint() throws {
    // Asymmetric margins catch top/right/bottom/left ordering mistakes.
    let schema = try SpringwaterParser.parse("^Springwater\n^presentation\n^page\n^width\n6in\n^width/\n^height\n9in\n^height/\n^margin_top\n0.6in\n^margin_top/\n^margin_right\n0.7in\n^margin_right/\n^margin_bottom\n0.8in\n^margin_bottom/\n^margin_left\n0.9in\n^margin_left/\n^page/\n^presentation/\n^Springwater/\n")
    let geometry = PageStyle(parsing: schema)
    #expect(geometry.width == "6in")
    #expect(geometry.height == "9in")
    #expect(geometry.marginTop == "0.6in")
    #expect(geometry.marginRight == "0.7in")
    #expect(geometry.marginBottom == "0.8in")
    #expect(geometry.marginLeft == "0.9in")
    let html = HTMLRenderer.render(try SpringwaterParser.parse(tinyDoc), presentation: schema)
    #expect(html.contains("width: 6in; min-height: 9in;"))
    #expect(html.contains("padding: 0.6in 0.7in 0.8in 0.9in;"))
    #expect(html.contains("@page { size: 6in 9in; margin: 0.6in 0.7in 0.8in 0.9in; }"))
    #expect(!html.contains("size: 8.5in 11in"))
    // Print margins belong to @page, not a second padded content wrapper.
    #expect(html.contains("width: auto; min-height: 0; margin: 0; padding: 0; box-shadow: none;"))
}

@Test func absentAndPartialPageGeometryRetainDefaults() throws {
    let absent = PageStyle(parsing: try SpringwaterParser.parse(tinySchema))
    #expect(absent == PageStyle())
    let partial = try SpringwaterParser.parse("^Springwater\n^presentation\n^page\n^width\n6in\n^width/\n^margin_left\n0.75in\n^margin_left/\n^margin_top\n\n^margin_top/\n^page/\n^presentation/\n^Springwater/\n")
    let geometry = PageStyle(parsing: partial)
    #expect(geometry.width == "6in")
    #expect(geometry.height == "11in")
    #expect(geometry.marginLeft == "0.75in")
    #expect(geometry.marginTop == "1in")
    #expect(geometry.marginRight == "1in")
    #expect(geometry.marginBottom == "1in")
}
