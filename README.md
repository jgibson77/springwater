# Springwater v1.0

**A line-oriented, plain-text format for hierarchical documents.**

```springwater
^Springwater
^novel
^chapter
^paragraph
Structure is explicit. Content is preserved exactly.
^paragraph/
^chapter/
^novel/
^Springwater/
```

---

## What is Springwater?

Springwater is a plain-text container for hierarchical documents: screenplays, novels, technical documentation, anything with nested structure. It is meant to be written and read by tools, kept for decades, and still be legible in any text editor.

Seven rules. They are frozen.

### Why Springwater?

- **One specification** — seven rules and one parse; there are no dialects
- **Durable** — plain text, UTF-8, line-oriented
- **Content-preserving** — every non-tag line is kept exactly, with no escaping
- **Checkable** — a schema, itself a Springwater document, defines a document type and validates against it
- **Git-friendly** — line-based diffs

### What it costs

- **It is verbose.** Every element takes an opening line, its content, and a closing line. The one-page scene in `examples/the_first_swim.springwater` is 144 lines. That suits tools; it is heavy to type by hand.
- **There are no inline tags.** A tag occupies its own line. Emphasis inside a sentence has to be a child element on its own lines, and only where the document's schema allows one. The bundled novel schema keeps paragraphs text-only.
- **One position is reserved.** A line whose first non-space character is `^` is never content: it is a tag, or it is an error. [CONVENTIONS.md](CONVENTIONS.md) shows how to carry such lines.

---

## Quick Start

Create `hello.springwater`:

```springwater
^Springwater
^document
^paragraph
Hello, Springwater!
^paragraph/
^document/
^Springwater/
```

Validate it:

```bash
python3 tools/springwater-validate hello.springwater
#   Valid: hello.springwater
```

---

## The Seven Rules

```
1. DOCUMENT CONTAINER   Every document begins with ^Springwater, ends with ^Springwater/.
2. STRUCTURAL TAG LINES  A tag line's trimmed form is exactly ^name or ^name/.
3. MANDATORY CLOSURE     Every opening tag has a matching closing tag.
4. PROPER NESTING        Children close before parents.
5. TAG NAMES             Start with letter. Letters, digits, underscores only.
6. CASE SENSITIVITY      All tags case-sensitive. ^chapter != ^Chapter.
7. CONTENT PRESERVATION  Non-tag lines are content, preserved exactly.
```

---

## Two kinds of validity

**Springwater validity** is the seven rules. It is immutable: a document that is valid Springwater today is valid, and parses the same way, forever.

**Schema validity** is relative to a schema. A schema is an ordinary Springwater document written by whoever designs a document type. Schemas can say whatever their designer decides, can change, and can multiply, without touching the core. A document can be valid Springwater and fail a given schema; no schema can make an invalid document valid.

---

## Content Safety

Springwater uses `^` (caret) as its tag character. This means content from any domain is safe:

```springwater
^Springwater
^code
@State var count = 0
@Observable class Model {}
@Override public void run() {}
#include <stdio.h>
john@example.com
$PATH
^code/
^Springwater/
```

No collisions with code annotations, email addresses, comments, variables, or other markup, with the one reserved position named above: a line may not begin with `^` unless it is a tag. [CONVENTIONS.md](CONVENTIONS.md) covers that case.

---

## Documentation

- **[SYNTAX.txt](SYNTAX.txt)** — Complete canonical syntax (frozen, immutable)
- **[CONVENTIONS.md](CONVENTIONS.md)** — Non-normative authoring conventions, including how to quote Springwater inside Springwater
- **[tools/conformance_vectors.json](tools/conformance_vectors.json)** — Language-neutral test vectors for anyone writing a parser
- **[ROSETTA.springwater](ROSETTA.springwater)** — A self-describing document that explains Springwater completely, in Springwater itself: the seven rules, grammar, parsing, proofs, and worked examples, written so the format can be reconstructed from that file alone.

---

## Implementations

| Language | Where | Status |
|----------|-------|--------|
| Swift | `swift/SpringwaterSyntax` | Reference: parser, serializer, schema validator, renderer, Fountain export, with tests |
| JavaScript | `javascript/springwater.js` | Parser, serializer, schema validator. `node javascript/test.js` runs the conformance vectors and checks every document in this repository |
| Kotlin | `kotlin/Springwater.kt` | Parser, serializer, schema validator for Android and the JVM. `kotlin/Test.kt` runs the conformance vectors and checks every document in this repository; the commands are at the top of that file |
| Python | `tools/springwater-validate` | Syntax validator only |

