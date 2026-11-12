# SpringwaterSyntax

The strict canonical parser for Springwater v1.0, as a Swift package.

Implements the frozen canonical syntax (SYNTAX.txt) exactly: UTF-8
validation, BOM rejection, physical line division at LF/CRLF/CR with
line-ending preservation, space-and-tab-only trimming, the reserved
root name, the first/last physical line rules, and the ordered
mixed-content tree representation.

No recovery. No invented nodes. No silent correction. Tolerant analysis
for editors is a separate system by design and does not belong in this
package.

The package ships four libraries, matching the Springwater architecture:

- **`SpringwaterSyntax`** — Layer 1 (Core): the syntax. Parse, tree,
  serialize. Knows nothing about what tags mean.
- **`SpringwaterSchema`** — Layer 2 (Schema): validity. Parses a schema
  (itself a Springwater document) into a rule model and checks a
  document against it. Depends only on `SpringwaterSyntax`; the
  dependency runs one way, never back.
- **`SpringwaterRender`** — rendering. Reads a presentation's
  `^rendering_rules` into a per-tag style map and renders a document to
  a styled HTML page. A presentation is a separate Springwater document
  that says how a document type looks; a schema says only what it is. No
  document-type logic is hardcoded, so the same renderer formats a
  screenplay, a novel, or a manual purely from its presentation. Depends
  only on `SpringwaterSyntax`.
- **`SpringwaterExport`** — export to Fountain. Walks a document and
  emits Fountain, inserting the forced markers (`!`, `@`, `.`, `>`) and
  escaping emphasis so a Fountain importer re-reads it into the same
  tree. A prior full-screenplay round-trip was reported as byte-lossless;
  see the verification limits below. Depends
  only on `SpringwaterSyntax`.

## Requirements

- Swift 6.0+
- Zero dependencies
- No platform floor. The package uses only `Data` and `String`, no
  OS-gated API, so it declares no `platforms:` minimum and embeds in an
  app of any deployment target the toolchain supports.

## Usage

```swift
import SpringwaterSyntax

let source = """
^Springwater
^screenplay
  ^scene
    ^slugline
    INT. OFFICE - DAY
    ^slugline/
    ^action
    JOHN enters the room.
    ^action/
  ^scene/
^screenplay/
^Springwater/
"""

let document = try SpringwaterParser.parse(source)

// Walk the ordered tree.
for child in document.root.children {
    if case .element(let screenplay) = child {
        print(screenplay.name)            // "screenplay"
        print(screenplay.children.count)  // 1
    }
}

// Serialize back to canonical form (flat tag lines, LF; content verbatim).
let canonical = SpringwaterSerializer.serialize(document)

// Or indent tag lines for reading. Tree-equal, but not canonical form.
let readable = SpringwaterSerializer.prettyPrinted(document)
```

### Schema validation

```swift
import SpringwaterSyntax
import SpringwaterSchema

// A schema is itself a Springwater document. Parse it, then build the model.
let schema = try Schema(parsing: try SpringwaterParser.parse(schemaSource))

// Validate a document. Returns every issue found; empty means valid.
let issues = SchemaValidator.validate(document, against: schema)
if issues.isValid {
    // conforms
} else {
    for issue in issues {
        print(issue.category, issue.tag, issue.message)
    }
}
```

Because a schema is just a document and the meta-schema
(`schema.schema.springwater`) is just another schema, the *same*
`SchemaValidator` checks both "this document conforms to its schema"
and "this schema conforms to the meta-schema." One validator, both
levels.

### Rendering

```swift
import SpringwaterSyntax
import SpringwaterRender

let document = try SpringwaterParser.parse(screenplaySource)
let presentation = try SpringwaterParser.parse(presentationSource)

// A complete styled HTML page, formatted per the presentation's rendering rules.
let html = HTMLRenderer.render(document, presentation: presentation, title: "LOW WATER")

// Or build the pieces: the CSS generated from the rules, and the body.
let styles = RenderStyles(parsing: presentation)
let css    = HTMLRenderer.css(styles)                       // one rule per tag
let body   = HTMLRenderer.bodyHTML(document, styles: styles)
```

The CSS is generated from the presentation's `^rendering_rules` — `indent` →
`margin-left`, `align` → `text-align`, `transform` → `text-transform`,
`spacing_after` → `margin-bottom`, and so on. The renderer adds no
screenplay knowledge of its own; point it at a different presentation and
it renders that document type instead.

### Export to Fountain

```swift
import SpringwaterSyntax
import SpringwaterExport

let document = try SpringwaterParser.parse(springwaterSource)
let fountain = FountainExporter.export(document)
```

The exporter inserts the forced markers and escapes the emphasis
characters a Fountain importer needs, so the result re-imports into the
same tree. A prior run with the reference importer reportedly reproduced
the full reference screenplay byte-for-byte. That importer and fixture
are not included here; see the verification limits below.

