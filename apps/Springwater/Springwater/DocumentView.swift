import SwiftUI
import SpringwaterSchema
import SpringwaterSyntax

/// One document window: the source or the page, a status line, and an
/// inspector that lists what is wrong.
struct DocumentView: View {
    @Binding var file: SpringwaterFile
    let library: Library

    private enum Mode: String, CaseIterable, Identifiable {
        case source = "Source"
        case page = "Page"
        var id: Self { self }
    }

    @State private var mode: Mode = .source
    @State private var reading: Reading?
    @State private var showsIssues = false
    @State private var startedBlank = false

    /// A new, untouched document: offer the kinds before showing an empty page.
    private var isChoosingKind: Bool {
        !startedBlank && file.text == SpringwaterFile.emptyDocumentText
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
                    Picker("View", selection: $mode) {
                        ForEach(Mode.allCases) { mode in
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
                reading = Reading(text: file.text, library: library)
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
        } else {
            documentContent
        }
    }

    @ViewBuilder
    private var documentContent: some View {
        switch mode {
        case .source:
            SourceEditor(text: $file.text)
        case .page:
            switch reading?.syntax {
            case .valid(let document):
                PageView(
                    document: document,
                    presentation: reading?.root.flatMap { library.presentations[$0] }
                )
            case .invalid(let error):
                ContentUnavailableView(
                    "Not Valid Springwater",
                    systemImage: "exclamationmark.triangle",
                    description: Text(error.description)
                )
            case nil:
                ProgressView()
            }
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

/// The document's text, edited as plain text.
private struct SourceEditor: View {
    @Binding var text: String
    @State private var selection: TextSelection?

    var body: some View {
        TextEditor(text: $text, selection: $selection)
            .font(.system(.body, design: .monospaced))
            .autocorrectionDisabled()
            #if os(iOS)
            .textInputAutocapitalization(.never)
            .toolbar {
                // The caret sits two keyboard pages deep on iPhone, and every
                // tag begins with one.
                ToolbarItemGroup(placement: .keyboard) {
                    Button("^") { replaceSelection(with: "^") }
                        .font(.system(.title3, design: .monospaced))
                        .accessibilityLabel("Caret")
                    Button("^/", action: closeInnermostElement)
                        .font(.system(.title3, design: .monospaced))
                        .accessibilityLabel("Close Tag")
                    Spacer()
                }
            }
            #endif
    }

    /// The selected range, or the end of the text when nothing is selected.
    private var selectedRange: Range<String.Index> {
        if case .selection(let range) = selection?.indices, range.upperBound <= text.endIndex {
            range
        } else {
            text.endIndex..<text.endIndex
        }
    }

    /// Types `insertion` at the insertion point, replacing any selected text,
    /// and leaves the insertion point after it.
    private func replaceSelection(with insertion: String) {
        let range = selectedRange
        let offset = text.utf16.distance(from: text.utf16.startIndex, to: range.lowerBound)
        text.replaceSubrange(range, with: insertion)
        selection = TextSelection(
            insertionPoint: String.Index(utf16Offset: offset + insertion.utf16.count, in: text)
        )
    }

    /// Writes the closing tag for the innermost element still open before the
    /// insertion point, on a line of its own. Does nothing when none is open.
    private func closeInnermostElement() {
        let range = selectedRange
        let before = text[..<range.lowerBound]
        guard let name = SpringwaterEditorSupport.openElementNames(in: String(before)).last else {
            return
        }
        var insertion = "^\(name)/"
        if let previous = before.last, !previous.isNewline {
            insertion = "\n" + insertion
        }
        if text[range.upperBound...].first?.isNewline != true {
            insertion += "\n"
        }
        replaceSelection(with: insertion)
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
            Label("Valid \(root)", systemImage: "checkmark.circle")
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
