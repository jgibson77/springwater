import SwiftUI
import SpringwaterSchema
import SpringwaterSyntax

/// One document window.
///
/// There are three ways to look at a document. Write is the page as a place
/// to type, with no tags in sight. Source is the Springwater text itself.
/// Page is the document as it reads. Where there is room, the source sits on
/// the left and Write or Page on the right, and each follows the other. On a
/// narrow screen there is room for one, and a control at the top switches
/// between them. A status line and an inspector say what is wrong.
struct DocumentView: View {
    @Binding var file: SpringwaterFile
    let library: Library

    private enum Mode: String, CaseIterable, Identifiable {
        case write = "Write"
        case source = "Source"
        case page = "Page"
        var id: Self { self }
    }

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    @State private var mode: Mode = .write
    @State private var reading: Reading?
    /// The most recent text that was valid Springwater. The page keeps showing
    /// it while the writer is partway through a tag, so the page does not
    /// vanish on every keystroke.
    @State private var lastValid: SpringwaterDocument?
    @State private var showsIssues = false
    @State private var startedBlank = false

    /// A new, untouched document: offer the kinds before showing an empty page.
    private var isChoosingKind: Bool {
        !startedBlank && file.text == SpringwaterFile.emptyDocumentText
    }

    /// True when the window is wide enough for the source and the page together.
    private var showsBoth: Bool {
        horizontalSizeClass == .regular
    }

