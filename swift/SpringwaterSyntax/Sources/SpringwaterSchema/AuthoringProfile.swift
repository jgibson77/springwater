import SpringwaterSyntax

/// An authoring profile: what a writer is likely to want next.
///
/// A schema says what a document is. A presentation says how it looks. An
/// authoring profile says how it is written: inside a given element, after a
/// given kind of element, which kinds usually come next. It is itself a
/// Springwater document (root element `authoring_profile`).
///
/// This type reads the profile's `completions`. Each one names a parent
/// element, optionally the element that came just before, and an ordered list
/// of suggestions.
public struct AuthoringProfile: Sendable, Equatable {

    /// One entry: inside `parent`, right after an element named `after` (or
    /// at the start of `parent` when `after` is nil), these kinds come next.
    public struct Completion: Sendable, Equatable {
        public let parent: String
        public let after: String?
        public let suggestions: [String]

        public init(parent: String, after: String?, suggestions: [String]) {
            self.parent = parent
            self.after = after
            self.suggestions = suggestions
        }
    }

    /// The root element name of the documents this profile is for.
    public let targetSchema: String?

    public let completions: [Completion]

    public init(targetSchema: String?, completions: [Completion]) {
        self.targetSchema = targetSchema
        self.completions = completions
    }

    /// Reads a parsed authoring profile document. Lenient by design: it takes
    /// the completions that are well formed and passes over the rest. Whether
    /// the profile is valid is answered by validating it against its schema.
    public init(parsing document: SpringwaterDocument) {
        let profile = document.root.childElements.first(where: { $0.name == "authoring_profile" })
        let metadata = profile?.childElements.first(where: { $0.name == "metadata" })
        targetSchema = metadata?.childElements.first(where: { $0.name == "target_schema" })?.contentValue

        var found: [Completion] = []
        let list = profile?.childElements.first(where: { $0.name == "completions" })
        for completion in list?.childElements ?? [] where completion.name == "completion" {
            guard let context = completion.childElements.first(where: { $0.name == "context" }),
                  let suggestions = completion.childElements.first(where: { $0.name == "suggestions" }),
                  let parent = context.childElements.first(where: { $0.name == "parent" })
            else { continue }
            let after = context.childElements.first(where: { $0.name == "after" })
            found.append(Completion(
                parent: parent.contentValue,
                after: after?.contentValue,
                suggestions: suggestions.childElements
                    .filter { $0.name == "suggestion" }
                    .map(\.contentValue)
                    .filter { !$0.isEmpty }
            ))
        }
        completions = found
    }

    /// The suggestions for exactly this place, or nil when the profile has no
    /// entry for it.
    public func suggestions(parent: String, after: String?) -> [String]? {
        completions.first { $0.parent == parent && $0.after == after }?.suggestions
    }
}
