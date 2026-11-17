import Testing
import Foundation
import SpringwaterSyntax
@testable import SpringwaterSchema

// These cases were first worked out and run against a JavaScript prototype of
// the same rules, then carried over here one for one.

private let repoRoot: URL = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()   // SpringwaterSchemaTests/
    .deletingLastPathComponent()   // Tests/
    .deletingLastPathComponent()   // SpringwaterSyntax/
    .deletingLastPathComponent()   // swift/
    .deletingLastPathComponent()   // <repo root>

private let repositoryAvailable: Bool =
    FileManager.default.fileExists(atPath: repoRoot.appendingPathComponent("profiles").path)

private func parseFile(_ relativePath: String) throws -> SpringwaterDocument {
    try SpringwaterParser.parse(try Data(contentsOf: repoRoot.appendingPathComponent(relativePath)))
}

private func screenplayEditor() throws -> BlockEditor {
    BlockEditor(
        schema: try Schema(parsing: parseFile("schemas/screenplay.schema.springwater")),
        profile: AuthoringProfile(parsing: try parseFile("profiles/screenplay.authoring.springwater"))
    )
}

/// A starter screenplay: one scene with an empty slugline.
private let starter = """
^Springwater
^screenplay
^validated_by
screenplay.schema v2.0
^validated_by/
^act1
^scene
^slugline

^slugline/
^scene/
^act1/
^screenplay/
^Springwater/

"""

/// Each block as "tag" or "tag=text", for compact comparison.
private func summary(_ editor: BlockEditor, _ document: SpringwaterDocument) -> [String] {
    editor.blocks(of: document).map { $0.text.isEmpty ? $0.tag : "\($0.tag)=\($0.text)" }
}

@Suite(.enabled(if: repositoryAvailable))
struct ScreenplayBlockEditing {

    /// Types a short scene with Return and Tab only and checks every step.
    @Test func writingASceneWithReturnAndTab() throws {
        let editor = try screenplayEditor()
        var document = try SpringwaterParser.parse(starter)
        #expect(summary(editor, document) == ["slugline"])

        var cursor = try #require(editor.blocks(of: document).first).path
        document = editor.settingText("INT. HOUSE - DAY", at: cursor, in: document)

        // Return after a slugline gives action.
        var change = try #require(editor.insertingBlock(after: cursor, in: document))
        document = change.document; cursor = change.path
        #expect(summary(editor, document) == ["slugline=INT. HOUSE - DAY", "action"])

        // Return after action gives action.
        document = editor.settingText("She waits.", at: cursor, in: document)
        change = try #require(editor.insertingBlock(after: cursor, in: document))
        document = change.document; cursor = change.path
        #expect(summary(editor, document) == ["slugline=INT. HOUSE - DAY", "action=She waits.", "action"])

        // The kinds a trailing action can be, in Tab order.
        let kinds = try #require(editor.kinds(at: cursor, in: document))
        #expect(kinds.names == ["action", "dialogue", "transition", "shot", "scene", "montage"])
        #expect(kinds.current == 0)

        // Tab turns the action into a character cue, inside a dialogue.
        change = try #require(editor.changingKind(at: cursor, in: document))
        document = change.document; cursor = change.path
        #expect(summary(editor, document) == ["slugline=INT. HOUSE - DAY", "action=She waits.", "character"])
        let cue = document

        // Three more Tabs: transition, shot, then a new scene's slugline.
        change = try #require(editor.changingKind(at: cursor, in: document))
        #expect(summary(editor, change.document).last == "transition")
        change = try #require(editor.changingKind(at: change.path, in: change.document))
        change = try #require(editor.changingKind(at: change.path, in: change.document))
        #expect(summary(editor, change.document) == ["slugline=INT. HOUSE - DAY", "action=She waits.", "slugline"])
        #expect(SpringwaterSerializer.serialize(change.document)
            .hasSuffix("^scene/\n^scene\n^slugline\n^slugline/\n^scene/\n^act1/\n^screenplay/\n^Springwater/\n"))

        // Three Shift-Tabs walk back to the cue exactly.
        for _ in 0..<3 {
            change = try #require(editor.changingKind(at: change.path, forward: false, in: change.document))
        }
        #expect(change.document == cue)

