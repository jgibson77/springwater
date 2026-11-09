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

Springwater is a format for writing screenplays, novels, technical documentation, and other hierarchical documents in plain text.

Seven rules. No exceptions. No edge cases.

### Why Springwater?

- **Simple** — Seven rules, learn in five minutes
- **Durable** — Plain text, UTF-8, line-oriented
- **Universal** — Content from any domain is safe (code, prose, data)
- **Permanent** — which documents are valid, and how they parse, are fixed
- **Git-friendly** — Line-based diffs, perfect for version control

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

No collisions with code annotations, email addresses, comments, variables, or markup.

---

## Documentation

- **[SYNTAX.txt](SYNTAX.txt)** — Complete canonical syntax (frozen, immutable)
- **[ROSETTA.springwater](ROSETTA.springwater)** — A self-describing document that explains Springwater completely, in Springwater itself: the seven rules, grammar, parsing, proofs, and worked examples, written so the format can be reconstructed from that file alone.

---

## Schemas

| Schema | Purpose |
|--------|---------|
| **screenplay.schema** | Industry-standard screenplays |
| **novel.schema** | Novels with metadata |
| **technical.schema** | Technical documentation |
| **rosetta.schema** | Self-descriptive archival docs |

All validate against `schema.schema.springwater` (meta-schema).

---

## Examples

Three short documents, each valid against its schema, show the same format
across different kinds of writing. The complete files are in
[`examples/`](examples/); longer, self-describing walk-throughs live in
[`ROSETTA.springwater`](ROSETTA.springwater).

### Screenplay — [`examples/the_first_swim.springwater`](examples/the_first_swim.springwater)

Nested structure: a title page, then an act holding a scene with a slug line,
action, and dialogue.

```springwater
^Springwater
^screenplay
^title_page
^title
THE FIRST SWIM
^title/
^title_page/
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

The seven rules will never change. Documents written today remain valid forever.

---

## Authorship and acknowledgments

Springwater — the format, its canon, and every design decision — is authored by John Gibson. Much of the reference implementation (the Swift package, schemas, renderer, exporter, and verification tooling) was written by two AI collaborators, Codex (OpenAI) and Claude (Anthropic), under the author's direction and canon decisions. The design and all binding decisions are the author's.

---

## License

MIT License. See [LICENSE](LICENSE).

---

**"Structure is explicit. Content is preserved exactly."**