Anyone writing another implementation can check it against `tools/conformance_vectors.json`.

---

## Schemas

| Schema | Purpose |
|--------|---------|
| **screenplay.schema** | Industry-standard screenplays |
| **novel.schema** | Novels with metadata |
| **technical.schema** | Technical documentation |
| **rosetta.schema** | Self-descriptive archival docs |
| **authoring.schema** | Authoring profiles |
| **parallel.schema** | One text in several languages, aligned passage by passage |
| **presentation.schema** | Presentations: how a document type looks |

All validate against `schema.schema.springwater` (meta-schema).

These are example schemas, not part of the core. Anyone can write a schema for their own document type.

A schema says what a document is: its elements and how they nest. It says nothing about how the document looks. Fonts, margins, page size, and per-element styling live in a separate **presentation** document under `presentations/`, validated by `presentation.schema` and naming the schema it dresses. A document is read and validated without any presentation; one schema can have many. Pages exist only when a presentation is applied at render or export time, so no Springwater document stores a page break.

---

## Examples

Three short documents, each valid against its schema, show the same format
across different kinds of writing. A fourth,
[`examples/genesis_1_3.springwater`](examples/genesis_1_3.springwater), carries
Genesis 1 to 3 verse by verse in English, Spanish, Mandarin, and the original
Hebrew, each verse holding all four languages side by side. The complete files are in
[`examples/`](examples/); longer, self-describing walk-throughs live in
[`ROSETTA.springwater`](ROSETTA.springwater).

### Screenplay — [`examples/the_first_swim.springwater`](examples/the_first_swim.springwater)

Nested structure: the work's metadata, then an act holding a scene with a slug line,
action, and dialogue.

```springwater
^Springwater
^screenplay
^metadata
^title
THE FIRST SWIM
^title/
^metadata/
^act1
^scene
^slugline
EXT. BEACH - NIGHT
^slugline/
^action
A driftwood fire. Sparks lift and die against the dark.
^action/
^dialogue
^character
YOUNG MAN
^character/
^lines
I'm going in. You coming?
^lines/
^dialogue/
^scene/
^act1/
^screenplay/
^Springwater/
```

### Novel — [`examples/sun_also_rises.springwater`](examples/sun_also_rises.springwater)

Content preserved verbatim: a metadata block, then a chapter whose scene holds
an unaltered opening paragraph.

```springwater
^Springwater
^novel
^metadata
^title
The Sun Also Rises
^title/
^author
Ernest Hemingway
^author/
^metadata/
^chapter
^scene
^paragraph
Robert Cohn was once middleweight boxing champion of Princeton.
^paragraph/
^scene/
^chapter/
^novel/
^Springwater/
```

### Technical — [`examples/swift_reference.springwater`](examples/swift_reference.springwater)

Content that looks like markup stays content: the `@`-prefixed lines are code,
not tags, because only a line whose first non-space character is `^` is
structure.

```springwater
^Springwater
^manual
^title
SwiftUI Quick Reference
^title/
^version
1.0
^version/
^chapter
^title
State Management
^title/
^section
^title
Property Wrappers
^title/
^paragraph
Annotations that begin with @ are ordinary content, not tags.
^paragraph/
^code_block
@State var count = 0
@Observable class UserModel {}
@MainActor func updateUI() {}
^code_block/
^section/
^chapter/
^manual/
^Springwater/
```

---

## Frozen

**Springwater Core v1.0 is frozen as of January 31, 2026.**

The seven rules will never change. A document that is valid Springwater today parses the same way forever. Schemas are separate and may evolve; see [Two kinds of validity](#two-kinds-of-validity).

---

## Authorship and acknowledgments

Springwater — the format, its canon, and every design decision — is authored by John Gibson. Much of the reference implementation (the Swift package, schemas, renderer, exporter, and verification tooling) was written by two AI collaborators, Codex (OpenAI) and Claude (Anthropic), under the author's direction and canon decisions. The design and all binding decisions are the author's.

---

## License

MIT License. See [LICENSE](LICENSE).

---

**"Structure is explicit. Content is preserved exactly."**
