# Changelog

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
