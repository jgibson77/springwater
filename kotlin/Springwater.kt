// Springwater v1.0 for Kotlin (Android and JVM): parser, canonical serializer,
// schema validator. Follows the parsing algorithm in SYNTAX.txt.
// Uses only the Kotlin and Java standard libraries.

package springwater

import java.nio.ByteBuffer
import java.nio.charset.CharacterCodingException
import java.nio.charset.CodingErrorAction

enum class LineEnding(val text: String) { LF("\n"), CRLF("\r\n"), CR("\r") }

sealed interface Node
data class Content(val text: String, val ending: LineEnding) : Node
data class Element(val name: String, val children: List<Node>) : Node {
    val childElements: List<Element> get() = children.filterIsInstance<Element>()
    val contentLines: List<String> get() = children.filterIsInstance<Content>().map { it.text }
    /** Content lines joined and trimmed: the value of a schema property. */
    val scalar: String get() = schemaTrim(contentLines.joinToString("\n"))
}

/** [kind] is one of the error names used by the conformance vectors. */
class SpringwaterException(val kind: String, val line: Int? = null, detail: String? = null) :
    Exception(listOfNotNull(kind, line?.let { "line $it" }, detail).joinToString(": "))

enum class LineKind { CONTENT, OPEN, CLOSE, INVALID }
data class Classified(val kind: LineKind, val name: String?)

object Springwater {

    private class PhysicalLine(val text: String, val ending: LineEnding?)

    /** Divide at LF, CRLF, CR. U+2028 and U+2029 are content. */
    private fun physicalLines(s: String): List<PhysicalLine> {
        val lines = ArrayList<PhysicalLine>()
        var start = 0
        var i = 0
        while (i < s.length) {
            val c = s[i]
            if (c == '\n') {
                lines.add(PhysicalLine(s.substring(start, i), LineEnding.LF)); i += 1; start = i
            } else if (c == '\r') {
                if (i + 1 < s.length && s[i + 1] == '\n') {
                    lines.add(PhysicalLine(s.substring(start, i), LineEnding.CRLF)); i += 2
                } else {
                    lines.add(PhysicalLine(s.substring(start, i), LineEnding.CR)); i += 1
                }
                start = i
            } else {
                i += 1
            }
        }
        if (start < s.length) lines.add(PhysicalLine(s.substring(start), null))
        return lines
    }

    /** Remove leading and trailing U+0020 and U+0009 only. */
    fun trimmed(text: String): String {
        var a = 0
        var b = text.length
        while (a < b && (text[a] == ' ' || text[a] == '\t')) a += 1
        while (b > a && (text[b - 1] == ' ' || text[b - 1] == '\t')) b -= 1
        return text.substring(a, b)
    }

    private fun isAsciiLetter(c: Char) = c in 'a'..'z' || c in 'A'..'Z'

    private fun isValidTagName(name: String): Boolean {
        if (name.isEmpty() || !isAsciiLetter(name[0])) return false
        return name.drop(1).all { isAsciiLetter(it) || it in '0'..'9' || it == '_' }
    }

    /** Classify one trimmed line. */
    fun classify(t: String): Classified {
        if (t.isEmpty() || t[0] != '^') return Classified(LineKind.CONTENT, null)
        var body = t.substring(1)
        var closing = false
        if (body.endsWith("/")) { closing = true; body = body.dropLast(1) }
        if (!isValidTagName(body)) return Classified(LineKind.INVALID, null)
        return Classified(if (closing) LineKind.CLOSE else LineKind.OPEN, body)
    }

    private class Frame(val name: String, val openedAt: Int) {
        val children = ArrayList<Node>()
    }

