import Foundation
import SpringwaterSchema
import SpringwaterSyntax

/// The schemas and presentations that ship inside the app.
///
/// They are the repository's own `schemas/` and `presentations/` folders,
/// copied into the bundle unchanged at build time.
struct Library: Sendable {
    /// One bundled schema and what the app needs to offer it by name.
    struct Kind: Sendable, Identifiable {
        /// The root element the schema requires, such as `screenplay`.
        let root: String
        /// The schema's own name, from its metadata, such as "Screenplay".
        let name: String
        /// What a document writes in `validated_by`, such as "screenplay.schema v1.0".
        let reference: String
        let schema: Schema

        var id: String { root }
    }

    /// Bundled kinds keyed by the root element they require.
    private(set) var kinds: [String: Kind] = [:]

    /// Presentation documents keyed by the schema root they dress.
    private(set) var presentations: [String: SpringwaterDocument] = [:]

    static let bundled = Library(bundle: .main)

    init(bundle: Bundle) {
        for (url, document) in Self.documents(in: "schemas", of: bundle) {
            guard let schema = try? Schema(parsing: document) else { continue }
            let metadata = document.root.firstElement(named: "schema")?.firstElement(named: "metadata")
            let name = metadata?.firstElement(named: "name")?.trimmedContent ?? ""
            let version = metadata?.firstElement(named: "version")?.trimmedContent ?? ""
            // "screenplay.schema.springwater" is referred to as "screenplay.schema".
            let stem = url.deletingPathExtension().lastPathComponent
            kinds[schema.requiredRoot] = Kind(
                root: schema.requiredRoot,
                name: name.isEmpty ? schema.requiredRoot : name,
                reference: version.isEmpty ? stem : "\(stem) v\(version)",
                schema: schema
            )
        }
        for (_, document) in Self.documents(in: "presentations", of: bundle) {
            let target = document.root
                .firstElement(named: "presentation")?
                .firstElement(named: "metadata")?
                .firstElement(named: "target_schema")?
                .trimmedContent
            if let target, !target.isEmpty {
                presentations[target] = document
            }
        }
    }

    /// The bundled kinds in alphabetical order by name.
    var sortedKinds: [Kind] {
        kinds.values.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private static func documents(in folder: String, of bundle: Bundle) -> [(URL, SpringwaterDocument)] {
        let urls = bundle.urls(forResourcesWithExtension: "springwater", subdirectory: folder) ?? []
        return urls.compactMap { url in
            guard let data = try? Data(contentsOf: url),
                  let document = try? SpringwaterParser.parse(data) else { return nil }
            return (url, document)
        }
    }
}

extension SpringwaterDocument.Element {
    /// The element's child elements, in document order.
    var elements: [SpringwaterDocument.Element] {
        children.compactMap { child in
            if case .element(let element) = child { element } else { nil }
        }
    }

    func firstElement(named name: String) -> SpringwaterDocument.Element? {
        elements.first { $0.name == name }
    }

    /// The element's own content lines joined with line feeds, exactly as written.
    var content: String {
        children.compactMap { child in
            if case .content(let line) = child { line.text } else { nil }
        }
        .joined(separator: "\n")
    }

    /// The content with surrounding whitespace removed, for short values.
    var trimmedContent: String {
        content.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
