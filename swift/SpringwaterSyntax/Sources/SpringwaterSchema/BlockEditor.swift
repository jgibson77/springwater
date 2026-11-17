import SpringwaterSyntax

/// The rules for writing a document block by block, with no tags typed.
///
/// A *block* is an element that holds text and no other elements: a slugline,
/// a paragraph, a line of dialogue. A writer types into blocks; the elements
/// around them (a scene, a dialogue, a chapter) are kept by the editor.
///
/// Everything here is a pure function from one document to the next. Nothing
/// is specific to any kind of document: what comes next is read from the
/// authoring profile when there is one and from the schema when there is not.
///
/// - Return adds a block after the current one (`insertingBlock`).
/// - Tab changes what kind of block the current one is (`changingKind`).
/// - Delete in an empty block removes it (`deletingBlock`).
///
/// The kinds offered at any point are one ordered list. Return takes the first
/// and Tab moves along it, so the two always agree.
public struct BlockEditor: Sendable {

    /// Where an element is: the index of each child to step into, starting
    /// from the document root.
    public typealias Path = [Int]

    /// One block of text in document order.
    public struct Block: Sendable, Equatable {
        public let path: Path
        public let tag: String
        /// The block's content lines joined with line feeds, exactly as written.
        public let text: String
    }

    /// The result of an edit: the new document, and the block the insertion
    /// point belongs in afterwards.
    public struct Change: Sendable, Equatable {
        public let document: SpringwaterDocument
        public let path: Path
    }

    public let schema: Schema?
    public let profile: AuthoringProfile?

    public init(schema: Schema?, profile: AuthoringProfile?) {
        self.schema = schema
        self.profile = profile
    }

    // MARK: - Blocks

    /// The blocks of the document's work, in order. A `validated_by` element
    /// is a note about the document and is not a block.
    public func blocks(of document: SpringwaterDocument) -> [Block] {
        guard let work = workIndex(of: document.root),
              case .element(let element) = document.root.children[work] else { return [] }
        var found: [Block] = []
        collectBlocks(in: element, at: [work], into: &found)
        return found
    }

    private func collectBlocks(in element: Element, at path: Path, into found: inout [Block]) {
        if element.name == "validated_by" { return }
        if isBlock(element) {
            found.append(Block(path: path, tag: element.name, text: text(of: element)))
            return
        }
        for (index, child) in element.children.enumerated() {
            if case .element(let childElement) = child {
                collectBlocks(in: childElement, at: path + [index], into: &found)
            }
        }
    }

    /// Replaces the text of the block at `path`. Content is written one line
    /// per line of `text`, each ending in a line feed. When the text is
    /// unchanged the document is returned as it was, line endings included.
    public func settingText(
        _ text: String,
        at path: Path,
        in document: SpringwaterDocument
    ) -> SpringwaterDocument {
        guard let element = element(at: path, in: document.root), self.text(of: element) != text else {
            return document
        }
        return SpringwaterDocument(root: replacing(document.root, at: path) { _ in Self.contentLines(text) })
    }

    // MARK: - Return

    /// Adds a block after the block at `path` and puts `text` in it. The new
    /// block is the first kind offered at that point. Returns nil when nothing
    /// may follow there.
    public func insertingBlock(
        after path: Path,
        carrying text: String = "",
        in document: SpringwaterDocument
    ) -> Change? {
        guard let last = path.last, element(at: path, in: document.root) != nil else { return nil }
        let places = levels(in: document.root, path: Array(path.dropLast()), index: last + 1, descending: false)
        for place in places {
            guard let container = element(at: place.path, in: document.root),
                  let tag = suggestions(in: container, after: place.after).first else { continue }
            let built = build(tag, text: text)
            let root = inserting(built, at: place, in: document.root)
            return Change(
                document: SpringwaterDocument(root: root),
                path: firstBlockPath(in: built, from: place.path + [place.index])
            )
        }
        return nil
    }

    // MARK: - Tab

