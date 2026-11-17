import SwiftUI
import SpringwaterRender
import SpringwaterSchema
import SpringwaterSyntax

/// The page as a place to write.
///
/// The writer types on the page and never types a tag. Each block of text is
/// set the way the presentation sets it. Return adds the block that usually
/// comes next, Tab turns the block into another kind, and Delete in an empty
/// block removes it. What comes next is read from the authoring profile when
/// there is one and from the schema when there is not.
///
/// The page owns no text. Every keystroke becomes a new document, handed
/// straight to `commit`, and the page shows whatever document it is given.
struct PageEditor: View {
    let document: SpringwaterDocument
    let presentation: SpringwaterDocument?
    let engine: BlockEditor
    let commit: (SpringwaterDocument) -> Void

    /// A block that should take the insertion point, until it has.
    @State private var focus: BlockFocus?
    /// The block that has the insertion point. Its kind shows in the margin.
    @State private var focusedIndex: Int?
    @State private var lastToken = 0

    var body: some View {
        let sheet = Sheet(presentation: presentation)
        let blocks = engine.blocks(of: document)

        if blocks.isEmpty {
            ContentUnavailableView(
                "Nothing to Write In Yet",
                systemImage: "text.cursor",
                description: Text("Add an element in the source and it appears here.")
            )
        } else {
            GeometryReader { proxy in
                // Horizontal measures shrink to fit a narrow window. Type size does not.
                let scale = min(1, proxy.size.width / sheet.width)
                ScrollViewReader { reader in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(Array(blocks.enumerated()), id: \.offset) { index, block in
                                row(block, at: index, of: blocks.count, sheet: sheet, scale: scale)
                                    .id(index)
                            }
                        }
                        .padding(.leading, sheet.marginLeft * scale)
                        .padding(.trailing, sheet.marginRight * scale)
                        .padding(.vertical, sheet.marginTop * scale)
                        .frame(width: sheet.width * scale, alignment: .leading)
                        .frame(maxWidth: .infinity)
                    }
                    .onChange(of: focus) { _, wanted in
                        if let wanted { reader.scrollTo(wanted.index) }
                    }
                }
            }
        }
    }

    // MARK: - One block

    private func row(
        _ block: BlockEditor.Block,
        at index: Int,
        of count: Int,
        sheet: Sheet,
        scale: CGFloat
    ) -> some View {
        let style = sheet.styles[block.tag] ?? RenderStyle()
        let lineHeight = sheet.fontSize * 1.2
        let margin = sheet.marginLeft * scale
        let alignment = Self.alignment(style)
        let uppercase = style.transform == "uppercase"
        let name = block.tag.replacing("_", with: " ")

        return VStack(alignment: .leading, spacing: 0) {
            // A line the page prints above the block, such as "Written by".
            if let above = style.labelAbove {
                Text(above)
                    .font(sheet.font)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: alignment)
            }
            BlockTextView(
                text: block.text,
                look: BlockLook(
                    family: sheet.fontFamily,
                    size: sheet.fontSize,
                    bold: style.fontWeight == "bold",
                    italic: style.fontStyle == "italic",
                    alignment: Self.lookAlignment(style),
                    uppercase: uppercase,
                    dimmed: style.hidden
                ),
                focus: focus?.index == index ? focus : nil,
                actions: actions(for: block, at: index, of: count)
            )
            .overlay(alignment: Self.topAlignment(style)) {
                // An empty block says what kind it is.
                if block.text.isEmpty {
                    Text(uppercase ? name.uppercased() : name)
                        .font(sheet.font)
                        .bold(style.fontWeight == "bold")
                        .italic(style.fontStyle == "italic")
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
            .frame(maxWidth: Measure.points(style.maxWidth).map { $0 * scale } ?? .infinity, alignment: alignment)
            .frame(maxWidth: .infinity, alignment: alignment)
            .accessibilityLabel(name)
        }
        .padding(.leading, (Measure.points(style.indent) ?? 0) * scale)
        .overlay(alignment: .topLeading) {
            // The kind of the block being written, in the margin beside it.
            if focusedIndex == index, margin > 44 {
                Text(name)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .frame(width: margin - 12, alignment: .trailing)
                    .offset(x: -margin)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
        .padding(.top, Measure.lines(style.spacingBefore) * lineHeight)
        .padding(.bottom, Measure.lines(style.spacingAfter) * lineHeight)
    }

    private static func alignment(_ style: RenderStyle) -> Alignment {
        switch style.align {
        case "center": .center
        case "right": .trailing
        default: .leading
        }
    }

    private static func topAlignment(_ style: RenderStyle) -> Alignment {
        switch style.align {
        case "center": .top
        case "right": .topTrailing
        default: .topLeading
        }
    }

    private static func lookAlignment(_ style: RenderStyle) -> BlockLook.Alignment {
        switch style.align {
        case "center": .center
        case "right": .trailing
        default: .leading
        }
    }

    // MARK: - What the keys do

    private func actions(for block: BlockEditor.Block, at index: Int, of count: Int) -> BlockActions {
        BlockActions(
            change: { typed in
                // Every line ends the same way in the document.
                let text = typed.replacing("\r\n", with: "\n").replacing("\r", with: "\n")
                guard BlockText.canHold(text) else { return }
                let changed = engine.settingText(text, at: block.path, in: document)
                if changed != document { commit(changed) }
            },
            split: { before, after in
                // The block keeps what is before the insertion point. What is
                // after it goes down into the new block.
                guard BlockText.canHold(before), BlockText.canHold(after) else { return false }
                let kept = engine.settingText(before, at: block.path, in: document)
                guard let change = engine.insertingBlock(after: block.path, carrying: after, in: kept) else {
                    return false
                }
                apply(change, location: 0)
                return true
            },
            changeKind: { forward, location in
                guard let change = engine.changingKind(at: block.path, forward: forward, in: document) else {
                    return false
                }
                apply(change, location: location)
                return true
            },
            deleteEmpty: {
                guard let change = engine.deletingBlock(at: block.path, in: document) else { return false }
                apply(change, location: nil)
                return true
            },
            move: { up in
                let target = index + (up ? -1 : 1)
                guard target >= 0, target < count else { return false }
                ask(for: target, location: up ? nil : 0)
                return true
            },
            focused: { focusedIndex = index },
            focusApplied: { focus = nil }
        )
    }

    /// Hands on the changed document and puts the insertion point where the
    /// change says it belongs.
    private func apply(_ change: BlockEditor.Change, location: Int?) {
        commit(change.document)
        let blocks = engine.blocks(of: change.document)
        guard let index = blocks.firstIndex(where: { $0.path == change.path }) else { return }
        ask(for: index, location: location)
    }

    private func ask(for index: Int, location: Int?) {
        lastToken += 1
        focus = BlockFocus(index: index, token: lastToken, location: location)
        focusedIndex = index
    }
}
