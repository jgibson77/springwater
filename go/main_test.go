package main

// This test was written after the clean-room parser, by someone who knows the
// repository. main.go itself was written from SYNTAX.txt alone and is kept as
// it was delivered. See CLEANROOM.md.

import (
	"bufio"
	"bytes"
	"encoding/base64"
	"encoding/json"
	"os"
	"path/filepath"
	"reflect"
	"strings"
	"testing"
)

type vectors struct {
	Parse []struct {
		Name   string `json:"name"`
		Input  string `json:"input_base64"`
		Expect struct {
			Tree  json.RawMessage `json:"tree"`
			Error string          `json:"error"`
		} `json:"expect"`
	} `json:"parse_vectors"`
	Classify []struct {
		Line string  `json:"line"`
		Kind string  `json:"kind"`
		Name *string `json:"name"`
	} `json:"classify_vectors"`
}

func loadVectors(t *testing.T) vectors {
	data, err := os.ReadFile(filepath.Join("..", "tools", "conformance_vectors.json"))
	if err != nil {
		t.Fatal(err)
	}
	var v vectors
	if err := json.Unmarshal(data, &v); err != nil {
		t.Fatal(err)
	}
	return v
}

func treeJSON(n *Node) any {
	var buf bytes.Buffer
	w := bufio.NewWriter(&buf)
	writeTree(w, n)
	w.Flush()
	var out any
	if err := json.Unmarshal(buf.Bytes(), &out); err != nil {
		panic(err)
	}
	return out
}

// A parser conforms on a vector when it rejects what must be rejected and
// builds the same tree for what must be accepted. The vectors also name an
// error kind; SYNTAX.txt defines no such names, so they are not checked here.
func TestParseVectors(t *testing.T) {
	for _, vec := range loadVectors(t).Parse {
		input, err := base64.StdEncoding.DecodeString(vec.Input)
		if err != nil {
			t.Fatal(err)
		}
		root, perr := parse(input)
		if vec.Expect.Error != "" {
			if perr == nil {
				t.Errorf("%s: accepted, want rejection (%s)", vec.Name, vec.Expect.Error)
			}
			continue
		}
		if perr != nil {
			t.Errorf("%s: rejected (%s), want a tree", vec.Name, perr.Reason)
			continue
		}
		var want any
		if err := json.Unmarshal(vec.Expect.Tree, &want); err != nil {
			t.Fatal(err)
		}
		if !reflect.DeepEqual(treeJSON(root), want) {
			t.Errorf("%s: tree differs", vec.Name)
		}
	}
}

func TestClassifyVectors(t *testing.T) {
	for _, vec := range loadVectors(t).Classify {
		kind, name := classify([]byte(vec.Line))
		wantName := ""
		if vec.Name != nil {
			wantName = *vec.Name
		}
		if kind != vec.Kind || name != wantName {
			t.Errorf("%q: got %s %q, want %s %q", vec.Line, kind, name, vec.Kind, wantName)
		}
	}
}

// Every Springwater document in the repository must parse, and its canonical
// form must parse back to the same tree.
func TestRepositoryDocuments(t *testing.T) {
	count := 0
	err := filepath.WalkDir("..", func(path string, d os.DirEntry, err error) error {
		if err != nil {
			return err
		}
		if d.IsDir() && (d.Name() == ".git" || d.Name() == ".build") {
			return filepath.SkipDir
		}
		if d.IsDir() || !strings.HasSuffix(path, ".springwater") {
			return nil
		}
		data, err := os.ReadFile(path)
		if err != nil {
			return err
		}
		root, perr := parse(data)
		if perr != nil {
			t.Errorf("%s: rejected at line %d: %s", path, perr.Line, perr.Reason)
			return nil
		}
		var buf bytes.Buffer
		w := bufio.NewWriter(&buf)
		writeCanon(w, root)
		w.Flush()
		again, perr := parse(buf.Bytes())
		if perr != nil || !reflect.DeepEqual(treeJSON(again), treeJSON(root)) {
			t.Errorf("%s: canonical form does not parse back to the same tree", path)
		}
		count++
		return nil
	})
	if err != nil {
		t.Fatal(err)
	}
	if count == 0 {
		t.Fatal("no .springwater documents found")
	}
	t.Logf("%d documents checked", count)
}
