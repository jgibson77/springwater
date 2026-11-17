# Conventions

*Non-normative.* Nothing here changes the seven rules of Springwater v1.0. A
conforming parser need not know any of it. These are patterns that sit above
the core format and use only what it already has: ordinary content lines and
ordinary tags.

## Quoting Springwater inside Springwater

Springwater has no escaping. A line whose first non-space character is `^` is
never content. If the rest of the line is a valid tag name it is a tag; if not,
the document is invalid. There is no raw mode and no escape character. That is
the design, and it is what gives the format one unambiguous parse.

The consequence: a line that must begin with `^` cannot be stored directly as
content. This comes up in documents that quote Springwater source, such as
tutorials, the specification, and this repository's `ROSETTA.springwater`, and
occasionally elsewhere (a regular expression that starts a line with `^`).

### The gutter

Prefix every line of the quoted text with a two-character gutter, `"| "`
(vertical bar, space).

Text to quote:

~~~
^screenplay
^title
HOOK
^title/
^screenplay/
~~~

Stored as content:

~~~
| ^screenplay
| ^title
| HOOK
| ^title/
| ^screenplay/
~~~

Each stored line begins with `|`, so it is ordinary content and is preserved
exactly. To recover the original, remove the leading `"| "` from each line.

Gutter every line of the quoted text, not only the lines that begin with `^`.
Recovery is then the same for every line, and it is lossless for any text,
including text whose own lines begin with `| `.

The gutter needs no tag of its own. Put guttered lines inside whatever element
the document's schema provides for quoted material. `ROSETTA.springwater` does
this in its `valid_example` and `invalid_example` elements. A schema designer
who wants tools to find quoted Springwater can name an element for it; that is
a schema decision, not a core one.

### When not to quote

If the embedded document is a real artifact and must stay directly parseable,
do not gutter it. Keep it as its own `.springwater` file and refer to it.

## Marks inside a line

Springwater has no inline markup. A line is a tag or it is content, and content
is never read for structure. Nothing in the core says that part of a line is
emphasized, added, or quoted.

How a word looks (italic, bold, a typeface) is presentation and does not belong
in a document. But some marks carry meaning. In the King James Bible, italics
mark words the translators added that have no counterpart in the Hebrew. That is
a fact about the text, and it should survive.

Write such a mark as ordinary characters in the content, and say what it means
in the document itself, in whatever element its schema provides for that.
`examples/genesis_1_3.springwater` puts the added words in square brackets and
explains the brackets in its `source` element:

~~~
And God saw the light, that [it was] good: and God divided the light from the darkness.
~~~

Springwater preserves the characters exactly and interprets none of them. The
meaning of a mark belongs to the document and its schema, not to the core.

### Emphasis

One mark is defined for any schema that wants it: text between two underscores
is emphasized.

~~~
She is _not_ coming back.
~~~

The rule, exactly:

- An underscore **opens** emphasis when it is at the start of the line or
  follows a character that is not a letter, a digit, or an underscore, and the
  character after it is not a space, a tab, or an underscore.
- An underscore **closes** emphasis when the character before it is not a
  space or a tab, and it is at the end of the line or is followed by a
  character that is not a letter, a digit, or an underscore.
- An opening underscore pairs with the nearest closing underscore after it
  that leaves at least one character between them.
- Emphasis does not cross a line.
- An underscore that pairs with nothing is ordinary text. `snake_case_name`
  contains no emphasis.

A schema that uses the mark says so in its own text, with a `marks` element:

~~~
^marks
^mark
^name
emphasis
^name/
^open
_
^open/
^close
_
^close/
^meaning
The words between the two marks are emphasized.
^meaning/
^mark/
^marks/
~~~

The declaration changes nothing about validation. It is there so that a reader
of the schema, now or much later, is told what the underscores mean.

A presentation says how emphasis is drawn, with a `mark_rules` element: the
screenplay presentation underlines it, as scripts do. A presentation with no
rule for a mark leaves the text exactly as written, underscores included.

The file always keeps the underscores. Drawing emphasis never changes the
document.

## Self-contained documents

A document names its schema in `validated_by`, for example
`parallel.schema v1.0`. That is a name, not a place. If the schema is lost, the
tags remain readable but what they were meant to require is a guess.

A schema is itself Springwater, so a document can carry its schema inside
itself. Nothing is quoted and nothing is escaped: the schema's tags are
ordinary tags, placed beside the work as further top-level elements.

~~~
^Springwater
^parallel_text
(the work)
^parallel_text/
^schema
(the schema whose required_root is parallel_text)
^schema/
^schema
(the schema whose required_root is schema: the schema for schemas)
^schema/
^Springwater/
~~~

The convention:

- The **work** is the first top-level element.
- The document may carry, after the work, top-level `schema` and
  `presentation` elements. No other top-level element may be carried.
- The schema a document carries for an element name is the first top-level
  `schema` whose `required_root` is that name. The presentation it carries is
  the first top-level `presentation` whose `target_schema` is that name.
- A carried schema is a document like any other. It is valid when it conforms
  to the schema for schemas, which the document may carry too. With both, the
  file needs nothing outside itself to be checked.
- Carried elements are not part of the work. The work's schema does not judge
  them, and a rendering of the work does not show them.

A validator that knows this convention checks the work against the schema the
document carries, when it carries one, and says that it did. A carried schema
is the document's own account of itself. Whether that account matches a schema
published under the same name is a separate question, and a validator may
answer it separately.

`examples/genesis_1_3.self_contained.springwater` is the Genesis example
carrying its schema and the schema for schemas.

## The primer

Everything that explains Springwater is written in a language: the rules in
`SYNTAX.txt`, the schemas, this file. A reader who has none of those languages
still has the marks themselves, and the marks follow a pattern that can be
found by looking and counting:

- some lines begin with the same mark;
- each such line appears twice, the second time with one more stroke at its end;
- the pairs sit inside one another and never cross;
- everything else lies between them.

`PRIMER.springwater` teaches that pattern from nothing, using no words until
its last step. It is a valid Springwater document with no schema: it stands on
the seven rules alone. Its steps, in order:

1. **A pair holds something.** The same pair holds nothing, then one stroke,
   then two, then three. The marks stay the same; what they hold changes.
2. **A different label holds a different kind of thing.** A second label holds
   a different sign, counted the same way.
3. **A pair can hold several lines.**
4. **A pair can hold pairs.** A third label holds one of the first, then two,
   then three.
5. **Pairs go inside pairs to any depth**, and different kinds sit side by side.
6. **The same thing written different ways.** The counts one to ten, each as
   strokes, as a digit, and as a word in English, Spanish, Mandarin, and
   Hebrew, under the same labels the Genesis example uses.

The labels in steps 1 to 5 are single letters because they are meant to be
read as marks, not words. The last step is the bridge to language: a reader
who has followed the strokes learns ten words in each of four scripts, and
learns which label goes with which script.

The primer cannot make a lost language readable. Nothing can. What it does is
remove the need to be told how the notation works.

## Non-goals

These were considered and rejected, because each costs more than the problem
it solves:

- **An escape character** (for example `^^` for a literal caret). It
  reintroduces the ambiguity that having no escaping removes.
- **A raw or verbatim block** (everything until a sentinel is literal). It makes
  parsing context-sensitive: a line would no longer be classified by its own
  first character.
- **A length-prefixed binary block.** Lossless, but no longer line-oriented or
  readable.
- **Inline markup** (delimiters the parser reads inside a content line). It
  would need escaping, and content would no longer be preserved exactly.

The conventions above meet these needs and leave the seven rules exactly as frozen.
