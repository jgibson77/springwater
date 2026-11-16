import SwiftUI

/// A document-based app whose documents are Springwater files.
///
/// Each file is its own document: the user names it, moves it, duplicates it,
/// and shares it like any other file. The app stores nothing of its own.
@main
struct SpringwaterApp: App {
    private let library = Library.bundled

    var body: some Scene {
        DocumentGroup(newDocument: SpringwaterFile()) { file in
            DocumentView(file: file.$document, library: library)
        }
        #if os(macOS)
        .commands {
            CommandGroup(after: .newItem) {
                NewFromSchemaMenu(kinds: library.sortedKinds)
            }
        }
        #endif
    }
}

#if os(macOS)
/// File > New From Schema: a new document of each bundled kind.
/// Mac only: the action that opens a new document from a menu does not exist on iOS,
/// where the in-window list does this job.
private struct NewFromSchemaMenu: View {
    let kinds: [Library.Kind]
    @Environment(\.newDocument) private var newDocument

    var body: some View {
        Menu("New From Schema") {
            ForEach(kinds) { kind in
                Button(kind.name) {
                    newDocument(SpringwaterFile(text: kind.starterText))
                }
            }
        }
    }
}
#endif
