# Springwater (app)

A document-based app for Mac, iPhone, and iPad that opens, edits, validates,
and saves `.springwater` files.

- **Source** shows the file's exact text and lets you edit it.
- **Page** shows the document as readable text, dressed by the presentation
  for its kind when the repository has one.
- The status line answers two separate questions: is this Springwater, and is
  it a valid document of its kind.

The app uses the Swift package in `swift/SpringwaterSyntax` and bundles the
repository's `schemas/` and `presentations/` folders unchanged.

Open `Springwater.xcodeproj` in Xcode 27 or later and run the Springwater
scheme on My Mac or an iOS simulator.
