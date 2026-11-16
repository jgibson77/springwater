import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    /// A Springwater document: UTF-8 plain text with the `.springwater` extension.
    /// Declared in Info.plist as an exported type.
    static let springwater = UTType(exportedAs: "io.github.jgibson77.springwater")
}

/// The file on disk, held as its exact text.
///
/// The text is the single source of truth. The parsed tree, the validation
/// result, and the page view are all derived from it and never stored.
/// A file that is not valid Springwater still opens, so it can be repaired.
struct SpringwaterFile: FileDocument {
    static let readableContentTypes: [UTType] = [.springwater]

    /// The smallest valid Springwater document.
    static let emptyDocumentText = "^Springwater\n^Springwater/\n"

    var text: String

    init(text: String = SpringwaterFile.emptyDocumentText) {
        self.text = text
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        // Springwater is UTF-8. Decode strictly, with no repair, so that what is
        // written back is byte for byte what was read plus the user's edits.
        guard let text = String(validating: data, as: UTF8.self) else {
            throw CocoaError(.fileReadInapplicableStringEncoding)
        }
        self.text = text
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(text.utf8))
    }
}
