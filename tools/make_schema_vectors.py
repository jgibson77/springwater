# Writes tools/schema_conformance_vectors.json.
# Usage: python3 tools/make_schema_vectors.py tools/schema_conformance_vectors.json
#
# Every expectation below is written by hand from SCHEMA_SPEC.txt, not taken
# from any validator's output.
import json, sys

def sw(*lines):                       # a whole Springwater document
    return "\n".join(["^Springwater", *lines, "^Springwater/"]) + "\n"
def el(tag, *lines):                  # an element as a list of lines
    return ["^" + tag, *lines, "^" + tag + "/"]
def rule(tag, **props):
    body = el("tag", tag) if tag is not None else []
    for k, v in props.items():
        body += el(k, *(v if isinstance(v, list) else [v]))
    return el("rule", *body)
def schema(root, *rules, extra=()):
    head = el("required_root", root) if root is not None else []
    return sw(*el("schema", *head, *extra, *el("structure_rules", *[l for r in rules for l in r])))
def I(kind, element, other=None):
    d = {"kind": kind, "element": element}
    if other is not None: d["other"] = other
    return d

V = []
def vec(name, sch, doc, issues=None, unusable=False):
    V.append({"name": name, "schema": sch, "document": doc,
              "expect": {"unusable_schema": True} if unusable else {"issues": issues}})

MEMO = schema("memo",
    rule("memo", must_contain="title", may_contain="body, note"),
    rule("title", text_only="true", cannot_be_empty="true", parent_must_be="memo"),
    rule("body", text_only="true", parent_must_be="memo"),
    rule("note"))
title = el("title", "Hi")

vec("valid minimal document", MEMO, sw(*el("memo", *title)), [])
vec("no top-level element at all", MEMO, sw(), [I("missing_root", "memo")])
vec("wrong top-level element", MEMO, sw(*el("letter")), [I("missing_root", "memo"), I("unexpected_top", "letter")])
vec("extra top-level element beside the work", MEMO, sw(*el("memo", *title), *el("extra")), [I("unexpected_top", "extra")])
vec("carried schema and presentation are not judged", MEMO,
    sw(*el("memo", *title), *el("schema", *el("anything")), *el("presentation")), [])
vec("every top-level work is checked", MEMO, sw(*el("memo", *title), *el("memo")), [I("missing_child", "memo", "title")])
vec("missing required child", MEMO, sw(*el("memo")), [I("missing_child", "memo", "title")])
vec("empty element with no lines", MEMO, sw(*el("memo", *el("title"))), [I("empty", "title")])
vec("empty element with only blank lines", MEMO, sw(*el("memo", *el("title", " ", "\t", ""))), [I("empty", "title")])
vec("a no-break space is not blank", MEMO, sw(*el("memo", *el("title", " "))), [])
vec("text-only element holding an element", MEMO, sw(*el("memo", *el("title", "x", *el("note")))),
    [I("not_text_only", "title"), I("child_not_allowed", "title", "note")])
vec("unknown element: reported by its parent and by its own check", MEMO, sw(*el("memo", *title, *el("zzz"))),
    [I("child_not_allowed", "memo", "zzz"), I("unknown_tag", "zzz", "memo")])
vec("nothing inside an unknown element is checked", MEMO, sw(*el("memo", *title, *el("zzz", *el("title")))),
    [I("child_not_allowed", "memo", "zzz"), I("unknown_tag", "zzz", "memo")])
vec("known element under the wrong parent", MEMO, sw(*el("memo", *title, *el("note", *el("title", "b")))),
    [I("child_not_allowed", "note", "title"), I("wrong_parent", "title", "note")])
vec("must_contain means at least one", MEMO, sw(*el("memo", *title, *el("title", "Again"))), [])
vec("order of children does not matter", MEMO, sw(*el("memo", *el("body", "b"), *title)), [])
vec("required root with no rule", schema("memo", rule("title")), sw(*el("memo")), [I("unknown_tag", "memo", "Springwater")])
vec("parent of a top-level work is Springwater", schema("memo", rule("memo", parent_must_be="Springwater")), sw(*el("memo")), [])
vec("top-level work with another required parent", schema("memo", rule("memo", parent_must_be="folder")), sw(*el("memo")),
    [I("wrong_parent", "memo", "Springwater")])

CFG = schema("cfg",
    rule("cfg", may_contain="mode, flag"),
    rule("mode", must_equal="fast"),
    rule("flag", must_be_boolean="true"))
