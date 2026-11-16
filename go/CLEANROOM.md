# Clean-room implementation

`main.go` was written from `SYNTAX.txt` alone. The implementer was given that
one file, told not to read anything else in this repository, and asked to
write a parser in a language no other implementation here uses. It is kept as
delivered. `main_test.go` was written afterwards to run it against the
repository's checks.

The purpose was to test the written rules, not the code: if a stranger can
build a correct parser from `SYNTAX.txt` and nothing else, the rules are
complete.

## Result

| Check | Agreement |
|---|---|
| Parse vectors: rejected or accepted, and the exact tree | 34 of 34 |
| Line classification vectors | 12 of 12 |
| Every `.springwater` document in the repository: same tree as the JavaScript implementation | 20 of 20 |
| The same documents: same canonical bytes as the JavaScript implementation | 20 of 20 |

Run the first three with `go test ./...` in this folder.

## Limits of the test

The implementer was an AI model, not a person, and its session showed it a
one-line description of Springwater before it began. It reported reading
nothing else outside its working folder; that report cannot be fully verified.
An implementation by a human stranger would be stronger evidence.

## Where the rules made the implementer choose

None of these changed an outcome. They are recorded because each is a place
where `SYNTAX.txt` could say more.

1. **Trailing line break.** The rules do not say outright that a final line
   break does not begin a new, empty physical line. Read the other way, every
   file ending in a line break would be invalid. Implemented: a line break
   ends the line before it; only the empty byte stream has zero lines.
2. **CR followed by LF.** Nothing says the match is longest first. Implemented:
   CR immediately followed by LF is always one CRLF.
3. **Line number when the root close is not the last line.** No error
   locations are defined. Reported: the root closing tag's line.
4. **Line number for failures before or after the lines** (BOM, invalid
   UTF-8, zero lines, root close never found). Reported: 0.
5. **Step 9's second condition cannot be reached alone.** "The stack contains
   more than the root frame" is only true when the root close was never
   found, which the first condition already rejects. Relatedly, the example
   INVALID 5 says a tag was "never closed"; the algorithm rejects it earlier,
   as a mismatched closing tag.
6. **"Name mismatch or stack underflow."** A stray closing tag directly under
   the root is a mismatch against the root frame, not an underflow.
7. **Whole-document classification or line by line.** LINE CLASSIFICATION
   says an invalid caret line makes the document invalid, which suggests a
   pass over every line first. The algorithm classifies as it goes. The two
   reject the same documents but can name different lines.
8. **First line is an invalid caret line.** Two reasons apply. Reported: the
   first line is not the root opening tag.
9. **A final content line with no line break.** Step 8b would store an ending
   the content line type cannot hold. The document is rejected at step 9
   regardless.
10. **"A single trailing / removed."** `^a//` leaves the candidate `a/`, which
    is not a valid name, so the line is invalid.
11. **Line break after the last line of the canonical form.** Implemented:
    always present.
12. **Reserved root name or mismatch.** A non-root `^Springwater/` violates
    Rule 5's reservation, but the algorithm reaches it as a mismatch.
13. **Classifying text that contains a line break.** Line text never contains
    one by definition; the command-line tool treats such bytes literally.
14. **Other control characters** (NUL, VT, FF, U+0085). Covered by "only
    these three sequences divide lines" and "only space and tab are
    whitespace": they are ordinary characters.
15. **`<content_line>` in the grammar excludes empty lines**; TERMS includes
    them. Terminology only.
16. **Limits.** None are stated for nesting, line length, or file size; none
    are imposed.

One consequence for the conformance vectors: they name an error kind for each
rejected document, and `SYNTAX.txt` defines no such names. This parser rejects
every document it must, but would label some differently (see 5). The Go test
therefore checks rejection and the tree, not the name.