    /** Parse a byte stream into the root element. */
    fun parse(bytes: ByteArray): Element {
        if (bytes.size >= 3 && bytes[0] == 0xEF.toByte() && bytes[1] == 0xBB.toByte() && bytes[2] == 0xBF.toByte()) {
            throw SpringwaterException("leadingBOM")
        }
        val s = try {
            Charsets.UTF_8.newDecoder()
                .onMalformedInput(CodingErrorAction.REPORT)
                .onUnmappableCharacter(CodingErrorAction.REPORT)
                .decode(ByteBuffer.wrap(bytes)).toString()
        } catch (e: CharacterCodingException) {
            throw SpringwaterException("invalidUTF8")
        }

        val lines = physicalLines(s)
        if (lines.isEmpty()) throw SpringwaterException("emptyDocument")
        if (trimmed(lines[0].text) != "^Springwater") {
            throw SpringwaterException("missingRootOpen", 1, trimmed(lines[0].text))
        }

        val stack = ArrayList<Frame>()
        stack.add(Frame("Springwater", 1))
        var root: Element? = null
        for (index in 1 until lines.size) {
            val lineNumber = index + 1
            val line = lines[index]
            val c = classify(trimmed(line.text))
            val top = stack.last()
            when (c.kind) {
                LineKind.CONTENT -> {
                    // Only the final physical line can lack an ending. If that line
                    // is content, the root was never closed: stop and report below.
                    val ending = line.ending ?: break
                    top.children.add(Content(line.text, ending))
                }
                LineKind.OPEN -> {
                    if (c.name == "Springwater") throw SpringwaterException("reservedRootName", lineNumber)
                    stack.add(Frame(c.name!!, lineNumber))
                }
                LineKind.CLOSE -> {
                    if (top.name != c.name) {
                        throw SpringwaterException(
                            "mismatchedClosingTag", lineNumber,
                            "^${top.name} opened on line ${top.openedAt}, but ^${c.name}/ closes here"
                        )
                    }
                    if (stack.size == 1) {
                        if (index != lines.size - 1) {
                            throw SpringwaterException("trailingLinesAfterRootClose", lineNumber)
                        }
                        stack.removeAt(stack.size - 1)
                        root = Element(top.name, top.children)
                    } else {
                        stack.removeAt(stack.size - 1)
                        stack.last().children.add(Element(top.name, top.children))
                    }
                }
                LineKind.INVALID -> throw SpringwaterException("invalidCaretLine", lineNumber, trimmed(line.text))
            }
        }
        if (root == null) {
            if (stack.size > 1) {
                val top = stack.last()
                throw SpringwaterException("unclosedTag", top.openedAt, "^${top.name}")
            }
            throw SpringwaterException("missingRootClose")
        }
        return root
    }

    /** Canonical form: tag lines flush left and LF-terminated, content verbatim. */
    fun serialize(root: Element): String {
        val out = StringBuilder()
        fun write(el: Element) {
            out.append('^').append(el.name).append('\n')
            for (child in el.children) {
                when (child) {
                    is Element -> write(child)
                    is Content -> out.append(child.text).append(child.ending.text)
                }
            }
            out.append('^').append(el.name).append("/\n")
        }
        write(root)
        return out.toString()
    }
}

// ---------------------------------------------------------------- schemas

/**
 * Removes leading and trailing schema whitespace: space, tab, and line feed,
 * and nothing else (SCHEMA_SPEC.txt, TERMS). Kotlin's own trim() removes more.
 */
fun schemaTrim(text: String): String = text.trim { it == ' ' || it == '\t' || it == '\n' }

data class Rule(
    val tag: String,
    val mustContain: List<String> = emptyList(),
    val mayContain: List<String> = emptyList(),
    val cannotContain: List<String> = emptyList(),
    val mustContainOneOf: List<String> = emptyList(),
    val mustContainCount: Pair<String, Int>? = null,
    val parentMustBe: List<String> = emptyList(),
    val cannotBeEmpty: Boolean = false,
    val textOnly: Boolean = false,
    val mustEqual: String? = null,
    val mustBeBoolean: Boolean = false,
    val allowsUnknownChildren: Boolean = false,
    val atMostOne: List<String> = emptyList(),
    val startsWith: List<String> = emptyList(),
)

/**
 * One finding of schema validation, as SCHEMA_SPEC.txt defines it: a kind, the
 * element it concerns, and for some kinds a second tag name.
 */