vec("exact value, surrounded by spaces, tabs, and blank lines", CFG, sw(*el("cfg", *el("mode", "", " \tfast\t ", ""))), [])
vec("exact value is case-sensitive", CFG, sw(*el("cfg", *el("mode", "Fast"))), [I("not_equal", "mode")])
vec("a no-break space is not trimmed from a value", CFG, sw(*el("cfg", *el("mode", " fast"))), [I("not_equal", "mode")])
vec("lines of a value are joined with a line feed", CFG, sw(*el("cfg", *el("mode", "fa", "st"))), [I("not_equal", "mode")])
vec("missing exact value", CFG, sw(*el("cfg", *el("mode"))), [I("not_equal", "mode")])
vec("boolean true", CFG, sw(*el("cfg", *el("flag", "true"))), [])
vec("boolean false with surrounding whitespace", CFG, sw(*el("cfg", *el("flag", "  false  "))), [])
vec("boolean is case-sensitive", CFG, sw(*el("cfg", *el("flag", "TRUE"))), [I("not_boolean", "flag")])
vec("empty boolean", CFG, sw(*el("cfg", *el("flag"))), [I("not_boolean", "flag")])
vec("a multi-line exact value", schema("cfg", rule("cfg", may_contain="mode"), rule("mode", must_equal=["a", "b"])),
    sw(*el("cfg", *el("mode", "a", "b"))), [])
vec("a value ignores child elements and joins the lines around them",
    schema("cfg", rule("cfg", may_contain="mode"), rule("mode", must_equal=["a", "b"], may_contain="k"), rule("k")),
    sw(*el("cfg", *el("mode", "a", *el("k", "ignored"), "b"))), [])
vec("an empty exact value requires the empty value", schema("cfg", rule("cfg", may_contain="mode"), rule("mode", must_equal=[])),
    sw(*el("cfg", *el("mode", "x"))), [I("not_equal", "mode")])
vec("a flag is true only when its value is exactly true",
    schema("cfg", rule("cfg", may_contain="flag"), rule("flag", must_be_boolean="True")),
    sw(*el("cfg", *el("flag", "maybe"))), [])
vec("text_only written as yes is not set",
    schema("cfg", rule("cfg", may_contain="mode"), rule("mode", text_only="yes", may_contain="k"), rule("k")),
    sw(*el("cfg", *el("mode", *el("k")))), [])
vec("text_only is satisfied by an element with nothing in it",
    schema("cfg", rule("cfg", may_contain="mode"), rule("mode", text_only="true")), sw(*el("cfg", *el("mode"))), [])
vec("an element holding an element is not empty",
    schema("cfg", rule("cfg", may_contain="mode"), rule("mode", cannot_be_empty="true", may_contain="k"), rule("k")),
    sw(*el("cfg", *el("mode", *el("k")))), [])

def PAIR(count): return schema("pair", rule("pair", must_contain_count=count), rule("item"))
item = el("item")
vec("count met", PAIR("item, 2"), sw(*el("pair", *item, *item)), [])
vec("count too few", PAIR("item, 2"), sw(*el("pair", *item)), [I("wrong_count", "pair", "item")])
vec("count too many", PAIR("item, 2"), sw(*el("pair", *item, *item, *item)), [I("wrong_count", "pair", "item")])
vec("count with none present", PAIR("item, 2"), sw(*el("pair")), [I("wrong_count", "pair", "item")])
vec("count with leading zero", PAIR("item, 02"), sw(*el("pair", *item, *item)), [])
vec("count of zero, met", PAIR("item, 0"), sw(*el("pair")), [])
vec("count of zero, not met", PAIR("item, 0"), sw(*el("pair", *item)), [I("wrong_count", "pair", "item")])
vec("a signed count is not a count", PAIR("item, +2"), sw(*el("pair", *item)), [I("child_not_allowed", "pair", "item")])
vec("a count with three parts is not a count", PAIR("item, 2, 3"), sw(*el("pair", *item, *item)),
    [I("child_not_allowed", "pair", "item"), I("child_not_allowed", "pair", "item")])
vec("a later malformed count leaves the earlier count in place",
    schema("pair", el("rule", *el("tag", "pair"), *el("must_contain_count", "item, 2"), *el("must_contain_count", "item, many")), rule("item")),
    sw(*el("pair", *item)), [I("wrong_count", "pair", "item")])

ONEOF = schema("doc", rule("doc", must_contain_one_of="a, b"), rule("a"), rule("b"))
vec("one-of with neither", ONEOF, sw(*el("doc")), [I("missing_one_of", "doc")])
vec("one-of with one", ONEOF, sw(*el("doc", *el("b"))), [])
vec("one-of with both", ONEOF, sw(*el("doc", *el("a"), *el("b"))), [])

