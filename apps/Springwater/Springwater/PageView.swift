import CoreText
import SwiftUI
import SpringwaterRender
import SpringwaterSchema
import SpringwaterSyntax

/// The document shown as readable text, dressed by a presentation when the
/// app has one for the document's kind.
///
/// This is one continuous page. A Springwater document does not store where
/// pages end, so page breaks appear only when a document is exported.
struct PageView: View {
    let document: SpringwaterDocument
    let presentation: SpringwaterDocument?

    var body: some View {
        let sheet = Sheet(presentation: presentation)
        let blocks = Block.blocks(of: document, styles: sheet.styles)

        GeometryReader { proxy in
            // Horizontal measures shrink to fit a narrow window. Type size does not.
            let scale = min(1, proxy.size.width / sheet.width)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(blocks) { block in
                        BlockView(block: block, sheet: sheet, scale: scale)
                    }
                }
                .padding(.leading, sheet.marginLeft * scale)
                .padding(.trailing, sheet.marginRight * scale)
                .padding(.vertical, sheet.marginTop * scale)
                .frame(width: sheet.width * scale, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
        }
        .textSelection(.enabled)
    }
}

/// Two pages are the same when they show the same document the same way, so
/// the page is not laid out again for every keystroke in the source beside it.
extension PageView: Equatable {
    nonisolated static func == (lhs: PageView, rhs: PageView) -> Bool {
        lhs.document == rhs.document && lhs.presentation == rhs.presentation
    }
}

/// One run of text on the page with the style its element is given.
private struct Block: Identifiable {
    let id: Int
    let text: String
    let style: RenderStyle
    /// When not empty, this block is a row of columns and has no text of its
    /// own: two speakers talking at once, set side by side.
    var columns: [[Block]] = []

    /// Walks the tree the same way the HTML renderer does: hidden elements are
    /// skipped, labelled containers print their label, containers recurse, and
    /// leaves print their content.
    static func blocks(of document: SpringwaterDocument, styles: RenderStyles) -> [Block] {
        var blocks: [Block] = []
        // The page shows the work. A schema or presentation the document carries
        // beside it describes the work and is not part of what is read.
        for (index, element) in document.root.elements.enumerated()
        where index == 0 || !CarriedDocuments.names.contains(element.name) {
            append(element, styles: styles, to: &blocks)
        }
        return blocks
    }

    private static func append(
        _ element: SpringwaterDocument.Element,
        styles: RenderStyles,
        to blocks: inout [Block]
    ) {
        // `validated_by` names the document's schema. It is a note about the
        // document, not something the writer wrote to be read on the page.
        if element.name == "validated_by" { return }

        let style = styles[element.name]
        if style?.hidden == true { return }

        let children = element.elements
        let text = element.content.trimmingCharacters(in: .newlines)

        if children.isEmpty {
            let shown = text.isEmpty ? (style?.content ?? "") : text
            if shown.isEmpty { return }
            // Printed on the same line as the block before it, in that block's
            // style: a cue's extension, as in ANNA (V.O.).
            if style?.joinsPrevious == true, let previous = blocks.last {
                blocks[blocks.count - 1] = Block(
                    id: previous.id, text: previous.text + " " + shown, style: previous.style
                )
                return
            }
            // A line printed above the content, in the same style, as a title
            // page prints "Written by" above the name. It is never transformed.
            if let style, let above = style.labelAbove {
                var labelStyle = style
                labelStyle.transform = nil
                labelStyle.spacingAfter = "1 line"
                blocks.append(Block(id: blocks.count, text: above, style: labelStyle))
                var valueStyle = style
                valueStyle.spacingBefore = nil
                blocks.append(Block(id: blocks.count, text: shown, style: valueStyle))
                return
            }
            blocks.append(Block(id: blocks.count, text: shown, style: style ?? RenderStyle()))
            return
        }
        // Children set in columns, left to right.
        if let style, style.sideBySide {
            var columns: [[Block]] = []
            for child in children {
                var column: [Block] = []
                append(child, styles: styles, to: &column)
                if !column.isEmpty { columns.append(column) }
            }
            if !columns.isEmpty {
                blocks.append(Block(id: blocks.count, text: "", style: style, columns: columns))
            }
            return
        }
        if let style, let label = style.content {
            blocks.append(Block(id: blocks.count, text: label, style: style))
        }
        for child in children {
            append(child, styles: styles, to: &blocks)
        }
    }
}

private struct BlockView: View {
    let block: Block
    let sheet: Sheet
    let scale: CGFloat

    var body: some View {
        if block.columns.isEmpty {
            textBlock
        } else {
            columns
        }
    }

