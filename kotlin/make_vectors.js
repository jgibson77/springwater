// Rewrites kotlin/vectors.tsv from tools/conformance_vectors.json, so the
// Kotlin test needs no JSON library. Usage: node kotlin/make_vectors.js
"use strict";
const fs = require("fs");
const path = require("path");
const repo = path.join(__dirname, "..");
const vectors = JSON.parse(fs.readFileSync(path.join(repo, "tools/conformance_vectors.json"), "utf8"));
const b64 = (s) => Buffer.from(s, "utf8").toString("base64");

// A tree as one line: "<name" opens an element, ">" closes it,
// "=ending base64(text)" is a content line. Parts are joined with "|".
function dump(node, out) {
  if (node.element !== undefined) {
    out.push("<" + node.element);
    for (const child of node.children) dump(child, out);
    out.push(">");
  } else {
    out.push("=" + node.ending + " " + b64(node.content));
  }
  return out;
}

const lines = [];
for (const v of vectors.parse_vectors) {
  const expected = v.expect.error ? "error:" + v.expect.error : "tree:" + dump(v.expect.tree, []).join("|");
  lines.push(["P", v.name, v.input_base64 === "" ? "-" : v.input_base64, expected].join("\t"));
}
for (const c of vectors.classify_vectors) {
  lines.push(["C", b64(c.line), c.kind + ":" + (c.name === null ? "-" : c.name)].join("\t"));
}
fs.writeFileSync(path.join(__dirname, "vectors.tsv"), lines.join("\n") + "\n");
console.log(`wrote ${lines.length} vectors`);