data class Issue(val kind: String, val element: String, val other: String? = null) {
    /** The issue in words. The wording is not part of the specification. */
    fun describe(): String = when (kind) {
        "missing_root" -> "missing required root <$element>"
        "unexpected_top" -> "unexpected top-level element <$element>"
        "unknown_tag" -> "unknown tag <$element> under <$other>"
        "wrong_parent" -> "<$element> is not allowed under <$other>"
        "not_text_only" -> "<$element> is text only but contains elements"
        "empty" -> "<$element> cannot be empty"
        "not_equal" -> "<$element> does not have its required value"
        "not_boolean" -> "<$element> must be true or false"
        "forbidden_child" -> "<$element> cannot contain <$other>"
        "child_not_allowed" -> "<$other> is not allowed in <$element>"
        "missing_child" -> "<$element> is missing required <$other>"
        "missing_one_of" -> "<$element> is missing one of its required alternatives"
        "wrong_count" -> "<$element> has the wrong number of <$other>"
        "too_many" -> "<$element> has more than one <$other>"
        "out_of_order" -> "<$other> is out of order in <$element>"
        else -> "$kind <$element>"
    }
}

class Schema(val requiredRoot: String, val rules: Map<String, Rule>) {

    /** Returns a list of messages; an empty list means the document is valid. */
    fun validate(root: Element): List<String> = validateIssues(root).map { it.describe() }

    /**
     * Validates a parsed document as SCHEMA_SPEC.txt defines. An empty list
     * means the document is valid against this schema. Order carries no meaning.
     */
    fun validateIssues(root: Element): List<Issue> {
        val issues = ArrayList<Issue>()
        val top = root.childElements
        val required = top.filter { it.name == requiredRoot }
        if (required.isEmpty()) issues.add(Issue("missing_root", requiredRoot))
        // A document may carry its own schema and presentation beside the work
        // (see CONVENTIONS.md, "Self-contained documents"). They are not part of
        // the work and are not judged by the work's schema.
        for (e in top) {
            if (e.name != requiredRoot && e.name !in CARRIED) issues.add(Issue("unexpected_top", e.name))
        }
        for (e in required) check(e, "Springwater", issues)
        return issues
    }

    private fun check(el: Element, parent: String, issues: MutableList<Issue>) {
        val rule = rules[el.name]
        if (rule == null) { issues.add(Issue("unknown_tag", el.name, parent)); return }
        if (rule.parentMustBe.isNotEmpty() && parent !in rule.parentMustBe) issues.add(Issue("wrong_parent", el.name, parent))
        val kids = el.childElements
        val names = kids.map { it.name }
        val hasText = el.contentLines.any { Springwater.trimmed(it).isNotEmpty() }
        if (rule.textOnly && kids.isNotEmpty()) issues.add(Issue("not_text_only", el.name))
        if (rule.cannotBeEmpty && !hasText && kids.isEmpty()) issues.add(Issue("empty", el.name))
        if (rule.mustEqual != null && el.scalar != rule.mustEqual) issues.add(Issue("not_equal", el.name))
        if (rule.mustBeBoolean && el.scalar != "true" && el.scalar != "false") issues.add(Issue("not_boolean", el.name))

        val allowed = HashSet<String>()
        allowed.addAll(rule.mustContain); allowed.addAll(rule.mayContain); allowed.addAll(rule.mustContainOneOf)
        rule.mustContainCount?.let { allowed.add(it.first) }
        for (k in kids) {
            if (k.name in rule.cannotContain) issues.add(Issue("forbidden_child", el.name, k.name))
            else if (!rule.allowsUnknownChildren && k.name !in allowed) issues.add(Issue("child_not_allowed", el.name, k.name))
        }
        for (t in rule.mustContain) if (t !in names) issues.add(Issue("missing_child", el.name, t))
        if (rule.mustContainOneOf.isNotEmpty() && names.none { it in rule.mustContainOneOf }) {
            issues.add(Issue("missing_one_of", el.name))
        }
        rule.mustContainCount?.let { (tag, count) ->
            if (names.count { it == tag } != count) issues.add(Issue("wrong_count", el.name, tag))
        }
        for (n in rule.atMostOne.distinct()) {
            if (names.count { it == n } > 1) issues.add(Issue("too_many", el.name, n))
        }
        if (rule.startsWith.isNotEmpty()) {
            var last = -1
            var passed = false
            for (n in names) {
                val i = rule.startsWith.indexOf(n)
                if (i < 0) passed = true
                else if (passed || i < last) issues.add(Issue("out_of_order", el.name, n))
                else last = i
            }
        }
        if (!rule.allowsUnknownChildren) for (k in kids) check(k, el.name, issues)
    }

