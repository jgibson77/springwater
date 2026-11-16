package main

import (
	"bufio"
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"os"
	"unicode/utf8"
)

type Ending int

const (
	EndNone Ending = iota
	EndLF
	EndCRLF
	EndCR
)

func (e Ending) Name() string {
	switch e {
	case EndLF:
		return "lf"
	case EndCRLF:
		return "crlf"
	case EndCR:
		return "cr"
	}
	return "none"
}

func (e Ending) Bytes() string {
	switch e {
	case EndLF:
		return "\n"
	case EndCRLF:
		return "\r\n"
	case EndCR:
		return "\r"
	}
	return ""
}

type PhysLine struct {
	Text   []byte
	Ending Ending
}

// Node is either an element (IsElem) or a content line.
type Node struct {
	IsElem   bool
	Name     string
	Children []*Node
	Text     string
	Ending   Ending
}

type ParseError struct {
	Line   int
	Reason string
}

// splitLines divides at LF, CRLF, CR. CR immediately followed by LF is one CRLF.
// A trailing line break terminates the last line; it does not start a new empty one.
func splitLines(b []byte) []PhysLine {
	var lines []PhysLine
	start := 0
	i := 0
	for i < len(b) {
		switch b[i] {
		case '\n':
			lines = append(lines, PhysLine{b[start:i], EndLF})
			i++
			start = i
		case '\r':
			if i+1 < len(b) && b[i+1] == '\n' {
				lines = append(lines, PhysLine{b[start:i], EndCRLF})
				i += 2
			} else {
				lines = append(lines, PhysLine{b[start:i], EndCR})
				i++
			}
			start = i
		default:
			i++
		}
	}
	if start < len(b) {
		lines = append(lines, PhysLine{b[start:], EndNone})
	}
	return lines
}

const (
	KindContent = "content"
	KindOpen    = "open"
	KindClose   = "close"
	KindInvalid = "invalid"
)

func trim(t []byte) []byte {
	s, e := 0, len(t)
	for s < e && (t[s] == ' ' || t[s] == '\t') {
		s++
	}
	for e > s && (t[e-1] == ' ' || t[e-1] == '\t') {
		e--
	}
	return t[s:e]
}

func validName(c []byte) bool {
	if len(c) == 0 {
		return false
	}
	for i, ch := range c {
		letter := (ch >= 'a' && ch <= 'z') || (ch >= 'A' && ch <= 'Z')
		if i == 0 {
			if !letter {
				return false
			}
			continue
		}
		if !(letter || (ch >= '0' && ch <= '9') || ch == '_') {
			return false
		}
	}
	return true
}

func classify(text []byte) (kind string, name string) {
	t := trim(text)
	if len(t) == 0 || t[0] != '^' {
		return KindContent, ""
	}
	cand := t[1:]
	closing := false
	if len(cand) > 0 && cand[len(cand)-1] == '/' {
		cand = cand[:len(cand)-1]
		closing = true
	}
	if !validName(cand) {
		return KindInvalid, ""
	}
	if closing {
		return KindClose, string(cand)
	}
	return KindOpen, string(cand)
}

