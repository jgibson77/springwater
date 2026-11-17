#!/usr/bin/env python3
"""Springwater parser (SYNTAX.txt) and schema validator (SCHEMA_SPEC.txt).
Clean-room implementation; standard library only."""
import json
import sys

try:
    sys.set_int_max_str_digits(0)  # counts are unbounded decimal numbers
except AttributeError:
    pass

WS = " \t"                 # SYNTAX whitespace
SCHEMA_WS = " \t\n"        # SCHEMA whitespace
LETTERS = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ"
DIGITS = "0123456789"
NAMECHARS = LETTERS + DIGITS + "_"
ROOT = "Springwater"


class ParseError(Exception):
    pass


class ContentLine:
    __slots__ = ("text", "ending")

    def __init__(self, text, ending):
        self.text = text
        self.ending = ending

    def __eq__(self, o):
        return isinstance(o, ContentLine) and (self.text, self.ending) == (o.text, o.ending)

    def __repr__(self):
        return "ContentLine(%r, %r)" % (self.text, self.ending)


class Element:
    __slots__ = ("name", "children")

    def __init__(self, name, children=None):
        self.name = name
        self.children = children if children is not None else []

    def __eq__(self, o):
        return isinstance(o, Element) and self.name == o.name and self.children == o.children

    def __repr__(self):
        return "Element(%r, %r)" % (self.name, self.children)


# ---------------------------------------------------------------- parsing

def split_lines(s):
    """Return list of (text, ending); ending in 'LF','CRLF','CR',None."""
    lines = []
    i = 0
    n = len(s)
    start = 0
    while i < n:
        c = s[i]
        if c == "\n":
            lines.append((s[start:i], "LF"))
            i += 1
            start = i
        elif c == "\r":
            if i + 1 < n and s[i + 1] == "\n":
                lines.append((s[start:i], "CRLF"))
                i += 2
            else:
                lines.append((s[start:i], "CR"))
                i += 1
            start = i
        else:
            i += 1
    if start < n:
        lines.append((s[start:], None))
    return lines


def is_tag_name(c):
    return bool(c) and c[0] in LETTERS and all(ch in NAMECHARS for ch in c)


def classify(text):
    """Return ('content',None) | ('open',name) | ('close',name) | ('invalid',None)."""
    t = text.strip(WS)
    if t == "" or t[0] != "^":
        return ("content", None)
    body = t[1:]
    if is_tag_name(body):
        return ("open", body)
    if body.endswith("/") and is_tag_name(body[:-1]):
        return ("close", body[:-1])
    return ("invalid", None)


def parse(data):
    if data[:3] == b"\xef\xbb\xbf":
        raise ParseError("leading UTF-8 BOM")
    try:
        s = data.decode("utf-8", "strict")
    except UnicodeDecodeError:
        raise ParseError("invalid UTF-8")
    lines = split_lines(s)
    if not lines:
        raise ParseError("zero physical lines")
    if classify(lines[0][0]) != ("open", ROOT):
        raise ParseError("line 1 is not ^Springwater")
    stack = [Element(ROOT)]
    last = len(lines) - 1
    for idx in range(1, len(lines)):
        text, ending = lines[idx]
        kind, name = classify(text)
        ln = idx + 1
        if kind == "content":
            if ending is None:  # unreachable for a valid doc; final line must be root close
                raise ParseError("last physical line is not ^Springwater/")
            stack[-1].children.append(ContentLine(text, ending))
        elif kind == "open":
            if name == ROOT:
                raise ParseError("line %d: Springwater is reserved for the root" % ln)
            stack.append(Element(name))
        elif kind == "close":
            if len(stack) == 1 and name == ROOT:
                if idx != last:
                    raise ParseError("line %d: lines after root closing tag" % ln)
                return stack.pop()
            elif len(stack) > 1 and stack[-1].name == name:
                e = stack.pop()
                stack[-1].children.append(e)
            else:
                raise ParseError("line %d: closing tag does not match" % ln)
        else:
            raise ParseError("line %d: invalid ^ line" % ln)
    if len(stack) > 1:
        raise ParseError("unclosed tags / root closing tag missing")
    raise ParseError("root closing tag missing")


# ---------------------------------------------------------------- schema terms

def child_elements(e):
    return [c for c in e.children if isinstance(c, Element)]


def value_of(e):
    texts = [c.text for c in e.children if isinstance(c, ContentLine)]
    return "\n".join(texts).strip(SCHEMA_WS)


def list_of(e):
    out = []
    for piece in value_of(e).split(","):
        piece = piece.strip(SCHEMA_WS)
        if piece:
            out.append(piece)
    return out


def is_empty(e):
    for c in e.children:
        if isinstance(c, Element):
            return False
        if c.text.strip(WS) != "":
            return False
    return True


LIST_NAMES = ("must_contain", "may_contain", "cannot_contain",
              "must_contain_one_of", "parent_must_be", "at_most_one", "starts_with")
FLAG_NAMES = ("cannot_be_empty", "text_only", "must_be_boolean",
              "allows_unknown_children")


class Rule:
    def __init__(self):
        self.tag = None
        self.lists = {n: [] for n in LIST_NAMES}
        self.flags = {n: False for n in FLAG_NAMES}
        self.has_exact = False
        self.exact = None
        self.count = None


