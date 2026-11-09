import SpringwaterSyntax

/// Physical page geometry from the schema's `page` block. Missing properties
/// retain the renderer's original Letter defaults; all values are CSS lengths.
public struct PageStyle: Sendable, Equatable {
    public var width = "8.5in"
    public var height = "11in"
    public var marginTop = "1in"
    public var marginRight = "1in"
    public var marginBottom = "1in"
    public var marginLeft = "1.5in"

    public init() {}

    public init(parsing schemaDocument: SpringwaterDocument) {
        self.init()
        let schema = schemaDocument.root.renderChildElements.first { $0.name == "schema" }
        let page = schema?.renderChildElements.first { $0.name == "page" }
        for property in page?.renderChildElements ?? [] {
            let value = property.scalarValue
            guard !value.isEmpty else { continue }
            switch property.name {
            case "width": width = value
            case "height": height = value
            case "margin_top": marginTop = value
            case "margin_right": marginRight = value
            case "margin_bottom": marginBottom = value
            case "margin_left": marginLeft = value
            default: break
            }
        }
    }

    var margins: String { "\(marginTop) \(marginRight) \(marginBottom) \(marginLeft)" }
}
