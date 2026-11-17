// Springwater v1.0 for JavaScript: parser, canonical serializer, schema validator.
// Follows the parsing algorithm in SYNTAX.txt. No dependencies.
//
// A tree is plain data:
//   element: { name: "scene", children: [ ... ] }
//   content: { text: "A line.", ending: "lf" | "crlf" | "cr" }

"use strict";

class SpringwaterError extends Error {
  constructor(kind, details = {}) {
    super(kind);
    this.kind = kind;       // e.g. "mismatchedClosingTag"
    this.details = details; // line numbers and names, where they apply
  }
}

// Divide at LF, CRLF, CR. U+2028 and U+2029 are content.
function physicalLines(s) {
  const lines = [];
  let start = 0, i = 0;
  while (i < s.length) {
    const c = s[i];
    if (c === "\n") { lines.push({ text: s.slice(start, i), ending: "lf" }); i += 1; start = i; }
    else if (c === "\r") {
      if (s[i + 1] === "\n") { lines.push({ text: s.slice(start, i), ending: "crlf" }); i += 2; }
      else { lines.push({ text: s.slice(start, i), ending: "cr" }); i += 1; }
      start = i;
    } else { i += 1; }
  }
  if (start < s.length) lines.push({ text: s.slice(start), ending: "none" });
  return lines;
}

// Remove leading and trailing U+0020 and U+0009 only.
function trimmed(text) {
  let a = 0, b = text.length;
  while (a < b && (text[a] === " " || text[a] === "\t")) a += 1;
  while (b > a && (text[b - 1] === " " || text[b - 1] === "\t")) b -= 1;
  return text.slice(a, b);
}

function isValidTagName(name) {
  return /^[A-Za-z][A-Za-z0-9_]*$/.test(name);
}

// Classify one trimmed line: content, open, close, or invalid.
function classify(t) {
  if (t.length === 0 || t[0] !== "^") return { kind: "content", name: null };
  let body = t.slice(1);
  let closing = false;
  if (body.endsWith("/")) { closing = true; body = body.slice(0, -1); }
  if (!isValidTagName(body)) return { kind: "invalid", name: null };
  return { kind: closing ? "close" : "open", name: body };
}

// Parse a byte stream (Uint8Array or Buffer) into the root element.
function parse(bytes) {
  if (bytes.length >= 3 && bytes[0] === 0xef && bytes[1] === 0xbb && bytes[2] === 0xbf) {
    throw new SpringwaterError("leadingBOM");
  }
  let s;
  try { s = new TextDecoder("utf-8", { fatal: true, ignoreBOM: true }).decode(bytes); }
  catch (e) { throw new SpringwaterError("invalidUTF8"); }

  const lines = physicalLines(s);
  if (lines.length === 0) throw new SpringwaterError("emptyDocument");
  if (trimmed(lines[0].text) !== "^Springwater") {
    throw new SpringwaterError("missingRootOpen", { found: trimmed(lines[0].text) });
  }

  const stack = [{ name: "Springwater", openedAt: 1, children: [] }];
  let root = null;
  for (let index = 1; index < lines.length; index++) {
    const line = index + 1;
    const { text, ending } = lines[index];
    const { kind, name } = classify(trimmed(text));
    const top = stack[stack.length - 1];
    if (kind === "content") {
      top.children.push({ text, ending });
    } else if (kind === "open") {
      if (name === "Springwater") throw new SpringwaterError("reservedRootName", { line });
      stack.push({ name, openedAt: line, children: [] });
    } else if (kind === "close") {
      if (top.name !== name) {
        throw new SpringwaterError("mismatchedClosingTag",
          { line, found: name, open: top.name, openedAt: top.openedAt });
      }
      if (stack.length === 1) {
        if (index !== lines.length - 1) throw new SpringwaterError("trailingLinesAfterRootClose", { line });
        stack.pop();
        root = { name: top.name, children: top.children };
      } else {
        stack.pop();
        stack[stack.length - 1].children.push({ name: top.name, children: top.children });
      }
    } else {
      throw new SpringwaterError("invalidCaretLine", { line, text: trimmed(text) });
    }
  }
  if (root === null) {
    if (stack.length > 1) {
      const top = stack[stack.length - 1];
      throw new SpringwaterError("unclosedTag", { name: top.name, openedAt: top.openedAt });
    }
    throw new SpringwaterError("missingRootClose");
  }
  return root;
}

const isElement = (node) => node.name !== undefined;
const ENDINGS = { lf: "\n", crlf: "\r\n", cr: "\r" };

// Canonical form: tag lines flush left and LF-terminated, content verbatim.
function serialize(root) {
  let out = "";
  const write = (el) => {
    out += "^" + el.name + "\n";
    for (const child of el.children) {
      if (isElement(child)) write(child);
      else out += child.text + ENDINGS[child.ending];
    }
    out += "^" + el.name + "/\n";
  };
  write(root);
  return out;
}

// ---------------------------------------------------------------- schemas