def read_rule(el):
    r = Rule()
    for c in child_elements(el):
        n = c.name
        if n == "tag":
            v = value_of(c)
            r.tag = v if v != "" else None
        elif n in LIST_NAMES:
            r.lists[n] = list_of(c)
        elif n in FLAG_NAMES:
            r.flags[n] = (value_of(c) == "true")
        elif n == "must_equal":
            r.has_exact = True
            r.exact = value_of(c)
        elif n == "must_contain_count":
            l = list_of(c)
            if len(l) == 2 and l[1] != "" and all(ch in DIGITS for ch in l[1]):
                r.count = (l[0], int(l[1]))
    return r


class SchemaModel:
    def __init__(self, required_root, rules):
        self.required_root = required_root
        self.rules = rules


def find_schema_element(root):
    for c in child_elements(root):
        if c.name == "schema":
            return c
    return None


def read_schema(schema_el):
    """Return SchemaModel, or None if the schema is unusable."""
    kids = child_elements(schema_el)
    rr = [c for c in kids if c.name == "required_root"]
    if not rr:
        return None
    required = value_of(rr[-1])
    if required == "":
        return None
    rules = {}
    for sr in kids:
        if sr.name != "structure_rules":
            continue
        for re_ in child_elements(sr):
            if re_.name != "rule":
                continue
            r = read_rule(re_)
            if r.tag is None:
                continue
            rules[r.tag] = r
    return SchemaModel(required, rules)


# ---------------------------------------------------------------- validation

CARRIED = ("schema", "presentation")


def validate(doc_root, model):
    issues = []

    def add(kind, element, other=None):
        d = {"kind": kind, "element": element}
        if other is not None:
            d["other"] = other
        issues.append(d)

    R = model.required_root
    tops = child_elements(doc_root)
    if not any(e.name == R for e in tops):
        add("missing_root", R)
    for e in tops:
        if e.name != R and e.name not in CARRIED:
            add("unexpected_top", e.name)

    # explicit work list (no recursion limit); issue order is undefined anyway
    work = [(e, ROOT) for e in tops if e.name == R]
    work.reverse()
    while work:
        E, P = work.pop()
        name = E.name
        rule = model.rules.get(name)
        if rule is None:
            add("unknown_tag", name, P)
            continue
        L = rule.lists
        F = rule.flags
        kids = child_elements(E)
        names = [k.name for k in kids]
        if L["parent_must_be"] and P not in L["parent_must_be"]:
            add("wrong_parent", name, P)
        if F["text_only"] and kids:
            add("not_text_only", name)
        if F["cannot_be_empty"] and is_empty(E):
            add("empty", name)
        v = None
        if rule.has_exact or F["must_be_boolean"]:
            v = value_of(E)
        if rule.has_exact and v != rule.exact:
            add("not_equal", name)
        if F["must_be_boolean"] and v != "true" and v != "false":
            add("not_boolean", name)
        allowed = set(L["must_contain"]) | set(L["may_contain"]) | set(L["must_contain_one_of"])
        if rule.count is not None:
            allowed.add(rule.count[0])
        auc = F["allows_unknown_children"]
        forbidden = set(L["cannot_contain"])
        for cn in names:
            if cn in forbidden:
                add("forbidden_child", name, cn)
            elif not auc and cn not in allowed:
                add("child_not_allowed", name, cn)
        nameset = set(names)
        for N in L["must_contain"]:
            if N not in nameset:
                add("missing_child", name, N)
        if L["must_contain_one_of"] and not any(n in nameset for n in L["must_contain_one_of"]):
            add("missing_one_of", name)
        if rule.count is not None:
            N, K = rule.count
            if names.count(N) != K:
                add("wrong_count", name, N)
        seen = set()
        for N in L["at_most_one"]:          # 2k
            if N in seen:
                continue
            seen.add(N)
            if names.count(N) > 1:
                add("too_many", name, N)
        sw = L["starts_with"]               # 2l
        if sw:
            pos = {}
            for i, N in enumerate(sw):
                pos.setdefault(N, i)
            last = None
            passed = False
            for cn in names:
                if cn not in pos:
                    passed = True
                else:
                    i = pos[cn]
                    if passed or (last is not None and i < last):
                        add("out_of_order", name, cn)
                    else:
                        last = i
        if not auc:                          # 2m
            for k in reversed(kids):
                work.append((k, name))
    return issues


# ---------------------------------------------------------------- CLI

def run_validate(schema_bytes, doc_bytes):
    try:
        sroot = parse(schema_bytes)
    except ParseError as e:
        return {"schema_not_parsed": True, "reason": str(e)}
    try:
        droot = parse(doc_bytes)
    except ParseError as e:
        return {"document_not_parsed": True, "reason": str(e)}
    sel = find_schema_element(sroot)
    if sel is None:
        return {"unusable_schema": True}
    model = read_schema(sel)
    if model is None:
        return {"unusable_schema": True}
    return {"issues": validate(droot, model)}


def main(argv):
    if len(argv) != 4 or argv[1] != "validate":
        sys.stderr.write("usage: swv.py validate <schema-path> <document-path>\n")
        return 2
    with open(argv[2], "rb") as f:
        sb = f.read()
    with open(argv[3], "rb") as f:
        db = f.read()
    out = json.dumps(run_validate(sb, db), ensure_ascii=False)
    sys.stdout.buffer.write(out.encode("utf-8", "surrogatepass") + b"\n")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
