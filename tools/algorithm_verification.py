#!/usr/bin/env python3
"""Faithful Python mirror of SpringwaterParser (Swift).

Branch-for-branch port of the canonical parsing algorithm, used to
machine-verify the algorithm against test vectors and real documents.
Not a shipping tool. The Swift package is the reference implementation.
"""

import sys
from pathlib import Path

LF, CRLF, CR, NONE = "lf", "crlf", "cr", "none"


class SWError(Exception):
    def __init__(self, kind, **info):
        self.kind = kind
        self.info = info
        super().__init__(f"{kind} {info}")


def physical_lines(s):
    """Divide at LF, CRLF, CR. U+2028/U+2029 are content. Returns (text, ending)."""
    lines = []
    start = 0
    i = 0
    n = len(s)
    while i < n:
        c = s[i]
        if c == "\n":
            lines.append((s[start:i], LF))
            i += 1
            start = i
        elif c == "\r":
            if i + 1 < n and s[i + 1] == "\n":
                lines.append((s[start:i], CRLF))
                i += 2
            else:
                lines.append((s[start:i], CR))
                i += 1
            start = i
        else:
            i += 1
    if start < n:
        lines.append((s[start:], NONE))
    return lines


def trimmed(text):
    """Remove leading/trailing U+0020 and U+0009 only. Not unicode-aware."""
    start = 0
    end = len(text)
    while start < end and text[start] in (" ", "\t"):
        start += 1
    while end > start and text[end - 1] in (" ", "\t"):
        end -= 1
    return text[start:end]


def is_ascii_letter(ch):
    return ("a" <= ch <= "z") or ("A" <= ch <= "Z")


def is_valid_tag_name(name):
    if not name or not is_ascii_letter(name[0]):
        return False
    return all(is_ascii_letter(c) or ("0" <= c <= "9") or c == "_" for c in name[1:])


CONTENT, OPEN, CLOSE, INVALID = "content", "open", "close", "invalid"


def classify(t):
    if not t or t[0] != "^":
        return (CONTENT, None)
    body = t[1:]
    closing = False
    if body.endswith("/"):
        closing = True
        body = body[:-1]
    if not is_valid_tag_name(body):
        return (INVALID, None)
    return (CLOSE if closing else OPEN, body)


def parse(data: bytes):
    if data.startswith(b"\xef\xbb\xbf"):
        raise SWError("leadingBOM")
    try:
        s = data.decode("utf-8", errors="strict")
    except UnicodeDecodeError:
        raise SWError("invalidUTF8")
    lines = physical_lines(s)
    if not lines:
        raise SWError("emptyDocument")
    if trimmed(lines[0][0]) != "^Springwater":
        raise SWError("missingRootOpen", found=str(trimmed(lines[0][0])))
    stack = [{"name": "Springwater", "openedAt": 1, "children": []}]
    parsed_root = None
    for index in range(1, len(lines)):
        line_number = index + 1
        text, ending = lines[index]
        kind, name = classify(trimmed(text))
        if kind == CONTENT:
            stack[-1]["children"].append(("content", text, ending))
        elif kind == OPEN:
            if name == "Springwater":
                raise SWError("reservedRootName", line=line_number)
            stack.append({"name": name, "openedAt": line_number, "children": []})
        elif kind == CLOSE:
            if len(stack) == 1:
                if name != "Springwater":
                    raise SWError("mismatchedClosingTag", line=line_number,
                                  found=name, open="Springwater", openedAt=1)
                if index != len(lines) - 1:
                    raise SWError("trailingLinesAfterRootClose", line=line_number)
                root = stack.pop()
                parsed_root = ("element", root["name"], root["children"])
            else:
                top = stack[-1]
                if top["name"] != name:
                    raise SWError("mismatchedClosingTag", line=line_number,
                                  found=name, open=top["name"], openedAt=top["openedAt"])
                frame = stack.pop()
                stack[-1]["children"].append(("element", frame["name"], frame["children"]))
        else:
            raise SWError("invalidCaretLine", line=line_number, text=str(trimmed(text)))
    if parsed_root is None:
        if len(stack) > 1:
            top = stack[-1]
            raise SWError("unclosedTag", name=top["name"], openedAt=top["openedAt"])
        raise SWError("missingRootClose")
    return parsed_root


# ============================================================================
# Test vectors mirroring the Swift test suite
# ============================================================================

passed = failed = 0


def check(name, data, expect_error=None, tree_check=None):
    global passed, failed
    if isinstance(data, str):
        data = data.encode("utf-8")
    try:
        tree = parse(data)
        if expect_error:
            print(f"  FAIL  {name}: expected {expect_error}, got valid")
            failed += 1
            return
        if tree_check and not tree_check(tree):
            print(f"  FAIL  {name}: tree check failed: {tree}")
            failed += 1
            return
        print(f"  pass  {name}")
        passed += 1
    except SWError as e:
        if expect_error and e.kind == expect_error:
            print(f"  pass  {name}")
            passed += 1
        else:
            print(f"  FAIL  {name}: expected {expect_error or 'valid'}, got {e.kind} {e.info}")
            failed += 1


print("VALID DOCUMENTS")
check("minimal", "^Springwater\n^Springwater/\n",
      tree_check=lambda t: t[2] == [])
check("minimal without trailing newline", "^Springwater\n^Springwater/",
      tree_check=lambda t: t[2] == [])
check("single container", "^Springwater\n^document\nHello, world!\n^document/\n^Springwater/\n",
      tree_check=lambda t: t[2][0][1] == "document" and t[2][0][2] == [("content", "Hello, world!", LF)])

mixed = ("^Springwater\n^paragraph\nThe word\n^emphasis\nimportant\n"
         "^emphasis/\nappears in this sentence.\n^paragraph/\n^Springwater/\n")
