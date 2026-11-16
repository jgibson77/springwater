// Runs the JavaScript implementation against the repository's conformance
// vectors and its own documents. Usage: node javascript/test.js
"use strict";
const fs = require("fs");
const path = require("path");
const SW = require("./springwater.js");

const repo = path.join(__dirname, "..");
const read = (p) => fs.readFileSync(path.join(repo, p));
let failures = 0;
const fail = (msg) => { failures += 1; console.log("FAIL " + msg); };

// 1. Conformance vectors.
const vectors = JSON.parse(read("tools/conformance_vectors.json").toString("utf8"));
const asVector = (n) => n.name !== undefined
  ? { element: n.name, children: n.children.map(asVector) }
  : { content: n.text, ending: n.ending };
let passed = 0;
for (const v of vectors.parse_vectors) {
  let got;
  try { got = { tree: asVector(SW.parse(Buffer.from(v.input_base64, "base64"))) }; }
  catch (e) { got = { error: e.kind }; }
  if (JSON.stringify(got) === JSON.stringify(v.expect)) passed += 1; else fail("parse vector: " + v.name);
}
for (const c of vectors.classify_vectors) {
  const g = SW.classify(SW.trimmed(c.line));
  if (g.kind === c.kind && g.name === c.name) passed += 1; else fail("classify vector: " + JSON.stringify(c.line));
}
console.log(`conformance vectors: ${passed} passed`);

// 2. Repository documents: parse, canonical round trip, schema validity.
const dir = (d) => fs.readdirSync(path.join(repo, d)).filter((f) => f.endsWith(".springwater")).sort().map((f) => d + "/" + f);
const meta = SW.buildSchema(SW.parse(read("schemas/schema.schema.springwater")));
const byRoot = {};
for (const f of dir("schemas")) {
  if (f.endsWith("schema.schema.springwater")) continue;
  const s = SW.buildSchema(SW.parse(read(f)));
  byRoot[s.requiredRoot] = s;
}
const documents = [...dir("schemas"), ...dir("examples"), ...dir("profiles"), ...dir("presentations"), "ROSETTA.springwater"];
for (const f of documents) {
  const bytes = read(f);
  const root = SW.parse(bytes);
  if (SW.serialize(root) !== bytes.toString("utf8")) fail("canonical round trip: " + f);
  const first = root.children.find((c) => c.name !== undefined);
  const schema = f.startsWith("schemas/") ? meta : byRoot[first.name];
  if (!schema) { fail("no schema for " + f); continue; }
  const issues = SW.validate(schema, root);
  if (issues.length) fail(f + ": " + issues.slice(0, 3).join("; "));
}
console.log(`repository documents: ${documents.length} checked`);

// 3. Self-contained documents: a document may carry its own schema.
{
  const f = "examples/genesis_1_3.self_contained.springwater";
  const root = SW.parse(read(f));
  const own = SW.carriedSchema(root);
  if (!own) fail("self-contained: no carried schema found");
  else {
    if (own.requiredRoot !== "parallel_text") fail("self-contained: carried schema is for " + own.requiredRoot);
    if (SW.validate(own, root).length) fail("self-contained: work is not valid against its carried schema");
    // The carried schema catches what a bundled schema would.
    const text = read(f).toString("utf8").replace(/\^hebrew\n[^\n]*\n\^hebrew\/\n(?=\^passage\/)/, "");
    if (SW.validate(SW.carriedSchema(SW.parse(Buffer.from(text))), SW.parse(Buffer.from(text))).length === 0) {
      fail("self-contained: carried schema missed a removed language");
    }
  }
  // It also carries the schema for schemas, so nothing outside the file is needed.
  const metaEl = SW.carriedSchemaElement(root, "schema");
  if (!metaEl) fail("self-contained: no carried schema for schemas");
  else {
    const carriedMeta = SW.buildSchemaFromElement(metaEl);
    for (const e of root.children.filter((c) => c.name === "schema")) {
      if (SW.validate(carriedMeta, { name: "Springwater", children: [e] }).length) {
        fail("self-contained: a carried schema is not valid against the carried schema for schemas");
      }
    }
  }
  // A document that carries no schema reports none.
  if (SW.carriedSchema(SW.parse(read("examples/genesis_1_3.springwater"))) !== null) fail("carried schema found where there is none");
  // Only schema and presentation may be carried; anything else is still unexpected.
  const stray = SW.parse(Buffer.from("^Springwater\n^parallel_text\n^parallel_text/\n^notes\n^notes/\n^Springwater/\n"));
  if (!SW.validate(byRoot["parallel_text"], stray).some((m) => m.includes("unexpected top-level element <notes>"))) {
    fail("stray top-level element was not reported");
  }
  console.log("self-contained documents: checked");
}

console.log(failures === 0 ? "all checks passed" : `${failures} failure(s)`);
process.exit(failures === 0 ? 0 : 1);