const childElements = (el) => el.children.filter(isElement);
const contentLines = (el) => el.children.filter((c) => !isElement(c)).map((c) => c.text);
// Schema whitespace is space, tab, and line feed, and nothing else
// (SCHEMA_SPEC.txt, TERMS). JavaScript's own trim() removes many more.
const schemaTrim = (text) => text.replace(/^[ \t\n]+/, "").replace(/[ \t\n]+$/, "");
const scalar = (el) => schemaTrim(contentLines(el).join("\n"));
const list = (text) => text.split(",").map(schemaTrim).filter((p) => p.length > 0);

// Build a schema model from a parsed schema document.
function buildSchema(schemaRoot) {
  const schemaEl = childElements(schemaRoot).find((e) => e.name === "schema");
  if (!schemaEl) throw new Error("unusable schema: no schema element");
  return buildSchemaFromElement(schemaEl);
}

// Build a schema model from a `schema` element, wherever it was found.
function buildSchemaFromElement(schemaEl) {
  const schema = { requiredRoot: null, rules: {} };
  for (const e of childElements(schemaEl)) {
    if (e.name === "required_root") schema.requiredRoot = scalar(e);
    if (e.name !== "structure_rules") continue;
    for (const r of childElements(e)) {
      if (r.name !== "rule") continue;
      const rule = {
        tag: null, mustContain: [], mayContain: [], cannotContain: [], mustContainOneOf: [],
        mustContainCount: null, parentMustBe: [], cannotBeEmpty: false, textOnly: false,
        mustEqual: null, mustBeBoolean: false, allowsUnknownChildren: false,
        atMostOne: [], startsWith: [],
      };
      for (const p of childElements(r)) {
        const v = scalar(p);
        switch (p.name) {
          case "tag": rule.tag = v; break;
          case "must_contain": rule.mustContain = list(v); break;
          case "may_contain": rule.mayContain = list(v); break;
          case "cannot_contain": rule.cannotContain = list(v); break;
          case "must_contain_one_of": rule.mustContainOneOf = list(v); break;
          case "must_contain_count": {
            const parts = list(v);
            if (parts.length === 2 && /^[0-9]+$/.test(parts[1])) {
              rule.mustContainCount = { tag: parts[0], count: parseInt(parts[1], 10) };
            }
            break;
          }
          case "parent_must_be": rule.parentMustBe = list(v); break;
          case "at_most_one": rule.atMostOne = list(v); break;
          case "starts_with": rule.startsWith = list(v); break;
          case "cannot_be_empty": rule.cannotBeEmpty = v === "true"; break;
          case "text_only": rule.textOnly = v === "true"; break;
          case "must_equal": rule.mustEqual = v; break;
          case "must_be_boolean": rule.mustBeBoolean = v === "true"; break;
          case "allows_unknown_children": rule.allowsUnknownChildren = v === "true"; break;
        }
      }
      if (rule.tag) schema.rules[rule.tag] = rule;
    }
  }
  // A schema with no required root cannot be validated against.
  if (!schema.requiredRoot) throw new Error("unusable schema: no required_root");
  return schema;
}

// Validate a parsed document against a schema, as SCHEMA_SPEC.txt defines it.
// Returns the issues found, each { kind, element, other? }; an empty list
// means the document is valid against that schema. Order carries no meaning.
function validateIssues(schema, root) {
  const issues = [];
  const add = (kind, element, other) => issues.push(other === undefined ? { kind, element } : { kind, element, other });
  const top = childElements(root);
  const required = top.filter((e) => e.name === schema.requiredRoot);
  if (required.length === 0) add("missing_root", schema.requiredRoot);
  for (const e of top) {
    // A document may carry its own schema and presentation beside the work
    // (see CONVENTIONS.md, "Self-contained documents"). They are not part of
    // the work and are not judged by the work's schema.
    if (e.name !== schema.requiredRoot && !CARRIED.includes(e.name)) add("unexpected_top", e.name);
  }
  for (const e of required) check(e, "Springwater", schema, add);
  return issues;
}