vec("cannot_contain wins over may_contain", schema("box", rule("box", may_contain="x", cannot_contain="x"), rule("x")),
    sw(*el("box", *el("x"))), [I("forbidden_child", "box", "x")])

OPEN = schema("open",
    rule("open", allows_unknown_children="true", must_contain="need", cannot_contain="bad"),
    rule("need", cannot_be_empty="true"))
vec("nothing inside an open element is checked", OPEN, sw(*el("open", *el("need"), *el("whatever", *el("deep")))), [])
vec("an open element still requires what it must contain", OPEN, sw(*el("open", *el("whatever"))), [I("missing_child", "open", "need")])
vec("an open element still forbids what it cannot contain", OPEN, sw(*el("open", *el("need", "x"), *el("bad"))),
    [I("forbidden_child", "open", "bad")])

vec("a later rule for the same tag replaces the earlier one",
    schema("r", rule("r", may_contain="t"), rule("t", must_contain="a"), rule("t", may_contain="a"), rule("a")),
    sw(*el("r", *el("t"))), [])
vec("a later property of the same name replaces the earlier one",
    schema("r", el("rule", *el("tag", "r"), *el("must_contain", "a"), *el("must_contain", "b")), rule("a"), rule("b")),
    sw(*el("r", *el("b"))), [])
vec("a rule with no tag, and a rule with an empty tag, are ignored",
    schema("r", rule(None, must_contain="a"), el("rule", *el("tag", " "), *el("must_contain", "a")), rule("r")),
    sw(*el("r")), [])
vec("an unknown property in a rule is ignored",
    schema("r", el("rule", *el("tag", "r"), *el("must_be_long", "true"))), sw(*el("r")), [])
vec("rules are read from every structure_rules element",
    sw(*el("schema", *el("required_root", "r"), *el("structure_rules", *rule("r", must_contain="a")), *el("structure_rules", *rule("a")))),
    sw(*el("r", *el("a"))), [])
vec("the last required_root is the one used",
    sw(*el("schema", *el("required_root", "memo"), *el("required_root", "letter"), *el("structure_rules", *rule("letter")))),
    sw(*el("letter")), [])
vec("a schema with no required_root is unusable",
    sw(*el("schema", *el("structure_rules", *rule("memo")))), sw(*el("memo")), unusable=True)
vec("a schema with an empty required_root is unusable",
    sw(*el("schema", *el("required_root", " "), *el("structure_rules", *rule("memo")))), sw(*el("memo")), unusable=True)
vec("a list drops empty pieces and trims the rest",
    schema("r", rule("r", must_contain=" a, ,b,, c "), rule("a"), rule("b"), rule("c")),
    sw(*el("r", *el("a"), *el("c"))), [I("missing_child", "r", "b")])
vec("a no-break space is not trimmed from a list item",
    schema("r", rule("r", must_contain="a, b"), rule("a"), rule("b")),
    sw(*el("r", *el("a"), *el("b"))), [I("missing_child", "r", " b"), I("child_not_allowed", "r", "b")])
vec("a required name listed twice is reported twice when missing",
    schema("r", rule("r", must_contain="a, a"), rule("a")), sw(*el("r")),
    [I("missing_child", "r", "a"), I("missing_child", "r", "a")])
vec("when the required root is schema, every top-level schema is a work",
    schema("schema", rule("schema", must_contain="metadata"), rule("metadata")),
    sw(*el("schema"), *el("schema", *el("metadata")), *el("presentation")),
    [I("missing_child", "schema", "metadata")])
vec("the schema element is the first top-level schema",
    sw(*el("note"), *el("schema", *el("required_root", "r"), *el("structure_rules", *rule("r"))),
       *el("schema", *el("required_root", "x"), *el("structure_rules", *rule("x")))),
    sw(*el("r")), [])

vec("a forbidden child is still checked", schema("box", rule("box", cannot_contain="x"), rule("x", cannot_be_empty="true")),
    sw(*el("box", *el("x"))), [I("forbidden_child", "box", "x"), I("empty", "x")])
vec("a later empty tag leaves the rule with no tag",
    schema("r", rule("r"), el("rule", *el("tag", "r"), *el("must_contain", "a"), *el("tag"))),
    sw(*el("r")), [])
vec("empty pieces do not count toward a count's two items", PAIR("item,,2"), sw(*el("pair", *item)),
    [I("wrong_count", "pair", "item")])
vec("two lines with no comma are one list item",
    schema("r", rule("r", must_contain=["a", "b"]), rule("a"), rule("b")),
    sw(*el("r", *el("a"), *el("b"))),
    [I("missing_child", "r", "a\nb"), I("child_not_allowed", "r", "a"), I("child_not_allowed", "r", "b")])