def mixed_check(t):
    p = t[2][0]
    kids = p[2]
    return (len(kids) == 3
            and kids[0] == ("content", "The word", LF)
            and kids[1][0] == "element" and kids[1][1] == "emphasis"
            and kids[2] == ("content", "appears in this sentence.", LF))
check("mixed content ordering", mixed, tree_check=mixed_check)

code = ("^Springwater\n^code\n@State var count = 0\n@Observable class Model {}\n"
        "#include <stdio.h>\n$PATH\njohn@example.com\n^code/\n^Springwater/\n")
check("code annotations are content", code,
      tree_check=lambda t: len(t[2][0][2]) == 5 and all(k[0] == "content" for k in t[2][0][2]))

check("content indentation preserved",
      "^Springwater\n^code\n    indented line\n^code/\n^Springwater/\n",
      tree_check=lambda t: t[2][0][2] == [("content", "    indented line", LF)])
check("blank lines preserved",
      "^Springwater\n^poem\nFirst\n\nThird\n^poem/\n^Springwater/\n",
      tree_check=lambda t: t[2][0][2] == [("content", "First", LF), ("content", "", LF), ("content", "Third", LF)])
check("indented tags are structural",
      "^Springwater\n  ^section\n  content\n  ^section/\n^Springwater/\n",
      tree_check=lambda t: t[2][0][1] == "section" and t[2][0][2] == [("content", "  content", LF)])
check("NBSP line is content",
      "^Springwater\n^p\n\u00a0^chapter\n^p/\n^Springwater/\n",
      tree_check=lambda t: t[2][0][2] == [("content", "\u00a0^chapter", LF)])
check("U+2028 is content",
      "^Springwater\n^p\nfirst\u2028second\n^p/\n^Springwater/\n",
      tree_check=lambda t: t[2][0][2] == [("content", "first\u2028second", LF)])
check("mixed line endings preserved",
      "^Springwater\n^p\r\nalpha\r\nbeta\ngamma\r^p/\n^Springwater/\n",
      tree_check=lambda t: t[2][0][2] == [("content", "alpha", CRLF), ("content", "beta", LF), ("content", "gamma", CR)])
check("interior U+FEFF is content",
      "^Springwater\n^p\nbefore\ufeffafter\n^p/\n^Springwater/\n",
      tree_check=lambda t: t[2][0][2] == [("content", "before\ufeffafter", LF)])

print()
print("INVALID DOCUMENTS")
check("leading BOM", b"\xef\xbb\xbf^Springwater\n^Springwater/\n", expect_error="leadingBOM")
check("invalid UTF-8", b"^Springwater\n\xff\xfe\x80\n^Springwater/\n", expect_error="invalidUTF8")
check("empty document", b"", expect_error="emptyDocument")
check("wrong case root", "^springwater\n^springwater/\n", expect_error="missingRootOpen")
check("content before root", "Preamble\n^Springwater\n^Springwater/\n", expect_error="missingRootOpen")
check("content after root close", "^Springwater\n^Springwater/\nTrailing\n", expect_error="trailingLinesAfterRootClose")
check("nested root", "^Springwater\n^Springwater\n^Springwater/\n^Springwater/\n", expect_error="reservedRootName")
check("unclosed tag", "^Springwater\n^paragraph\nContent\n", expect_error="unclosedTag")
check("missing root close", "^Springwater\ncontent\n", expect_error="missingRootClose")
check("case mismatch", "^Springwater\n^Chapter\nContent\n^chapter/\n^Springwater/\n", expect_error="mismatchedClosingTag")
check("improper nesting", "^Springwater\n^outer\n^inner\n^outer/\n^inner/\n^Springwater/\n", expect_error="mismatchedClosingTag")
check("root close mid-document then paragraph close",
      "^Springwater\n^paragraph\nText\n^Springwater/\n^paragraph/\n", expect_error="mismatchedClosingTag")

for bad in ["^my-tag", "^123", "^_name", "^", "^/", "^^tag", "^tag  /",
            "^tag /more", "^paragraph This is text. ^paragraph/", "^john said hello"]:
    check(f"invalid caret line: {bad!r}",
          f"^Springwater\n{bad}\n^Springwater/\n", expect_error="invalidCaretLine")

print()
print("CLASSIFICATION TABLE")
table = [
    ("^chapter", (OPEN, "chapter")),
    ("  ^chapter  ", (OPEN, "chapter")),
    ("^chapter/", (CLOSE, "chapter")),
    ("  ^chapter/  ", (CLOSE, "chapter")),
    ("chapter", (CONTENT, None)),
    ("text ^chapter", (CONTENT, None)),
    ("Email: a@b.com", (CONTENT, None)),
    ("", (CONTENT, None)),
    ("   ", (CONTENT, None)),
    ("^chapter text", (INVALID, None)),
    ("^my-tag", (INVALID, None)),
    ("\u00a0^chapter", (CONTENT, None)),
]
for line, expected in table:
    got = classify(trimmed(line))
    if got == expected:
        print(f"  pass  classify({line!r})")
        passed += 1
    else:
        print(f"  FAIL  classify({line!r}): expected {expected}, got {got}")
        failed += 1

print()
print("REAL DOCUMENTS")
repo = Path(__file__).resolve().parent.parent
roots = [repo / "schemas", repo / "examples", repo / "profiles"]
for root in roots:
    for path in sorted(root.glob("*.springwater")):
        check(str(path.relative_to(repo)), path.read_bytes())

print()
print("=" * 60)
print(f"RESULTS: {passed} passed, {failed} failed")
print("=" * 60)
sys.exit(0 if failed == 0 else 1)
