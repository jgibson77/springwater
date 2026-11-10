# Conventions

*Non-normative.* Nothing here changes the seven rules of Springwater v1.0. A
conforming parser need not know any of it. These are authoring patterns that sit
above the core format and use only ordinary content lines.

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

The gutter meets the need and leaves the seven rules exactly as frozen.