Parsing throws a typed error:

```swift
do {
    _ = try SpringwaterParser.parse(data)
} catch let error as SpringwaterError {
    print(error)  // e.g. "Line 4: Tag mismatch: ^Chapter opened on line 2, but ^chapter/ closes here"
}
```

## API

`SpringwaterSyntax`:

- `SpringwaterParser.parse(_: Data) throws(SpringwaterError) -> SpringwaterDocument`
- `SpringwaterParser.parse(_: String) throws(SpringwaterError) -> SpringwaterDocument`
- `SpringwaterSerializer.serialize(_:) -> String` (canonical form)
- `SpringwaterSerializer.prettyPrinted(_:indentWidth:) -> String` (tree-equal, indented)
- `SpringwaterDocument` / `.Element` / `.Child` / `.ContentLine`
- `SpringwaterDocument.PhysicalLineEnding` (has `none`) / `.ContentLineEnding` (never `none`)
- `SpringwaterError`

`SpringwaterSchema`:

- `Schema.init(parsing: SpringwaterDocument) throws(SchemaError)`
- `Schema.requiredRoot` / `.rules` / `Rule` (eleven predicate fields + `CountConstraint`)
- `SchemaValidator.validate(_: SpringwaterDocument, against: Schema) -> [ValidationIssue]`
- `ValidationIssue` / `.Category` (`unknownTag`, `invalidNesting`, `missingRequired`, `emptyTag`, `mismatch`)
- `[ValidationIssue].isValid`
- `SchemaError`

`SpringwaterRender`:

- `RenderStyle` (per-tag style) / `RenderStyles.init(parsing: SpringwaterDocument)`
- `HTMLRenderer.render(_: SpringwaterDocument, presentation: SpringwaterDocument, title:) -> String`
- `HTMLRenderer.css(_: RenderStyles) -> String` / `HTMLRenderer.bodyHTML(_:styles:) -> String`

`SpringwaterExport`:

- `FountainExporter.export(_: SpringwaterDocument) -> String`

All types are value types, `Sendable`, and `Equatable`.

## Conformance notes

- Content lines preserve original text and original line-ending sequence.
  A document mixing LF, CRLF, and CR endings round-trips its content
  lines byte-exactly. A content line's ending is always `lf`, `crlf`, or
  `cr` — the `none` case belongs to `PhysicalLineEnding` and is
  unrepresentable on a `ContentLine`.
- Tag-line indentation is cosmetic per the canonical syntax and is not
  stored in the tree. `serialize` emits canonical form, which carries no
  tag-line indentation; `prettyPrinted` adds indentation for reading and
  is tree-equal but not canonical.
- Canonical form is a fixed point: serializing a reparsed canonical
  document reproduces it exactly, and two tree-equal documents have
  identical canonical forms.

## Tests

```bash
swift test
```

- `SpringwaterSyntaxTests` mirrors the canonical syntax's valid and
  invalid examples, plus encoding, line-ending, Unicode-whitespace,
  canonical-form, pretty-print, and mixed-content ordering cases.
- `SpringwaterRenderTests` checks the render-style parsing, the CSS
  generated per tag, the body HTML (including dual-dialogue columns,
  page breaks, and HTML escaping), and the full page, against golden
  fragments captured from the reference renderer.
- `SpringwaterExportTests` checks the Fountain output against a golden
  capture: forced character/action/transition markers, scene-heading
  forcing, dual-dialogue `^`, and emphasis escaping.
- `SpringwaterSchemaTests` exercises the rule model and every predicate
  (`must_contain`, `may_contain`, `cannot_contain`, `must_contain_one_of`,
  `must_contain_count`, `parent_must_be`, `cannot_be_empty`, `text_only`,
  `must_equal`, `must_be_boolean`, `allows_unknown_children`) against
  crafted schemas with known-good and known-bad documents. It also includes a
  `RepositoryConformance` integration suite that reads the repository's own
  `schemas/`, `examples/`, `profiles/`, and `presentations/` files and asserts that every schema
  conforms to the meta-schema and every document validates against the schema
  for its `required_root`. That suite is skipped automatically when the package
  is built outside the repository.

## Verification

The package builds with Swift 6 and all tests pass (`swift test`): unit tests for the
parser, schema validator, renderer, and Fountain exporter, plus a `RepositoryConformance`
suite that validates every schema against the meta-schema and every example against the
schema for its root (skipped automatically outside the repository). From the repository
root, `python3 tools/algorithm_verification.py` runs the syntax conformance vectors and
`python3 tools/springwater-validate <files>` checks documents against the canonical syntax.

Not verified here: a full Fountain round-trip (Fountain export is a one-way projection and
no importer ships), physical print output and other browser print engines, and code coverage.

## License

MIT. Part of the Springwater project.