        // Six Tabs from the cue come all the way round.
        change = BlockEditor.Change(document: cue, path: cursor)
        for _ in 0..<6 {
            change = try #require(editor.changingKind(at: change.path, in: change.document))
        }
        #expect(change.document == cue)

        // Return after a cue gives lines, which the dialogue still requires.
        document = editor.settingText("ANNA", at: cursor, in: document)
        change = try #require(editor.insertingBlock(after: cursor, in: document))
        document = change.document; cursor = change.path
        #expect(Array(summary(editor, document).suffix(2)) == ["character=ANNA", "lines"])
        #expect(editor.kinds(at: cursor, in: document)?.names
            == ["lines", "parenthetical", "action", "dialogue", "transition", "shot", "scene", "montage"])

        // Tab on empty lines gives a parenthetical.
        let parenthetical = try #require(editor.changingKind(at: cursor, in: document))
        #expect(Array(summary(editor, parenthetical.document).suffix(2)) == ["character=ANNA", "parenthetical"])

        // A cue that has lines can be nothing else.
        document = editor.settingText("Not yet.", at: cursor, in: document)
        #expect(editor.changingKind(at: editor.blocks(of: document)[2].path, in: document) == nil)

        // Return after lines leaves the dialogue and gives action.
        change = try #require(editor.insertingBlock(after: cursor, in: document))
        document = change.document; cursor = change.path
        #expect(summary(editor, document)
            == ["slugline=INT. HOUSE - DAY", "action=She waits.", "character=ANNA", "lines=Not yet.", "action"])

        // What was written is a valid screenplay.
        let finished = editor.settingText("Rain.", at: cursor, in: document)
        let schema = try #require(editor.schema)
        #expect(SchemaValidator.validate(finished, against: schema).isEmpty)

        // Deleting the empty action puts the insertion point in the lines.
        let deleted = try #require(editor.deletingBlock(at: cursor, in: document))
        #expect(summary(editor, deleted.document)
            == ["slugline=INT. HOUSE - DAY", "action=She waits.", "character=ANNA", "lines=Not yet."])
        #expect(deleted.path == editor.blocks(of: deleted.document)[3].path)

        // The first block and required blocks are not deleted.
        #expect(editor.deletingBlock(at: editor.blocks(of: document)[0].path, in: document) == nil)
        #expect(editor.deletingBlock(at: editor.blocks(of: document)[3].path, in: document) == nil)

        // In the middle of a scene the kinds stay inside the scene.
        #expect(editor.kinds(at: editor.blocks(of: document)[1].path, in: document)?.names == ["action", "dialogue"])

        // Return in the middle of a block carries the text after the cursor.
        let split = try #require(editor.insertingBlock(
            after: editor.blocks(of: document)[1].path, carrying: "tail", in: document))
        #expect(Array(summary(editor, split.document)[1...2]) == ["action=She waits.", "action=tail"])
    }

    /// A screenplay needs no acts: scenes sit directly in it, and a new scene
    /// or a montage is a Tab away.
    @Test func writingWithoutActs() throws {
        let editor = try screenplayEditor()
        var document = try SpringwaterParser.parse("""
        ^Springwater
        ^screenplay
        ^scene
        ^slugline

        ^slugline/
        ^scene/
        ^screenplay/
        ^Springwater/

        """)
        var cursor = try #require(editor.blocks(of: document).first).path
        document = editor.settingText("INT. HOUSE - DAY", at: cursor, in: document)
        var change = try #require(editor.insertingBlock(after: cursor, in: document))
        document = change.document; cursor = change.path
        #expect(summary(editor, document) == ["slugline=INT. HOUSE - DAY", "action"])
        #expect(editor.kinds(at: cursor, in: document)?.names == ["action", "dialogue", "scene", "montage", "transition"])

        // Two Tabs: a new scene, directly in the screenplay.
        change = try #require(editor.changingKind(at: cursor, in: document))
        change = try #require(editor.changingKind(at: change.path, in: change.document))
        #expect(summary(editor, change.document) == ["slugline=INT. HOUSE - DAY", "slugline"])
        let twoScenes = editor.settingText("EXT. YARD - DAY", at: change.path, in: change.document)
        let schema = try #require(editor.schema)
        #expect(SchemaValidator.validate(twoScenes, against: schema).isEmpty)

        // One more Tab: a montage, which begins with its heading; Return gives a shot.
        change = try #require(editor.changingKind(at: change.path, in: change.document))
        #expect(summary(editor, change.document) == ["slugline=INT. HOUSE - DAY", "heading"])
        let headed = editor.settingText("MONTAGE - TRAINING", at: change.path, in: change.document)
        change = try #require(editor.insertingBlock(after: change.path, in: headed))
        #expect(summary(editor, change.document) == ["slugline=INT. HOUSE - DAY", "heading=MONTAGE - TRAINING", "shot"])
    }

    /// An action right after a cue with no lines can become that cue's lines.
    @Test func actionAfterALoneCueCanBecomeItsLines() throws {
        let editor = try screenplayEditor()
        let document = try SpringwaterParser.parse("""
        ^Springwater
        ^screenplay
        ^act1
        ^scene
        ^slugline
        X
        ^slugline/
        ^dialogue
        ^character
        BOB
        ^character/
        ^dialogue/
        ^action
        hi
        ^action/
        ^scene/
        ^act1/
        ^screenplay/
        ^Springwater/

        """)
        let action = editor.blocks(of: document)[2].path
        #expect(editor.kinds(at: action, in: document)?.names
            == ["lines", "parenthetical", "action", "dialogue", "transition", "shot", "scene", "montage"])
    }

    /// Setting every block to the text it already has changes nothing.
    @Test func settingUnchangedTextLeavesEveryExampleAsItWas() throws {
        let editor = try screenplayEditor()
        for name in ["the_first_swim", "sun_also_rises", "swift_reference", "genesis_1_3"] {
            let document = try parseFile("examples/\(name).springwater")
            var edited = document
            for block in editor.blocks(of: document) {
                edited = editor.settingText(block.text, at: block.path, in: edited)
            }
            #expect(edited == document, "\(name) changed")
        }
    }

    /// With no profile, the schema decides: the same kind again comes first.
    @Test func withoutAProfileReturnRepeatsTheKind() throws {
        let editor = BlockEditor(
            schema: try Schema(parsing: parseFile("schemas/novel.schema.springwater")),
            profile: nil
        )
        let document = try parseFile("examples/sun_also_rises.springwater")
        let paragraph = try #require(editor.blocks(of: document).last { $0.tag == "paragraph" })
        let change = try #require(editor.insertingBlock(after: paragraph.path, in: document))
        let added = try #require(editor.blocks(of: change.document).first { $0.path == change.path })
        #expect(added.tag == "paragraph")
    }
}