    companion object {
        private fun list(text: String) = text.split(",").map { schemaTrim(it) }.filter { it.isNotEmpty() }

        /** Build a schema model from a parsed schema document. */
        fun from(schemaRoot: Element): Schema {
            val schemaEl = schemaRoot.childElements.firstOrNull { it.name == "schema" }
                ?: throw IllegalArgumentException("unusable schema: no schema element")
            return fromElement(schemaEl)
        }

        /** The element names a document may carry at its top level beside the work. */
        val CARRIED = listOf("schema", "presentation")

        /**
         * The `schema` element this document carries for elements named [name]:
         * the first top-level `schema` whose required_root is [name].
         */
        fun carriedSchemaElement(root: Element, name: String): Element? =
            root.childElements.firstOrNull { e ->
                e.name == "schema" && e.childElements.any { it.name == "required_root" && it.scalar == name }
            }

        /**
         * The `presentation` element this document carries for elements named
         * [name]: the first top-level `presentation` whose target_schema is [name].
         */
        fun carriedPresentationElement(root: Element, name: String): Element? =
            root.childElements.firstOrNull { e ->
                e.name == "presentation" && e.childElements.any { m ->
                    m.name == "metadata" && m.childElements.any { it.name == "target_schema" && it.scalar == name }
                }
            }

        /**
         * The schema a document carries for its own work (its first top-level
         * element). Null when it carries none.
         */
        fun carried(root: Element): Schema? {
            val work = root.childElements.firstOrNull() ?: return null
            return carriedSchemaElement(root, work.name)?.let { fromElement(it) }
        }

        /** Build a schema model from a `schema` element, wherever it was found. */
        fun fromElement(schemaEl: Element): Schema {
            var requiredRoot = ""
            val rules = LinkedHashMap<String, Rule>()
            for (e in schemaEl.childElements) {
                if (e.name == "required_root") requiredRoot = e.scalar
                if (e.name != "structure_rules") continue
                for (r in e.childElements) {
                    if (r.name != "rule") continue
                    var rule = Rule(tag = "")
                    for (p in r.childElements) {
                        val v = p.scalar
                        rule = when (p.name) {
                            "tag" -> rule.copy(tag = v)
                            "must_contain" -> rule.copy(mustContain = list(v))
                            "may_contain" -> rule.copy(mayContain = list(v))
                            "cannot_contain" -> rule.copy(cannotContain = list(v))
                            "must_contain_one_of" -> rule.copy(mustContainOneOf = list(v))
                            "must_contain_count" -> {
                                val parts = list(v)
                                val n = parts.getOrNull(1)?.takeIf { d -> d.isNotEmpty() && d.all { it in '0'..'9' } }?.toIntOrNull()
                                if (parts.size == 2 && n != null) rule.copy(mustContainCount = parts[0] to n) else rule
                            }
                            "parent_must_be" -> rule.copy(parentMustBe = list(v))
                            "at_most_one" -> rule.copy(atMostOne = list(v))
                            "starts_with" -> rule.copy(startsWith = list(v))
                            "cannot_be_empty" -> rule.copy(cannotBeEmpty = v == "true")
                            "text_only" -> rule.copy(textOnly = v == "true")
                            "must_equal" -> rule.copy(mustEqual = v)
                            "must_be_boolean" -> rule.copy(mustBeBoolean = v == "true")
                            "allows_unknown_children" -> rule.copy(allowsUnknownChildren = v == "true")
                            else -> rule
                        }
                    }
                    if (rule.tag.isNotEmpty()) rules[rule.tag] = rule
                }
            }
            // A schema with no required root cannot be validated against.
            if (requiredRoot.isEmpty()) throw IllegalArgumentException("unusable schema: no required_root")
            return Schema(requiredRoot, rules)
        }
    }
}
