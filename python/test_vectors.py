#!/usr/bin/env python3
"""Runs the clean-room validator against the schema conformance vectors.

    python3 python/test_vectors.py

swv.py was written from SYNTAX.txt and SCHEMA_SPEC.txt alone and is kept as it
was delivered. This runner was written afterwards. See CLEANROOM.md.
"""
import json
import os
import subprocess
import sys
import tempfile

here = os.path.dirname(os.path.abspath(__file__))
repo = os.path.dirname(here)
vectors = json.load(open(os.path.join(repo, "tools", "schema_conformance_vectors.json"), encoding="utf-8"))["vectors"]


def key(issue):
    return (issue["kind"], issue["element"], issue.get("other") or "")


agreed = 0
with tempfile.TemporaryDirectory() as folder:
    schema_path = os.path.join(folder, "schema.springwater")
    document_path = os.path.join(folder, "document.springwater")
    for vector in vectors:
        with open(schema_path, "w", encoding="utf-8", newline="") as f:
            f.write(vector["schema"])
        with open(document_path, "w", encoding="utf-8", newline="") as f:
            f.write(vector["document"])
        out = subprocess.run(
            [sys.executable, os.path.join(here, "swv.py"), "validate", schema_path, document_path],
            capture_output=True, text=True, encoding="utf-8",
        ).stdout
        got = json.loads(out)
        want = vector["expect"]
        if want.get("unusable_schema"):
            same = got.get("unusable_schema") is True
        else:
            same = "issues" in got and sorted(map(key, got["issues"])) == sorted(map(key, want["issues"]))
        if same:
            agreed += 1
        else:
            print("DISAGREE:", vector["name"], "\n  got ", got, "\n  want", want)

print(f"schema conformance vectors: {agreed} of {len(vectors)} agree")
sys.exit(0 if agreed == len(vectors) else 1)