/// With neither schema nor profile every element without children is a block,
/// and Return repeats the kind.
@Test func withNothingToGoOnEveryLeafIsABlock() throws {
    let editor = BlockEditor(schema: nil, profile: nil)
    let document = try SpringwaterParser.parse("^Springwater\n^list\n^item\none\n^item/\n^list/\n^Springwater/\n")
    #expect(editor.blocks(of: document).map(\.tag) == ["item"])
    let change = try #require(editor.insertingBlock(after: editor.blocks(of: document)[0].path, in: document))
    #expect(editor.blocks(of: change.document).map(\.tag) == ["item", "item"])
}

@Test func profileIsReadFromItsCompletions() throws {
    let profile = AuthoringProfile(parsing: try SpringwaterParser.parse("""
    ^Springwater
    ^authoring_profile
    ^metadata
    ^target_schema
    memo
    ^target_schema/
    ^metadata/
    ^completions
    ^completion
    ^context
    ^parent
    memo
    ^parent/
    ^context/
    ^suggestions
    ^suggestion
    title
    ^suggestion/
    ^suggestions/
    ^completion/
    ^completion
    ^context
    ^parent
    memo
    ^parent/
    ^after
    title
    ^after/
    ^context/
    ^suggestions
    ^suggestion
    body
    ^suggestion/
    ^suggestion
    note
    ^suggestion/
    ^suggestions/
    ^completion/
    ^completions/
    ^authoring_profile/
    ^Springwater/

    """))
    #expect(profile.targetSchema == "memo")
    #expect(profile.suggestions(parent: "memo", after: nil) == ["title"])
    #expect(profile.suggestions(parent: "memo", after: "title") == ["body", "note"])
    #expect(profile.suggestions(parent: "memo", after: "body") == nil)
}