    /// Columns share the width evenly. Inside a column the indents shrink with
    /// it, so a cue still sits right of its lines.
    private var columns: some View {
        HStack(alignment: .top, spacing: 12 * scale) {
            ForEach(Array(block.columns.enumerated()), id: \.offset) { _, column in
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(column) { inner in
                        BlockView(block: inner, sheet: sheet, scale: scale * 0.45)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
    }

    private var textBlock: some View {
        let style = block.style
        let lineHeight = sheet.fontSize * 1.2

        return Text(attributed)
            .font(sheet.font)
            .bold(style.fontWeight == "bold")
            .italic(style.fontStyle == "italic")
            .lineSpacing(Self.extraLineSpacing(style.lineHeight, fontSize: sheet.fontSize))
            .multilineTextAlignment(textAlignment)
            .frame(maxWidth: Measure.points(style.maxWidth).map { $0 * scale } ?? .infinity, alignment: alignment)
            .frame(maxWidth: .infinity, alignment: alignment)
            .padding(.leading, (Measure.points(style.indent) ?? 0) * scale)
            .padding(.top, Measure.lines(style.spacingBefore) * lineHeight)
            .padding(.bottom, Measure.lines(style.spacingAfter) * lineHeight)
    }

    /// The block's text, with emphasis drawn when the presentation says how.
    private var attributed: AttributedString {
        let uppercase = block.style.transform == "uppercase"
        guard let emphasis = sheet.styles.markStyles["emphasis"] else {
            return AttributedString(uppercase ? block.text.uppercased() : block.text)
        }
        var result = AttributedString()
        for (index, line) in block.text.components(separatedBy: "\n").enumerated() {
            if index > 0 { result += AttributedString("\n") }
            for run in InlineMarks.runs(in: line) {
                var piece = AttributedString(uppercase ? run.text.uppercased() : run.text)
                if run.isEmphasized {
                    if emphasis == "underline" {
                        piece.underlineStyle = .single
                    } else {
                        piece.inlinePresentationIntent = .emphasized
                    }
                }
                result += piece
            }
        }
        return result
    }

    private var textAlignment: TextAlignment {
        switch block.style.align {
        case "center": .center
        case "right": .trailing
        default: .leading
        }
    }

    private var alignment: Alignment {
        switch block.style.align {
        case "center": .center
        case "right": .trailing
        default: .leading
        }
    }

    private static func extraLineSpacing(_ multiplier: String?, fontSize: CGFloat) -> CGFloat {
        guard let multiplier, let value = Double(multiplier), value > 1 else { return 0 }
        return (value - 1) * fontSize
    }
}

/// The page measures and typeface a presentation asks for, in points.
struct Sheet {
    let styles: RenderStyles
    let width: CGFloat
    let marginTop: CGFloat
    let marginLeft: CGFloat
    let marginRight: CGFloat
    let fontSize: CGFloat
    let font: Font
    /// The installed font family the presentation asks for, or nil when the
    /// system has none of them and its own serif face is used.
    let fontFamily: String?

    init(presentation: SpringwaterDocument?) {
        let page = presentation.map(PageStyle.init(parsing:)) ?? PageStyle()
        styles = presentation.map(RenderStyles.init(parsing:)) ?? RenderStyles(styles: [:])
        width = Measure.points(page.width) ?? 612
        marginTop = Measure.points(page.marginTop) ?? 72
        marginLeft = Measure.points(page.marginLeft) ?? 72
        marginRight = Measure.points(page.marginRight) ?? 72

        let fontElement = presentation?.root
            .firstElement(named: "presentation")?
            .firstElement(named: "font")
        let size = fontElement?.firstElement(named: "size")
            .flatMap { Double($0.trimmedContent) } ?? 12
        fontSize = size

        let names = ["family", "fallback"].compactMap {
            fontElement?.firstElement(named: $0)?.trimmedContent
        }
        fontFamily = names.first(where: Self.isInstalled)
        if let family = fontFamily {
            font = .custom(family, size: size, relativeTo: .body)
        } else {
            font = .system(.body, design: .serif)
        }
    }

    /// True when the system has a font family with exactly this name.
    private static func isInstalled(_ family: String) -> Bool {
        let font = CTFontCreateWithName(family as CFString, 12, nil)
        return (CTFontCopyFamilyName(font) as String).caseInsensitiveCompare(family) == .orderedSame
    }
}

/// Reads the lengths a presentation writes, such as `1.5in` and `2 lines`.
enum Measure {
    /// A length in points, or nil when the text is not a length this app knows.
    static func points(_ text: String?) -> CGFloat? {
        guard let text = text?.trimmingCharacters(in: .whitespaces) else { return nil }
        let units: [(suffix: String, points: Double)] = [
            ("in", 72), ("pt", 1), ("cm", 72 / 2.54), ("mm", 72 / 25.4)
        ]
        for unit in units where text.hasSuffix(unit.suffix) {
            if let value = Double(text.dropLast(unit.suffix.count)) {
                return value * unit.points
            }
        }
        return nil
    }

    /// The number at the start of a value such as `2 lines`. Zero when absent.
    static func lines(_ text: String?) -> CGFloat {
        guard let first = text?.split(separator: " ").first, let value = Double(first) else { return 0 }
        return value
    }
}
