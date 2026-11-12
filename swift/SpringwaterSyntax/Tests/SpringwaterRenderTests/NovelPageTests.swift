import Foundation
import Testing
import SpringwaterSyntax
@testable import SpringwaterRender

private let repository = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent()
    .deletingLastPathComponent().deletingLastPathComponent()
    .deletingLastPathComponent()

@Suite(.enabled(if: FileManager.default.fileExists(atPath:
    repository.appendingPathComponent("presentations/novel.presentation.springwater").path)))
struct NovelPageTests {
    @Test func includedNovelUsesItsActualPresentationGeometry() throws {
        let presentation = try SpringwaterParser.parse(Data(contentsOf:
            repository.appendingPathComponent("presentations/novel.presentation.springwater")))
        let document = try SpringwaterParser.parse(Data(contentsOf:
            repository.appendingPathComponent("examples/sun_also_rises.springwater")))
        let html = HTMLRenderer.render(document, presentation: presentation)
        #expect(html.contains("width: 6in; min-height: 9in;"))
        #expect(html.contains("padding: 0.75in 0.75in 0.75in 0.75in;"))
        #expect(html.contains("@page { size: 6in 9in; margin: 0.75in 0.75in 0.75in 0.75in; }"))
        #expect(html.contains("The Sun Also Rises"))
        #expect(html.contains("Spider Kelly not only remembered Cohn."))
    }
}