func parse(b []byte) (*Node, *ParseError) {
	if bytes.HasPrefix(b, []byte{0xEF, 0xBB, 0xBF}) {
		return nil, &ParseError{0, "byte stream begins with the UTF-8 BOM (EF BB BF)"}
	}
	if !utf8.Valid(b) {
		return nil, &ParseError{0, "byte stream is not valid UTF-8"}
	}
	lines := splitLines(b)
	if len(lines) == 0 {
		return nil, &ParseError{0, "document has zero physical lines"}
	}
	k, n := classify(lines[0].Text)
	if k != KindOpen || n != "Springwater" {
		return nil, &ParseError{1, "first physical line is not the root opening tag ^Springwater"}
	}
	stack := []*Node{{IsElem: true, Name: "Springwater", Children: []*Node{}}}
	for i := 1; i < len(lines); i++ {
		ln := i + 1
		top := stack[len(stack)-1]
		k, n := classify(lines[i].Text)
		switch k {
		case KindContent:
			if lines[i].Ending == EndNone {
				// Final physical line without a line break that is content: the root
				// closing tag can no longer appear. Step 9 outcome, reported here
				// because a ContentLine cannot carry an absent ending.
				return nil, &ParseError{0, "root closing tag ^Springwater/ never encountered (document ends with a content line)"}
			}
			top.Children = append(top.Children, &Node{Text: string(lines[i].Text), Ending: lines[i].Ending})
		case KindOpen:
			if n == "Springwater" {
				return nil, &ParseError{ln, "tag name Springwater is reserved for the root and may not be opened again"}
			}
			stack = append(stack, &Node{IsElem: true, Name: n, Children: []*Node{}})
		case KindClose:
			if len(stack) == 1 && n == "Springwater" {
				if i != len(lines)-1 {
					return nil, &ParseError{ln, "root closing tag ^Springwater/ is not the last physical line"}
				}
				return stack[0], nil
			} else if top.Name == n && len(stack) > 1 {
				stack = stack[:len(stack)-1]
				p := stack[len(stack)-1]
				p.Children = append(p.Children, top)
			} else {
				return nil, &ParseError{ln, fmt.Sprintf("closing tag ^%s/ does not match the nearest unclosed opening tag ^%s", n, top.Name)}
			}
		default:
			return nil, &ParseError{ln, "line begins with ^ after trimming but is not a valid tag line"}
		}
	}
	return nil, &ParseError{0, "root closing tag ^Springwater/ never encountered"}
}

func jstr(s string) []byte {
	var buf bytes.Buffer
	enc := json.NewEncoder(&buf)
	enc.SetEscapeHTML(false)
	enc.Encode(s)
	return bytes.TrimRight(buf.Bytes(), "\n")
}

func writeTree(w *bufio.Writer, n *Node) {
	if !n.IsElem {
		w.WriteString(`{"content":`)
		w.Write(jstr(n.Text))
		w.WriteString(`,"ending":"` + n.Ending.Name() + `"}`)
		return
	}
	w.WriteString(`{"element":`)
	w.Write(jstr(n.Name))
	w.WriteString(`,"children":[`)
	for i, c := range n.Children {
		if i > 0 {
			w.WriteByte(',')
		}
		writeTree(w, c)
	}
	w.WriteString(`]}`)
}

func writeCanon(w *bufio.Writer, n *Node) {
	if !n.IsElem {
		w.WriteString(n.Text)
		w.WriteString(n.Ending.Bytes())
		return
	}
	w.WriteString("^" + n.Name + "\n")
	for _, c := range n.Children {
		writeCanon(w, c)
	}
	w.WriteString("^" + n.Name + "/\n")
}

func writeErr(w *bufio.Writer, e *ParseError) {
	fmt.Fprintf(w, `{"ok":false,"line":%d,"reason":%s}`+"\n", e.Line, jstr(e.Reason))
}

func main() {
	w := bufio.NewWriter(os.Stdout)
	defer w.Flush()
	if len(os.Args) < 2 {
		fmt.Fprintln(os.Stderr, "usage: sw parse <path> | sw classify | sw serialize <path>")
		w.Flush()
		os.Exit(2)
	}
	switch os.Args[1] {
	case "classify":
		in, _ := io.ReadAll(os.Stdin)
		k, n := classify(in)
		if k == KindOpen || k == KindClose {
			fmt.Fprintf(w, `{"kind":"%s","name":%s}`+"\n", k, jstr(n))
		} else {
			fmt.Fprintf(w, `{"kind":"%s","name":null}`+"\n", k)
		}
	case "parse", "serialize":
		if len(os.Args) < 3 {
			fmt.Fprintln(os.Stderr, "missing <path>")
			w.Flush()
			os.Exit(2)
		}
		b, err := os.ReadFile(os.Args[2])
		if err != nil {
			writeErr(w, &ParseError{0, "cannot read file: " + err.Error()})
			return
		}
		tree, perr := parse(b)
		if perr != nil {
			writeErr(w, perr)
			return
		}
		if os.Args[1] == "parse" {
			w.WriteString(`{"ok":true,"tree":`)
			writeTree(w, tree)
			w.WriteString("}\n")
		} else {
			writeCanon(w, tree)
		}
	default:
		fmt.Fprintln(os.Stderr, "unknown command")
		w.Flush()
		os.Exit(2)
	}
}