function check(el, parent, schema, add) {
  const rule = schema.rules[el.name];
  if (!rule) { add("unknown_tag", el.name, parent); return; }
  if (rule.parentMustBe.length && !rule.parentMustBe.includes(parent)) add("wrong_parent", el.name, parent);
  const kids = childElements(el);
  const names = kids.map((k) => k.name);
  const hasText = contentLines(el).some((t) => trimmed(t) !== "");
  if (rule.textOnly && kids.length) add("not_text_only", el.name);
  if (rule.cannotBeEmpty && !hasText && !kids.length) add("empty", el.name);
  if (rule.mustEqual !== null && scalar(el) !== rule.mustEqual) add("not_equal", el.name);
  if (rule.mustBeBoolean && scalar(el) !== "true" && scalar(el) !== "false") add("not_boolean", el.name);
  const allowed = new Set([...rule.mustContain, ...rule.mayContain, ...rule.mustContainOneOf]);
  if (rule.mustContainCount) allowed.add(rule.mustContainCount.tag);
  for (const k of kids) {
    if (rule.cannotContain.includes(k.name)) add("forbidden_child", el.name, k.name);
    else if (!rule.allowsUnknownChildren && !allowed.has(k.name)) add("child_not_allowed", el.name, k.name);
  }
  for (const t of rule.mustContain) {
    if (!names.includes(t)) add("missing_child", el.name, t);
  }
  if (rule.mustContainOneOf.length && !names.some((n) => rule.mustContainOneOf.includes(n))) add("missing_one_of", el.name);
  if (rule.mustContainCount) {
    const { tag, count } = rule.mustContainCount;
    if (names.filter((n) => n === tag).length !== count) add("wrong_count", el.name, tag);
  }
  for (const n of [...new Set(rule.atMostOne)]) {
    if (names.filter((x) => x === n).length > 1) add("too_many", el.name, n);
  }
  if (rule.startsWith.length) {
    let last = -1, passed = false;
    for (const n of names) {
      const i = rule.startsWith.indexOf(n);
      if (i < 0) passed = true;
      else if (passed || i < last) add("out_of_order", el.name, n);
      else last = i;
    }
  }
  if (!rule.allowsUnknownChildren) for (const k of kids) check(k, el.name, schema, add);
}

// The category each kind of issue belongs to (SCHEMA_SPEC.txt, ISSUES).
const ISSUE_CATEGORY = {
  missing_root: "missing_required", unexpected_top: "unknown_tags", unknown_tag: "unknown_tags",
  wrong_parent: "invalid_nesting", not_text_only: "invalid_nesting", empty: "empty_tags",
  not_equal: "mismatch", not_boolean: "mismatch", forbidden_child: "invalid_nesting",
  child_not_allowed: "unknown_tags", missing_child: "missing_required", missing_one_of: "missing_required",
  wrong_count: "missing_required",
  too_many: "invalid_nesting", out_of_order: "invalid_nesting",
};

// One issue in words. The wording is not part of the specification.
function describeIssue(i) {
  switch (i.kind) {
    case "missing_root": return `missing required root <${i.element}>`;
    case "unexpected_top": return `unexpected top-level element <${i.element}>`;
    case "unknown_tag": return `unknown tag <${i.element}> under <${i.other}>`;
    case "wrong_parent": return `<${i.element}> is not allowed under <${i.other}>`;
    case "not_text_only": return `<${i.element}> is text only but contains elements`;
    case "empty": return `<${i.element}> cannot be empty`;
    case "not_equal": return `<${i.element}> does not have its required value`;
    case "not_boolean": return `<${i.element}> must be true or false`;
    case "forbidden_child": return `<${i.element}> cannot contain <${i.other}>`;
    case "child_not_allowed": return `<${i.other}> is not allowed in <${i.element}>`;
    case "missing_child": return `<${i.element}> is missing required <${i.other}>`;
    case "missing_one_of": return `<${i.element}> is missing one of its required alternatives`;
    case "wrong_count": return `<${i.element}> has the wrong number of <${i.other}>`;
    case "too_many": return `<${i.element}> has more than one <${i.other}>`;
    case "out_of_order": return `<${i.other}> is out of order in <${i.element}>`;
    default: return `${i.kind} <${i.element}>`;
  }
}

// Validate and describe: a list of messages, empty when the document is valid.
function validate(schema, root) {
  return validateIssues(schema, root).map(describeIssue);
}

// ---------------------------------------------- self-contained documents

// The element names a document may carry at its top level beside the work.
const CARRIED = ["schema", "presentation"];

// The `schema` element this document carries for elements named `name`:
// the first top-level `schema` whose required_root is `name`. Null if none.
function carriedSchemaElement(root, name) {
  return childElements(root).find((e) =>
    e.name === "schema" && childElements(e).some((c) => c.name === "required_root" && scalar(c) === name)
  ) || null;
}

// The `presentation` element this document carries for elements named
// `name`: the first top-level `presentation` whose target_schema is `name`.
function carriedPresentationElement(root, name) {
  return childElements(root).find((e) => {
    if (e.name !== "presentation") return false;
    const metadata = childElements(e).find((c) => c.name === "metadata");
    return !!metadata && childElements(metadata).some((c) => c.name === "target_schema" && scalar(c) === name);
  }) || null;
}

// The schema a document carries for its own work (its first top-level
// element), as a schema model. Null when it carries none.
function carriedSchema(root) {
  const work = childElements(root)[0];
  if (!work) return null;
  const el = carriedSchemaElement(root, work.name);
  return el ? buildSchemaFromElement(el) : null;
}

module.exports = {
  SpringwaterError, parse, serialize, classify, trimmed, physicalLines, buildSchema, validate,
  buildSchemaFromElement, carriedSchema, carriedSchemaElement, carriedPresentationElement,
  validateIssues, describeIssue, ISSUE_CATEGORY,
};
