import CoreText
import SwiftUI
import SpringwaterRender
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

/// One run of text on the page with the style its element is given.
private struct Block: Identifiable {
    let id: Int
    let text: String
    let style: RenderStyle

    /// Walks the tree the same way the HTML renderer does: hidden elements are
    /// skipped, labelled containers print their label, containers recurse, and
    /// leaves print their content.
    static func blocks(of document: SpringwaterDocument, styles: RenderStyles) -> [Block] {
        var blocks: [Block] = []
        for element in document.root.elements {
            append(element, styles: styles, to: &blocks)
        }
        return blocks
    }

    private static func append(
        _ element: SpringwaterDocument.Element,
        styles: RenderStyles,
        to blocks: inout [Block]
    ) {
        let style = styles[element.name]
        if style?.hidden == true { return }

        let children = element.elements
        let text = element.content.trimmingCharacters(in: .newlines)

        if children.isEmpty {
            let shown = text.isEmpty ? (style?.content ?? "") : text
            if !shown.isEmpty {
                blocks.append(Block(id: blocks.count, text: shown, style: style ?? RenderStyle()))
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
        let style = block.style
        let lineHeight = sheet.fontSize * 1.2

        Text(style.transform == "uppercase" ? block.text.uppercased() : block.text)
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
private struct Sheet {
    let styles: RenderStyles
    let width: CGFloat
    let marginTop: CGFloat
    let marginLeft: CGFloat
    let marginRight: CGFloat
    let fontSize: CGFloat
    let font: Font

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
        if let family = names.first(where: Self.isInstalled) {
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
private enum Measure {
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
