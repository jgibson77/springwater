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
const scalar = (el) => contentLines(el).join("\n").trim();
const list = (text) => text.split(",").map((p) => p.trim()).filter((p) => p.length > 0);

// Build a schema model from a parsed schema document.
function buildSchema(schemaRoot) {
  const schemaEl = childElements(schemaRoot).find((e) => e.name === "schema");
  if (!schemaEl) throw new Error("no schema element");
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
  return schema;
}

// Validate a parsed document against a schema. Returns a list of messages;
// an empty list means the document is valid against that schema.
function validate(schema, root) {
  const issues = [];
  const top = childElements(root);
  const required = top.filter((e) => e.name === schema.requiredRoot);
  if (required.length === 0) issues.push(`missing required root <${schema.requiredRoot}>`);
  for (const e of top) {
    if (e.name !== schema.requiredRoot) issues.push(`unexpected top-level element <${e.name}>`);
  }
  for (const e of required) check(e, "Springwater", schema, issues);
  return issues;
}

function check(el, parent, schema, issues) {
  const rule = schema.rules[el.name];
  if (!rule) { issues.push(`unknown tag <${el.name}> under <${parent}>`); return; }
  if (rule.parentMustBe.length && !rule.parentMustBe.includes(parent)) {
    issues.push(`<${el.name}> under <${parent}>: parent must be one of ${rule.parentMustBe.join(", ")}`);
  }
  const kids = childElements(el);
  const names = kids.map((k) => k.name);
  const hasText = contentLines(el).some((t) => trimmed(t) !== "");
  if (rule.textOnly && kids.length) issues.push(`<${el.name}> is text only but contains ${names.join(", ")}`);
  if (rule.cannotBeEmpty && !hasText && !kids.length) issues.push(`<${el.name}> cannot be empty`);
  if (rule.mustEqual !== null && scalar(el) !== rule.mustEqual) {
    issues.push(`<${el.name}> must equal '${rule.mustEqual}'`);
  }
  if (rule.mustBeBoolean && scalar(el) !== "true" && scalar(el) !== "false") {
    issues.push(`<${el.name}> must be true or false`);
  }
  const allowed = new Set([...rule.mustContain, ...rule.mayContain, ...rule.mustContainOneOf]);
  if (rule.mustContainCount) allowed.add(rule.mustContainCount.tag);
  for (const k of kids) {
    if (rule.cannotContain.includes(k.name)) issues.push(`<${el.name}> cannot contain <${k.name}>`);
    else if (!rule.allowsUnknownChildren && !allowed.has(k.name)) {
      issues.push(`<${k.name}> is not allowed in <${el.name}>`);
    }
  }
  for (const t of rule.mustContain) {
    if (!names.includes(t)) issues.push(`<${el.name}> is missing required <${t}>`);
  }
  if (rule.mustContainOneOf.length && !names.some((n) => rule.mustContainOneOf.includes(n))) {
    issues.push(`<${el.name}> must contain one of ${rule.mustContainOneOf.join(", ")}`);
  }
  if (rule.mustContainCount) {
    const { tag, count } = rule.mustContainCount;
    const found = names.filter((n) => n === tag).length;
    if (found !== count) issues.push(`<${el.name}> must contain exactly ${count} <${tag}>, found ${found}`);
  }
  if (!rule.allowsUnknownChildren) for (const k of kids) check(k, el.name, schema, issues);
}

module.exports = {
  SpringwaterError, parse, serialize, classify, trimmed, physicalLines, buildSchema, validate,
};