    /// The kinds the block at `path` could be, in the order Tab moves through
    /// them, and which of them it is now.
    public func kinds(at path: Path, in document: SpringwaterDocument) -> (names: [String], current: Int)? {
        guard let choices = kindChoices(at: path, in: document) else { return nil }
        return (choices.kinds.map { $0.tag }, choices.current)
    }

    /// Changes the block at `path` into the next kind (or the previous one),
    /// keeping its text. Returns nil when it can be nothing else.
    public func changingKind(
        at path: Path,
        forward: Bool = true,
        in document: SpringwaterDocument
    ) -> Change? {
        guard let choices = kindChoices(at: path, in: document), choices.kinds.count > 1,
              let block = element(at: path, in: document.root) else { return nil }
        let count = choices.kinds.count
        let next = choices.kinds[(choices.current + (forward ? 1 : count - 1)) % count]
        let built = build(next.tag, text: text(of: block))
        let root = inserting(built, at: next.place, in: choices.without)
        return Change(
            document: SpringwaterDocument(root: root),
            path: firstBlockPath(in: built, from: next.place.path + [next.place.index])
        )
    }

    private struct KindChoices {
        var kinds: [(tag: String, place: Place)]
        var current: Int
        /// The document root with the block's unit taken out.
        var without: Element
    }

    private func kindChoices(at path: Path, in document: SpringwaterDocument) -> KindChoices? {
        guard path.count >= 2, element(at: path, in: document.root) != nil else { return nil }
        let unit = unitPath(for: path, in: document.root)
        guard let unitElement = element(at: unit, in: document.root), let index = unit.last else { return nil }
        let parentPath = Array(unit.dropLast())
        let without = replacing(document.root, at: parentPath) { children in
            var remaining = children
            remaining.remove(at: index)
            return remaining
        }

        var kinds: [(tag: String, place: Place)] = []
        for place in levels(in: without, path: parentPath, index: index, descending: true) {
            guard let container = element(at: place.path, in: without) else { continue }
            for tag in suggestions(in: container, after: place.after)
            where !kinds.contains(where: { $0.tag == tag }) {
                kinds.append((tag, place))
            }
        }
        if let current = kinds.firstIndex(where: { $0.tag == unitElement.name }) {
            return KindChoices(kinds: kinds, current: current, without: without)
        }
        // What the block is now is always one of the choices.
        kinds.insert((unitElement.name, Place(path: parentPath, index: index, after: nil)), at: 0)
        return KindChoices(kinds: kinds, current: 0, without: without)
    }

    // MARK: - Delete

    /// Removes the block at `path`, with any element that held nothing else,
    /// and returns the block before it. Returns nil for the first block, and
    /// for a block its parent requires and has no other of.
    public func deletingBlock(at path: Path, in document: SpringwaterDocument) -> Change? {
        let all = blocks(of: document)
        guard let position = all.firstIndex(where: { $0.path == path }), position > 0 else { return nil }
        let unit = unitPath(for: path, in: document.root)
        let parentPath = Array(unit.dropLast())
        guard let index = unit.last,
              let parent = element(at: parentPath, in: document.root),
              let unitElement = element(at: unit, in: document.root) else { return nil }

        if let rule = schema?.rules[parent.name] {
            let names = elements(of: parent).map(\.name)
            let onlyRequired = rule.mustContain.contains(unitElement.name)
                && names.filter({ $0 == unitElement.name }).count == 1
            // The last of a group the parent needs at least one of.
            let onlyOneOf = rule.mustContainOneOf.contains(unitElement.name)
                && names.filter({ rule.mustContainOneOf.contains($0) }).count == 1
            if onlyRequired || onlyOneOf { return nil }
        }
        let root = replacing(document.root, at: parentPath) { children in
            var remaining = children
            remaining.remove(at: index)
            return remaining
        }
        // Removing an element never moves a block that comes before it.
        return Change(document: SpringwaterDocument(root: root), path: all[position - 1].path)
    }

    // MARK: - What may come next

