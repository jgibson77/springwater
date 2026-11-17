# Clean-room schema validator

`swv.py` is a parser and schema validator written from `SYNTAX.txt` and
`SCHEMA_SPEC.txt` alone. The implementer was given those two files, told not
to read anything else in this repository, including the conformance vectors,
and asked to write both in Python. It is kept as delivered.
`test_vectors.py` was written afterwards.

The purpose was to test `SCHEMA_SPEC.txt`: if a stranger can build a correct
validator from the written description and nothing else, the description is
complete.

## Result

| Check | Agreement |
|---|---|
| Schema conformance vectors written before the first test (65) | 65 of 65 |
| Vectors added afterwards from the implementer's notes (7), run without changing `swv.py` | 7 of 7 |
| Every document in the repository, validated against its schema: no issues, as in the JavaScript validator | 21 of 21 |

Run the vectors with `python3 python/test_vectors.py`.

## Second round: version 1.1

When the specification gained `at_most_one` and `starts_with`, the same
implementer was given the revised `SCHEMA_SPEC.txt` and nothing else, and
updated `swv.py` from it. Seventeen vectors for the new properties had been
written beforehand and were not shown to it. All 89 vectors agree.

It reported eight further points, of which five were written into the
specification: an out-of-date sentence about order, the effect of a name
listed twice in `starts_with`, that every child takes part in ordering, that
the new properties still apply inside an open element, and that names taken
from a schema need not be legal tag names.

## Limits of the test

The implementer was an AI model, not a person, and its session showed it a
one-line description of Springwater before it began, with nothing about
schemas. It reported reading only the two specification files; that report
cannot be fully verified. An implementation by a human stranger would be
stronger evidence.

## What the implementer had to decide

It reported 23 places where `SCHEMA_SPEC.txt` was silent or could be read two
ways. In every one it chose the reading the other validators already
followed, which is why no vector disagreed. The ones that mattered were then
written into the specification, and vectors were added for them:

- A document with no `schema` element is treated like an unusable schema.
- Only the first top-level `schema` is read, even when it is unusable.
- A later empty `tag` in a rule leaves the rule with no tag.
- A forbidden child is still checked, like a child that is not allowed.
- Empty pieces of a list do not count toward a count's two items.
- Two content lines with no comma between them are one list item.
- Content lines at the document root are not an issue.
- Tag names are matched exactly; case is significant.
- A required root, a rule's tag, and list items are not checked for being
  legal tag names.
- A count's digits are 0 to 9 only, leading zeros are allowed, and there is no
  upper limit.
- When the required root is a carried name, elements with that name are works.

Left as they are, because they are true and harmless:

- BLANK removes space and tab; VALUE also removes line feed. A line's text
  cannot contain a line feed, so the two never differ in effect.
- The categories in the ISSUES table are not used by the algorithm. They
  classify issues for the reader of a result.
