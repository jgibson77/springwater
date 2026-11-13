# Changelog

## Unreleased

Springwater Core is unchanged: the seven rules and `SYNTAX.txt` are as frozen.

- Schemas now describe only what a document is. The `font`, `page`, and
  `rendering_rules` blocks moved, unchanged, out of every schema into separate
  presentation documents under `presentations/`, validated by the new
  `presentation.schema`. The meta-schema no longer requires rendering rules.
- The screenplay schema no longer has a `page_break` element. A document
  does not store where a page ends; pages exist only when a presentation is
  applied.
- In the screenplay schema, `title_page` is renamed `metadata` and the
  `centered` element is removed. Both were named for how something looks.
  The break after a screenplay's metadata is now a rule in the screenplay
  presentation, as it already was for novels.
- The renderer reads a presentation instead of a schema:
  `HTMLRenderer.render(_:presentation:title:)`.
- Added JavaScript (`javascript/`) and Kotlin (`kotlin/`) implementations.
  Each passes the conformance vectors and checks every document in the
  repository.
- Added `CONVENTIONS.md` (non-normative) and `tools/conformance_vectors.json`.
- The README states the format's costs and the two kinds of validity.

## v1.0 - Initial public release

Springwater is a line-oriented, plain-text format for hierarchical documents,
defined by seven rules and frozen at v1.0.

This release includes:
- The canonical syntax specification (`SYNTAX.txt`), frozen and immutable.
- `ROSETTA.springwater`: a self-describing document that explains the entire format
  in Springwater itself, so it can be reconstructed from that file alone.
- Schemas for screenplay, novel, technical, authoring-profile, and self-descriptive
  (Rosetta) documents, each validating against the self-validating meta-schema.
- A Swift 6 reference implementation (`SpringwaterSyntax`): parser, schema validator,
  schema-driven HTML renderer, and Fountain exporter, with tests.
- An authoring-profile layer (snippets, completions, editor preferences) that never
  affects document validity.
- Python tools: a strict syntax validator and a conformance-vector suite.

Notes:
- Fountain export is a one-way projection; the `written_by`, `author`, and `revision`
  title-page fields map to Fountain `Credit`, `Author`, and `Revision`. No Fountain
  importer ships; canonical Springwater is the preservation form.
