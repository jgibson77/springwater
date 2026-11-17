#!/usr/bin/env python3
"""Writes schemas/screenplay.schema.springwater.

    python3 tools/make_screenplay_schema.py

The schema is long and regular, so it is generated from the table below. The
generated file is the schema; this script is only how it is kept consistent.
"""
import os

def rule(tag, **props):
    out = ["^rule", "^tag", tag, "^tag/"]
    for key in ["must_contain", "must_contain_one_of", "must_contain_count", "may_contain", "at_most_one",
                "starts_with", "text_only", "cannot_be_empty", "parent_must_be"]:
        if key in props:
            out += ["^" + key, props[key], "^" + key + "/"]
    return out + ["^rule/", ""]

def leaf(tag, parent, may_be_empty=False):
    props = {"text_only": "true", "parent_must_be": parent}
    if not may_be_empty:
        props["cannot_be_empty"] = "true"
    return rule(tag, **props)

# Where the things that stand between scenes may go.
OUTER = "screenplay, act1, act2, act3, sequence"
# What may stand between scenes, beside scenes and sequences themselves.
BETWEEN = "transition, title_card, montage, intercut, omitted, note"

rules = []
rules += rule("screenplay",
    must_contain_one_of="scene, sequence, act1",
    may_contain="validated_by, metadata, act1, act2, act3, sequence, scene, " + BETWEEN,
    at_most_one="validated_by, metadata, act1, act2, act3",
    starts_with="validated_by, metadata")
rules += leaf("validated_by", "screenplay")

# The work's own facts: what a title page prints.
rules += rule("metadata",
    must_contain="title",
    may_contain="written_by, story_by, screenplay_by, author, based_on, contact, revision, date, copyright, registration",
    at_most_one="title, written_by, story_by, screenplay_by, author, based_on, contact, revision, date, copyright, registration",
    starts_with="title",
    parent_must_be="screenplay")
for tag in ["title", "written_by", "story_by", "screenplay_by", "author", "based_on", "revision", "date",
            "copyright", "registration"]:
    rules += leaf(tag, "metadata")
rules += leaf("contact", "metadata", may_be_empty=True)

# A note is the writer's remark about the work. It is not part of the script.
rules += leaf("note", OUTER + ", scene, dialogue, montage, intercut", may_be_empty=True)

# Acts and sequences are ways of grouping scenes. Neither is required.
for act in ["act1", "act2", "act3"]:
    rules += rule(act,
        must_contain_one_of="scene, sequence",
        may_contain="scene, sequence, " + BETWEEN,
        parent_must_be="screenplay")
rules += rule("sequence",
    must_contain_one_of="scene, sequence",
    may_contain="label, scene, sequence, " + BETWEEN,
    at_most_one="label",
    starts_with="label",
    parent_must_be=OUTER)
rules += leaf("label", "sequence")

rules += rule("scene",
    must_contain="slugline",
    may_contain="number, action, dialogue, dual_dialogue, shot, super, title_card, transition, montage, intercut, note",
    at_most_one="number, slugline",
    starts_with="number, slugline",
    parent_must_be=OUTER + ", montage, intercut")
rules += leaf("number", "scene, omitted")
rules += leaf("slugline", "scene")
rules += leaf("action", "scene, montage, intercut")
rules += leaf("shot", "scene, montage, intercut")
# Words that appear on the screen over the picture.
rules += leaf("super", "scene, montage, intercut")
# Words that fill the screen on their own, such as a title or THE END.
rules += leaf("title_card", OUTER + ", scene")
rules += leaf("transition", OUTER + ", scene")

rules += rule("dialogue",
    must_contain="character",
    must_contain_one_of="lines, lyrics",
    may_contain="extension, parenthetical, lines, lyrics, note",
    at_most_one="character, extension",
    starts_with="character, extension",
    parent_must_be="scene, dual_dialogue, montage, intercut")
for tag in ["character", "extension", "parenthetical", "lines", "lyrics"]:
    rules += leaf(tag, "dialogue")
rules += rule("dual_dialogue", must_contain_count="dialogue, 2", parent_must_be="scene")

# A montage and an intercut are written the same way: a heading, what is
# shown, and optionally a line that closes it. SERIES OF SHOTS is a montage
# whose heading says so.
for tag in ["montage", "intercut"]:
    rules += rule(tag,
        must_contain="heading",
        must_contain_one_of="action, shot, scene, dialogue",
        may_contain="action, shot, scene, dialogue, super, closing, note",
        at_most_one="heading, closing",
        starts_with="heading",
        parent_must_be=OUTER + ", scene")
rules += leaf("heading", "montage, intercut")
rules += leaf("closing", "montage, intercut")

# A scene removed from a numbered draft. Its number stays so the others keep theirs.
rules += rule("omitted", must_contain="number", at_most_one="number", parent_must_be=OUTER)

lines = ["^Springwater", "^schema", "^validated_by", "schema.schema v1.1", "^validated_by/", "",
    "^metadata", "^name", "Screenplay", "^name/", "^version", "2.0", "^version/", "^description",
    "A screenplay: scenes, what is seen and said in them, and the facts a title page prints. Acts and sequences are optional ways of grouping scenes.",
    "^description/", "^strictness", "absolute", "^strictness/", "^metadata/", "",
    "^required_root", "screenplay", "^required_root/", "",
    "^marks", "^mark", "^name", "emphasis", "^name/", "^open", "_", "^open/", "^close", "_", "^close/",
    "^meaning", "The words between the two marks are emphasized.", "^meaning/", "^mark/", "^marks/", "",
    "^structure_rules", "", *rules, "^structure_rules/", "",
    "^validation", "^empty_tags", "error", "^empty_tags/", "^unknown_tags", "error", "^unknown_tags/",
    "^invalid_nesting", "error", "^invalid_nesting/", "^missing_required", "error", "^missing_required/",
    "^validation/", "", "^schema/", "^Springwater/"]

path = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "schemas", "screenplay.schema.springwater")
with open(path, "w", encoding="utf-8", newline="\n") as f:
    f.write("\n".join(lines) + "\n")
print("wrote", len(rules) and sum(1 for l in rules if l == "^rule"), "rules")