    var body: some View {
        content
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if let reading {
                    StatusLine(reading: reading) { showsIssues.toggle() }
                }
            }
            .toolbar {
                ToolbarItem(placement: .principal) {
                    // Beside the source there is only the right-hand side to choose.
                    Picker("View", selection: showsBoth ? rightSide : $mode) {
                        ForEach(showsBoth ? [Mode.write, .page] : Mode.allCases) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                ToolbarItem(placement: .primaryAction) {
                    Toggle("Issues", systemImage: "exclamationmark.triangle", isOn: $showsIssues)
                }
            }
            .inspector(isPresented: $showsIssues) {
                IssueList(reading: reading)
                    .inspectorColumnWidth(min: 220, ideal: 300, max: 420)
            }
            .task(id: file.text) {
                // Read at once the first time, then wait for a pause in typing.
                if reading != nil {
                    try? await Task.sleep(for: .milliseconds(250))
                    if Task.isCancelled { return }
                }
                let reading = Reading(text: file.text, library: library)
                self.reading = reading
                if let document = reading.document {
                    lastValid = document
                }
            }
    }

    @ViewBuilder
    private var content: some View {
        if isChoosingKind {
            KindChooser(kinds: library.sortedKinds) { kind in
                if let kind {
                    file.text = kind.starterText
                } else {
                    startedBlank = true
                }
            }
        } else if showsBoth {
            sideBySide
        } else {
            switch mode {
            case .write: writingPane
            case .source: SourceTextView(text: $file.text)
            case .page: pagePane
            }
        }
    }

    /// The source on the left and the page on the right.
    @ViewBuilder
    private var sideBySide: some View {
        #if os(macOS)
        HSplitView {
            SourceTextView(text: $file.text)
                .frame(minWidth: 260, maxWidth: .infinity, maxHeight: .infinity)
            rightPane
                .frame(minWidth: 260, maxWidth: .infinity, maxHeight: .infinity)
        }
        #else
        HStack(spacing: 0) {
            SourceTextView(text: $file.text)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider()
            rightPane
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        #endif
    }

    /// What sits beside the source: the page to write on, or the page to read.
    private var rightSide: Binding<Mode> {
        Binding(
            get: { mode == .page ? .page : .write },
            set: { mode = $0 }
        )
    }

    @ViewBuilder
    private var rightPane: some View {
        if mode == .page {
            pagePane
        } else {
            writingPane
        }
    }

    /// The page as a place to write. Each change made on it becomes the
    /// document's text at once, so the source beside it follows. While the
    /// source is not valid Springwater the page cannot be typed on: there is
    /// no document to change until the source is whole again.
    @ViewBuilder
    private var writingPane: some View {
        if let document = lastValid {
            let root = CarriedDocuments.workName(of: document)
            let isCurrent = reading?.document != nil
            PageEditor(
                document: document,
                presentation: root.flatMap { root in
                    CarriedDocuments.presentationDocument(in: document, for: root)
                        ?? library.presentations[root]
                },
                engine: BlockEditor(
                    schema: reading?.schema,
                    profile: root.flatMap { library.profiles[$0] }
                )
            ) { changed in
                lastValid = changed
                file.text = SpringwaterSerializer.serialize(changed)
            }
            .disabled(!isCurrent)
            .opacity(isCurrent ? 1 : 0.45)
        } else if case .invalid(let error) = reading?.syntax {
            ContentUnavailableView(
                "Not Valid Springwater",
                systemImage: "exclamationmark.triangle",
                description: Text(error.description)
            )
        } else {
            ProgressView()
        }
    }

    /// The page for the latest valid text. While the current text is not valid
    /// Springwater the last good page stays, dimmed, and the status line says
    /// what is wrong.
    @ViewBuilder
    private var pagePane: some View {
        if let document = lastValid {
            let root = CarriedDocuments.workName(of: document)
            PageView(
                document: document,
                presentation: root.flatMap { root in
                    CarriedDocuments.presentationDocument(in: document, for: root)
                        ?? library.presentations[root]
                }
            )
            .equatable()
            .opacity(reading?.document == nil ? 0.45 : 1)
        } else if case .invalid(let error) = reading?.syntax {
            ContentUnavailableView(
                "Not Valid Springwater",
                systemImage: "exclamationmark.triangle",
                description: Text(error.description)
            )
        } else {
            ProgressView()
        }
    }
}

/// Offers a starting document for each bundled schema, or a blank one.
private struct KindChooser: View {
    let kinds: [Library.Kind]
    /// Called with the chosen kind, or nil for a blank document.
    let choose: (Library.Kind?) -> Void

    var body: some View {
        List {
            Section("New Document") {
                Button("Blank") { choose(nil) }
                ForEach(kinds) { kind in
                    Button(kind.name) { choose(kind) }
                }
            }
        }
    }
}

/// One line that answers both questions: is it Springwater, and is it a valid
/// document of its kind.
private struct StatusLine: View {
    let reading: Reading
    let showIssues: () -> Void

    var body: some View {
        Button(action: showIssues) {
            HStack(spacing: 12) {
                syntaxLabel
                kindLabel
                Spacer(minLength: 0)
            }
            .font(.callout)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .background(.bar)
        .accessibilityHint("Shows the list of issues")
    }

    @ViewBuilder
    private var syntaxLabel: some View {
        switch reading.syntax {
        case .valid:
            Label("Valid Springwater", systemImage: "checkmark.circle")
        case .invalid:
            Label("Not valid Springwater", systemImage: "xmark.octagon")
                .foregroundStyle(.red)
        }
    }

    @ViewBuilder
    private var kindLabel: some View {
        switch reading.kind {
        case .none:
            EmptyView()
        case .unknown(let root):
            Label("No schema for \(root)", systemImage: "questionmark.circle")
                .foregroundStyle(.secondary)
        case .checked(let root, let issues) where issues.isEmpty:
            Label(
                reading.usesCarriedSchema ? "Valid \(root), by the schema it carries" : "Valid \(root)",
                systemImage: "checkmark.circle"
            )
        case .checked(let root, let issues):
            Label(
                issues.count == 1 ? "1 \(root) issue" : "\(issues.count) \(root) issues",
                systemImage: "exclamationmark.triangle"
            )
                .foregroundStyle(.orange)
        }
    }
}

/// Everything that is wrong with the document, in plain words.
private struct IssueList: View {
    let reading: Reading?

    var body: some View {
        if let reading, reading.hasProblems {
            List {
                if case .invalid(let error) = reading.syntax {
                    Section("Springwater") {
                        Text(error.description)
                    }
                }
                if !reading.issues.isEmpty {
                    Section(reading.root ?? "Schema") {
                        ForEach(Array(reading.issues.enumerated()), id: \.offset) { _, issue in
                            Text(issue.message)
                        }
                    }
                }
            }
        } else {
            ContentUnavailableView("No Issues", systemImage: "checkmark.circle")
        }
    }
}