    /// The kinds that may be added inside `container` right after a child
    /// named `after`, or at its start when `after` is nil.
    ///
    /// A profile, when there is one, is the only authority and is read
    /// literally: an entry with no `after` says what begins a container, an
    /// entry with `after` says what follows that kind, and no entry means
    /// nothing goes here. Without a profile the schema is the fallback.
    /// What the container still requires comes first.
    private func suggestions(in container: Element, after: String?) -> [String] {
        let list: [String]
        if let profile {
            list = profile.suggestions(parent: container.name, after: after) ?? []
        } else {
            list = schemaSuggestions(parent: container.name, after: after)
        }
        let required = list.filter { isRequiredAndAbsent($0, in: container) }
        return required + list.filter { !required.contains($0) }
    }

    private func schemaSuggestions(parent: String, after: String?) -> [String] {
        guard let rule = schema?.rules[parent] else {
            return after.map { [$0] } ?? []
        }
        var all: [String] = []
        for tag in rule.mustContain + rule.mustContainOneOf + rule.mayContain
        where tag != "validated_by" && !all.contains(tag) {
            all.append(tag)
        }
        // With nothing better to go on, the same kind again comes first.
        if let after, all.contains(after) {
            all = [after] + all.filter { $0 != after }
        }
        return all
    }

    private func isRequiredAndAbsent(_ tag: String, in container: Element) -> Bool {
        guard let rule = schema?.rules[container.name] else { return false }
        let present = elements(of: container).map(\.name)
        if rule.mustContain.contains(tag) { return !present.contains(tag) }
        // One of a group the container needs at least one of, and has none of.
        return rule.mustContainOneOf.contains(tag)
            && !present.contains(where: { rule.mustContainOneOf.contains($0) })
    }

    // MARK: - Places

    /// A place a new element could go: inside the container at `path`, at
    /// position `index` among its children, right after an element named
    /// `after`.
    private struct Place {
        var path: Path
        var index: Int
        var after: String?
    }

    /// The places a new block could go at one point in the document,
    /// innermost first.
    ///
    /// From the given position it looks outward: when the position is at the
    /// end of its container, the place just after that container counts too,
    /// and so on up to the work itself. When `descending`, it first looks
    /// inward: the end of the element just before the position, and the end of
    /// that element's last element, and so on.
    private func levels(in root: Element, path: Path, index: Int, descending: Bool) -> [Place] {
        var places: [Place] = []

        if descending, var container = element(at: path, in: root) {
            var inner: [Place] = []
            var containerPath = path
            var position = index
            while let previous = lastElementIndex(in: container, before: position),
                  case .element(let child) = container.children[previous], !isBlock(child) {
                containerPath.append(previous)
                container = child
                position = container.children.count
                inner.append(Place(
                    path: containerPath,
                    index: position,
                    after: elementName(in: container, before: position)
                ))
            }
            places.append(contentsOf: inner.reversed())
        }

        var containerPath = path
        var position = index
        while let container = element(at: containerPath, in: root) {
            places.append(Place(
                path: containerPath,
                index: position,
                after: elementName(in: container, before: position)
            ))
            // Go up only from the end of a container, and never above the work.
            guard containerPath.count > 1, !hasElement(in: container, from: position),
                  let own = containerPath.last else { break }
            position = own + 1
            containerPath.removeLast()
        }
        return places
    }

    private func inserting(_ element: Element, at place: Place, in root: Element) -> Element {
        replacing(root, at: place.path) { children in
            var changed = children
            changed.insert(.element(element), at: min(place.index, changed.count))
            return changed
        }
    }

    /// The largest element around the block that holds nothing but that
    /// block. A cue alone in its dialogue stands for the whole dialogue.
    private func unitPath(for path: Path, in root: Element) -> Path {
        var unit = path
        while unit.count > 2,
              let parent = element(at: Array(unit.dropLast()), in: root),
              elements(of: parent).count == 1 {
            unit.removeLast()
        }
        return unit
    }

    // MARK: - Building

