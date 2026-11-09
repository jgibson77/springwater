/// The result of parsing a valid Springwater document: an ordered tree.
///
/// The model follows the PARSED REPRESENTATION section of the canonical
/// syntax. Each element holds an ordered sequence of children, where each
/// child is either a content line or a child element. Ordering reflects
/// the order of physical lines in the source. A parser that loses this
/// ordering, or that discards original line endings, does not conform.
///
/// The parsed result is the root element itself, named `Springwater`,
/// whose children are the document's top-level content lines and elements.
/// The root opening and closing tag lines are not stored as content or as
/// children.
public struct SpringwaterDocument: Sendable, Equatable {

    /// The single document root. Its name is always `Springwater`.
    public let root: Element

    public init(root: Element) {
        self.root = root
    }

    /// A named container in the document tree.
    public struct Element: Sendable, Equatable {
        public let name: String
        public let children: [Child]

        public init(name: String, children: [Child]) {
            self.name = name
            self.children = children
        }
    }

    /// One ordered child of an element: a preserved content line or a
    /// nested element.
    public enum Child: Sendable, Equatable {
        case content(ContentLine)
        case element(Element)
    }

    /// A preserved content line.
    ///
    /// `text` is the original line text, exactly as it appeared in the
    /// source, including leading and trailing whitespace. `lineEnding`
    /// is the original delimiter that terminated the physical line, and is
    /// always `lf`, `crlf`, or `cr` — never absent, because a content line
    /// is never the final physical line of a valid document.
    public struct ContentLine: Sendable, Equatable {
        public let text: String
        public let lineEnding: ContentLineEnding

        public init(text: String, lineEnding: ContentLineEnding) {
            self.text = text
            self.lineEnding = lineEnding
        }
    }

    /// The line-ending sequence of a physical line, as produced by line
    /// division. `none` is the final physical line of a file that has no
    /// trailing line break.
    ///
    /// This is the PhysicalLineEnding of the canonical syntax. It carries
    /// the `none` case; `ContentLineEnding` does not. Keeping them distinct
    /// makes "a content line never carries an absent ending" a fact of the
    /// type system rather than a convention.
    public enum PhysicalLineEnding: Sendable, Equatable {
        case lf
        case crlf
        case cr
        case none
    }

    /// The line-ending sequence of a preserved content line: always one of
    /// `lf`, `crlf`, or `cr`. There is no absent case, because a content
    /// line is never the final physical line of a valid document.
    public enum ContentLineEnding: Sendable, Equatable {
        case lf
        case crlf
        case cr

        /// Narrows a physical line ending to a content line ending.
        /// Returns `nil` for `.none`, the one physical ending a content
        /// line can never carry.
        public init?(_ physical: PhysicalLineEnding) {
            switch physical {
            case .lf: self = .lf
            case .crlf: self = .crlf
            case .cr: self = .cr
            case .none: return nil
            }
        }
    }
}