vec("content lines at the document root are not an issue", MEMO, sw("loose text", *el("memo", *title)), [])
vec("only the first top-level schema is read, even when unusable",
    sw(*el("schema", *el("structure_rules", *rule("r"))), *el("schema", *el("required_root", "r"), *el("structure_rules", *rule("r")))),
    sw(*el("r")), unusable=True)
vec("a document with no schema element gives no schema to read", sw(*el("note")), sw(*el("r")), unusable=True)

# --- version 1.1: at_most_one and starts_with
ONCE = schema("scene", rule("scene", must_contain="slug", may_contain="act, num", at_most_one="slug, num"),
    rule("slug"), rule("act"), rule("num"))
vec("at most one: one is fine", ONCE, sw(*el("scene", *el("slug"), *el("act"), *el("act"))), [])
vec("at most one: two is one issue", ONCE, sw(*el("scene", *el("slug"), *el("slug"))), [I("too_many", "scene", "slug")])
vec("at most one: five is still one issue", ONCE, sw(*el("scene", *[l for _ in range(5) for l in el("slug")])),
    [I("too_many", "scene", "slug")])
vec("at most one: each listed name is judged separately", ONCE,
    sw(*el("scene", *el("slug"), *el("slug"), *el("num"), *el("num"))),
    [I("too_many", "scene", "slug"), I("too_many", "scene", "num")])
vec("at most one: a name listed twice is judged once",
    schema("scene", rule("scene", may_contain="slug", at_most_one="slug, slug"), rule("slug")),
    sw(*el("scene", *el("slug"), *el("slug"))), [I("too_many", "scene", "slug")])
vec("at most one does not permit the child",
    schema("scene", rule("scene", at_most_one="slug"), rule("slug")),
    sw(*el("scene", *el("slug"))), [I("child_not_allowed", "scene", "slug")])

FIRST = schema("scene", rule("scene", may_contain="num, slug, act, talk", starts_with="num, slug"),
    rule("num"), rule("slug"), rule("act"), rule("talk"))
vec("starts with: listed children first and in order", FIRST,
    sw(*el("scene", *el("num"), *el("slug"), *el("act"), *el("talk"))), [])
vec("starts with: a listed child may be absent", FIRST, sw(*el("scene", *el("slug"), *el("act"))), [])
vec("starts with: none of the listed children present", FIRST, sw(*el("scene", *el("act"), *el("talk"))), [])
vec("starts with: a listed child after another child", FIRST,
    sw(*el("scene", *el("act"), *el("slug"))), [I("out_of_order", "scene", "slug")])
vec("starts with: listed children in the wrong order", FIRST,
    sw(*el("scene", *el("slug"), *el("num"), *el("act"))), [I("out_of_order", "scene", "num")])
vec("starts with: a listed name may repeat in place", FIRST,
    sw(*el("scene", *el("num"), *el("num"), *el("slug"), *el("slug"), *el("act"))), [])
vec("starts with: every misplaced child is its own issue", FIRST,
    sw(*el("scene", *el("act"), *el("num"), *el("slug"), *el("talk"), *el("slug"))),
    [I("out_of_order", "scene", "num"), I("out_of_order", "scene", "slug"), I("out_of_order", "scene", "slug")])
vec("starts with: a misplaced child does not move the mark", FIRST,
    sw(*el("scene", *el("slug"), *el("num"), *el("slug"), *el("act"))), [I("out_of_order", "scene", "num")])
vec("starts with: content lines may come anywhere", FIRST,
    sw(*el("scene", "text", *el("num"), "more", *el("slug"), *el("act"))), [])
vec("starts with does not permit the child",
    schema("scene", rule("scene", may_contain="act", starts_with="slug"), rule("slug"), rule("act")),
    sw(*el("scene", *el("slug"), *el("act"))), [I("child_not_allowed", "scene", "slug")])
vec("starts with: a name listed twice takes its first position",
    schema("scene", rule("scene", may_contain="a, b", starts_with="a, b, a"), rule("a"), rule("b")),
    sw(*el("scene", *el("a"), *el("b"), *el("a"))), [I("out_of_order", "scene", "a")])

out = {"description": "Schema validation conformance vectors for SCHEMA_SPEC.txt. Each vector gives a schema document and a document as Springwater text, and the expected result: either the multiset of issues, in no particular order, or that the schema is unusable. Expectations were written by hand from the specification.",
       "vectors": V}
json.dump(out, open(sys.argv[1], "w", encoding="utf-8"), ensure_ascii=False, indent=1)
print(len(V), "vectors")