    /// A new element of this kind holding `text`. A kind that holds other
    /// elements is built down to its first block: a dialogue is built as a
    /// dialogue holding a character.
    private func build(_ tag: String, text: String, depth: Int = 0) -> Element {
        guard !isLeafTag(tag), depth < 8 else {
            return Element(name: tag, children: Self.contentLines(text))
        }
        let rule = schema?.rules[tag]
        let first = profile?.suggestions(parent: tag, after: nil)?.first
            ?? rule?.mustContain.first
            ?? rule?.mustContainOneOf.first
            ?? rule?.mayContain.first
        guard let first else {
            return Element(name: tag, children: Self.contentLines(text))
        }
        return Element(name: tag, children: [.element(build(first, text: text, depth: depth + 1))])
    }

    private func firstBlockPath(in element: Element, from path: Path) -> Path {
        var current = element
        var found = path
        while !isBlock(current),
              let index = current.children.firstIndex(where: { if case .element = $0 { true } else { false } }),
              case .element(let child) = current.children[index] {
            found.append(index)
            current = child
        }
        return found
    }

    // MARK: - Tree

    private typealias Element = SpringwaterDocument.Element
    private typealias Child = SpringwaterDocument.Child

    /// True when elements with this name hold text and no other elements.
    private func isLeafTag(_ tag: String) -> Bool {
        guard let rule = schema?.rules[tag] else { return true }
        if rule.textOnly { return true }
        return rule.mustContain.isEmpty && rule.mustContainOneOf.isEmpty
            && rule.mayContain.isEmpty && rule.mustContainCount == nil
    }

    private func isBlock(_ element: Element) -> Bool {
        elements(of: element).isEmpty && isLeafTag(element.name)
    }

    private func elements(of element: Element) -> [Element] {
        element.children.compactMap { if case .element(let child) = $0 { child } else { nil } }
    }

    private func text(of element: Element) -> String {
        element.children.compactMap { child -> String? in
            if case .content(let line) = child { line.text } else { nil }
        }
        .joined(separator: "\n")
    }

    private static func contentLines(_ text: String) -> [Child] {
        guard !text.isEmpty else { return [] }
        return text.split(separator: "\n", omittingEmptySubsequences: false).map { line in
            Child.content(SpringwaterDocument.ContentLine(text: String(line), lineEnding: .lf))
        }
    }

    /// The index of the document's work: the first element under the root.
    private func workIndex(of root: Element) -> Int? {
        root.children.firstIndex { if case .element = $0 { true } else { false } }
    }

    private func element(at path: Path, in root: Element) -> Element? {
        var current = root
        for index in path {
            guard current.children.indices.contains(index),
                  case .element(let child) = current.children[index] else { return nil }
            current = child
        }
        return current
    }

    /// A copy of `root` in which the children of the element at `path` are
    /// replaced by what `transform` returns. A path that leads nowhere leaves
    /// the tree as it was.
    private func replacing(
        _ root: Element,
        at path: Path,
        with transform: ([Child]) -> [Child]
    ) -> Element {
        guard let index = path.first else {
            return Element(name: root.name, children: transform(root.children))
        }
        guard root.children.indices.contains(index),
              case .element(let child) = root.children[index] else { return root }
        var children = root.children
        children[index] = .element(replacing(child, at: Array(path.dropFirst()), with: transform))
        return Element(name: root.name, children: children)
    }

    private func lastElementIndex(in container: Element, before position: Int) -> Int? {
        var index = min(position, container.children.count) - 1
        while index >= 0 {
            if case .element = container.children[index] { return index }
            index -= 1
        }
        return nil
    }

    private func elementName(in container: Element, before position: Int) -> String? {
        guard let index = lastElementIndex(in: container, before: position),
              case .element(let element) = container.children[index] else { return nil }
        return element.name
    }

    private func hasElement(in container: Element, from position: Int) -> Bool {
        container.children.dropFirst(max(position, 0)).contains { if case .element = $0 { true } else { false } }
    }
}
